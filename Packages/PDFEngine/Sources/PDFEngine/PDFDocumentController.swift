import Core
import Foundation
import Observation
import PDFKit

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
/// actor. It is the only type features use to work with an open document. Annotations and saving
/// are in `PDFDocumentController+Annotations.swift` and `PDFDocumentController+Saving.swift`.
@MainActor
@Observable
public final class PDFDocumentController {
  // MARK: - State

  /// The zero-based index of the page on screen.
  public internal(set) var currentPageIndex = 0
  /// Whether the document is still locked by a password.
  public private(set) var isLocked: Bool
  /// Whether there are changes not yet written to disk.
  public internal(set) var hasUnsavedChanges = false
  /// Whether touches on the page draw ink instead of scrolling and selecting (F2a).
  public internal(set) var isDrawing = false
  /// What a drag draws while drawing is on.
  public internal(set) var drawingTool = DrawingTool.pen
  /// The annotation the person selected, if any (F3).
  public internal(set) var selection: AnnotationSelection?
  /// The selected annotation itself; PDFKit objects stay out of `selection`.
  @ObservationIgnored var selected: (annotation: PDFAnnotation, page: PDFPage)?
  /// How pages are laid out.
  public var displayMode: ReaderDisplayMode = .continuous {
    didSet { view?.apply(displayMode) }
  }

  @ObservationIgnored let document: PDFDocument
  @ObservationIgnored weak var view: PDFReaderHostView?
  /// Called after each stroke is added while drawing, so the reader can save.
  @ObservationIgnored var onInk: (@MainActor () -> Void)?
  @ObservationIgnored private var pendingPageIndex: Int?
  @ObservationIgnored var password: String?
  @ObservationIgnored let wasEncrypted: Bool
  /// Form fields and their values when the document was opened, unlocked or last saved.
  @ObservationIgnored var formValues: [(widget: PDFAnnotation, value: FormValue)] = []
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
    recordFormValues()
  }

  /// Opens a PDF from data (used by tests and previews).
  ///
  /// - Throws: `PDFEngineError.unreadable` when the data is not a readable PDF.
  public init(data: Data) throws {
    guard let document = PDFDocument(data: data) else { throw PDFEngineError.unreadable }
    self.document = document
    isLocked = document.isLocked
    wasEncrypted = document.isEncrypted
    recordFormValues()
  }

  /// Unlocks an encrypted document; returns whether the password was right.
  @discardableResult
  public func unlock(password: String) -> Bool {
    guard document.unlock(withPassword: password) else { return false }
    self.password = password
    isLocked = false
    recordFormValues()
    view?.reload()
    return true
  }

  // MARK: - Content

  /// The number of pages.
  public var pageCount: Int { document.pageCount }

  /// The text of one page, from the text layer; empty when the page has none or does not exist.
  public func pageText(at pageIndex: Int) -> String {
    document.page(at: pageIndex)?.string ?? ""
  }

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

  /// Shows the system find bar, which finds text and moves between matches (FR-READ-003).
  public func showFind() {
    view?.presentFind()
  }

  func attach(_ view: PDFReaderHostView) {
    self.view = view
    view.apply(displayMode)
    view.setDrawing(isDrawing, tool: drawingTool)
    if let pendingPageIndex, let page = document.page(at: pendingPageIndex) {
      view.show(page)
      self.pendingPageIndex = nil
    }
  }

  func pageChanged(to page: PDFPage) {
    currentPageIndex = document.index(for: page)
  }

}
