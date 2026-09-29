import Core
import Foundation
import Observation
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

/// An entry in a document's outline (table of contents).
public struct OutlineItem: Hashable, Sendable, Identifiable {
  /// The entry's title.
  public let title: String
  /// The zero-based page the entry points to.
  public let pageIndex: Int
  /// Nesting depth, zero for top-level entries.
  public let depth: Int

  /// Creates an outline item.
  public init(title: String, pageIndex: Int, depth: Int) {
    self.title = title
    self.pageIndex = pageIndex
    self.depth = depth
  }

  /// A stable identity for lists.
  public var id: String { "\(depth)|\(pageIndex)|\(title)" }
}

/// A text match found by `find(_:)`.
public struct TextMatch: Hashable, Sendable {
  /// The zero-based page of the match.
  public let pageIndex: Int
  /// The matched text as it appears in the document.
  public let text: String
}

/// One open PDF: pages, text, outline, annotations, navigation and saving.
///
/// PDFKit objects are not `Sendable`, so the controller and everything it owns stay on the main
/// actor. It is the only type features use to work with an open document.
@MainActor
@Observable
public final class PDFDocumentController {
  // MARK: - State

  /// The zero-based index of the page on screen.
  public internal(set) var currentPageIndex = 0
  /// Whether the document is still locked by a password.
  public private(set) var isLocked: Bool
  /// Whether there are changes not yet written to disk.
  public private(set) var hasUnsavedChanges = false
  /// How pages are laid out.
  public var displayMode: ReaderDisplayMode = .continuous {
    didSet { view?.apply(displayMode) }
  }

  @ObservationIgnored let document: PDFDocument
  @ObservationIgnored weak var view: PDFReaderHostView?
  @ObservationIgnored private var pendingPageIndex: Int?
  @ObservationIgnored private var password: String?
  @ObservationIgnored private let wasEncrypted: Bool
  /// Undo for every annotation change (FR-EDIT-007).
  @ObservationIgnored public let undoManager = UndoManager()

  // MARK: - Opening

  /// Opens the PDF at a URL.
  ///
  /// - Throws: `PDFEngineError.unreadable` when the file is not a readable PDF.
  public init(url: URL) throws {
    guard let document = PDFDocument(url: url) else { throw PDFEngineError.unreadable }
    self.document = document
    isLocked = document.isLocked
    wasEncrypted = document.isEncrypted
  }

  /// Opens a PDF from data (used by tests and previews).
  ///
  /// - Throws: `PDFEngineError.unreadable` when the data is not a readable PDF.
  public init(data: Data) throws {
    guard let document = PDFDocument(data: data) else { throw PDFEngineError.unreadable }
    self.document = document
    isLocked = document.isLocked
    wasEncrypted = document.isEncrypted
  }

  /// Unlocks an encrypted document; returns whether the password was right.
  @discardableResult
  public func unlock(password: String) -> Bool {
    guard document.unlock(withPassword: password) else { return false }
    self.password = password
    isLocked = false
    view?.reload()
    return true
  }

  // MARK: - Content

  /// The number of pages.
  public var pageCount: Int { document.pageCount }

  /// The text of every page, from the text layer.
  public func pageTexts() -> [PageText] {
    (0..<document.pageCount).map { PageText(pageIndex: $0, text: document.page(at: $0)?.string ?? "") }
  }

  /// The document outline, flattened depth-first.
  public var outline: [OutlineItem] {
    guard let root = document.outlineRoot else { return [] }
    var items: [OutlineItem] = []
    func walk(_ node: PDFOutline, depth: Int) {
      for index in 0..<node.numberOfChildren {
        guard let child = node.child(at: index) else { continue }
        if let page = child.destination?.page {
          items.append(OutlineItem(title: child.label ?? "", pageIndex: document.index(for: page), depth: depth))
        }
        walk(child, depth: depth + 1)
      }
    }
    walk(root, depth: 0)
    return items
  }

  /// Finds text in the document, case- and diacritic-insensitively (FR-READ-003).
  public func find(_ query: String) -> [TextMatch] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    return document.findString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive]).compactMap {
      selection in
      guard let page = selection.pages.first else { return nil }
      return TextMatch(pageIndex: document.index(for: page), text: selection.string ?? trimmed)
    }
  }

  // MARK: - Navigation

  /// Shows a page; out-of-range indices are clamped.
  public func goTo(pageIndex: Int) {
    let clamped = max(0, min(pageIndex, max(0, pageCount - 1)))
    currentPageIndex = clamped
    guard let view, let page = document.page(at: clamped) else {
      pendingPageIndex = clamped
      return
    }
    view.show(page)
  }

  /// Shows a page and selects the passage that supports a citation, if it can be found on that
  /// page; returns whether the passage was found (FR-AI-002).
  @discardableResult
  public func reveal(_ citation: Citation) -> Bool {
    goTo(pageIndex: citation.pageIndex)
    guard let quote = citation.quote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty,
      let page = document.page(at: citation.pageIndex)
    else { return false }
    let match = document.findString(quote, withOptions: [.caseInsensitive, .diacriticInsensitive]).first {
      $0.pages.contains(page)
    }
    guard let match else { return false }
    view?.select(match)
    return true
  }

  func attach(_ view: PDFReaderHostView) {
    self.view = view
    view.apply(displayMode)
    if let pendingPageIndex, let page = document.page(at: pendingPageIndex) {
      view.show(page)
      self.pendingPageIndex = nil
    }
  }

  func pageChanged(to page: PDFPage) {
    currentPageIndex = document.index(for: page)
  }

  // MARK: - Annotations

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

  // MARK: - Saving

  /// Writes the document atomically with coordinated access; a failed save leaves the file unchanged (NFR-REL-002).
  ///
  /// Encrypted documents keep their password.
  ///
  /// - Throws: `PDFEngineError.saveFailed`.
  public func save(to url: URL) throws {
    var options: [PDFDocumentWriteOption: Any] = [:]
    if wasEncrypted, let password {
      options[.userPasswordOption] = password
      options[.ownerPasswordOption] = password
    }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staging) }
    guard document.write(to: staging, withOptions: options), let data = try? Data(contentsOf: staging),
      PDFDocument(data: data) != nil
    else { throw PDFEngineError.saveFailed }
    var coordinationError: NSError?
    var writeError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) {
      target in
      do {
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch {
        writeError = error
      }
    }
    guard coordinationError == nil, writeError == nil else { throw PDFEngineError.saveFailed }
    hasUnsavedChanges = false
  }
}
