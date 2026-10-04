import PDFKit

/// A colour the reader can give an annotation (FR-ANN-005): system colours, so they read in light and dark.
public enum AnnotationColor: String, CaseIterable, Sendable {
  /// Blue, the colour drawing starts with.
  case blue
  /// Red.
  case red
  /// Green.
  case green
  /// Yellow.
  case yellow
  /// Black.
  case black

  var platformColor: PlatformColor {
    switch self {
    case .blue: .systemBlue
    case .red: .systemRed
    case .green: .systemGreen
    case .yellow: .systemYellow
    case .black: .black
    }
  }
}

extension AnnotationSelection {
  /// Whether it can be moved and resized.
  ///
  /// Text markup follows the words it marks, so it stays where it is.
  public var isMovable: Bool {
    ![.highlight, .underline, .strikeThrough].contains(kind)
  }

  /// Whether its colour can be changed.
  public var isRecolorable: Bool { kind != .stamp && kind != .other }
}

/// Everything that places an annotation on its page: enough to put it back exactly.
struct AnnotationGeometry {
  var bounds: CGRect
  var paths: [PlatformBezierPath]
  var startPoint: CGPoint
  var endPoint: CGPoint
  var fontSize: CGFloat?

  @MainActor
  init(_ annotation: PDFAnnotation) {
    bounds = annotation.bounds
    paths = (annotation.paths ?? []).map { PlatformBezierPath(cgPath: $0.cgPath) }
    startPoint = annotation.startPoint
    endPoint = annotation.endPoint
    fontSize = annotation.font?.pointSize
  }
}

extension PDFDocumentController {
  /// The smallest an annotation can be made, in points.
  static let minimumAnnotationSide: CGFloat = 12

  /// Moves the selected annotation by an offset in page space, keeping it on the page.
  ///
  /// Undo moves it back. Returns whether it moved.
  @discardableResult
  public func moveSelection(by offset: CGSize) -> Bool {
    guard let selected, selection?.isMovable == true, offset != .zero else { return false }
    let before = AnnotationGeometry(selected.annotation)
    var after = before
    after.bounds = clamp(before.bounds.offsetBy(dx: offset.width, dy: offset.height), to: selected.page)
    guard after.bounds != before.bounds else { return false }
    setGeometry(after, of: selected.annotation, on: selected.page, undoTo: before)
    return true
  }

  /// Scales the selected annotation about its centre, keeping it on the page and at least a few points across.
  ///
  /// Ink, lines and text scale with it. Undo restores its size. Returns whether it changed.
  @discardableResult
  public func resizeSelection(by factor: CGFloat) -> Bool {
    guard let selected, selection?.isMovable == true, factor > 0, factor != 1 else { return false }
    let before = AnnotationGeometry(selected.annotation)
    guard let after = scaled(before, by: factor, on: selected.page) else { return false }
    setGeometry(after, of: selected.annotation, on: selected.page, undoTo: before)
    return true
  }

  /// Gives the selected annotation a new colour.
  ///
  /// Text boxes change their text colour, lines and shapes their stroke. Undo restores the colour.
  /// Returns whether it changed.
  @discardableResult
  public func setSelectionColor(_ color: AnnotationColor) -> Bool {
    guard let selected, let selection, selection.isRecolorable else { return false }
    setColor(color.platformColor, of: selected.annotation, kind: selection.kind, on: selected.page)
    return true
  }

  // MARK: - Direct manipulation

  /// The selected annotation's geometry when a drag or pinch starts; the gesture changes it live.
  func beginTransform() -> AnnotationGeometry? {
    guard let selected, selection?.isMovable == true else { return nil }
    return AnnotationGeometry(selected.annotation)
  }

  /// Shows the selected annotation moved and scaled from where the gesture started, without an undo step.
  func updateTransform(from start: AnnotationGeometry, offset: CGSize, scale: CGFloat) {
    guard let selected else { return }
    var geometry = scaled(start, by: scale, on: selected.page) ?? start
    geometry.bounds = clamp(geometry.bounds.offsetBy(dx: offset.width, dy: offset.height), to: selected.page)
    apply(geometry, to: selected.annotation, on: selected.page)
  }

  /// Ends a gesture: the whole change becomes one undo step.
  func endTransform(from start: AnnotationGeometry) {
    guard let selected else { return }
    let end = AnnotationGeometry(selected.annotation)
    guard end.bounds != start.bounds else { return }
    setGeometry(end, of: selected.annotation, on: selected.page, undoTo: start)
    onAnnotationTransformed?()
  }

  /// Whether a point in page space is on the selected annotation, so a gesture there moves it.
  func isOnSelection(_ point: CGPoint, pageIndex: Int) -> Bool {
    guard let selected, selection?.isMovable == true, document.index(for: selected.page) == pageIndex else {
      return false
    }
    return selected.annotation.bounds.insetBy(dx: -12, dy: -12).contains(point)
  }

  // MARK: - Helpers

  private func setGeometry(
    _ geometry: AnnotationGeometry, of annotation: PDFAnnotation, on page: PDFPage, undoTo previous: AnnotationGeometry
  ) {
    apply(geometry, to: annotation, on: page)
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated {
        controller.setGeometry(previous, of: annotation, on: page, undoTo: geometry)
      }
    }
  }

  private func apply(_ geometry: AnnotationGeometry, to annotation: PDFAnnotation, on page: PDFPage) {
    annotation.bounds = geometry.bounds
    for path in annotation.paths ?? [] { annotation.remove(path) }
    for path in geometry.paths { annotation.add(PlatformBezierPath(cgPath: path.cgPath)) }
    annotation.startPoint = geometry.startPoint
    annotation.endPoint = geometry.endPoint
    if let size = geometry.fontSize, let font = annotation.font, font.pointSize != size {
      annotation.font = PlatformFont(descriptor: font.fontDescriptor, size: size)
    }
    redraw(annotation, on: page)
  }

  private func setColor(
    _ color: PlatformColor, of annotation: PDFAnnotation, kind: AnnotationSelection.Kind, on page: PDFPage
  ) {
    let previous = kind == .textBox ? annotation.fontColor : annotation.color
    if kind == .textBox {
      annotation.fontColor = color
    } else {
      annotation.color = kind == .highlight ? AnnotationPalette.highlighter(color) : color
      if kind == .line { annotation.interiorColor = color }
    }
    hasUnsavedChanges = true
    redraw(annotation, on: page)
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated {
        controller.setColor(previous ?? AnnotationPalette.ink, of: annotation, kind: kind, on: page)
      }
    }
  }

  /// PDFKit redraws an annotation reliably when it is put back on its page.
  private func redraw(_ annotation: PDFAnnotation, on page: PDFPage) {
    page.removeAnnotation(annotation)
    page.addAnnotation(annotation)
  }

  private func scaled(_ geometry: AnnotationGeometry, by factor: CGFloat, on page: PDFPage) -> AnnotationGeometry? {
    let old = geometry.bounds
    let box = page.bounds(for: .cropBox)
    let smallest = Self.minimumAnnotationSide / max(min(old.width, old.height), 1)
    let largest = min(box.width / max(old.width, 1), box.height / max(old.height, 1))
    let factor = min(max(factor, smallest), max(largest, smallest))
    guard abs(factor - 1) > 0.001 else { return nil }
    var result = geometry
    let size = CGSize(width: old.width * factor, height: old.height * factor)
    result.bounds = clamp(
      CGRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height),
      to: page)
    var transform = CGAffineTransform(scaleX: factor, y: factor)
    result.paths = geometry.paths.map { path in
      PlatformBezierPath(cgPath: path.cgPath.copy(using: &transform) ?? path.cgPath)
    }
    result.startPoint = geometry.startPoint.applying(transform)
    result.endPoint = geometry.endPoint.applying(transform)
    result.fontSize = geometry.fontSize.map { max($0 * factor, 6) }
    return result
  }

  /// Moves a rectangle the least needed to keep it inside the page's crop box.
  private func clamp(_ rect: CGRect, to page: PDFPage) -> CGRect {
    let box = page.bounds(for: .cropBox)
    var rect = rect
    rect.origin.x = min(max(rect.minX, box.minX), max(box.maxX - rect.width, box.minX))
    rect.origin.y = min(max(rect.minY, box.minY), max(box.maxY - rect.height, box.minY))
    return rect
  }
}
