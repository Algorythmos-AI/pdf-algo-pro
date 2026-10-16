import PDFKit

/// What Copy or Cut put aside: one annotation, ready to be placed again, in this document or another.
///
/// It stays in the app and is never put on the system pasteboard, so nothing from a document leaves
/// the app this way.
@MainActor
final class AnnotationClipboard {
  /// The one clipboard the app has, shared by every open document.
  static let shared = AnnotationClipboard()

  /// A copy of what was copied or cut, kept apart from any page; `nil` when nothing was.
  var annotation: PDFAnnotation?
}

extension PDFDocumentController {
  /// How far Duplicate puts the copy from the original, in points: right and down.
  static let duplicateOffset = CGSize(width: 16, height: -16)

  /// Whether Copy or Cut has put an annotation aside to paste.
  public var canPasteAnnotation: Bool {
    // Read so that a view showing this is drawn again after Copy or Cut.
    _ = clipboardGeneration
    return AnnotationClipboard.shared.annotation != nil
  }

  /// Copies the selected annotation so that it can be pasted, here or in another document.
  ///
  /// Marks on text are not copied: they belong to the words they mark. Returns whether it was copied.
  @discardableResult
  public func copySelection() -> Bool {
    guard let selected, selection?.isMovable == true, let copy = Self.copy(of: selected.annotation) else {
      return false
    }
    AnnotationClipboard.shared.annotation = copy
    clipboardChanged()
    return true
  }

  /// Copies the selected annotation, then removes it from the page.
  ///
  /// Undo puts it back; what was copied stays copied. Returns whether it was cut.
  @discardableResult
  public func cutSelection() -> Bool {
    guard copySelection() else { return false }
    return deleteSelection()
  }

  /// Puts a copy of the selected annotation beside it and selects the copy, so it can be dragged into place.
  ///
  /// What was copied before is kept. Undo removes the copy. Returns whether one was made.
  @discardableResult
  public func duplicateSelection() -> Bool {
    guard let selected, selection?.isMovable == true, let copy = Self.copy(of: selected.annotation) else {
      return false
    }
    let page = selected.page
    copy.bounds = clamped(
      selected.annotation.bounds.offsetBy(dx: Self.duplicateOffset.width, dy: Self.duplicateOffset.height), to: page)
    add([(copy, page)])
    select(copy, on: page)
    return true
  }

  /// Pastes what was copied, centred on a point in page space and kept on the page.
  ///
  /// The selection is let go of, so that the next tap pastes again. Undo removes what was pasted.
  /// Returns whether something was pasted.
  @discardableResult
  public func pasteAnnotation(at point: CGPoint, onPage pageIndex: Int) -> Bool {
    guard let original = AnnotationClipboard.shared.annotation, let page = document.page(at: pageIndex),
      let copy = Self.copy(of: original)
    else { return false }
    let size = original.bounds.size
    copy.bounds = clamped(
      CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
      to: page)
    clearSelection()
    add([(copy, page)])
    return true
  }

  /// Pastes what was copied in the middle of the page on screen, and selects it so it can be dragged into place.
  ///
  /// For when there is no point to paste at: VoiceOver, Switch Control and a keyboard. Returns whether something was pasted.
  @discardableResult
  public func pasteAnnotationOnCurrentPage() -> Bool {
    guard let page = document.page(at: currentPageIndex) else { return false }
    let box = page.bounds(for: .cropBox)
    guard pasteAnnotation(at: CGPoint(x: box.midX, y: box.midY), onPage: currentPageIndex),
      let pasted = page.annotations.last
    else { return false }
    select(pasted, on: page)
    return true
  }

  /// Whether taps on the page paste what was copied, instead of selecting.
  ///
  /// It starts after Copy or Cut and ends with Done, or when the clipboard is emptied.
  public var isPastingAnnotations: Bool {
    get { isPasting && canPasteAnnotation }
    set {
      isPasting = newValue && canPasteAnnotation
      if isPasting {
        clearSelection()
        // One mode at a time: placing ends drawing, marking and editing text.
        if isDrawing { setDrawing(false) }
        if markupTool != nil { setMarkupTool(nil) }
        if isEditingText { setEditingText(false) }
      }
    }
  }

  /// A copy of an annotation that keeps what it is and how it looks, but no page.
  static func copy(of annotation: PDFAnnotation) -> PDFAnnotation? {
    guard let copy = annotation.copy() as? PDFAnnotation else { return nil }
    // PDFKit copies the drawing's paths as the same objects; the copy gets its own.
    for path in copy.paths ?? [] { copy.remove(path) }
    for path in annotation.paths ?? [] { copy.add(PlatformBezierPath(cgPath: path.cgPath)) }
    return copy
  }

  private func clipboardChanged() {
    clipboardGeneration += 1
  }

  private func clamped(_ rect: CGRect, to page: PDFPage) -> CGRect {
    let box = page.bounds(for: .cropBox)
    var rect = rect
    rect.origin.x = min(max(rect.minX, box.minX), max(box.maxX - rect.width, box.minX))
    rect.origin.y = min(max(rect.minY, box.minY), max(box.maxY - rect.height, box.minY))
    return rect
  }
}
