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
