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
  /// Whether taps on the page pick existing text to edit, instead of annotations (FR-EDIT-001).
  public internal(set) var isEditingText = false
  /// The existing text the person picked to edit, if any.
  ///
  /// Separate from `selection`, which is for annotations.
  public internal(set) var selectedTextRegion: TextRegionSelection?
  /// A link to outside the document that the person tapped, waiting for them to confirm (T-02).
  public var tappedLink: DocumentLink?
  /// The selected annotation itself; PDFKit objects stay out of `selection`.
  @ObservationIgnored var selected: (annotation: PDFAnnotation, page: PDFPage)? {
    didSet { view?.selectionChanged() }
  }
  /// How pages are laid out.
  public var displayMode: ReaderDisplayMode = .continuous {
    didSet { view?.apply(displayMode) }
  }

  @ObservationIgnored let document: PDFDocument
  @ObservationIgnored weak var view: PDFReaderHostView?
  /// Called after each stroke is added while drawing, so the reader can save.
  @ObservationIgnored var onInk: (@MainActor () -> Void)?
  /// The markup a drag across text applies, while a markup tool is in hand.
  public internal(set) var markupTool: TextMarkup?
  /// Called after a drag has marked some text, so the reader can save.
  @ObservationIgnored var onMarkup: (@MainActor () -> Void)?
  /// Called when a drag or pinch has moved or resized the selected annotation, so the reader can save.
  @ObservationIgnored public var onAnnotationTransformed: (@MainActor () -> Void)?
  @ObservationIgnored private var pendingPageIndex: Int?
  @ObservationIgnored var password: String?
  @ObservationIgnored var wasEncrypted: Bool
  /// A password change waiting for the next save (FR-EDIT-006).
  @ObservationIgnored var pendingProtection: ProtectionChange?
  /// Whether the file was digitally signed when opened or unlocked; saving it in place would break
  /// the signature (plan item H9).
  @ObservationIgnored public private(set) var digitalSignature: DigitalSignatureStatus
  /// Form fields and their values when the document was opened, unlocked or last saved.
  @ObservationIgnored var formValues: [(widget: PDFAnnotation, value: FormValue)] = []
  /// Undo for every annotation change (FR-EDIT-007).
  @ObservationIgnored public let undoManager = UndoManager()
  /// What finds and changes the existing text of a page (ADR-0025).
  @ObservationIgnored let textEditor: any PDFTextEditing
  /// The text found on pages, kept while the page object is unchanged.
  @ObservationIgnored var textPages: [ObjectIdentifier: TextPage] = [:]
  /// Counts changes to which pages the document has, so work that awaited can tell it is out of date.
  @ObservationIgnored var structureGeneration = 0
  /// Pages whose content was edited since the last save, checked again in the staged file.
  @ObservationIgnored var contentEditedPages: [PDFPage] = []
  /// Whether a text edit is being made; a second one waits its turn by being refused.
  @ObservationIgnored var isCommittingText = false
  /// Which links point at which page, found once so that swapping a page does not walk the document.
  @ObservationIgnored var incomingLinks: [ObjectIdentifier: [PDFAnnotation]]?
  /// Roughly how many bytes of replaced pages the undo history is holding on to.
  @ObservationIgnored var textUndoBytes = 0
  /// Searches for pages' text that are running now, so that a second ask joins the first.
  @ObservationIgnored var textSearches: [ObjectIdentifier: (page: PDFPage, work: Task<Bool, Never>)] = [:]
  /// How long finding one page's text may take before the page is reported as taking too long.
  ///
  /// Assumption: 5 seconds is many times what an ordinary page needs on the oldest supported
  /// iPhone; validated in the device test plan.
  @ObservationIgnored var textFindLimit = Duration.seconds(5)
  /// How long making and proving one edit may take before it is refused.
  ///
  /// Assumption: 15 seconds, on the same grounds as `textFindLimit`; proving an edit draws the
  /// page twice, so it is allowed longer.
  @ObservationIgnored var textEditLimit = Duration.seconds(15)
  /// What happened the last time text was looked for or edited, as counts only.
  @ObservationIgnored public internal(set) var textEditingDiagnostics = TextEditingDiagnostics(pageKind: .unreadable)
  /// Called whenever `textEditingDiagnostics` changes, so the app can keep it for a problem report.
  @ObservationIgnored public var onTextEditingDiagnostics: (@MainActor (TextEditingDiagnostics) -> Void)?
  /// The work of finding `incomingLinks`, while it runs.
  @ObservationIgnored var linkIndexing: Task<Void, Never>?

  // MARK: - Opening

  /// Opens the PDF at a URL.
  ///
  /// - Parameters:
  ///   - url: The file.
  ///   - textEditor: What edits existing text; the native editor unless a test or another engine
  ///     replaces it.
  /// - Throws: `PDFEngineError.unreadable` when the file is not a readable PDF.
  public init(url: URL, textEditor: any PDFTextEditing = ContentStreamTextEditor()) throws {
    guard let document = PDFDocument(url: url) else { throw PDFEngineError.unreadable }
    self.document = document
    self.textEditor = textEditor
    isLocked = document.isLocked
    wasEncrypted = document.isEncrypted
    digitalSignature = DigitalSignatureStatus.of(fileAt: url)
    recordFormValues()
  }

  /// Opens a PDF from data (used by tests and previews).
  ///
  /// - Parameters:
  ///   - data: The PDF.
  ///   - textEditor: What edits existing text; the native editor unless a test or another engine
  ///     replaces it.
  /// - Throws: `PDFEngineError.unreadable` when the data is not a readable PDF.
  public init(data: Data, textEditor: any PDFTextEditing = ContentStreamTextEditor()) throws {
    guard let document = PDFDocument(data: data) else { throw PDFEngineError.unreadable }
    self.document = document
    self.textEditor = textEditor
    isLocked = document.isLocked
    wasEncrypted = document.isEncrypted
    digitalSignature = DigitalSignatureStatus.of(data: data)
    recordFormValues()
  }

  /// Unlocks an encrypted document; returns whether the password was right.
  @discardableResult
  public func unlock(password: String) -> Bool {
    guard document.unlock(withPassword: password) else { return false }
    self.password = password
    isLocked = false
    // A locked file's signature fields cannot be read, so the status is worked out again now.
    if let pdf = document.documentRef { digitalSignature = DigitalSignatureStatus.of(pdf) }
    structureGeneration += 1
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
        // An entry for a page no longer in the document (deleted since) is left out.
        if let page = child.destination?.page, case let index = document.index(for: page), index != NSNotFound {
          items.append(OutlineItem(title: child.label ?? "", pageIndex: index, depth: depth))
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

  /// Lets go of a view that now shows another controller's document.
  func detach(_ view: PDFReaderHostView) {
    if self.view === view { self.view = nil }
  }

  func pageChanged(to page: PDFPage) {
    currentPageIndex = document.index(for: page)
  }

}
