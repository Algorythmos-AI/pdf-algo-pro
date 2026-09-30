import Core
import PDFKit

/// A text markup annotation the reader can add to selected text (FR-ANN-001).
public enum TextMarkup: String, CaseIterable, Sendable {
  /// A translucent highlight.
  case highlight
  /// An underline.
  case underline
  /// A strike-through.
  case strikeThrough

  fileprivate var subtype: PDFAnnotationSubtype {
    switch self {
    case .highlight: .highlight
    case .underline: .underline
    case .strikeThrough: .strikeOut
    }
  }
}

extension PDFDocumentController {
  /// The number of annotations on a page, not counting the pop-ups PDFKit attaches to notes.
  public func annotationCount(onPage pageIndex: Int) -> Int {
    document.page(at: pageIndex)?.annotations.filter { $0.type?.lowercased() != "popup" }.count ?? 0
  }

  /// Marks up the current selection; returns `false` when nothing is selected.
  @discardableResult
  public func markUpSelection(_ markup: TextMarkup) -> Bool {
    guard let selection = view?.currentSelection else { return false }
    return markUp(selection, as: markup)
  }

  /// Marks up the first occurrence of some text (used by tests and by citations).
  @discardableResult
  public func markUp(text: String, as markup: TextMarkup) -> Bool {
    guard let selection = document.findString(text, withOptions: [.caseInsensitive]).first else { return false }
    return markUp(selection, as: markup)
  }

  /// Adds a note annotation near the top-left corner of a page.
  public func addNote(_ contents: String, onPage pageIndex: Int) {
    guard let page = document.page(at: pageIndex) else { return }
    let bounds = page.bounds(for: .cropBox)
    let note = PDFAnnotation(
      bounds: CGRect(x: bounds.minX + 24, y: bounds.maxY - 48, width: 24, height: 24), forType: .text,
      withProperties: nil)
    note.contents = contents
    note.color = AnnotationPalette.yellow
    add([(note, page)])
  }

  /// Turns drawing on or off (F2a).
  ///
  /// While it is on, a stroke on a page becomes an ink annotation and `onStroke` runs, so the reader
  /// can save; scrolling and selection wait until it is off.
  public func setDrawing(_ isDrawing: Bool, onStroke: @escaping @MainActor () -> Void = {}) {
    self.isDrawing = isDrawing
    onInk = isDrawing ? onStroke : nil
    view?.setDrawing(isDrawing)
  }

  /// A stroke finished on a page, in page space; the page view calls this while drawing.
  func strokeEnded(_ points: [CGPoint], onPage pageIndex: Int) {
    guard isDrawing, addInk([points], onPage: pageIndex) else { return }
    onInk?()
  }

  /// The width of the pen, in points.
  public static let inkLineWidth: CGFloat = 2.5

  /// Adds strokes drawn on a page as one ink annotation (F2a), a standard `/Ink` annotation that other
  /// PDF readers show and edit.
  ///
  /// Points are in page space (PDF points, origin at the bottom left, before the page's rotation), as
  /// `PDFView.convert(_:to:)` gives them, so strokes stay where they were drawn on rotated pages.
  /// Strokes of a single point are dropped. Returns whether anything was added.
  @discardableResult
  public func addInk(_ strokes: [[CGPoint]], onPage pageIndex: Int, contents: String? = nil) -> Bool {
    let strokes = strokes.filter { $0.count > 1 }
    guard let page = document.page(at: pageIndex), let first = strokes.first?.first else { return false }
    let points = strokes.flatMap(\.self)
    var box = CGRect(origin: first, size: .zero)
    for point in points { box = box.union(CGRect(origin: point, size: .zero)) }
    let bounds = box.insetBy(dx: -Self.inkLineWidth * 2, dy: -Self.inkLineWidth * 2)
    let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
    let border = PDFBorder()
    border.lineWidth = Self.inkLineWidth
    annotation.border = border
    annotation.color = AnnotationPalette.ink
    annotation.contents = contents
    for stroke in strokes {
      // Ink paths are in the annotation's own space, from its bounds' origin.
      let path = CGMutablePath()
      path.move(to: CGPoint(x: stroke[0].x - bounds.minX, y: stroke[0].y - bounds.minY))
      for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)) }
      annotation.add(PlatformBezierPath(cgPath: path))
    }
    add([(annotation, page)])
    return true
  }

  /// Places a saved signature on a page as ink (F1c, FR-EDIT-004).
  ///
  /// It is `width` points wide and centred in the lower third of the page. Returns whether it was
  /// placed. The signature's strokes are in a unit box from the top left; the page's space runs up from the
  /// bottom left, so the vertical axis is flipped.
  @discardableResult
  public func placeSignature(_ signature: SavedSignature, onPage pageIndex: Int, width: CGFloat = 180) -> Bool {
    guard let page = document.page(at: pageIndex), signature.aspectRatio > 0 else { return false }
    let box = page.bounds(for: .cropBox)
    let signatureWidth = min(width, box.width * 0.8)
    let size = CGSize(width: signatureWidth, height: signatureWidth / CGFloat(signature.aspectRatio))
    let origin = CGPoint(x: box.midX - size.width / 2, y: box.minY + box.height / 3 - size.height / 2)
    let strokes: [[CGPoint]] = signature.strokes.map { stroke in
      stroke.map { point in
        let x: CGFloat = origin.x + CGFloat(point.x) * size.width
        let y: CGFloat = origin.y + (1 - CGFloat(point.y)) * size.height
        return CGPoint(x: x, y: y)
      }
    }
    return addInk(strokes, onPage: pageIndex, contents: Self.signatureContents)
  }

  /// Places a typed name as a signature (F1c).
  ///
  /// It is a standard free-text annotation in a script font, for anyone who cannot or prefers not to
  /// draw. Returns whether it was placed.
  @discardableResult
  public func placeTypedSignature(_ name: String, onPage pageIndex: Int) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let page = document.page(at: pageIndex) else { return false }
    let font = PlatformFont(name: "SnellRoundhand", size: 28) ?? PlatformFont.systemFont(ofSize: 28)
    let width = min(CGFloat(name.count) * 17 + 40, page.bounds(for: .cropBox).width * 0.8)
    let box = page.bounds(for: .cropBox)
    let bounds = CGRect(x: box.midX - width / 2, y: box.minY + box.height / 3 - 22, width: width, height: 44)
    let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
    annotation.contents = name
    annotation.font = font
    annotation.fontColor = AnnotationPalette.ink
    annotation.color = .clear
    let border = PDFBorder()
    border.lineWidth = 0
    annotation.border = border
    add([(annotation, page)])
    return true
  }

  /// The contents of a placed signature's ink, so it can be told apart from drawing.
  public static let signatureContents = "Signature"

  private func markUp(_ selection: PDFSelection, as markup: TextMarkup) -> Bool {
    var added: [(PDFAnnotation, PDFPage)] = []
    for line in selection.selectionsByLine() {
      for page in line.pages {
        let bounds = line.bounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        let annotation = PDFAnnotation(bounds: bounds, forType: markup.subtype, withProperties: nil)
        annotation.color = markup == .highlight ? AnnotationPalette.yellow : AnnotationPalette.red
        added.append((annotation, page))
      }
    }
    guard !added.isEmpty else { return false }
    add(added)
    return true
  }

  private func add(_ annotations: [(PDFAnnotation, PDFPage)]) {
    for (annotation, page) in annotations { page.addAnnotation(annotation) }
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.remove(annotations) }
    }
  }

  private func remove(_ annotations: [(PDFAnnotation, PDFPage)]) {
    for (annotation, page) in annotations { page.removeAnnotation(annotation) }
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.add(annotations) }
    }
  }
}
