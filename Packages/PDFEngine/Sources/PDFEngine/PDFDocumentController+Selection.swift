import PDFKit

/// An annotation the person selected on a page (F3, FR-ANN-002): what it is, where, and its text.
public struct AnnotationSelection: Equatable, Sendable {
  /// What kind of annotation it is.
  public enum Kind: String, Sendable, CaseIterable {
    /// A highlight.
    case highlight
    /// An underline.
    case underline
    /// A strike-through.
    case strikeThrough
    /// A note.
    case note
    /// Freehand ink, including signatures.
    case ink
    /// A rectangle.
    case rectangle
    /// An oval.
    case oval
    /// A line or arrow.
    case line
    /// A text box or typed signature.
    case textBox
    /// A stamp.
    case stamp
    /// Any other annotation type.
    case other
  }

  /// What kind of annotation it is.
  public let kind: Kind
  /// The zero-based page it is on.
  public let pageIndex: Int
  /// Its text, for notes and text boxes.
  public let text: String?

  /// Whether its text can be edited: notes and text boxes.
  public var isTextEditable: Bool { kind == .note || kind == .textBox }
}

extension PDFDocumentController {
  /// Selects the topmost annotation at a point in page space.
  ///
  /// Clears the selection when there is none, and returns whether one was selected. Form fields, links and pop-ups are not selectable: they are part of how the document works, not
  /// marks on it.
  @discardableResult
  func selectAnnotation(at point: CGPoint, onPage pageIndex: Int) -> Bool {
    guard let page = document.page(at: pageIndex),
      let annotation = page.annotations.last(where: {
        Self.isSelectable($0) && $0.bounds.insetBy(dx: -6, dy: -6).contains(point)
      })
    else {
      clearSelection()
      return false
    }
    selected = (annotation, page)
    selection = AnnotationSelection(
      kind: Self.kind(of: annotation), pageIndex: pageIndex, text: annotation.contents)
    return true
  }

  /// Clears the selection.
  public func clearSelection() {
    selected = nil
    selection = nil
  }

  /// Deletes the selected annotation.
  ///
  /// Undo brings it back. Returns whether one was deleted.
  @discardableResult
  public func deleteSelection() -> Bool {
    guard let selected else { return false }
    remove([(selected.annotation, selected.page)])
    clearSelection()
    return true
  }

  /// Replaces the text of the selected note or text box.
  ///
  /// Undo restores it. Returns whether it changed.
  @discardableResult
  public func setSelectionText(_ text: String) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let selected, let selection, selection.isTextEditable, !text.isEmpty else { return false }
    setContents(text, of: selected.annotation)
    self.selection = AnnotationSelection(kind: selection.kind, pageIndex: selection.pageIndex, text: text)
    return true
  }

  private func setContents(_ text: String?, of annotation: PDFAnnotation) {
    let previous = annotation.contents
    annotation.contents = text
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.setContents(previous, of: annotation) }
    }
  }

  static func isSelectable(_ annotation: PDFAnnotation) -> Bool {
    !["widget", "link", "popup"].contains(annotation.type?.lowercased() ?? "")
  }

  static func kind(of annotation: PDFAnnotation) -> AnnotationSelection.Kind {
    switch annotation.type?.lowercased() {
    case "highlight": .highlight
    case "underline": .underline
    case "strikeout": .strikeThrough
    case "text": .note
    case "ink": .ink
    case "square": .rectangle
    case "circle": .oval
    case "line": .line
    case "freetext": .textBox
    case "stamp": .stamp
    default: .other
    }
  }
}
