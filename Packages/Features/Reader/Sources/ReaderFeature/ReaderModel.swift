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
  /// Whether the outline sheet is open.
  public var showsOutline = false
  /// Whether the page grid is open.
  public var showsPages = false
  /// Read aloud.
  public let speech = SpeechReader()

  private let documentID: DocumentID
  private let startPage: Int?
  private let library: any DocumentLibrary
  private let intake: DocumentIntake
  private let index: any DocumentIndexing
  private let settings: any SettingsStoring
  private let telemetry: any TelemetryRecording
  private let builder: SearchablePDFBuilder
  private var recognition: Task<Void, Never>?

  /// Creates a reader for a document.
  public init(
    selection documentID: DocumentID, pageIndex: Int? = nil, task: AssistantTask? = nil, library: any DocumentLibrary,
    intake: DocumentIntake, index: any DocumentIndexing, settings: any SettingsStoring,
    telemetry: any TelemetryRecording,
    builder: SearchablePDFBuilder
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
      speech.speak(controller.pageTexts()[safe: controller.currentPageIndex]?.text ?? "")
    }
  }

  // MARK: - Annotating

  /// Marks up the selected text and saves; returns whether anything was selected.
  @discardableResult
  public func markUpSelection(_ markup: TextMarkup) async -> Bool {
    guard let controller, controller.markUpSelection(markup) else {
      errorMessage = String(localized: "Select some text first, then choose how to mark it.", bundle: .module)
      return false
    }
    await save()
    return true
  }

  /// Adds a note to the current page and saves.
  public func addNote(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let controller, !trimmed.isEmpty else { return }
    controller.addNote(trimmed, onPage: controller.currentPageIndex)
    await save()
  }

  /// Undoes the last annotation change and saves.
  public func undo() async {
    controller?.undoManager.undo()
    await save()
  }

  /// Writes changes atomically (autosave, FR-EDIT-007); a failed save changes nothing on disk.
  public func save() async {
    guard let controller, controller.hasUnsavedChanges else { return }
    do {
      try controller.save(to: try await library.fileURL(for: documentID))
      try await library.recordModified(documentID)
      await telemetry.record("task.core.completed")
    } catch {
      errorMessage = String(
        localized: "Couldn't save your changes. The document on disk hasn't changed. Try again.", bundle: .module)
      await telemetry.record("quality.operation.failed")
    }
  }

  // MARK: - Recognition

  /// Whether the document has pages with no text, so recognition can help (FR-SCAN-003).
  public var canRecognizeText: Bool {
    guard let document, phase == .ready else { return false }
    return !document.hasTextLayer && !document.isEncrypted
  }

  /// Recognises text on device and replaces the file with a searchable version, with progress.
  ///
  /// Unsaved notes and markup are saved first, so the searchable version includes them. If the
  /// document changes while recognition runs, the file is left alone, so nothing added meanwhile is lost.
  public func recognizeText() {
    guard recognitionProgress == nil else { return }
    recognitionProgress = 0
    recognition = Task {
      defer { recognitionProgress = nil }
      do {
        await save()
        // A failed save has already said so; replacing the file now would lose those changes.
        guard controller?.hasUnsavedChanges != true else { return }
        let url = try await library.fileURL(for: documentID)
        let version = try FileVersion(url)
        let result = try await builder.addTextLayer(toPDFAt: url) { progress in
          Task { @MainActor in self.recognitionProgress = progress }
        }
        // No suspension between this check and the write, so no save can slip in between.
        guard controller?.hasUnsavedChanges != true, try FileVersion(url) == version else {
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
        self?.assistantTask = nil
        self?.controller?.reveal(citation)
      })
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
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
