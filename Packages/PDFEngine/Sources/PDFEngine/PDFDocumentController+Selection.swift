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
  /// Whether it is a drawn signature, so the reader can call it that.
  public var isSignature = false

  /// Whether its text can be edited: notes and text boxes.
  public var isTextEditable: Bool { kind == .note || kind == .textBox }
}

/// One annotation in the document's list of annotations (FR-ANN-003).
public struct AnnotationSummary: Identifiable, Equatable, Sendable {
  /// Its position in the list, stable while the document is unchanged.
  public let id: Int
  /// What kind of annotation it is.
  public let kind: AnnotationSelection.Kind
  /// The zero-based page it is on.
  public let pageIndex: Int
  /// Its text: what a note or text box says, or the words a highlight, underline or strike-through marks.
  public let text: String?
  /// Whether it is a placed signature.
  public let isSignature: Bool

  /// Creates a summary.
  public init(id: Int, kind: AnnotationSelection.Kind, pageIndex: Int, text: String?, isSignature: Bool) {
    self.id = id
    self.kind = kind
    self.pageIndex = pageIndex
    self.text = text
    self.isSignature = isSignature
  }
}

extension PDFDocumentController {
  /// Every annotation a person can see and select, in page order and top to bottom on each page (FR-ANN-003).
  public func annotationSummaries() -> [AnnotationSummary] {
    var summaries: [AnnotationSummary] = []
    for pageIndex in 0..<document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      let annotations = page.annotations.filter(Self.isSelectable).sorted { $0.bounds.maxY > $1.bounds.maxY }
      for annotation in annotations {
        let kind = Self.kind(of: annotation)
        let text: String?
        switch kind {
        case .highlight, .underline, .strikeThrough:
          text = page.selection(for: annotation.bounds)?.string
        case .ink:
          text = nil
        default:
          text = annotation.contents
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        summaries.append(
          AnnotationSummary(
            id: summaries.count, kind: kind, pageIndex: pageIndex, text: trimmed?.isEmpty == false ? trimmed : nil,
            isSignature: kind == .ink && annotation.contents == Self.signatureContents))
      }
    }
    return summaries
  }

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
    let kind = Self.kind(of: annotation)
    selection = AnnotationSelection(
      kind: kind, pageIndex: pageIndex, text: annotation.contents,
      isSignature: kind == .ink && annotation.contents == Self.signatureContents)
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
