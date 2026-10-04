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

/// What a drag on the page draws (F2a, F2b).
public enum DrawingTool: String, CaseIterable, Sendable {
  /// Freehand ink.
  case pen
  /// A rectangle from where the drag starts to where it ends.
  case rectangle
  /// An oval inside that rectangle.
  case oval
  /// A line with an arrowhead where the drag ends.
  case arrow
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

  /// Whether text is selected on a page.
  public var hasTextSelection: Bool {
    !(view?.currentSelection?.string ?? "").isEmpty
  }

  /// Takes a markup tool in hand, or puts it down with `nil`.
  ///
  /// While a tool is in hand, dragging a finger across text marks it as it goes: the reader calls
  /// `onMarked` after each drag so it can save.
  public func setMarkupTool(_ markup: TextMarkup?, onMarked: (@MainActor () -> Void)? = nil) {
    markupTool = markup
    onMarkup = markup == nil ? nil : onMarked
  }

  /// The text between two points on a page, as a drag across it would select.
  func textSelection(from start: CGPoint, to end: CGPoint, onPage pageIndex: Int) -> PDFSelection? {
    guard let page = document.page(at: pageIndex), let selection = page.selection(from: start, to: end),
      !(selection.string ?? "").isEmpty
    else { return nil }
    return selection
  }

  /// Marks the text between two points on a page with the tool in hand; returns whether any was marked.
  @discardableResult
  public func markUpText(from start: CGPoint, to end: CGPoint, onPage pageIndex: Int) -> Bool {
    guard let markupTool, let selection = textSelection(from: start, to: end, onPage: pageIndex),
      markUp(selection, as: markupTool)
    else { return false }
    onMarkup?()
    return true
  }

  /// Clears the text selection.
  public func clearTextSelection() {
    view?.clearSelection()
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
  public func setDrawing(
    _ isDrawing: Bool, tool: DrawingTool = .pen, onStroke: @escaping @MainActor () -> Void = {}
  ) {
    // Drawing and editing text are separate modes; turning one on turns the other off.
    if isDrawing, isEditingText { setEditingText(false) }
    self.isDrawing = isDrawing
    drawingTool = tool
    onInk = isDrawing ? onStroke : nil
    view?.setDrawing(isDrawing, tool: tool)
  }

  /// A stroke finished on a page, in page space; the page view calls this while drawing.
  func strokeEnded(_ points: [CGPoint], onPage pageIndex: Int) {
    guard isDrawing, let first = points.first, let last = points.last else { return }
    let added =
      drawingTool == .pen
      ? addInk([points], onPage: pageIndex) : addShape(drawingTool, from: first, to: last, onPage: pageIndex)
    if added { onInk?() }
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

  /// Adds a rectangle, oval or arrow between two points in page space (F2b).
  ///
  /// They are the standard `/Square`, `/Circle` and `/Line` annotations. Returns whether it was added:
  /// shapes smaller than a few points, and the pen, which draws ink, are not.
  @discardableResult
  public func addShape(_ tool: DrawingTool, from start: CGPoint, to end: CGPoint, onPage pageIndex: Int) -> Bool {
    guard tool != .pen, let page = document.page(at: pageIndex), hypot(end.x - start.x, end.y - start.y) >= 6 else {
      return false
    }
    let box = CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    let annotation: PDFAnnotation
    switch tool {
    case .rectangle, .oval:
      annotation = PDFAnnotation(
        bounds: box.insetBy(dx: -Self.inkLineWidth, dy: -Self.inkLineWidth), forType: tool == .oval ? .circle : .square,
        withProperties: nil)
    case .arrow:
      // Room around the line for the arrowhead; the end points are in the annotation's own space.
      let bounds = box.insetBy(dx: -Self.inkLineWidth * 6, dy: -Self.inkLineWidth * 6)
      annotation = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
      annotation.startPoint = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
      annotation.endPoint = CGPoint(x: end.x - bounds.minX, y: end.y - bounds.minY)
      annotation.endLineStyle = .closedArrow
      annotation.interiorColor = AnnotationPalette.ink
    case .pen:
      return false
    }
    let border = PDFBorder()
    border.lineWidth = Self.inkLineWidth
    annotation.border = border
    annotation.color = AnnotationPalette.ink
    add([(annotation, page)])
    return true
  }

  /// Adds a text box to a page (F2b).
  ///
  /// It is a standard free-text annotation with a thin border, centred in the upper third of the page.
  /// Returns whether it was added; blank text is not.
  @discardableResult
  public func addTextBox(_ text: String, onPage pageIndex: Int) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let page = document.page(at: pageIndex) else { return false }
    let box = page.bounds(for: .cropBox)
    let lines = text.split(whereSeparator: \.isNewline)
    let longest = lines.map(\.count).max() ?? 0
    let width = min(CGFloat(longest) * 8.5 + 24, box.width * 0.8)
    let height = CGFloat(max(lines.count, 1)) * 20 + 12
    // In the middle of what is on screen, so it appears where the person is looking; without a view,
    // two thirds of the way up the page.
    let fallback = CGPoint(x: box.midX, y: box.minY + box.height * 2 / 3)
    let middle = view?.visibleCenter(on: page).flatMap { box.contains($0) ? $0 : nil } ?? fallback
    var bounds = CGRect(x: middle.x - width / 2, y: middle.y - height / 2, width: width, height: height)
    bounds.origin.x = min(max(bounds.minX, box.minX + 8), box.maxX - width - 8)
    bounds.origin.y = min(max(bounds.minY, box.minY + 8), box.maxY - height - 8)
    let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
    annotation.contents = text
    annotation.font = AnnotationPalette.font(size: 15)
    annotation.fontColor = AnnotationPalette.text
    // Opaque, so it stays readable over the page's own text until it is dragged into place.
    annotation.color = PlatformColor.white
    let border = PDFBorder()
    border.lineWidth = 1
    annotation.border = border
    add([(annotation, page)])
    // Selected straight away, so it can be dragged to where it belongs.
    select(annotation, on: page)
    return true
  }

  /// A stamp to put on a page (FR-ANN-006).
  public enum Stamp: Equatable, Sendable {
    /// A date, written in the reader's locale.
    case date(Date)
    /// A tick.
    case tick
    /// A cross.
    case cross
    /// Any short text, such as initials, "Paid" or "Received".
    case text(String)

    /// What the stamp says.
    public var text: String {
      switch self {
      case .date(let date): date.formatted(date: .long, time: .omitted)
      case .tick: "✓"
      case .cross: "✗"
      case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
  }

  /// Puts a stamp near the top right of a page (FR-ANN-006).
  ///
  /// It is a framed text annotation, which other PDF apps show and can edit. Returns whether it was
  /// placed.
  @discardableResult
  public func addStamp(_ stamp: Stamp, onPage pageIndex: Int) -> Bool {
    let text = stamp.text
    guard !text.isEmpty, text.count <= 60, let page = document.page(at: pageIndex) else { return false }
    let box = page.bounds(for: .cropBox)
    let isMark = stamp == .tick || stamp == .cross
    let fontSize: CGFloat = isMark ? 28 : 16
    let width = min(isMark ? 44 : CGFloat(text.count) * 10 + 28, box.width * 0.6)
    let height = isMark ? 44 : 30.0
    let margin = min(box.width, box.height) * 0.06
    var bounds = CGRect(x: box.maxX - margin - width, y: box.maxY - margin - height, width: width, height: height)
    // A stamp never lands on another annotation: it steps down the right edge until it has room.
    while bounds.minY > box.minY + margin,
      page.annotations.contains(where: { $0.bounds.insetBy(dx: -2, dy: -2).intersects(bounds) })
    {
      bounds.origin.y -= height + 6
    }
    let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
    annotation.contents = text
    annotation.font = AnnotationPalette.font(size: fontSize, bold: true)
    // Text and frame share one colour; PDFKit draws a free-text frame in black.
    annotation.fontColor =
      stamp == .cross ? AnnotationPalette.red : (isMark ? AnnotationPalette.ink : AnnotationPalette.text)
    annotation.alignment = .center
    // A framed stamp is opaque, so it stays readable over whatever the page has there.
    annotation.color = isMark ? .clear : PlatformColor.white
    let border = PDFBorder()
    border.lineWidth = isMark ? 0 : 2
    annotation.border = border
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
    var replaced: [(PDFAnnotation, PDFPage)] = []
    let type = markup.subtype.rawValue.replacingOccurrences(of: "/", with: "")
    for line in selection.selectionsByLine() {
      for page in line.pages {
        var bounds = line.bounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        // Marking text that is already marked the same way never stacks a second layer: marks on the
        // same line that touch the new one are merged into it.
        let touching = page.annotations.filter { existing in
          existing.type == type && Self.isOnSameLine(existing.bounds, bounds)
            && existing.bounds.insetBy(dx: -1, dy: 0).intersects(bounds)
        }
        if touching.contains(where: { $0.bounds.insetBy(dx: -1, dy: -1).contains(bounds) }) { continue }
        for existing in touching {
          bounds = bounds.union(existing.bounds)
          replaced.append((existing, page))
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: markup.subtype, withProperties: nil)
        annotation.color = markup == .highlight ? AnnotationPalette.yellow : AnnotationPalette.red
        added.append((annotation, page))
      }
    }
    guard !added.isEmpty else { return !replaced.isEmpty }
    exchange(removing: replaced, adding: added)
    return true
  }

  /// Whether two marks sit on the same line of text: their heights overlap by more than half.
  static func isOnSameLine(_ first: CGRect, _ second: CGRect) -> Bool {
    let overlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
    return overlap > min(first.height, second.height) / 2
  }

  /// Swaps annotations in one undo step.
  func exchange(removing: [(PDFAnnotation, PDFPage)], adding: [(PDFAnnotation, PDFPage)]) {
    for (annotation, page) in removing { page.removeAnnotation(annotation) }
    for (annotation, page) in adding { page.addAnnotation(annotation) }
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.exchange(removing: adding, adding: removing) }
    }
  }

  func add(_ annotations: [(PDFAnnotation, PDFPage)]) {
    for (annotation, page) in annotations { page.addAnnotation(annotation) }
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.remove(annotations) }
    }
  }

  func remove(_ annotations: [(PDFAnnotation, PDFPage)]) {
    for (annotation, page) in annotations { page.removeAnnotation(annotation) }
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.add(annotations) }
    }
  }
}
