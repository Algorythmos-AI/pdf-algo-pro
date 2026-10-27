import Core
import Foundation
import Observation
import PDFEngine

/// What the assistant needs from the open document, handed to the view the app composes.
public struct ReaderAssistantContext {
  /// The task to start with.
  public let task: AssistantTask
  /// The document's page texts.
  public let pages: () async -> [PageText]
  /// Opens a cited page and highlights the passage.
  public let reveal: (Citation) -> Void
  /// Closes the assistant and then opens the subscription offer, when the day's requests are used.
  public let seePlans: () -> Void
}

/// A saved document file offered to the share sheet.
public struct SharedFile: Identifiable, Equatable {
  /// The file.
  public let url: URL
  /// Whether the share sheet may offer Print.
  public let allowsPrinting: Bool
  /// The file's identity.
  public var id: URL { url }
}

/// One open document (FR-READ-001 to FR-READ-006, FR-ANN-001, FR-SCAN-003).
@MainActor
@Observable
public final class ReaderModel {
  /// What the reader is showing.
  public enum Phase: Equatable {
    /// Opening the file.
    case loading
    /// The document needs its password.
    case locked(wrongPassword: Bool)
    /// Pages are shown.
    case ready
    /// The file could not be opened; the message says so plainly.
    case failed(String)
  }

  // MARK: - State

  /// What is shown.
  public private(set) var phase: Phase = .loading
  /// The open document, once loaded.
  public private(set) var controller: PDFDocumentController?
  /// The library entry.
  public private(set) var document: Document?
  /// The document's file, once loaded.
  public private(set) var fileURL: URL?
  /// Recognition progress from 0 to 1 while text is being recognised; `nil` otherwise.
  public var recognitionProgress: Double? {
    recognition.progress[documentID] ?? (isPreparingRecognition ? 0 : nil)
  }
  /// Saving before recognition starts, so progress shows at once.
  private var isPreparingRecognition = false
  /// The page shown when recognition replaced the file, where the searchable version opens.
  @ObservationIgnored private var pageBeforeRecognition: Int?
  /// A message for the last failed action.
  public var errorMessage: String?
  /// A notice that an action did something other than the obvious, such as making a new document, or
  /// that the document was updated with another app's changes.
  public var notice: String?
  /// Whether another app changed the file while this reader had unsaved changes, so the person
  /// chooses which version to keep (plan item H5).
  public var hasConflictingChange = false
  /// Hears when another app changes the file.
  @ObservationIgnored private var watcher: FileWatcher?
  /// The file as this reader last read or wrote it, to tell another app's changes from its own.
  @ObservationIgnored private var knownVersion: FileVersion?
  /// The assistant sheet, when open.
  public var assistantTask: AssistantTask?
  /// A citation to open once the assistant sheet has finished closing.
  @ObservationIgnored private var pendingReveal: Citation?
  /// Whether the outline sheet is open.
  public var showsOutline = false
  /// Whether the page grid is open.
  public var showsPages = false
  /// Whether the list of annotations is open (FR-ANN-003).
  public var showsAnnotations = false
  /// A page chosen in the outline or the page grid, opened once its sheet has finished closing.
  @ObservationIgnored private var pendingPageIndex: Int?
  /// Whether the signature sheet is open (F1c).
  public var showsSignatures = false
  /// Saved signatures, oldest first, once loaded.
  public private(set) var savedSignatures: [SavedSignature] = []
  /// Whether "Go to page" is asking for a page number.
  public var showsGoToPage = false
  /// The saved file the share sheet is showing, if it is open.
  public var sharing: SharedFile?
  /// Whether the version from before the last save is kept and can be restored (FR-EDIT-008, first step).
  public private(set) var canRestorePreviousVersion = false
  /// Whether there is an annotation change to undo.
  public private(set) var canUndo = false
  /// Whether there is an undone annotation change to redo.
  public private(set) var canRedo = false
  /// Read aloud.
  public let speech: SpeechReader

  /// The document being read.
  ///
  /// For a digitally signed document it becomes the copy the changes are saved in, once there is one.
  private var documentID: DocumentID
  /// Whether this reader has moved from a signed document to the copy its changes are saved in.
  private var isEditingCopy = false
  /// The document this reader's version was kept in while another app's change waited for the
  /// person's choice, so it is kept once per conflict (#257).
  @ObservationIgnored private var conflictCopy: Task<Document?, Never>?
  /// Whether another app's change waits for the person's choice, so nothing is written over it.
  ///
  /// The alert's binding can't clear it: only showing the file as it is on disk does (#257).
  @ObservationIgnored private var conflictWaits = false
  /// The title of the copy this reader's changes were last kept in while a conflict waited.
  private var changesKeptIn: String?
  /// How many saves are waiting for the one before them to finish (#233).
  private(set) var savesWaiting = 0
  /// The save being made, which the next save waits for (#233).
  @ObservationIgnored private var saving: Task<Bool, Never>?
  private let startPage: Int?
  private let library: any DocumentLibrary
  private let intake: DocumentIntake
  private let index: any DocumentIndexing
  private let settings: any SettingsStoring
  /// Whether the reader's newer controls are part of this build.
  ///
  /// They are the strip of small pages, the zoom limits and the keyboard commands
  /// (`ReleaseFlag.readingControls`). Off, the reader is as it was before them.
  public let offersReadingControls: Bool
  /// Whether the person wants the strip of small pages; whether it shows is `showsPageStrip`.
  public private(set) var wantsPageStrip = true
  private let telemetry: any TelemetryRecording
  private let recognition: RecognitionCoordinator
  private let signatures: any SignatureStoring
  private let textEditing: any TextEditingAccessProviding
  /// What finds and changes existing text: the native editor unless a test or another engine is
  /// given (ADR-0025).
  private let textEditor: any PDFTextEditing
  /// Where counts about text editing go, for a problem report; nothing from the document.
  private let textEditingDiagnostics: TextEditingDiagnosticsLog?

  /// Creates a reader for a document.
  ///
  /// Editing existing text is hidden unless `textEditing` says otherwise: the app decides whether a
  /// build and a person have it, and the reader only asks.
  public init(
    selection documentID: DocumentID, pageIndex: Int? = nil, task: AssistantTask? = nil, library: any DocumentLibrary,
    intake: DocumentIntake, index: any DocumentIndexing, settings: any SettingsStoring,
    telemetry: any TelemetryRecording,
    recognition: RecognitionCoordinator, signatures: any SignatureStoring, speech: SpeechReader = SpeechReader(),
    textEditing: any TextEditingAccessProviding = FixedTextEditingAccess(.hidden),
    textEditingDiagnostics: TextEditingDiagnosticsLog? = nil,
    textEditor: any PDFTextEditing = ContentStreamTextEditor(), readingControls: Bool = false
  ) {
    offersReadingControls = readingControls
    self.textEditor = textEditor
    self.textEditing = textEditing
    self.textEditingDiagnostics = textEditingDiagnostics
    self.documentID = documentID
    startPage = pageIndex
    assistantTask = task
    self.library = library
    self.intake = intake
    self.index = index
    self.settings = settings
    self.telemetry = telemetry
    self.recognition = recognition
    self.signatures = signatures
    self.speech = speech
  }

  // MARK: - Opening

  /// Opens the file at the page asked for, or where the user left off (FR-READ-006).
  public func load() async {
    // To the reader being ready on its first page; drawing it is PDFKit's work after this.
    let interval = Signposts.begin("Document.FirstPage")
    defer { interval.end() }
    // A document that is shown again starts with no tool in hand: the page it had is gone.
    controller?.setMarkupTool(nil)
    controller?.isPastingAnnotations = false
    watchRecognition()
    canRestorePreviousVersion = await library.hasPreviousVersion(of: documentID)
    do {
      guard let document = try await library.document(withID: documentID) else {
        phase = .failed(String(localized: "This document is no longer in the library.", bundle: .module))
        return
      }
      self.document = document
      let url = try await library.fileURL(for: documentID)
      fileURL = url
      let controller = try PDFDocumentController(url: url, textEditor: textEditor)
      knownVersion = FileVersion.current(at: url)
      // The reader shows the file as it is on disk, so no other version waits to be chosen, and the
      // next conflict gets a copy of its own (#257). The question is cleared too: hearing of the other
      // app's write again while the choice was being carried out asks it again.
      conflictWaits = false
      hasConflictingChange = false
      conflictCopy = nil
      changesKeptIn = nil
      watch(url)
      let stored = settings.load()
      controller.displayMode = stored.readerDisplayMode
      if offersReadingControls {
        controller.limitsZoom = true
        wantsPageStrip = stored.showsPageStrip
      }
      controller.onAnnotationTransformed = { [weak self] in
        Task { await self?.annotationTransformed() }
      }
      controller.onTextMoveRequested = { [weak self] selection, offset in
        Task { await self?.moveText(selection, by: offset) }
      }
      if let log = textEditingDiagnostics {
        controller.onTextEditingDiagnostics = { record in log.record(record) }
      }
      self.controller = controller
      if controller.isLocked {
        phase = .locked(wrongPassword: false)
      } else {
        show(controller)
      }
      if document.lastOpenedAt == nil { await telemetry.record("activation.first_document.opened") }
    } catch {
      phase = .failed(
        String(
          localized: "This file can't be opened. It may be damaged or not a PDF. Your library hasn't changed.",
          bundle: .module))
    }
  }

  /// Unlocks a password-protected document.
  public func unlock(password: String) {
    guard let controller else { return }
    if controller.unlock(password: password) {
      show(controller)
    } else {
      phase = .locked(wrongPassword: true)
    }
  }

  private func show(_ controller: PDFDocumentController) {
    phase = .ready
    bookmarkedPages = controller.bookmarkedPages
    controller.goTo(pageIndex: startPage ?? document?.lastPageIndex ?? 0)
    Task { textEditingAccess = await textEditing.textEditingAccess() }
  }

  // MARK: - Reading

  /// The page indicator text, "3 of 12".
  public var pageLabel: String {
    guard let controller else { return "" }
    return String(localized: "\(controller.currentPageIndex + 1) of \(controller.pageCount)", bundle: .module)
  }

  /// Switches between continuous and single-page layout, and remembers it.
  public func setDisplayMode(_ mode: ReaderDisplayMode) {
    controller?.displayMode = mode
    var current = settings.load()
    current.readerDisplayMode = mode
    settings.save(current)
  }

  /// Shows or hides the strip of small pages, and remembers it.
  public func setWantsPageStrip(_ isWanted: Bool) {
    guard offersReadingControls else { return }
    wantsPageStrip = isWanted
    var current = settings.load()
    current.showsPageStrip = isWanted
    settings.save(current)
  }

  /// Whether the strip of small pages is on screen now.
  ///
  /// Only while reading: with a tool in hand, text being edited or something selected, the bottom
  /// of the reader belongs to that. A one-page document has nowhere to go.
  public var showsPageStrip: Bool {
    guard offersReadingControls, wantsPageStrip, let controller, controller.pageCount > 1 else { return false }
    return !controller.isDrawing && markupTool == nil && !controller.isEditingText && selection == nil
  }

  /// Goes to the page a person typed, counting from 1 (FR-READ-002); says so when there is no such page.
  @discardableResult
  public func goToPage(_ text: String) -> Bool {
    guard let controller else { return false }
    guard let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), (1...controller.pageCount) ~= number
    else {
      errorMessage = String(
        localized: "Enter a page number from 1 to \(controller.pageCount).", bundle: .module)
      return false
    }
    controller.goTo(pageIndex: number - 1)
    return true
  }

  /// Records the reading position; called when the page changes and when the reader closes.
  public func recordPosition() async {
    guard let controller, phase == .ready else { return }
    try? await library.recordOpened(documentID, pageIndex: controller.currentPageIndex)
  }

  /// Reads aloud from the page on screen to the end of the document, or stops (FR-READ-004, FR-READ-008).
  ///
  /// The pages turn as it goes, so starting again carries on from the page on screen.
  public func toggleReadAloud() {
    guard let controller else { return }
    if speech.isSpeaking {
      speech.stop()
    } else {
      // Each page's text is taken when it is reached, so a long document is never extracted up front.
      speech.read(
        from: controller.currentPageIndex, pageCount: controller.pageCount,
        text: { [weak controller] in controller?.pageText(at: $0) ?? "" },
        onPage: { [weak controller] in controller?.goTo(pageIndex: $0) })
    }
  }

  // MARK: - Annotating

  /// Marks up the selected text and saves; returns whether anything was marked.
  ///
  /// With nothing selected, the markup becomes the tool in hand (`markupTool`): each piece of text
  /// the person selects next is marked, until they tap Done.
  @discardableResult
  public func markUpSelection(_ markup: TextMarkup) async -> Bool {
    guard let controller, checkAnnotatingIsAllowed(controller) else { return false }
    guard controller.markUpSelection(markup) else {
      startMarkupTool(markup)
      return false
    }
    controller.clearTextSelection()
    updateUndoState()
    await save()
    return true
  }

  /// The markup applied to text as it is selected, or `nil` when no markup tool is in hand.
  ///
  /// Read from the document, so that another mode ending it (placing a stamp) is seen here too.
  public var markupTool: TextMarkup? { controller?.markupTool }

  /// Takes a markup tool in hand: dragging across text marks it, until Done.
  public func startMarkupTool(_ markup: TextMarkup) {
    guard let controller, checkAnnotatingIsAllowed(controller) else { return }
    controller.clearTextSelection()
    controller.setMarkupTool(markup) { [weak self] in
      self?.updateUndoState()
      Task { await self?.save() }
    }
  }

  /// Puts the markup tool down.
  public func stopMarkupTool() {
    controller?.setMarkupTool(nil)
  }

  /// Adds a note to the current page and saves.
  public func addNote(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let controller, !trimmed.isEmpty, checkAnnotatingIsAllowed(controller) else { return }
    controller.addNote(trimmed, onPage: controller.currentPageIndex)
    updateUndoState()
    await save()
  }

  /// Undoes the last change and saves.
  ///
  /// Not while a text edit is being made or typed: the edit in hand is finished or cancelled first.
  public func undo() async {
    guard let controller, controller.undoManager.canUndo, !isBusyEditingText else { return }
    controller.undoManager.undo()
    updateUndoState()
    // Only undoing or redoing a text edit changes the words that search finds.
    if controller.hasUnsavedTextEdits { textChangedSinceIndexing = true }
    await save()
  }

  /// Redoes the last undone change and saves.
  public func redo() async {
    guard let controller, controller.undoManager.canRedo, !isBusyEditingText else { return }
    controller.undoManager.redo()
    updateUndoState()
    // Only undoing or redoing a text edit changes the words that search finds.
    if controller.hasUnsavedTextEdits { textChangedSinceIndexing = true }
    await save()
  }

  /// Whether touches on the page draw ink (F2a).
  public var isDrawing: Bool { controller?.isDrawing ?? false }

  /// What a drag draws while drawing is on.
  public var drawingTool: DrawingTool { controller?.drawingTool ?? .pen }

  /// Starts or stops drawing; each stroke is saved and can be undone.
  public func setDrawing(_ isDrawing: Bool, tool: DrawingTool = .pen) {
    guard let controller else { return }
    if isDrawing, !checkAnnotatingIsAllowed(controller) { return }
    controller.setDrawing(isDrawing, tool: tool) { [weak self] in
      Task { await self?.inkAdded() }
    }
  }

  // MARK: - Organising pages (FR-ORG-001)

  /// Whether the document's author allows its pages to be organised.
  public var allowsOrganizing: Bool { controller?.allowsOrganizing ?? false }

  /// Rotates pages by 90 degrees, clockwise or not, and saves.
  public func rotatePages(_ pages: IndexSet, clockwise: Bool) async {
    guard let controller, checkOrganizingIsAllowed(controller) else { return }
    guard controller.rotatePages(pages, by: clockwise ? 90 : -90) else { return }
    await pagesChanged()
  }

  /// Deletes pages and saves; at least one page always stays.
  public func deletePages(_ pages: IndexSet) async {
    guard let controller, checkOrganizingIsAllowed(controller) else { return }
    guard controller.deletePages(pages) else {
      errorMessage = String(localized: "A document needs at least one page.", bundle: .module)
      return
    }
    await pagesChanged()
  }

  /// Moves a page one place earlier or later and saves.
  ///
  /// - Returns: The page's new position, or `nil` when it couldn't move.
  @discardableResult
  public func movePage(_ page: Int, earlier: Bool) async -> Int? {
    guard let controller, checkOrganizingIsAllowed(controller) else { return nil }
    let target = earlier ? page - 1 : page + 1
    guard controller.movePage(from: page, to: target) else { return nil }
    await pagesChanged()
    return target
  }

  /// Copies pages into a new document in the library; this document is unchanged.
  public func extractPages(_ pages: IndexSet) async {
    guard let controller, checkOrganizingIsAllowed(controller) else { return }
    do {
      let data = try controller.extractPages(pages)
      let title = document?.title ?? ""
      let copy = try await intake.add(data: data, title: String(localized: "\(title) (pages)", bundle: .module))
      notice = String(localized: "The pages are in a new document, “\(copy.title)”.", bundle: .module)
    } catch {
      errorMessage = String(localized: "Couldn't copy those pages. The document hasn't changed.", bundle: .module)
    }
  }

  private func pagesChanged() async {
    updateUndoState()
    await save()
  }

  private func checkOrganizingIsAllowed(_ controller: PDFDocumentController) -> Bool {
    guard controller.allowsOrganizing else {
      errorMessage = String(localized: "This document's author doesn't allow its pages to be changed.", bundle: .module)
      return false
    }
    return true
  }

  // MARK: - Editing annotations
  // MARK: - Editing annotations

  /// The annotation the person selected on the page, if any (F3, FR-ANN-002).
  public var selection: AnnotationSelection? { controller?.selection }

  /// Deletes the selected annotation and saves; undo brings it back.
  public func deleteSelection() async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.deleteSelection() else { return }
    updateUndoState()
    await save()
  }

  /// Replaces the text of the selected note or text box and saves.
  public func setSelectionText(_ text: String) async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.setSelectionText(text) else { return }
    updateUndoState()
    await save()
  }

  /// Moves the selected annotation by an offset in page space and saves (FR-ANN-005).
  public func moveSelection(by offset: CGSize) async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.moveSelection(by: offset) else { return }
    await annotationTransformed()
  }

  /// Scales the selected annotation and saves (FR-ANN-005).
  public func resizeSelection(by factor: CGFloat) async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.resizeSelection(by: factor) else { return }
    await annotationTransformed()
  }

  /// Gives the selected annotation a new colour and saves (FR-ANN-005).
  public func setSelectionColor(_ color: AnnotationColor) async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.setSelectionColor(color) else { return }
    await annotationTransformed()
  }

  private func annotationTransformed() async {
    updateUndoState()
    await save()
  }

  /// Clears the selection.
  public func clearSelection() {
    controller?.clearSelection()
  }

  // MARK: Copy and paste

  /// Whether Copy or Cut has put an annotation aside to paste.
  public var canPasteAnnotation: Bool { controller?.canPasteAnnotation ?? false }

  /// Whether taps on the page paste what was copied, until Done.
  public var isPastingAnnotations: Bool { controller?.isPastingAnnotations ?? false }

  /// Copies the selected annotation, then lets each tap on a page paste it.
  public func copySelection() {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.copySelection() else { return }
    controller.isPastingAnnotations = true
  }

  /// Cuts the selected annotation and saves, then lets each tap on a page paste it.
  public func cutSelection() async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.cutSelection() else { return }
    controller.isPastingAnnotations = true
    updateUndoState()
    await save()
  }

  /// Puts a copy of the selected annotation beside it, selected, and saves.
  public func duplicateSelection() async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.duplicateSelection() else { return }
    updateUndoState()
    await save()
  }

  /// Lets each tap on a page paste what was copied, or stops it.
  public func setPastingAnnotations(_ isOn: Bool) {
    guard let controller else { return }
    if isOn, !checkAnnotatingIsAllowed(controller) { return }
    controller.isPastingAnnotations = isOn
  }

  /// Pastes what was copied in the middle of the page on screen and saves; for VoiceOver and Switch Control.
  public func pasteAnnotationOnCurrentPage() async {
    guard let controller, checkAnnotatingIsAllowed(controller), controller.pasteAnnotationOnCurrentPage() else {
      return
    }
    controller.isPastingAnnotations = false
    updateUndoState()
    await save()
  }

  /// Whether a stamp's text (initials, "Paid" and the like) is being asked for.
  public var isAddingStampText = false

  /// Picks up a stamp (FR-ANN-006): each tap on a page then puts it where the finger lands, until Done.
  ///
  /// Nothing is placed until a tap, so nothing has to be dragged from a corner into place.
  public func addStamp(_ stamp: PDFDocumentController.Stamp) async {
    guard let controller, checkAnnotatingIsAllowed(controller) else { return }
    controller.clearSelection()
    controller.pickUpStamp(stamp)
  }

  /// The bookmarked pages, kept in the file's outline (FR-READ-009).
  public private(set) var bookmarkedPages: [Int] = []

  /// Whether the page on screen is bookmarked.
  public var isCurrentPageBookmarked: Bool {
    guard let controller else { return false }
    return bookmarkedPages.contains(controller.currentPageIndex)
  }

  /// Bookmarks the page on screen, or removes its bookmark, and saves (FR-READ-009).
  public func toggleBookmark() async {
    guard let controller, checkAnnotatingIsAllowed(controller) else { return }
    controller.toggleBookmark(onPage: controller.currentPageIndex)
    bookmarkedPages = controller.bookmarkedPages
    updateUndoState()
    await save()
  }

  /// Adds a text box to the page on screen and saves (F2b).
  public func addTextBox(_ text: String) async {
    guard let controller, checkAnnotatingIsAllowed(controller),
      controller.addTextBox(text, onPage: controller.currentPageIndex)
    else { return }
    updateUndoState()
    await save()
  }

  private func inkAdded() async {
    updateUndoState()
    await save()
  }

  // MARK: - Editing existing text (FR-EDIT-001)

  /// What the reader says about the text in hand or the page on screen while editing text.
  public enum TextEditMessage: Equatable, Sendable {
    /// The page is an image, such as a scan: it has no text of its own to edit.
    case pageIsImage
    /// The page could not be read safely, so nothing on it is offered.
    case pageNotEditable
    /// The new text does not fit where the old text is.
    case tooLong
    /// The new text has characters that cannot be drawn there, or is empty.
    case unsupportedCharacters
    /// The text cannot be changed; nothing was changed.
    case cannotEdit
    /// The font will be matched as closely as possible.
    case fontMatched
    /// The text can only be covered; the original stays in the file underneath.
    case coversOriginal
    /// The same, in a few words: said for each such text after the first, which got the whole
    /// sentence.
    case coversOriginalBriefly
    /// The page's text is still being found.
    case lookingForText
    /// The page has text, but none of it can be edited or covered.
    case noEditableText
    /// Finding the text or making the edit took too long; nothing was changed.
    case tookTooLong
    /// Text was dropped where something else is, or where it does not fit; nothing was moved.
    case somethingInTheWay
    /// The text can be neither changed nor covered where it is; nothing was changed, and the only
    /// thing left to do is close the editor.
    case cannotEditOrCover
  }

  /// Something the reader did while editing text that the person must be told, and can undo.
  public enum TextEditNotice: Equatable, Sendable {
    /// The typed text was placed over the old text, because the old text could not be changed.
    /// The old text is still in the file.
    case coveredInstead
  }

  /// Whether editing existing text is offered in this build and to this person.
  public private(set) var textEditingAccess = TextEditingAccess.hidden
  /// Whether taps on the page pick existing text to edit.
  public var isEditingText: Bool { controller?.isEditingText ?? false }
  /// The existing text the person picked, if any.
  ///
  /// Separate from `selection`, which is an annotation.
  public var selectedTextRegion: TextRegionSelection? { controller?.selectedTextRegion }
  /// What to say about the page or the text in hand, if anything.
  public private(set) var textEditMessage: TextEditMessage?
  /// What the reader did that the person must know; it stays until they dismiss it, undo it, pick
  /// other text or leave text editing.
  public private(set) var textEditNotice: TextEditNotice?
  /// Whether an edit is being worked out and proven; the editor waits.
  public private(set) var isCommittingTextEdit = false
  /// Whether another app's change was heard while an edit was being worked out, to look at once it ends.
  @ObservationIgnored private var heardFileChangeWhileEditing = false
  /// Whether the person is being asked to confirm editing a digitally signed document.
  public var confirmsEditingSigned = false
  /// Whether the explanation that editing text needs a purchase is showing.
  public var showsTextEditingLocked = false
  /// Opens the subscription offer from that explanation; `nil` where there is none to open.
  @ObservationIgnored public var onSeePlans: (() -> Void)?
  /// Opens the subscription offer because the day's free requests are used.
  @ObservationIgnored public var onAllowanceUsed: (() -> Void)?
  /// Whether to open the offer once the assistant's sheet has closed: two sheets are never up at once.
  @ObservationIgnored private var opensPlansAfterAssistant = false
  /// Whether the person has agreed, in this reader, to edit a signed document in a copy.
  private var hasConfirmedEditingSigned = false
  /// Whether the document's words changed since the search text was last brought up to date.
  private var textChangedSinceIndexing = false
  /// Whether, in this reader, the person has been told a font will be matched, and that text
  /// will be covered, and has picked any text at all.
  private var hasExplainedFontMatching = false
  private var hasExplainedCovering = false
  private var hasPickedText = false
  /// Counts looks at a page's text, so an answer about a page that is no longer the question is dropped.
  private var textSearches = 0

  /// Whether a text edit is being typed or made, so other changes wait.
  private var isBusyEditingText: Bool { isCommittingTextEdit || selectedTextRegion != nil }

  /// Whether the tip that points at Edit may show: only when a tap on Edit would let the person
  /// start editing at once, and nothing else is on screen over the page.
  ///
  /// A locked or hidden feature is never advertised, and a document that would answer with a
  /// refusal or a question (restricted, signed) is not where to learn the button.
  public var offersEditTip: Bool {
    guard phase == .ready, textEditingAccess == .available, let controller,
      controller.textEditability == .editable
    else { return false }
    return !controller.isDrawing && markupTool == nil && !controller.isEditingText && selection == nil
      && !isPresenting
  }

  /// Whether a sheet, alert or dialog the reader owns is up, or about to be.
  private var isPresenting: Bool {
    errorMessage != nil || assistantTask != nil || sharing != nil || showsOutline || showsPages || showsAnnotations
      || showsSignatures || showsGoToPage || isAddingStampText || confirmsEditingSigned || showsTextEditingLocked
      || showsVersions || isAddingPassword || confirmsPasswordRemoval
  }

  /// Whether the page on screen has text that Edit would outline.
  ///
  /// A scan answers Edit with "this page is an image", which is no first impression to point at.
  public func currentPageHasEditableText() async -> Bool {
    guard let controller else { return false }
    let text = await controller.pageText(onPage: controller.currentPageIndex)
    return text.kind == .text && !text.regions.isEmpty
  }

  /// Enters text editing, or says why it cannot be entered.
  ///
  /// Access is asked for each time, because a purchase can come or go while the document is open.
  public func beginTextEditing() async {
    guard let controller, phase == .ready else { return }
    textEditingAccess = await textEditing.textEditingAccess()
    switch textEditingAccess {
    case .hidden:
      return
    case .locked:
      showsTextEditingLocked = true
      return
    case .available:
      break
    }
    switch controller.textEditability {
    case .restricted:
      errorMessage = Self.restrictedMessage
    case .signed where !hasConfirmedEditingSigned && !isEditingCopy:
      confirmsEditingSigned = true
    case .signed, .editable:
      // The person has found Edit; the tip that points at it has done its work.
      EditTextTip.markUsed()
      stopMarkupTool()
      controller.setEditingText(true)
      await textEditingPageChanged()
    }
  }

  /// Carries on into text editing after the person agreed to edit a signed document in a copy.
  public func confirmEditingSigned() async {
    hasConfirmedEditingSigned = true
    await beginTextEditing()
  }

  /// Leaves text editing.
  ///
  /// Anything typed and not committed is dropped; the document is unchanged by it.
  public func endTextEditing() async {
    guard let controller, controller.isEditingText else { return }
    controller.setEditingText(false)
    textEditMessage = nil
    textEditNotice = nil
    lookAtFileChangeHeardWhileEditing()
    await refreshSearchTextIfNeeded()
  }

  /// Works out what to say about the page on screen: nothing when it has text to edit.
  ///
  /// The reader is never silent about a page it cannot offer: while the text is being found for
  /// longer than a moment it says so, and afterwards it says when there is nothing to tap.
  public func textEditingPageChanged() async {
    guard let controller, controller.isEditingText, controller.selectedTextRegion == nil else { return }
    let page = controller.currentPageIndex
    textSearches += 1
    let search = textSearches
    // Most pages are found at once; saying "looking" for those would only flicker.
    let notice = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard let self, !Task.isCancelled, self.textSearches == search, self.controller === controller,
        controller.isEditingText, controller.selectedTextRegion == nil
      else { return }
      self.textEditMessage = .lookingForText
    }
    let text = await controller.pageText(onPage: page)
    notice.cancel()
    guard self.controller === controller, controller.isEditingText, controller.currentPageIndex == page,
      controller.selectedTextRegion == nil, textSearches == search
    else { return }
    switch text.kind {
    case .text: textEditMessage = text.regions.isEmpty ? .noEditableText : nil
    case .image: textEditMessage = .pageIsImage
    case .unreadable: textEditMessage = .pageNotEditable
    case .tookTooLong: textEditMessage = .tookTooLong
    }
  }

  /// What to tell the person about the text they just picked, before they type.
  public func textRegionPicked() {
    guard let region = selectedTextRegion?.region else { return }
    textEditNotice = nil
    hasPickedText = true
    // An explanation is given once. Said again at every line it reads as nagging (a tester's
    // report, 2026-10-06). That a text will be covered is still said each time, because it
    // changes what Done does, but in a few words after the first.
    switch region.capability {
    case .direct: textEditMessage = nil
    case .limited:
      textEditMessage = hasExplainedFontMatching ? nil : .fontMatched
      hasExplainedFontMatching = true
    case .visualReplacementOnly:
      textEditMessage = hasExplainedCovering ? .coversOriginalBriefly : .coversOriginal
      hasExplainedCovering = true
    }
  }

  /// Whether to show how to start editing: only until the person has picked some text once.
  public var showsTextEditStartHint: Bool { !hasPickedText }

  /// Makes the edit the person typed, proves it and saves.
  ///
  /// Returns whether the text was changed.
  ///
  /// When it was not, `textEditMessage` says why and the editor stays open with what was typed, so
  /// nothing is lost. Text that can only be covered is covered, which the editor said before Done.
  @discardableResult
  public func commitTextEdit(_ replacement: String) async -> Bool {
    guard let controller, let selection = controller.selectedTextRegion, !isCommittingTextEdit else { return false }
    // A soft hyphen, a zero-width space or a direction mark comes with words pasted from a web
    // page and cannot be seen; it is left out rather than refused (issue #231).
    let typed = Self.withoutInvisibleCharacters(replacement).trimmingCharacters(in: .whitespacesAndNewlines)
    guard typed != selection.region.text else {
      cancelTextEdit()
      return false
    }
    isCommittingTextEdit = true
    defer { endCommittingTextEdit() }
    let outcome: TextEditOutcome
    if selection.region.capability.editsContent {
      outcome = await controller.replaceSelectedText(with: typed)
    } else {
      outcome = controller.coverSelectedText(with: typed)
    }
    // The document may have been reloaded while the edit was worked out; that edit is gone with it.
    guard self.controller === controller else { return false }
    switch outcome {
    case .edited(let mode):
      textEditMessage = nil
      updateUndoState()
      // Covered text is still what the page reads as, so the search text is unchanged by it.
      if mode != .visualReplacement { textChangedSinceIndexing = true }
      await save()
      await textEditingPageChanged()
      return true
    case .tooLong:
      textEditMessage = .tooLong
    case .refused(.unsupportedCharacters):
      textEditMessage = .unsupportedCharacters
    case .refused(.restricted):
      controller.clearTextRegionSelection()
      errorMessage = Self.restrictedMessage
    case .refused(.timedOut):
      textEditMessage = .tookTooLong
    case .refused(let refusal) where refusal.meansNotEditableInPlace && selection.region.capability.editsContent:
      // The words could not be changed in the page. The person is never left with typing that
      // goes nowhere: their text covers the old text instead, and the reader says so.
      return await coverInstead(of: selection, with: typed, in: controller)
    case .refused(.stale):
      // The page changed underneath; Done again works on the page as it is now.
      textEditMessage = .cannotEdit
    case .refused:
      textEditMessage = .cannotEditOrCover
    }
    return false
  }

  /// Ends working out an edit, and then looks at another app's change heard meanwhile (#249).
  private func endCommittingTextEdit() {
    isCommittingTextEdit = false
    guard heardFileChangeWhileEditing else { return }
    heardFileChangeWhileEditing = false
    Task { await fileChangedOnDisk() }
  }

  /// The text with every character no one sees taken out (issue #231).
  static func withoutInvisibleCharacters(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }))
  }

  /// Finishes an edit that could not be made in the page's content by covering the text.
  private func coverInstead(
    of selection: TextRegionSelection, with typed: String, in controller: PDFDocumentController
  ) async -> Bool {
    if controller.selectedTextRegion == nil {
      controller.selectTextRegion(selection.region, onPage: selection.pageIndex)
    }
    guard controller.coverSelectedText(with: typed, insteadOfEditing: true).isEdited else {
      textEditMessage = .cannotEditOrCover
      return false
    }
    // The same would happen to the next line of this page, so its lines now say so up front. Only
    // once the cover is made: a page is not marked for a line nothing could be done with (#231).
    controller.markTextCoverOnly(onPage: selection.pageIndex)
    textEditMessage = nil
    textEditNotice = .coveredInstead
    updateUndoState()
    await save()
    await textEditingPageChanged()
    return true
  }

  // MARK: - Moving existing text (FR-EDIT-009)

  /// How many times text has been moved in this reader; the view announces each to VoiceOver.
  public private(set) var textMoves = 0

  /// Moves a line of text to where the person dropped it, and saves.
  ///
  /// The words are erased where they were and drawn at the new place, proven like any edit. Text
  /// that cannot be changed in the page is covered where it was and placed at the new place, and
  /// the reader says so. Nothing is moved onto other content or off the page.
  ///
  /// - Returns: Whether the text was moved.
  @discardableResult
  public func moveText(_ selection: TextRegionSelection, by offset: CGVector) async -> Bool {
    guard let controller, controller.isEditingText, controller.selectedTextRegion == nil, !isCommittingTextEdit
    else { return false }
    isCommittingTextEdit = true
    defer { endCommittingTextEdit() }
    textEditNotice = nil
    hasPickedText = true
    let kept = controller.offset(offset, keeping: selection.region, onPage: selection.pageIndex)
    var outcome: TextEditOutcome
    if selection.region.capability.editsContent {
      outcome = await controller.moveText(selection, by: kept)
      if case .refused(let refusal) = outcome, refusal != .overlapsOtherContent, refusal.meansNotEditableInPlace {
        controller.markTextCoverOnly(onPage: selection.pageIndex)
        outcome = controller.cover(selection, with: selection.region.text, insteadOfEditing: true, movedBy: kept)
      }
    } else {
      outcome = controller.cover(selection, with: selection.region.text, movedBy: kept)
    }
    guard self.controller === controller else { return false }
    switch outcome {
    case .edited(let mode):
      textEditMessage = nil
      // Covered text is still in the file where it was, and the person must know.
      if mode == .visualReplacement { textEditNotice = .coveredInstead } else { textChangedSinceIndexing = true }
      textMoves += 1
      updateUndoState()
      await save()
      return true
    case .tooLong, .refused(.overlapsOtherContent):
      textEditMessage = .somethingInTheWay
    case .refused(.restricted):
      errorMessage = Self.restrictedMessage
    case .refused(.timedOut):
      textEditMessage = .tookTooLong
    case .refused:
      textEditMessage = .cannotEditOrCover
    }
    return false
  }

  /// Takes back the cover the reader placed, and its notice.
  public func undoCoverInstead() async {
    // Undo waits while text is being edited; the notice stays until it can undo (#269). With
    // nothing left to undo, as after an edit that could not be saved was put back, the notice
    // goes, so its Undo is never a button that does nothing.
    guard textEditNotice == .coveredInstead, !isBusyEditingText else { return }
    textEditNotice = nil
    guard controller?.undoManager.canUndo == true else { return }
    await undo()
  }

  /// Puts the notice away; what it told of stays as it is.
  public func dismissTextEditNotice() {
    textEditNotice = nil
  }

  /// Lets go of the picked text without changing it.
  public func cancelTextEdit() {
    controller?.clearTextRegionSelection()
    textEditMessage = nil
    lookAtFileChangeHeardWhileEditing()
    Task { await textEditingPageChanged() }
  }

  /// Brings the search text and Spotlight up to date with edited words, once, not after every edit.
  private func refreshSearchTextIfNeeded() async {
    guard textChangedSinceIndexing, await save() else { return }
    // Done only once the refresh worked, so the next chance tries again (#236).
    guard let refreshed = await refreshLibraryRecord() else { return }
    textChangedSinceIndexing = false
    document = refreshed
  }

  // MARK: - Signing

  /// Opens the signature sheet, or says why the document cannot be signed (F1c, FR-EDIT-004).
  public func showSignatures() {
    guard let controller, checkAnnotatingIsAllowed(controller) else { return }
    showsSignatures = true
  }

  /// Loads the signatures saved on this device.
  public func loadSignatures() async {
    do {
      savedSignatures = try await signatures.signatures()
    } catch {
      errorMessage = Self.signatureStoreMessage
    }
  }

  /// Saves a signature drawn on the pad; returns it, or `nil` when nothing was drawn or saving failed.
  @discardableResult
  public func saveSignature(drawn strokes: [[CGPoint]]) async -> SavedSignature? {
    guard let signature = SavedSignature(drawn: strokes) else { return nil }
    do {
      try await signatures.save(signature)
      savedSignatures.append(signature)
      return signature
    } catch {
      errorMessage = Self.signatureStoreMessage
      return nil
    }
  }

  /// Deletes a saved signature from this device.
  public func deleteSignature(_ id: UUID) async {
    do {
      try await signatures.delete(id)
      savedSignatures.removeAll { $0.id == id }
    } catch {
      errorMessage = Self.signatureStoreMessage
    }
  }

  /// Places a saved signature on the page on screen, then saves.
  public func place(_ signature: SavedSignature) async {
    guard let controller, checkAnnotatingIsAllowed(controller),
      controller.placeSignature(signature, onPage: controller.currentPageIndex)
    else { return }
    updateUndoState()
    await save()
  }

  /// Places a typed name as a signature on the page on screen, then saves.
  public func placeTyped(_ name: String) async {
    guard let controller, checkAnnotatingIsAllowed(controller),
      controller.placeTypedSignature(name, onPage: controller.currentPageIndex)
    else { return }
    updateUndoState()
    await save()
  }

  private static var signatureStoreMessage: String {
    String(localized: "Couldn't reach the signatures saved on this device. Try again.", bundle: .module)
  }

  /// Says so when the document's author does not allow notes and markup (defect D9).
  private func checkAnnotatingIsAllowed(_ controller: PDFDocumentController) -> Bool {
    guard controller.allowsAnnotating else {
      errorMessage = Self.restrictedMessage
      return false
    }
    return true
  }

  private static var restrictedMessage: String {
    String(
      localized: "The author of this document doesn't allow notes, markup or changes to it, so nothing was changed.",
      bundle: .module)
  }

  private func updateUndoState() {
    canUndo = controller?.undoManager.canUndo ?? false
    canRedo = controller?.undoManager.canRedo ?? false
  }

  /// Saves before the app is suspended, so nothing typed or marked is lost if the system ends it.
  ///
  /// `keepAlive` asks the system for time to finish (on iOS, a background task) and returns the call
  /// that ends it; the reader ends it once the save and the reading position are written (defect D2).
  ///
  /// While another app's change waits for the person's choice, nothing is written over either version:
  /// this reader's version goes into a new document beside the original instead (#257).
  public func saveBeforeSuspending(keepAlive: () -> (@MainActor () -> Void)) async {
    let finished = keepAlive()
    if await !save() { await keepUnsavedVersionAside() }
    await recordPosition()
    finished()
  }

  /// Writes changes atomically (autosave, FR-EDIT-007); a failed save changes nothing on disk.
  ///
  /// Form entries count as changes, including text still being typed into a field (defect D1).
  ///
  /// Returns whether the file on disk now has every change; a failure has already been explained.
  ///
  /// Saves run one at a time, each after the one before has finished, so two quick changes to a
  /// signed document make one copy, not two (#233). The file is not written while another app's
  /// change waits for the person's choice, or over a change this reader has not heard of yet: the
  /// person is asked which version to keep instead (#257).
  @discardableResult
  public func save() async -> Bool {
    let earlier = saving
    let current = Task {
      if let earlier {
        savesWaiting += 1
        _ = await earlier.value
        savesWaiting -= 1
      }
      return await saveNow()
    }
    saving = current
    let saved = await current.value
    if saving == current { saving = nil }
    return saved
  }

  private func saveNow() async -> Bool {
    guard let controller else { return false }
    controller.endEditing()
    // While another app's change waits for the person's choice, nothing is written; the choice is
    // offered again (#257).
    guard !conflictWaits else {
      hasConflictingChange = true
      return false
    }
    guard controller.needsSaving else { return true }
    do {
      if controller.digitalSignature.isSigned, !isEditingCopy {
        // A copy made from a version another app has since replaced would skip their change (#257).
        if let fileURL, raisesConflictIfChanged(at: fileURL) { return false }
        try await saveSignedAsCopy(controller)
        reportTextEditsPutBack(by: controller)
        return true
      }
      let url = try await library.fileURL(for: documentID)
      let previous = try await library.previousVersionURL(for: documentID)
      // A change another app made since this reader last read or wrote the file is not written over,
      // whether or not the reader has heard of it yet: looked at now, and again with write access
      // coordinated, just before the replace (#257).
      guard !conflictWaits else {
        hasConflictingChange = true
        return false
      }
      guard !raisesConflictIfChanged(at: url) else { return false }
      let expected = knownVersion
      var written: FileVersion?
      try controller.save(
        to: url, keepingPreviousAt: previous,
        onlyIf: { target in expected == nil || FileVersion.current(at: target) == expected },
        // Read with write access still coordinated, straight after the replace: another app's write
        // after it is then another app's change, never taken for this reader's own (#257).
        written: { target in written = FileVersion.current(at: target) })
      reportTextEditsPutBack(by: controller)
      knownVersion = written
      try await library.recordModified(documentID)
      canRestorePreviousVersion = await library.hasPreviousVersion(of: documentID)
      await telemetry.record("task.core.completed")
      return true
    } catch PDFEngineError.changedOnDisk {
      // Another app wrote the file while this save was being made (#257).
      knownVersion = fileURL.flatMap { FileVersion.current(at: $0) }
      raiseConflict()
      reportTextEditsPutBack(by: controller)
      return false
    } catch PDFEngineError.restricted {
      errorMessage = Self.restrictedMessage
    } catch PDFEngineError.insufficientSpace {
      errorMessage = String(
        localized:
          "Couldn't save your changes because this iPhone is almost full. The document on disk hasn't changed. Free up some space, then try again.",
        bundle: .module)
      await telemetry.record("quality.operation.failed")
    } catch {
      errorMessage = String(
        localized: "Couldn't save your changes. The document on disk hasn't changed. Try again.", bundle: .module)
      await telemetry.record("quality.operation.failed")
    }
    // A failed save can still have put an edit back before it failed; that is said too.
    reportTextEditsPutBack(by: controller)
    return false
  }

  /// Says that a text edit the written file did not keep was put back, and what was saved (#232).
  ///
  /// The page now shows its earlier words, so what was found of its text is found again. Nothing is
  /// said when the save kept every edit.
  private func reportTextEditsPutBack(by controller: PDFDocumentController) {
    guard !controller.textEditsPutBack.isEmpty else { return }
    let putBack = String(
      localized:
        "A change to the text couldn't be saved safely, so the text was put back as it was. Your other changes are saved.",
      bundle: .module)
    errorMessage = errorMessage.map { putBack + " " + $0 } ?? putBack
    updateUndoState()
    Task { await textEditingPageChanged() }
  }

  /// Saves a digitally signed document's changes in a new copy and reads that copy from now on.
  ///
  /// Saving through PDFKit rewrites the file, which breaks every signature, so the signed original is
  /// left as it was (plan item H9).
  private func saveSignedAsCopy(_ controller: PDFDocumentController) async throws {
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent("signed-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staged) }
    let unsaved = controller.unsavedChanges
    try controller.save(to: staged)
    let copy: Document
    do {
      let data = try Data(contentsOf: staged, options: .mappedIfSafe)
      let title = document?.title ?? ""
      copy = try await intake.add(data: data, title: String(localized: "\(title) (edited)", bundle: .module))
    } catch {
      // The copy isn't in the library, so the changes are still only here (#223).
      controller.countAsUnsaved(unsaved)
      throw error
    }
    documentID = copy.id
    document = copy
    let copyURL = try await library.fileURL(for: copy.id)
    fileURL = copyURL
    // From now on this reader writes the copy, so that is the file to watch for other apps' changes.
    knownVersion = FileVersion.current(at: copyURL)
    watch(copyURL)
    isEditingCopy = true
    // Recognition of the copy must hear this reader too, so it never replaces the file behind it (#255).
    watchRecognition()
    canRestorePreviousVersion = false
    notice = String(
      localized:
        "This document is digitally signed, so your changes are saved in a copy, “\(copy.title)”. The original keeps its valid signature.",
      bundle: .module)
    await telemetry.record("task.core.completed")
  }

  // MARK: - Another app's changes (plan item H5)

  private func watch(_ url: URL) {
    watcher?.stop()
    let watcher = FileWatcher(url: url) { [weak self] in
      Task { await self?.fileChangedOnDisk() }
    }
    watcher.start()
    self.watcher = watcher
  }

  /// Stops hearing about file changes while the app is in the background, and on returning checks
  /// whether another app changed the file meanwhile.
  public func setWatching(_ isActive: Bool) async {
    if isActive {
      // A rename in the Files app while the app was away isn't heard, so the library finds the file
      // (#224); otherwise the watcher would watch the old name for the rest of the session.
      if phase == .ready, let moved = try? await library.fileURL(for: documentID), !Self.isSameURL(moved, fileURL) {
        fileURL = moved
        watch(moved)
      } else {
        watcher?.start()
      }
      await fileChangedOnDisk()
    } else {
      watcher?.stop()
    }
  }

  /// Stops hearing about file changes, when the reader closes.
  public func stopWatching() {
    watcher?.stop()
  }

  /// Saves and brings the search text up to date as the reader closes.
  ///
  /// While another app's change waits for the person's choice, this reader's version goes into a new
  /// document beside the original, as on going to the background (#257).
  public func saveBeforeClosing() async {
    if await !save() { await keepUnsavedVersionAside() }
    await refreshSearchTextIfNeeded()
  }

  /// Handles a change to the file made by another app: with no unsaved changes, the reader shows the
  /// new version; with unsaved changes, it asks which version to keep.
  ///
  /// A text edit being worked out, or text picked to edit with nothing else unsaved, is not
  /// interrupted: the change is looked at once the editor lets go of it, so what is typed is never
  /// thrown away (#249). While a choice waits, it is offered again.
  func fileChangedOnDisk() async {
    // The watcher follows a file renamed or moved in the Files app (#224). Nothing is awaited before
    // the check below: a suspension would let the check the reader's own save set off claim another
    // app's change, and this one return before that change is shown.
    if let watched = watcher?.presentedItemURL, !Self.isSameURL(watched, fileURL) { fileURL = watched }
    guard !isCommittingTextEdit, selectedTextRegion == nil || controller?.needsSaving == true else {
      heardFileChangeWhileEditing = true
      return
    }
    guard !conflictWaits else {
      hasConflictingChange = true
      return
    }
    guard phase == .ready, let fileURL, let current = FileVersion.current(at: fileURL), current != knownVersion else {
      return
    }
    knownVersion = current
    if controller?.needsSaving == true {
      raiseConflict()
    } else {
      await reload()
      notice = String(
        localized: "This document was changed in another app, and now shows those changes.", bundle: .module)
    }
  }

  /// Whether two file URLs name the same place, however they are spelled.
  private static func isSameURL(_ url: URL, _ other: URL?) -> Bool {
    guard let other else { return false }
    return url.standardizedFileURL.resolvingSymlinksInPath().path
      == other.standardizedFileURL.resolvingSymlinksInPath().path
  }

  /// Asks the person which version to keep when the file isn't the version this reader last read or wrote.
  ///
  /// Returns whether it asked (#257).
  private func raisesConflictIfChanged(at url: URL) -> Bool {
    guard let expected = knownVersion, let onDisk = FileVersion.current(at: url), onDisk != expected else {
      return false
    }
    knownVersion = onDisk
    raiseConflict()
    return true
  }

  /// Asks the person which version to keep, and writes nothing until they have chosen (#257).
  private func raiseConflict() {
    conflictWaits = true
    hasConflictingChange = true
  }

  /// Looks at another app's change heard while text was picked, once the editor has let go of it (#249).
  private func lookAtFileChangeHeardWhileEditing() {
    guard heardFileChangeWhileEditing, selectedTextRegion == nil, !isCommittingTextEdit else { return }
    heardFileChangeWhileEditing = false
    Task { await fileChangedOnDisk() }
  }

  /// Drops this reader's unsaved changes and shows the version another app saved.
  public func useOtherVersion() async {
    hasConflictingChange = false
    // A version kept aside meanwhile stays in the library; the next conflict gets its own (#257).
    conflictCopy = nil
    await reload()
  }

  /// Keeps this reader's unsaved version in a new document beside the original, when a save was
  /// refused because another app's change waits for the person's choice and the app may end before
  /// they make it (#257).
  ///
  /// One copy per conflict: the choice can still be made, and keeping mine then makes no second copy.
  ///
  /// The notice says where the changes went, or that they couldn't be kept, for when the person comes back.
  private func keepUnsavedVersionAside() async {
    guard conflictWaits, let controller, controller.needsSaving else { return }
    let title = String(localized: "\(document?.title ?? "") (conflict)", bundle: .module)
    if let copy = await keepAside(controller, titled: title), !controller.needsSaving {
      changesKeptIn = copy.title
      notice = String(localized: "Your changes are kept in “\(copy.title)”, beside the original.", bundle: .module)
    } else {
      notice = String(
        localized: "Your changes couldn't be kept in a copy. They are still open here; choose which version to keep.",
        bundle: .module)
    }
  }

  /// The copy that already has every change of this reader while another app's change waits, if any.
  ///
  /// The conflict alert then says the changes are kept there rather than unsaved (#257).
  public var conflictChangesKeptIn: String? {
    guard conflictWaits, controller?.needsSaving == false else { return nil }
    return changesKeptIn
  }

  /// Writes this reader's version to the conflict's copy, made the first time and brought up to date
  /// with any change since after that; `nil` when no copy could be added (#257).
  ///
  /// The copy has every change, so nothing counts as unsaved until the next one. Neither the original
  /// nor the other app's version is written.
  private func keepAside(_ controller: PDFDocumentController, titled title: String) async -> Document? {
    let earlier = conflictCopy
    let keeping = Task { () -> Document? in
      // A copy the person has deleted meanwhile is made again (#257).
      guard let kept = await earlier?.value, let current = try? await library.document(withID: kept.id),
        !current.isDeleted
      else { return try? await addCopy(of: controller, titled: title) }
      guard controller.needsSaving, let url = try? await library.fileURL(for: kept.id) else { return current }
      let saved = (try? controller.save(to: url)) != nil
      reportTextEditsPutBack(by: controller)
      if saved { _ = try? await intake.refresh(kept.id) }
      return current
    }
    conflictCopy = keeping
    return await keeping.value
  }

  /// Writes the version this reader shows to a new document in the library, beside the original; on
  /// failure the changes still count as unsaved (#223).
  private func addCopy(of controller: PDFDocumentController, titled title: String) async throws -> Document {
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent("mine-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staged) }
    let unsaved = controller.unsavedChanges
    do {
      defer { reportTextEditsPutBack(by: controller) }
      try controller.save(to: staged)
      let data = try Data(contentsOf: staged, options: .mappedIfSafe)
      return try await intake.add(data: data, title: title)
    } catch {
      controller.countAsUnsaved(unsaved)
      throw error
    }
  }

  /// Keeps this reader's version as a new document in the library, then shows the version another
  /// app saved in the original.
  ///
  /// A copy kept while the choice waited is used, brought up to date with any change since, rather
  /// than a second one made (#257).
  public func keepMineAsCopy() async {
    hasConflictingChange = false
    guard let controller else { return }
    let title = String(localized: "\(document?.title ?? "") (my version)", bundle: .module)
    if let copy = await keepAside(controller, titled: title), !controller.needsSaving {
      conflictCopy = nil
      await reload()
      notice = String(localized: "Your version is saved as “\(copy.title)”.", bundle: .module)
    } else {
      // This version is still only here, unsaved (#223), and the other app's version is still
      // protected: the choice is offered again (#257).
      hasConflictingChange = conflictWaits
      errorMessage = String(
        localized: "Couldn't keep your version. It is still open here; share it to keep it.", bundle: .module)
    }
  }

  private func reload() async {
    speech.stop()
    controller = nil
    phase = .loading
    await load()
  }

  // MARK: - The version before the last save

  /// Puts back the version from before the last save and reopens the document (FR-EDIT-008, first step).
  ///
  /// Unsaved changes are dropped, which the confirmation says. The current version becomes the kept
  /// one, so restoring again undoes the restore.
  public func restorePreviousVersion() async {
    await restoring { try await self.library.restorePreviousVersion(of: self.documentID) }
  }

  /// Whether the version history is showing.
  public var showsVersions = false
  /// The document's earlier versions, newest first, once loaded (FR-EDIT-008).
  public private(set) var versions: [DocumentVersion] = []

  /// Loads the earlier versions for the history.
  public func loadVersions() async {
    versions = await library.versions(of: documentID)
  }

  /// Puts an earlier version back and reopens the document; the current one is kept, so this can be
  /// undone from the history (FR-EDIT-008).
  public func restore(_ version: DocumentVersion) async {
    showsVersions = false
    await restoring { try await self.library.restore(version, of: self.documentID) }
  }

  private func restoring(_ swap: @escaping () async throws -> Void) async {
    // A save still being written would be taken for another app's change (#257).
    _ = await saving?.value
    speech.stop()
    controller = nil
    phase = .loading
    do {
      try await swap()
      // The two versions can differ in their text (a restore across text recognition), so the search
      // text and Spotlight follow the restored file.
      _ = await refreshLibraryRecord()
    } catch {
      errorMessage = String(
        localized: "Couldn't restore the earlier version. The document hasn't changed.", bundle: .module)
    }
    await load()
  }

  // MARK: - Sharing

  /// The saved file, ready to share or print: changes are saved first, so what leaves the app is what
  /// the person sees. `nil` when saving failed, which has been explained.
  ///
  /// While another app's change waits for the person's choice, this version is shared from a copy
  /// made for it, and neither version is written (#257).
  public func fileForSharing() async -> URL? {
    guard phase == .ready else { return nil }
    if conflictWaits, let controller { return try? sharedCopy(of: controller) }
    guard await save() else { return nil }
    return try? await library.fileURL(for: documentID)
  }

  /// The version this reader shows, written to a file of its own to share; it still counts as unsaved.
  private func sharedCopy(of controller: PDFDocumentController) throws -> URL {
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staged) }
    let unsaved = controller.unsavedChanges
    defer { controller.countAsUnsaved(unsaved) }
    defer { reportTextEditsPutBack(by: controller) }
    try controller.save(to: staged)
    return try Self.shareableFile(Data(contentsOf: staged), named: document?.title ?? "", extension: "pdf")
  }

  /// Whether the document's author allows printing; always true for unencrypted documents.
  public var allowsPrinting: Bool { controller?.allowsPrinting ?? false }

  /// Saves, then opens the share sheet with the file.
  public func share() async {
    guard let url = await fileForSharing() else { return }
    sharing = SharedFile(url: url, allowsPrinting: allowsPrinting)
  }

  // MARK: - Tools (FR-ORG-004, FR-ORG-006, FR-ORG-007, FR-EDIT-006)

  /// Whether "Add a password" is asking for the password.
  public var isAddingPassword = false
  /// Whether "Remove password" is asking for confirmation.
  public var confirmsPasswordRemoval = false
  /// Whether a password protects the document.
  public var isPasswordProtected: Bool { controller?.isPasswordProtected ?? false }
  /// Whether the password can be removed (opened with the owner password).
  public var canRemovePassword: Bool { controller?.canRemovePassword ?? false }

  /// Shares a copy with notes, markup and form entries drawn into the pages, so nobody can change them.
  public func shareFlattened() async {
    guard let controller, await save() else { return }
    do {
      let url = try Self.shareableFile(
        controller.flattenedData(),
        named: String(localized: "\(document?.title ?? "") (flattened)", bundle: .module), extension: "pdf")
      sharing = SharedFile(url: url, allowsPrinting: allowsPrinting)
    } catch {
      errorMessage = String(localized: "Couldn't make a flattened copy. The document hasn't changed.", bundle: .module)
    }
  }

  /// Shares the page on screen as a PNG image, with its notes and markup.
  public func sharePageImage() async {
    guard let controller else { return }
    do {
      let page = controller.currentPageIndex
      let url = try Self.shareableFile(
        controller.imageData(ofPage: page, format: .png),
        named: String(localized: "\(document?.title ?? "") page \(page + 1)", bundle: .module), extension: "png")
      sharing = SharedFile(url: url, allowsPrinting: allowsPrinting)
    } catch {
      errorMessage = String(localized: "Couldn't make an image of this page.", bundle: .module)
    }
  }

  /// Saves a smaller copy of the document in the library, or says it is already about as small as
  /// it gets; the document itself is unchanged (FR-ORG-004).
  public func reduceSize(_ preset: PDFDocumentController.CompressionPreset) async {
    guard let controller, await save(), let fileURL else { return }
    do {
      let original = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
      guard let data = try controller.compressed(preset, comparedTo: original) else {
        notice = String(localized: "This document is already about as small as it gets.", bundle: .module)
        return
      }
      let title = document?.title ?? ""
      let copy = try await intake.add(data: data, title: String(localized: "\(title) (smaller)", bundle: .module))
      let before = original.formatted(.byteCount(style: .file))
      let after = data.count.formatted(.byteCount(style: .file))
      notice = String(localized: "Saved a smaller copy, “\(copy.title)”: \(before) down to \(after).", bundle: .module)
    } catch PDFEngineError.restricted {
      errorMessage = Self.restrictedMessage
    } catch {
      errorMessage = String(localized: "Couldn't make a smaller copy. The document hasn't changed.", bundle: .module)
    }
  }

  /// Protects the document with a password and saves (FR-EDIT-006).
  public func setPassword(_ password: String) async {
    guard let controller else { return }
    guard controller.setPassword(password) else {
      errorMessage = String(
        localized: "This document's author doesn't allow its password to be changed.", bundle: .module)
      return
    }
    if await save() {
      // The library's record follows the file: its lock, its page count and its search text. If that
      // fails, the words still leave search and Spotlight now: removing them needs no space, so it
      // works on the full disk that made the refresh fail; then the title goes back if it can (#236).
      if await refreshLibraryRecord() == nil, var locked = document {
        locked.isEncrypted = true
        do {
          try await index.remove(documentID)
          try await index.index(locked, pages: [])
        } catch {
          await telemetry.record("quality.operation.failed")
        }
      }
      notice = String(localized: "The document now needs its password to open.", bundle: .module)
    }
  }

  /// Removes the password and every restriction, and saves (FR-EDIT-006).
  public func removePassword() async {
    guard let controller, controller.removePassword() else {
      errorMessage = String(
        localized: "Only the document's owner password can remove its protection.", bundle: .module)
      return
    }
    if await save() {
      // The library's record follows the file: its lock, its page count and its search text.
      _ = await refreshLibraryRecord()
      notice = String(localized: "The document no longer needs a password.", bundle: .module)
    }
  }

  /// Brings the library's record, search text and Spotlight up to date with the saved file.
  ///
  /// A failure is counted, not shown: the save worked. The entry is left older than its file, so the
  /// next library load tries again (#236). Returns the refreshed document, or `nil` when it failed.
  private func refreshLibraryRecord() async -> Document? {
    do {
      return try await intake.refresh(documentID)
    } catch {
      await telemetry.record("quality.operation.failed")
      return nil
    }
  }

  /// A file to share, under a readable name, in a folder of its own in the temporary directory.
  static func shareableFile(_ data: Data, named name: String, extension ext: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
    let url = folder.appendingPathComponent(safe.isEmpty ? "Document" : safe).appendingPathExtension(ext)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return url
  }

  // MARK: - Recognition
  // MARK: - Recognition

  /// Whether the document has pages with no text, so recognition can help (FR-SCAN-003).
  public var canRecognizeText: Bool {
    guard let document, phase == .ready else { return false }
    return !document.hasTextLayer && !document.isEncrypted
  }

  /// Whether recognition was stopped from the system's interface with the pages done kept, so
  /// "Resume recognising" is offered in place of "Recognise text"; recognising resumes from them (#253).
  public var canResumeRecognition: Bool {
    canRecognizeText && recognitionProgress == nil && recognition.isStopped(documentID)
  }

  /// Recognises text on device and replaces the file with a searchable version, with progress.
  ///
  /// Unsaved notes, markup and form entries are saved first, so the searchable version includes them.
  /// Recognition runs in the app's coordinator, so it goes on if the reader closes and resumes after
  /// the app was stopped (P8). If the document changes meanwhile, the file is left alone, so nothing
  /// added meanwhile is lost.
  public func recognizeText() {
    guard recognitionProgress == nil else { return }
    isPreparingRecognition = true
    Task {
      defer { isPreparingRecognition = false }
      await save()
      // A failed save has already said so; replacing the file now would lose those changes.
      guard controller?.needsSaving != true else { return }
      // The save may have moved this reader to a signed document's copy (#255).
      watchRecognition()
      // With App Lock on, the Live Activity on the Lock Screen and in the Dynamic Island must not say
      // which document it is (#254).
      var subtitle = document?.title ?? ""
      if settings.load().isAppLockEnabled {
        subtitle = String(
          localized: "A document", bundle: .module,
          comment: "Live Activity subtitle while text is recognised with App Lock on, in place of the title")
      }
      recognition.start(documentID, startedFor: subtitle)
    }
  }

  /// Stops recognition; the document is left as it was, unless the file was already replaced, in which
  /// case the searchable version opens.
  public func cancelRecognition() {
    recognition.cancel(documentID)
  }

  /// Hears how recognition ended, and blocks replacing the file while there are unsaved changes.
  private func watchRecognition() {
    recognition.watch(
      documentID, canReplace: { [weak self] in self?.canReplaceWithRecognizedText() ?? true },
      willReplace: { [weak self] in self?.recognitionReplacedFile() },
      onFinish: { [weak self] outcome in await self?.recognitionFinished(outcome) })
  }

  /// Lets go of the document shown once recognition has replaced its file, so no save writes it over
  /// the searchable version; the reader shows the new file when recognition has finished (#219).
  private func recognitionReplacedFile() {
    pageBeforeRecognition = controller?.currentPageIndex
    speech.stop()
    controller = nil
    phase = .loading
  }

  /// Whether recognition may replace the file: not while there are unsaved changes, counting text
  /// still being typed into a form field, which PDFKit puts in the field only when editing ends (#220).
  private func canReplaceWithRecognizedText() -> Bool {
    guard let controller else { return true }
    controller.endEditing()
    return !controller.needsSaving
  }

  private func recognitionFinished(_ outcome: RecognitionCoordinator.Outcome) async {
    switch outcome {
    case .replaced:
      // Opens the searchable version on the page the reader showed.
      if let page = pageBeforeRecognition {
        pageBeforeRecognition = nil
        try? await library.recordOpened(documentID, pageIndex: page)
      } else {
        await recordPosition()
      }
      await load()
      updateUndoState()
    case .fileChanged:
      errorMessage = String(
        localized: "The document changed while its text was being recognised, so it wasn't replaced. Try again.",
        bundle: .module)
    case .failed:
      errorMessage = String(
        localized: "Text recognition didn't finish. The document hasn't changed.", bundle: .module)
    }
  }

  // MARK: - Intelligence

  /// Whether AI features are shown (FR-AI-009).
  public var showsIntelligence: Bool { !settings.load().isIntelligenceHidden }

  /// The page texts for the assistant: the index's copy (which includes recognised text) or the
  /// text layer.
  public func pageTexts() async -> [PageText] {
    let stored = (try? await index.pages(of: documentID)) ?? []
    if stored.contains(where: { !$0.text.isEmpty }) { return stored }
    return controller?.pageTexts() ?? []
  }

  /// The context the assistant view needs.
  public func assistantContext(for task: AssistantTask) -> ReaderAssistantContext {
    ReaderAssistantContext(
      task: task, pages: { [weak self] in await self?.pageTexts() ?? [] },
      reveal: { [weak self] citation in
        guard let self else { return }
        guard assistantTask != nil else {
          controller?.reveal(citation)
          return
        }
        pendingReveal = citation
        assistantTask = nil
      },
      seePlans: { [weak self] in
        guard let self else { return }
        opensPlansAfterAssistant = true
        assistantTask = nil
      })
  }

  /// Closes the outline and the page grid, and opens a page chosen in either once it has closed.
  public func openAfterClosingSheets(pageIndex: Int) {
    pendingPageIndex = pageIndex
    showsOutline = false
    showsPages = false
    showsAnnotations = false
  }

  // MARK: - Annotation list (FR-ANN-003)

  /// Every annotation in the document, in reading order.
  public var annotationSummaries: [AnnotationSummary] { controller?.annotationSummaries() ?? [] }

  /// The annotations as plain text, to share or paste elsewhere: grouped by page, each with its kind and text.
  public func annotationsText() -> String {
    let summaries = annotationSummaries
    var lines = [document?.title ?? ""]
    var page: Int?
    for summary in summaries {
      if summary.pageIndex != page {
        page = summary.pageIndex
        lines.append("")
        lines.append(String(localized: "Page \(summary.pageIndex + 1)", bundle: .module))
      }
      let name = Self.name(of: summary)
      lines.append(summary.text.map { "• \(name): \($0)" } ?? "• \(name)")
    }
    return lines.joined(separator: "\n")
  }

  /// What an annotation is, in words.
  static func name(of summary: AnnotationSummary) -> String {
    if summary.isSignature { return String(localized: "Signature", bundle: .module) }
    return switch summary.kind {
    case .highlight: String(localized: "Highlight", bundle: .module)
    case .underline: String(localized: "Underline", bundle: .module)
    case .strikeThrough: String(localized: "Strike-through", bundle: .module)
    case .note: String(localized: "Note", bundle: .module)
    case .ink: String(localized: "Drawing", bundle: .module)
    case .rectangle: String(localized: "Rectangle", bundle: .module)
    case .oval: String(localized: "Oval", bundle: .module)
    case .line: String(localized: "Line", bundle: .module)
    case .textBox: String(localized: "Text box", bundle: .module)
    case .stamp: String(localized: "Stamp", bundle: .module)
    case .other: String(localized: "Annotation", bundle: .module)
    }
  }

  /// Opens the page chosen in the outline or the page grid, now that its sheet has closed.
  ///
  /// Like `assistantDismissed()`: the page view re-lays out as the reader grows back, so a page
  /// opened while the sheet was still on screen could be scrolled away from.
  public func pageSheetDismissed() {
    guard let pageIndex = pendingPageIndex else { return }
    pendingPageIndex = nil
    controller?.goTo(pageIndex: pageIndex)
  }

  /// Opens the citation chosen in the assistant, once its sheet has closed.
  ///
  /// While a large sheet is open it shrinks the reader behind it; the page view re-lays out as the
  /// reader grows back and could scroll back to the page it showed before. Opening the page after
  /// the sheet has gone keeps the citation's page on screen.
  public func assistantDismissed() {
    if opensPlansAfterAssistant {
      opensPlansAfterAssistant = false
      onAllowanceUsed?()
    }
    guard let citation = pendingReveal else { return }
    pendingReveal = nil
    controller?.reveal(citation)
  }
}
