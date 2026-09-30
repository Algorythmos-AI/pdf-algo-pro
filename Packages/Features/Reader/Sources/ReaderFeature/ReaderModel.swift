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
  public private(set) var recognitionProgress: Double?
  /// A message for the last failed action.
  public var errorMessage: String?
  /// The assistant sheet, when open.
  public var assistantTask: AssistantTask?
  /// A citation to open once the assistant sheet has finished closing.
  @ObservationIgnored private var pendingReveal: Citation?
  /// Whether the outline sheet is open.
  public var showsOutline = false
  /// Whether the page grid is open.
  public var showsPages = false
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
  /// Whether there is an annotation change to undo.
  public private(set) var canUndo = false
  /// Whether there is an undone annotation change to redo.
  public private(set) var canRedo = false
  /// Read aloud.
  public let speech: SpeechReader

  private let documentID: DocumentID
  private let startPage: Int?
  private let library: any DocumentLibrary
  private let intake: DocumentIntake
  private let index: any DocumentIndexing
  private let settings: any SettingsStoring
  private let telemetry: any TelemetryRecording
  private let builder: SearchablePDFBuilder
  private let signatures: any SignatureStoring
  private var recognition: Task<Void, Never>?

  /// Creates a reader for a document.
  public init(
    selection documentID: DocumentID, pageIndex: Int? = nil, task: AssistantTask? = nil, library: any DocumentLibrary,
    intake: DocumentIntake, index: any DocumentIndexing, settings: any SettingsStoring,
    telemetry: any TelemetryRecording,
    builder: SearchablePDFBuilder, signatures: any SignatureStoring, speech: SpeechReader = SpeechReader()
  ) {
    self.documentID = documentID
    startPage = pageIndex
    assistantTask = task
    self.library = library
    self.intake = intake
    self.index = index
    self.settings = settings
    self.telemetry = telemetry
    self.builder = builder
    self.signatures = signatures
    self.speech = speech
  }

  // MARK: - Opening

  /// Opens the file at the page asked for, or where the user left off (FR-READ-006).
  public func load() async {
    do {
      guard let document = try await library.document(withID: documentID) else {
        phase = .failed(String(localized: "This document is no longer in the library.", bundle: .module))
        return
      }
      self.document = document
      let url = try await library.fileURL(for: documentID)
      fileURL = url
      let controller = try PDFDocumentController(url: url)
      controller.displayMode = settings.load().readerDisplayMode
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
    controller.goTo(pageIndex: startPage ?? document?.lastPageIndex ?? 0)
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

  /// Reads the current page aloud, or stops (FR-READ-004).
  public func toggleReadAloud() {
    guard let controller else { return }
    if speech.isSpeaking {
      speech.stop()
    } else {
      // Only the page on screen is read, so a long document does not extract every page first.
      speech.speak(controller.pageText(at: controller.currentPageIndex))
    }
  }

  // MARK: - Annotating

  /// Marks up the selected text and saves; returns whether anything was selected.
  @discardableResult
  public func markUpSelection(_ markup: TextMarkup) async -> Bool {
    guard let controller, checkAnnotatingIsAllowed(controller) else { return false }
    guard controller.markUpSelection(markup) else {
      errorMessage = String(localized: "Select some text first, then choose how to mark it.", bundle: .module)
      return false
    }
    updateUndoState()
    await save()
    return true
  }

  /// Adds a note to the current page and saves.
  public func addNote(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let controller, !trimmed.isEmpty, checkAnnotatingIsAllowed(controller) else { return }
    controller.addNote(trimmed, onPage: controller.currentPageIndex)
    updateUndoState()
    await save()
  }

  /// Undoes the last annotation change and saves.
  public func undo() async {
    guard let controller, controller.undoManager.canUndo else { return }
    controller.undoManager.undo()
    updateUndoState()
    await save()
  }

  /// Redoes the last undone annotation change and saves.
  public func redo() async {
    guard let controller, controller.undoManager.canRedo else { return }
    controller.undoManager.redo()
    updateUndoState()
    await save()
  }

  /// Whether touches on the page draw ink (F2a).
  public var isDrawing: Bool { controller?.isDrawing ?? false }

  /// Starts or stops drawing; each stroke is saved and can be undone.
  public func setDrawing(_ isDrawing: Bool, tool: DrawingTool = .pen) {
    guard let controller else { return }
    if isDrawing, !checkAnnotatingIsAllowed(controller) { return }
    controller.setDrawing(isDrawing, tool: tool) { [weak self] in
      Task { await self?.inkAdded() }
    }
  }

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

  /// Clears the selection.
  public func clearSelection() {
    controller?.clearSelection()
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
  public func saveBeforeSuspending(keepAlive: () -> (@MainActor () -> Void)) async {
    let finished = keepAlive()
    await save()
    await recordPosition()
    finished()
  }

  /// Writes changes atomically (autosave, FR-EDIT-007); a failed save changes nothing on disk.
  ///
  /// Form entries count as changes, including text still being typed into a field (defect D1).
  ///
  /// Returns whether the file on disk now has every change; a failure has already been explained.
  @discardableResult
  public func save() async -> Bool {
    guard let controller else { return false }
    controller.endEditing()
    guard controller.needsSaving else { return true }
    do {
      try controller.save(to: try await library.fileURL(for: documentID))
      try await library.recordModified(documentID)
      await telemetry.record("task.core.completed")
      return true
    } catch PDFEngineError.restricted {
      errorMessage = Self.restrictedMessage
    } catch {
      errorMessage = String(
        localized: "Couldn't save your changes. The document on disk hasn't changed. Try again.", bundle: .module)
      await telemetry.record("quality.operation.failed")
    }
    return false
  }

  // MARK: - Sharing

  /// The saved file, ready to share or print: changes are saved first, so what leaves the app is what
  /// the person sees. `nil` when saving failed, which has been explained.
  public func fileForSharing() async -> URL? {
    guard phase == .ready, await save() else { return nil }
    return try? await library.fileURL(for: documentID)
  }

  /// Whether the document's author allows printing; always true for unencrypted documents.
  public var allowsPrinting: Bool { controller?.allowsPrinting ?? false }

  /// Saves, then opens the share sheet with the file.
  public func share() async {
    guard let url = await fileForSharing() else { return }
    sharing = SharedFile(url: url, allowsPrinting: allowsPrinting)
  }

  // MARK: - Recognition

  /// Whether the document has pages with no text, so recognition can help (FR-SCAN-003).
  public var canRecognizeText: Bool {
    guard let document, phase == .ready else { return false }
    return !document.hasTextLayer && !document.isEncrypted
  }

  /// Recognises text on device and replaces the file with a searchable version, with progress.
  ///
  /// Unsaved notes, markup and form entries are saved first, so the searchable version includes them. If the
  /// document changes while recognition runs, the file is left alone, so nothing added meanwhile is lost.
  public func recognizeText() {
    guard recognitionProgress == nil else { return }
    recognitionProgress = 0
    recognition = Task {
      defer { recognitionProgress = nil }
      do {
        await save()
        // A failed save has already said so; replacing the file now would lose those changes.
        guard controller?.needsSaving != true else { return }
        let url = try await library.fileURL(for: documentID)
        let version = try FileVersion(url)
        let result = try await builder.addTextLayer(toPDFAt: url) { progress in
          Task { @MainActor in self.recognitionProgress = progress }
        }
        // Stopped during the last page: the builder has finished, but the file is left as it was.
        try Task.checkCancellation()
        // No suspension between this check and the write, so no save can slip in between.
        guard controller?.needsSaving != true, try FileVersion(url) == version else {
          errorMessage = String(
            localized: "The document changed while its text was being recognised, so it wasn't replaced. Try again.",
            bundle: .module)
          return
        }
        try result.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        document = try await intake.refresh(documentID)
        let reopened = try PDFDocumentController(url: url)
        reopened.displayMode = settings.load().readerDisplayMode
        controller = reopened
        updateUndoState()
        show(reopened)
        await telemetry.record("task.core.completed")
      } catch is CancellationError {
        return
      } catch {
        errorMessage = String(
          localized: "Text recognition didn't finish. The document hasn't changed.", bundle: .module)
      }
    }
  }

  /// Stops recognition; the document is left as it was.
  public func cancelRecognition() {
    recognition?.cancel()
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
      })
  }

  /// Closes the outline and the page grid, and opens a page chosen in either once it has closed.
  public func openAfterClosingSheets(pageIndex: Int) {
    pendingPageIndex = pageIndex
    showsOutline = false
    showsPages = false
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
    guard let citation = pendingReveal else { return }
    pendingReveal = nil
    controller?.reveal(citation)
  }
}

/// One version of a file on disk.
///
/// Saves are atomic and replace the file, so its file number changes; the modification date and size
/// catch in-place writes.
private struct FileVersion: Equatable {
  let number: Int?
  let modified: Date?
  let size: Int?

  init(_ url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    number = (attributes[.systemFileNumber] as? NSNumber)?.intValue
    modified = attributes[.modificationDate] as? Date
    size = (attributes[.size] as? NSNumber)?.intValue
  }
}
