import Core
import CoreTestSupport
import Foundation
import PDFEngineTestSupport
import PDFKit
import SwiftUI
import Testing

@testable import PDFEngine
@testable import ReaderFeature

// The iOS 27 SDK adds a SwiftUI type also called `Document`; here the name means ours.
private typealias Document = Core.Document

@MainActor
private struct Harness {
  let library = FakeDocumentLibrary()
  let index = FakeIndex()
  let settings = InMemorySettingsStore()
  let telemetry = RecordingTelemetry()
  let signatures = InMemorySignatureStore()
  let checkpoints = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoints-\(UUID())")

  var intake: DocumentIntake { DocumentIntake(library: library, inspector: PDFKitInspector(), index: index) }

  func coordinator(
    recognizer: any TextRecognizing = FakeRecognizer(), keepAlive: BackgroundLog = BackgroundLog(),
    continued: (any ContinuedWork)? = nil
  ) -> RecognitionCoordinator {
    RecognitionCoordinator(
      library: library, intake: intake, builder: SearchablePDFBuilder(recognizer: recognizer, renderPixelSize: 400),
      telemetry: telemetry, folder: checkpoints, keepAlive: keepAlive.begin, continued: continued)
  }

  func reader(
    for document: Document, pageIndex: Int? = nil, task: AssistantTask? = nil,
    recognizer: any TextRecognizing = FakeRecognizer(), textEditing: TextEditingAccess = .available,
    diagnostics: TextEditingDiagnosticsLog? = nil, editor: any PDFTextEditing = ContentStreamTextEditor()
  ) -> ReaderModel {
    ReaderModel(
      selection: document.id, pageIndex: pageIndex, task: task, library: library,
      intake: intake, index: index, settings: settings, telemetry: telemetry,
      recognition: coordinator(recognizer: recognizer), signatures: signatures,
      speech: SpeechReader(engine: SilentSpeech()), textEditing: FixedTextEditingAccess(textEditing),
      textEditingDiagnostics: diagnostics, textEditor: editor)
  }

  func seed(
    _ data: Data, title: String = "Doc", lastPage: Int = 0, opened: Bool = false, textLayer: Bool = true
  ) async -> Document {
    await library.seed(
      Document(
        title: title, fileName: "\(UUID()).pdf", addedAt: .distantPast, lastOpenedAt: opened ? .distantPast : nil,
        lastPageIndex: lastPage, hasTextLayer: textLayer), data: data)
  }
}

@MainActor
@Suite("Reader model")
struct ReaderModelTests {
  @Test("A document opens where the reader left off (FR-READ-006)")
  func resumes() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample(), lastPage: 2, opened: true)
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(reader.phase == .ready)
    #expect(reader.controller?.currentPageIndex == 2)
    #expect(reader.pageLabel == "3 of 3")
    await reader.recordPosition()
    #expect(try await harness.library.document(withID: document.id)?.lastPageIndex == 2)
    #expect(await harness.telemetry.events.isEmpty)
  }

  @Test("A link to a page wins over the last position, and first opens are recorded")
  func explicitPage() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample(), lastPage: 2)
    let reader = harness.reader(for: document, pageIndex: 1, task: .summarize)
    await reader.load()
    #expect(reader.controller?.currentPageIndex == 1)
    #expect(reader.assistantTask == .summarize)
    #expect(await harness.telemetry.events == ["activation.first_document.opened"])
  }

  @Test("Password-protected documents ask for the password (FR-READ-001)")
  func passwords() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeEncrypted(pages: ["Private"], password: "pw"))
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(reader.phase == .locked(wrongPassword: false))
    reader.unlock(password: "nope")
    #expect(reader.phase == .locked(wrongPassword: true))
    reader.unlock(password: "pw")
    #expect(reader.phase == .ready)
  }

  @Test("Damaged or missing files show a plain failure")
  func failures() async throws {
    let harness = Harness()
    let damaged = await harness.seed(Data("%PDF-garbage".utf8))
    let reader = harness.reader(for: damaged)
    await reader.load()
    guard case .failed = reader.phase else { throw Failure.unexpected }
    let missing = harness.reader(for: Document(title: "x", fileName: "x.pdf", addedAt: .now))
    await missing.load()
    guard case .failed = missing.phase else { throw Failure.unexpected }
  }

  @Test("A save keeps the version before it, which can be restored and restored back (FR-EDIT-008)")
  func restoresTheVersionBeforeTheLastSave() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(!reader.canRestorePreviousVersion)
    await reader.addNote("Check this")
    #expect(reader.canRestorePreviousVersion)
    let url = try await harness.library.fileURL(for: document.id)

    await reader.restorePreviousVersion()
    #expect(reader.phase == .ready && reader.errorMessage == nil)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 0)
    await reader.restorePreviousVersion()
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
  }

  @Test("The version history lists kept versions and restores one (FR-EDIT-008)")
  func versionHistory() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addNote("Kept change")
    await reader.loadVersions()
    let version = try #require(reader.versions.first)
    reader.showsVersions = true
    await reader.restore(version)
    #expect(!reader.showsVersions && reader.phase == .ready)
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 0)
    let sheet = VersionHistorySheet(model: reader).frame(width: 390, height: 700)
    #expect(ImageRenderer(content: sheet).uiImage != nil)
  }

  @Test("A document that won't open offers the version before its last save")
  func damagedFileRecovers() async throws {
    let harness = Harness()
    let document = await harness.seed(Data("%PDF-garbage".utf8))
    let previous = try #require(try await harness.library.previousVersionURL(for: document.id))
    try SyntheticPDF.makeSample().write(to: previous)
    let reader = harness.reader(for: document)
    await reader.load()
    guard case .failed = reader.phase else { throw Failure.unexpected }
    #expect(reader.canRestorePreviousVersion)
    await reader.restorePreviousVersion()
    #expect(reader.phase == .ready)
  }

  @Test("A failed restore says so and leaves the document as it was")
  func failedRestore() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.restorePreviousVersion()
    #expect(reader.errorMessage != nil)
    #expect(reader.phase == .ready)
  }

  @Test("Pages rotate, move, delete and copy out from the page grid, each saved (FR-ORG-001)")
  func organisePages() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.make(pages: ["One", "Two", "Three"]), title: "Report")
    let reader = harness.reader(for: document)
    await reader.load()
    let url = try await harness.library.fileURL(for: document.id)
    func titles() throws -> [String] {
      try PDFDocumentController(url: url).pageTexts().map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    #expect(reader.allowsOrganizing)
    await reader.rotatePages([0], clockwise: true)
    #expect(try PDFDocumentController(url: url).document.page(at: 0)?.rotation == 90)
    #expect(await reader.movePage(2, earlier: true) == 1)
    #expect(try titles() == ["One", "Three", "Two"])
    #expect(await reader.movePage(0, earlier: true) == nil, "The first page can't move earlier")
    await reader.deletePages([0, 1, 2])
    #expect(reader.errorMessage != nil && reader.controller?.pageCount == 3, "At least one page stays")
    reader.errorMessage = nil
    await reader.deletePages([1])
    #expect(try titles() == ["One", "Two"])
    await reader.extractPages([1])
    #expect(reader.notice != nil)
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).map(\.title).contains("Report (pages)"))
    #expect(reader.canUndo)
  }

  @Test("Tools share a flattened copy and a page image, and reduce size into a copy or say it's small")
  func tools() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample(), title: "Invoice")
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.shareFlattened()
    let flat = try #require(reader.sharing?.url)
    #expect(flat.lastPathComponent == "Invoice (flattened).pdf")
    #expect(try PDFDocumentController(url: flat).pageCount == 3)
    await reader.sharePageImage()
    #expect(reader.sharing?.url.pathExtension == "png" && reader.sharing?.url != flat)

    await reader.reduceSize(.email)
    #expect(reader.notice != nil && reader.errorMessage == nil, "A small text document says so, or makes a copy")
    let titles = try await harness.library.documents(in: .all, sortedBy: .title).map(\.title)
    #expect(titles.allSatisfy { $0 == "Invoice" || $0 == "Invoice (smaller)" })
  }

  @Test("A password is added and removed from the reader, and the file follows (FR-EDIT-006)")
  func passwordTools() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    let url = try await harness.library.fileURL(for: document.id)
    #expect(!reader.isPasswordProtected)
    await reader.removePassword()
    #expect(reader.errorMessage != nil, "Nothing to remove")
    reader.errorMessage = nil
    await reader.setPassword("secret")
    #expect(reader.isPasswordProtected && reader.notice != nil)
    #expect(try PDFDocumentController(url: url).isLocked)
    #expect(reader.canRemovePassword)
    await reader.removePassword()
    #expect(!reader.isPasswordProtected)
    #expect(try !PDFDocumentController(url: url).isLocked)
  }

  @Test("A document whose author forbids changing its pages says so")
  func organiseRestricted() async throws {
    let harness = Harness()
    let document = await harness.seed(
      try TestPDFs.makeProtected(userPassword: nil, ownerPassword: "owner-pw", permissions: []))
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(!reader.allowsOrganizing)
    await reader.deletePages([0])
    #expect(reader.errorMessage != nil)
  }

  @Test("The page grid draws while selecting, at a large text size")
  func pageGridDraws() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try SyntheticPDF.makeSample()))
    await reader.load()
    let view = PageGrid(model: reader, isSelecting: true, selection: .constant([1])).frame(width: 390, height: 800)
      .environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: view).uiImage != nil)
    #expect(ImageRenderer(content: PageGridSheet(model: reader).frame(width: 390, height: 800)).uiImage != nil)
  }

  @Test("A signed document's changes go into a copy, so its signature stays valid (H9)")
  func signedDocumentsSaveACopy() async throws {
    let harness = Harness()
    let signed = await harness.seed(TestPDFs.makeSigned(.signed), title: "Signed lease")
    let original = try Data(contentsOf: try await harness.library.fileURL(for: signed.id))
    // The signature field is itself an annotation on the first page.
    let existing = try PDFDocumentController(data: original).annotationCount(onPage: 0)
    let reader = harness.reader(for: signed)
    await reader.load()
    await reader.addNote("First")
    #expect(reader.notice != nil && reader.errorMessage == nil)
    #expect(
      try Data(contentsOf: try await harness.library.fileURL(for: signed.id)) == original, "The original is untouched")
    let titles = try await harness.library.documents(in: .all, sortedBy: .title).map(\.title)
    #expect(titles.sorted() == ["Signed lease", "Signed lease (edited)"])
    #expect(reader.document?.title == "Signed lease (edited)")

    reader.notice = nil
    await reader.addNote("Second")
    #expect(reader.notice == nil, "Later saves go to the copy without asking again")
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).count == 2)
    let copyURL = try #require(reader.fileURL)
    #expect(try PDFDocumentController(url: copyURL).annotationCount(onPage: 0) == existing + 2)
    #expect(try Data(contentsOf: try await harness.library.fileURL(for: signed.id)) == original)
  }

  @Test("Saving with no changes leaves the file untouched, byte for byte (Trust suite, plan §4.1)")
  func unchangedSaveIsANoOp() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    let url = try await harness.library.fileURL(for: document.id)
    let bytes = try Data(contentsOf: url)
    let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    #expect(await reader.save())
    await reader.saveBeforeSuspending(keepAlive: { {} })
    #expect(try Data(contentsOf: url) == bytes)
    #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
    #expect(await !harness.library.hasPreviousVersion(of: document.id), "No earlier version is kept for a no-op")
  }

  @Test("The file watcher hears a coordinated write made on another thread, without a crash (H5)")
  func watcherHearsOtherThreads() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("watched-\(UUID().uuidString).pdf")
    try SyntheticPDF.make(pages: ["One"]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let heard = Heard()
    let watcher = FileWatcher(url: url) { heard.count += 1 }
    watcher.start()
    defer { watcher.stop() }
    let data = try SyntheticPDF.make(pages: ["Two"])
    // File coordination reads the presenter's URL and queue on its own threads; this failed with a
    // main-actor isolation crash when the watcher inherited the module's default isolation.
    await Task.detached {
      var error: NSError?
      NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &error) {
        try? data.write(to: $0)
      }
    }.value
    for _ in 0..<100 where heard.count == 0 { try await Task.sleep(for: .milliseconds(20)) }
    #expect(heard.count > 0)
  }

  @Test("Another app's change is shown when nothing is unsaved; its own saves aren't mistaken for one (H5)")
  func otherAppChange() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.make(pages: ["Mine"]), title: "Shared")
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addNote("Saved here")
    await reader.fileChangedOnDisk()
    #expect(reader.notice == nil && !reader.hasConflictingChange, "Its own save isn't another app's change")

    let url = try await harness.library.fileURL(for: document.id)
    try SyntheticPDF.make(pages: ["Theirs", "Two"]).write(to: url)
    await reader.fileChangedOnDisk()
    #expect(reader.notice != nil && reader.controller?.pageCount == 2)
    reader.stopWatching()
  }

  @Test("With unsaved changes, the person keeps theirs as a copy or takes the other version (H5)")
  func conflictingChange() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.make(pages: ["Mine"]), title: "Shared")
    let reader = harness.reader(for: document)
    await reader.load()
    let url = try await harness.library.fileURL(for: document.id)
    reader.controller?.addNote("Not saved yet", onPage: 0)
    try SyntheticPDF.make(pages: ["Theirs", "Two"]).write(to: url)
    await reader.fileChangedOnDisk()
    #expect(reader.hasConflictingChange)

    await reader.keepMineAsCopy()
    #expect(!reader.hasConflictingChange && reader.notice != nil)
    #expect(reader.controller?.pageCount == 2, "The original now shows the other app's version")
    let titles = try await harness.library.documents(in: .all, sortedBy: .title).map(\.title)
    #expect(titles.contains("Shared (my version)"))

    reader.controller?.addNote("Again", onPage: 0)
    try SyntheticPDF.make(pages: ["Third"]).write(to: url)
    await reader.fileChangedOnDisk()
    await reader.useOtherVersion()
    #expect(reader.controller?.pageCount == 1 && reader.controller?.needsSaving == false)
    await reader.setWatching(false)
    await reader.setWatching(true)
    reader.stopWatching()
  }

  @Test("Stamps are added to the page on screen and saved (FR-ANN-006)")
  func stamps() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addStamp(.tick)
    await reader.addStamp(.text("SK"))
    await reader.addStamp(.text("  "))
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 2)
    #expect(reader.canUndo)
  }

  @Test("The page on screen is bookmarked and unbookmarked, and the file keeps it (FR-READ-009)")
  func bookmarks() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample(), lastPage: 1, opened: true)
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(!reader.isCurrentPageBookmarked)
    await reader.toggleBookmark()
    #expect(reader.isCurrentPageBookmarked && reader.bookmarkedPages == [1])
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).bookmarkedPages == [1])
    await reader.toggleBookmark()
    #expect(!reader.isCurrentPageBookmarked)
  }

  @Test("Notes and markup save automatically and can be undone (FR-ANN-001, FR-EDIT-007)")
  func annotations() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addNote("Check this")
    await reader.addNote("   ")
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
    // With nothing selected, Highlight becomes the tool in hand instead of an error.
    #expect(await !reader.markUpSelection(.highlight))
    #expect(reader.errorMessage == nil && reader.markupTool == .highlight)
    reader.stopMarkupTool()
    #expect(reader.markupTool == nil)
    await reader.undo()
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 0)
    #expect(await harness.telemetry.events.contains("task.core.completed"))
  }

  @Test("Undo and redo follow the annotation history and save each step (FR-EDIT-007)")
  func undoAndRedo() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(!reader.canUndo && !reader.canRedo)
    await reader.redo()
    await reader.undo()
    await reader.addNote("First")
    #expect(reader.canUndo && !reader.canRedo)
    let url = try await harness.library.fileURL(for: document.id)

    await reader.undo()
    #expect(!reader.canUndo && reader.canRedo)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 0)
    await reader.redo()
    #expect(reader.canUndo && !reader.canRedo)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
  }

  @Test("Moving to the background saves, keeping the app alive until the save is written (defect D2)")
  func saveBeforeSuspending() async throws {
    let harness = Harness()
    let document = await harness.seed(try TestPDFs.makeForm())
    let reader = harness.reader(for: document)
    await reader.load()
    let widgets = try #require(reader.controller?.document.page(at: 0)?.annotations)
    try #require(widgets.first { $0.fieldName == "name" }).widgetStringValue = "Grace Hopper"
    let url = try await harness.library.fileURL(for: document.id)
    var steps: [String] = []

    await reader.saveBeforeSuspending {
      steps.append("began")
      return { steps.append("ended, saved: \(TestPDFs.storedValue(of: "name", in: url) ?? "nothing")") }
    }

    #expect(steps == ["began", "ended, saved: Grace Hopper"])
    #expect(try await harness.library.document(withID: document.id)?.lastOpenedAt != nil, "The position is kept too")
  }

  @Test("Form entries save automatically, with nothing else changed (defect D1)")
  func formEntriesSave() async throws {
    let harness = Harness()
    let document = await harness.seed(try TestPDFs.makeForm())
    let reader = harness.reader(for: document)
    await reader.load()
    let url = try await harness.library.fileURL(for: document.id)
    let before = try Data(contentsOf: url)
    await reader.save()
    #expect(try Data(contentsOf: url) == before, "Nothing to save, nothing written")

    let widgets = try #require(reader.controller?.document.page(at: 0)?.annotations)
    try #require(widgets.first { $0.fieldName == "name" }).widgetStringValue = "Ada Lovelace"
    await reader.save()

    #expect(TestPDFs.storedValue(of: "name", in: url) == "Ada Lovelace")
    #expect(reader.controller?.needsSaving == false)
    #expect(await harness.telemetry.events.contains("task.core.completed"))
  }

  @Test("Documents whose author forbids changes say so and stay as they were (defect D9)")
  func restrictedDocuments() async throws {
    let harness = Harness()
    let data = try TestPDFs.makeProtected(
      userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsLowQualityPrinting])
    let document = await harness.seed(data)
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(reader.phase == .ready)

    await reader.addNote("Not allowed")
    #expect(reader.errorMessage?.contains("doesn't allow") == true)
    reader.errorMessage = nil
    #expect(await !reader.markUpSelection(.highlight))
    #expect(reader.errorMessage?.contains("doesn't allow") == true)
    #expect(try Data(contentsOf: try await harness.library.fileURL(for: document.id)) == data)
    #expect(!reader.canUndo)
  }

  @Test("Go to page takes a page number from 1, and says when there is no such page (FR-READ-002, FR-READ-003)")
  func goToPage() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    #expect(!reader.goToPage("1"), "Nothing happens before the document opens")
    await reader.load()
    #expect(reader.goToPage(" 3 "))
    #expect(reader.controller?.currentPageIndex == 2)
    for invalid in ["0", "4", "two", ""] {
      reader.errorMessage = nil
      #expect(!reader.goToPage(invalid))
      #expect(reader.errorMessage?.contains("from 1 to 3") == true, "\(invalid)")
    }
    #expect(reader.controller?.currentPageIndex == 2)
    reader.controller?.showFind()
  }

  @Test("Sharing and printing save first, and respect the author's printing restriction")
  func shareAndPrint() async throws {
    let harness = Harness()
    let form = await harness.seed(try TestPDFs.makeForm())
    let reader = harness.reader(for: form)
    #expect(await reader.fileForSharing() == nil, "Nothing to share before the document opens")
    await reader.load()
    let widgets = try #require(reader.controller?.document.page(at: 0)?.annotations)
    try #require(widgets.first { $0.fieldName == "name" }).widgetStringValue = "Katherine Johnson"

    await reader.share()

    let url = try await harness.library.fileURL(for: form.id)
    #expect(reader.sharing == SharedFile(url: url, allowsPrinting: true))
    #expect(TestPDFs.storedValue(of: "name", in: url) == "Katherine Johnson", "Shared as the person sees it")

    let restricted = await harness.seed(
      try TestPDFs.makeProtected(userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsCommenting]))
    let noPrinting = harness.reader(for: restricted)
    await noPrinting.load()
    #expect(!noPrinting.allowsPrinting)
    await noPrinting.share()
    #expect(noPrinting.sharing?.allowsPrinting == false)
  }

  @Test("Drawing adds ink that is saved and can be undone; documents that forbid notes say so (F2a)")
  func drawing() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    reader.setDrawing(true)
    #expect(reader.isDrawing)
    reader.controller?.strokeEnded([CGPoint(x: 100, y: 500), CGPoint(x: 200, y: 520)], onPage: 0)
    let url = try await harness.library.fileURL(for: document.id)
    for _ in 0..<200 where (try? PDFDocumentController(url: url).annotationCount(onPage: 0)) != 1 {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
    #expect(reader.canUndo)
    reader.setDrawing(false)
    #expect(!reader.isDrawing)

    let restricted = harness.reader(
      for: await harness.seed(
        try TestPDFs.makeProtected(
          userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsLowQualityPrinting])))
    await restricted.load()
    restricted.setDrawing(true)
    #expect(!restricted.isDrawing && restricted.errorMessage?.contains("doesn't allow") == true)
  }

  @Test("Signatures are drawn, saved on this device, placed, typed and deleted (F1c, FR-EDIT-004)")
  func signing() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    reader.showSignatures()
    #expect(reader.showsSignatures)
    await reader.loadSignatures()
    #expect(reader.savedSignatures.isEmpty)
    #expect(await reader.saveSignature(drawn: []) == nil)

    let drawn = [[CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 40)], [CGPoint(x: 20, y: 30), CGPoint(x: 70, y: 30)]]
    let signature = try #require(await reader.saveSignature(drawn: drawn))
    #expect(try await harness.signatures.signatures() == [signature])
    await reader.place(signature)
    await reader.placeTyped("Ada Lovelace")
    await reader.placeTyped("   ")
    let url = try await harness.library.fileURL(for: document.id)
    let types = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.map(\.type))
    #expect(types.contains("Ink") && types.contains("FreeText") && types.count == 2)
    #expect(reader.canUndo)

    await reader.deleteSignature(signature.id)
    let remaining = try await harness.signatures.signatures()
    #expect(reader.savedSignatures.isEmpty && remaining.isEmpty)
    await harness.signatures.failNext(with: .keychain(-25308))
    await reader.loadSignatures()
    #expect(reader.errorMessage?.contains("signatures saved on this device") == true)

    let restricted = harness.reader(
      for: await harness.seed(
        try TestPDFs.makeProtected(
          userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsLowQualityPrinting])))
    await restricted.load()
    restricted.showSignatures()
    #expect(!restricted.showsSignatures && restricted.errorMessage?.contains("doesn't allow") == true)
  }

  @Test("The signature sheet draws at a large text size, with and without saved signatures")
  func signatureSheetDraws() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try SyntheticPDF.makeSample()))
    await reader.load()
    func draws() -> Bool {
      let view = SignatureSheet(model: reader).frame(width: 390, height: 800)
        .environment(\.dynamicTypeSize, .accessibility3)
      return ImageRenderer(content: view).uiImage != nil
    }
    #expect(draws())
    _ = await reader.saveSignature(drawn: [[CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20)]])
    #expect(draws())
    let preview = SignaturePreview(signature: try #require(reader.savedSignatures.first)).frame(width: 200, height: 60)
    #expect(ImageRenderer(content: preview).uiImage != nil)
  }

  @Test("Shapes are drawn with the chosen tool and text boxes are added, each saved (F2b)")
  func shapesAndTextBoxes() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    reader.setDrawing(true, tool: .arrow)
    #expect(reader.controller?.drawingTool == .arrow)
    reader.controller?.strokeEnded([CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 450)], onPage: 0)
    reader.setDrawing(false)
    await reader.addTextBox("Check with accounts")
    await reader.addTextBox("  ")
    let url = try await harness.library.fileURL(for: document.id)
    for _ in 0..<200 where (try? PDFDocumentController(url: url).annotationCount(onPage: 0)) != 2 {
      try await Task.sleep(for: .milliseconds(10))
    }
    let types = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.map(\.type))
    #expect(Set(types) == ["Line", "FreeText"])
  }

  @Test("Every drawing tool has a label", arguments: DrawingTool.allCases)
  func toolLabels(tool: DrawingTool) {
    _ = ReaderToolbar.label(for: tool)
  }

  @Test("A selected annotation can be deleted and its text edited, each saved (F3, FR-ANN-002)")
  func editingAnnotations() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addTextBox("Draft")
    let box = try #require(reader.controller?.document.page(at: 0)?.annotations.first?.bounds)
    #expect(reader.controller?.selectAnnotation(at: CGPoint(x: box.midX, y: box.midY), onPage: 0) == true)
    #expect(reader.selection?.kind == .textBox)
    await reader.setSelectionText("Final")
    let url = try await harness.library.fileURL(for: document.id)
    #expect(PDFDocument(url: url)?.page(at: 0)?.annotations.first?.contents == "Final")
    await reader.deleteSelection()
    #expect(reader.selection == nil)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 0)
    reader.clearSelection()

    let restricted = harness.reader(
      for: await harness.seed(
        try TestPDFs.makeProtected(
          userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsLowQualityPrinting])))
    await restricted.load()
    // PDFKit adds no annotation to a document whose author forbids comments, so nothing there can be
    // selected; the refusal is checked directly.
    await restricted.deleteSelection()
    #expect(restricted.errorMessage?.contains("doesn't allow") == true)
    restricted.errorMessage = nil
    await restricted.setSelectionText("New")
    #expect(restricted.errorMessage?.contains("doesn't allow") == true)
  }

  @Test("A selected annotation can be moved, resized and recoloured, each saved (FR-ANN-005)")
  func transformingAnnotations() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addTextBox("Draft")
    let box = try #require(reader.controller?.document.page(at: 0)?.annotations.first?.bounds)
    #expect(reader.controller?.selectAnnotation(at: CGPoint(x: box.midX, y: box.midY), onPage: 0) == true)
    let url = try await harness.library.fileURL(for: document.id)

    await reader.moveSelection(by: CGSize(width: 0, height: -40))
    let moved = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first?.bounds)
    #expect(abs(moved.minY - (box.minY - 40)) < 0.5)
    #expect(reader.canUndo)

    await reader.resizeSelection(by: 1.25)
    let resized = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first?.bounds)
    #expect(resized.width > moved.width)

    await reader.setSelectionColor(.red)
    #expect(reader.controller?.hasUnsavedChanges == false, "Saved after each change")
  }

  @Test(
    "A tapped link's confirmation draws for links that open and links that don't (T-02)",
    arguments: ["https://example.com/terms", "file:///etc/hosts"])
  func linkConfirmationDraws(address: String) throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    controller.linkTapped(try #require(URL(string: address)))
    let view = Text(verbatim: "Page").modifier(LinkConfirmation(controller: controller)).frame(width: 390, height: 700)
    #expect(ImageRenderer(content: view).uiImage != nil)
    controller.dismissLink()
    #expect(controller.tappedLink == nil)
  }

  @Test("The annotation list opens a page and exports as text (FR-ANN-003)")
  func annotationList() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try SyntheticPDF.makeSample()))
    await reader.load()
    #expect(reader.annotationSummaries.isEmpty)
    func draws() -> Bool {
      let sheet = AnnotationListSheet(model: reader).frame(width: 390, height: 700)
        .environment(\.dynamicTypeSize, .accessibility3)
      return ImageRenderer(content: sheet).uiImage != nil
    }
    #expect(draws(), "The empty list draws")
    await reader.addTextBox("Check the total")
    #expect(draws(), "The list with an annotation draws")
    #expect(reader.annotationSummaries.map(\.kind) == [.textBox])
    let text = reader.annotationsText()
    #expect(text.contains("Page 1") && text.contains("Text box: Check the total"))
    reader.showsAnnotations = true
    reader.openAfterClosingSheets(pageIndex: 0)
    #expect(!reader.showsAnnotations)
    let signature = AnnotationSummary(id: 0, kind: .ink, pageIndex: 0, text: nil, isSignature: true)
    #expect(ReaderModel.name(of: signature) == "Signature")
  }

  @Test("The selection bar draws for every kind at a large text size", arguments: AnnotationSelection.Kind.allCases)
  func selectionBarDraws(kind: AnnotationSelection.Kind) {
    let view = SelectionBar(
      selection: AnnotationSelection(kind: kind, pageIndex: 0, text: "Text"), onEdit: {}, onDelete: {}, onDone: {},
      onMove: { _ in }, onResize: { _ in }, onColor: { _ in }
    )
    .frame(width: 390).environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: view).uiImage != nil)
  }

  @Test("Layout choices are remembered")
  func displayMode() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try SyntheticPDF.makeSample()))
    await reader.load()
    reader.setDisplayMode(.singlePage)
    #expect(reader.controller?.displayMode == .singlePage)
    #expect(harness.settings.load().readerDisplayMode == .singlePage)
  }

  @Test("Image-only documents gain searchable text on device (FR-SCAN-003)")
  func recognition() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["Scanned"]), textLayer: false)
    let reader = harness.reader(for: document)
    await reader.load()
    #expect(reader.canRecognizeText)
    reader.recognizeText()
    for _ in 0..<200 where reader.recognitionProgress != nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(reader.recognitionProgress == nil)
    #expect(reader.document?.hasTextLayer == true)
    #expect(!reader.canRecognizeText)
    #expect(await reader.pageTexts().first?.text == "Recognised text")

    // Recognition keeps the version before it, like a save; restoring it brings back the image-only
    // file, and the library's view of its text follows (FR-EDIT-008).
    #expect(await harness.library.hasPreviousVersion(of: document.id))
    await reader.restorePreviousVersion()
    #expect(reader.phase == .ready)
    #expect(reader.document?.hasTextLayer == false)
    #expect(reader.canRecognizeText)
  }

  @Test("A note saved while text is being recognised is kept, not overwritten")
  func recognitionKeepsChangesMadeMeanwhile() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["Scanned"]), textLayer: false)
    let recognizer = GatedRecognizer()
    let reader = harness.reader(for: document, recognizer: recognizer)
    await reader.load()
    reader.recognizeText()
    for _ in 0..<200 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    await reader.addNote("Added meanwhile")
    await recognizer.open()
    for _ in 0..<200 where reader.recognitionProgress != nil { try await Task.sleep(for: .milliseconds(20)) }
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
    #expect(reader.errorMessage != nil)
    #expect(reader.canRecognizeText)
  }

  @Test("The assistant gets the page texts and can reveal a citation")
  func assistantContext() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    let context = reader.assistantContext(for: .ask)
    #expect(context.task == .ask)
    #expect(await context.pages().count == 3)
    reader.assistantTask = .ask
    context.reveal(Citation(pageIndex: 1, quote: "Invoice number"))
    #expect(reader.assistantTask == nil)
    #expect(reader.controller?.currentPageIndex == 0, "The page opens once the sheet has closed")
    reader.assistantDismissed()
    #expect(reader.controller?.currentPageIndex == 1)
    reader.assistantDismissed()
    context.reveal(Citation(pageIndex: 2, quote: nil))
    #expect(reader.controller?.currentPageIndex == 2, "With no sheet open, the page opens at once")
    await harness.index.seed(document.id, pages: [PageText(pageIndex: 0, text: "stored")])
    #expect(await context.pages().map(\.text) == ["stored"])
  }

  @Test("A page chosen in Contents or Pages opens once the sheet has closed")
  func pageAfterSheet() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    reader.showsPages = true
    reader.openAfterClosingSheets(pageIndex: 2)
    #expect(!reader.showsPages && reader.controller?.currentPageIndex == 0)
    reader.pageSheetDismissed()
    #expect(reader.controller?.currentPageIndex == 2)
    reader.showsOutline = true
    reader.openAfterClosingSheets(pageIndex: 1)
    #expect(!reader.showsOutline)
    reader.pageSheetDismissed()
    reader.pageSheetDismissed()
    #expect(reader.controller?.currentPageIndex == 1, "A second dismissal opens nothing")
  }

  @Test("AI can be hidden (FR-AI-009)")
  func hiddenIntelligence() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try SyntheticPDF.makeSample()))
    #expect(reader.showsIntelligence)
    harness.settings.save(AppSettings(isIntelligenceHidden: true))
    #expect(!reader.showsIntelligence)
  }

  @Test("The locked, failed and recognising states draw at a large text size")
  func statesDraw() async throws {
    let harness = Harness()
    func draws(_ reader: ReaderModel) -> Bool {
      let view = ReaderView(model: reader) { _ in EmptyView() }
        .frame(width: 390, height: 700).environment(\.dynamicTypeSize, .accessibility3)
      return ImageRenderer(content: view).uiImage != nil
    }
    let locked = harness.reader(
      for: await harness.seed(try SyntheticPDF.makeEncrypted(pages: ["Private"], password: "pw")))
    await locked.load()
    #expect(draws(locked))
    locked.unlock(password: "nope")
    #expect(draws(locked))
    let damaged = harness.reader(for: await harness.seed(Data("%PDF-garbage".utf8)))
    await damaged.load()
    #expect(draws(damaged))
    let recognizer = GatedRecognizer()
    let scanned = harness.reader(
      for: await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["Scanned"]), textLayer: false),
      recognizer: recognizer)
    await scanned.load()
    scanned.recognizeText()
    for _ in 0..<200 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    #expect(scanned.recognitionProgress != nil)
    #expect(draws(scanned))
    await recognizer.open()
    for _ in 0..<200 where scanned.recognitionProgress != nil { try await Task.sleep(for: .milliseconds(20)) }
  }

  @Test("Stopping recognition, even on the last page, leaves the file as it was")
  func stoppingRecognition() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["Scanned"]), textLayer: false)
    let url = try await harness.library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    let recognizer = GatedRecognizer()
    let reader = harness.reader(for: document, recognizer: recognizer)
    await reader.load()
    reader.recognizeText()
    for _ in 0..<200 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    reader.cancelRecognition()
    await recognizer.open()
    for _ in 0..<200 where reader.recognitionProgress != nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(reader.recognitionProgress == nil && reader.errorMessage == nil)
    #expect(try Data(contentsOf: url) == original)
    #expect(reader.canRecognizeText)
  }

  @Test("Read aloud ends when the system finishes or cancels speech")
  func speechEnds() {
    let engine = SilentSpeech()
    let speech = SpeechReader(engine: engine)
    speech.speak("   ")
    #expect(!speech.isSpeaking && engine.spoken.isEmpty, "Blank text is not spoken")
    speech.speak(" One ")
    #expect(speech.isSpeaking && engine.spoken == ["One"])
    engine.onEnd?(true)
    #expect(!speech.isSpeaking)
    speech.speak("Two")
    speech.stop()
    #expect(!speech.isSpeaking && engine.stops == 1)
  }

  @Test("Reading goes on page by page, skips blank pages, turns the pages and stops at the end (FR-READ-008)")
  func readsPageAfterPage() {
    let engine = SilentSpeech()
    let speech = SpeechReader(engine: engine)
    let pages = ["One", "  ", "Three", "Four"]
    var shown: [Int] = []
    speech.read(from: 0, pageCount: pages.count, text: { pages[$0] }, onPage: { shown.append($0) })
    #expect(engine.spoken == ["One"] && speech.isSpeaking)
    engine.onEnd?(true)
    #expect(engine.spoken == ["One", "Three"] && shown == [0, 2], "The blank page is skipped")
    engine.onEnd?(true)
    engine.onEnd?(true)
    #expect(engine.spoken == ["One", "Three", "Four"] && !speech.isSpeaking, "Reading stops after the last page")
  }

  @Test("A cancel or a stop ends reading; it doesn't go on to the next page")
  func readingStops() {
    let engine = SilentSpeech()
    let speech = SpeechReader(engine: engine)
    speech.read(from: 1, pageCount: 3, text: { "Page \($0)" }, onPage: { _ in })
    #expect(engine.spoken == ["Page 1"])
    engine.onEnd?(false)
    #expect(!speech.isSpeaking)
    engine.onEnd?(true)
    #expect(engine.spoken == ["Page 1"], "Nothing more after a cancel")
    speech.read(from: 0, pageCount: 3, text: { "Page \($0)" }, onPage: { _ in })
    speech.stop()
    engine.onEnd?(true)
    #expect(engine.spoken == ["Page 1", "Page 0"] && !speech.isSpeaking)
    speech.read(from: 5, pageCount: 3, text: { "Page \($0)" }, onPage: { _ in })
    #expect(!speech.isSpeaking, "Past the end there is nothing to read")
  }

  @Test("The system engine touches the voices only when asked to speak")
  func systemEngineIsLazy() {
    let engine = SystemSpeechEngine()
    engine.stop()
    _ = SpeechReader(engine: engine)
  }

  @Test func readAloudToggles() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try SyntheticPDF.makeSample()))
    await reader.load()
    reader.toggleReadAloud()
    #expect(reader.speech.isSpeaking)
    reader.toggleReadAloud()
    #expect(!reader.speech.isSpeaking)
  }

  @Test("Every markup kind has a label", arguments: TextMarkup.allCases)
  func markupLabels(markup: TextMarkup) {
    _ = ReaderToolbar.label(for: markup)
  }
}

@MainActor
@Suite("Reader: editing existing text (FR-EDIT-001)")
struct ReaderTextEditingTests {
  private typealias Line = TextEditFixtures.Line

  /// Opens a document, enters text editing and picks the region containing some text.
  private func editing(
    _ data: Data, in harness: Harness, title: String = "Doc", picking text: String? = nil, textLayer: Bool = true
  ) async throws -> (reader: ReaderModel, document: Document) {
    let document = await harness.seed(data, title: title, textLayer: textLayer)
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.beginTextEditing()
    if let text { try await pick(text, in: reader) }
    return (reader, document)
  }

  private func pick(_ text: String, in reader: ReaderModel, page: Int = 0) async throws {
    let controller = try #require(reader.controller)
    let regions = await controller.pageText(onPage: page).regions
    controller.selectTextRegion(try #require(regions.first { $0.text.contains(text) }), onPage: page)
    reader.textRegionPicked()
  }

  private func savedText(_ document: Document, in harness: Harness) async throws -> String {
    let url = try await harness.library.fileURL(for: document.id)
    return try PDFDocumentController(url: url).pageText(at: 0).filter { !$0.isWhitespace }
  }

  @Test("Edit is offered only when the build and the person have it")
  func access() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())

    let hidden = harness.reader(for: document, textEditing: .hidden)
    await hidden.load()
    await hidden.beginTextEditing()
    #expect(hidden.textEditingAccess == .hidden && !hidden.isEditingText && !hidden.showsTextEditingLocked)

    let locked = harness.reader(for: document, textEditing: .locked)
    await locked.load()
    await locked.beginTextEditing()
    #expect(locked.textEditingAccess == .locked && !locked.isEditingText && locked.showsTextEditingLocked)

    let available = harness.reader(for: document)
    await available.load()
    await available.beginTextEditing()
    #expect(available.textEditingAccess == .available && available.isEditingText)
    #expect(available.textEditMessage == nil && available.errorMessage == nil)
    await available.endTextEditing()
    #expect(!available.isEditingText)
    // Before the document is ready, or with none, nothing happens.
    let unloaded = harness.reader(for: document)
    await unloaded.beginTextEditing()
    await unloaded.endTextEditing()
    #expect(!unloaded.isEditingText)
  }

  @Test("Scenario 1: picking a name, typing a new one and pressing Done changes the saved file")
  func commit() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(try TextEditFixtures.invoice(), in: harness, picking: "John Smith")
    #expect(reader.selectedTextRegion?.region.text == "Customer: John Smith" && reader.textEditMessage == nil)
    #expect(reader.selection == nil, "Picked text is not a selected annotation")
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    #expect(reader.selectedTextRegion == nil && reader.textEditMessage == nil && reader.errorMessage == nil)
    #expect(reader.canUndo && reader.isEditingText && !reader.isCommittingTextEdit)
    let saved = try await savedText(document, in: harness)
    #expect(saved.contains("Customer:DavidSmith") && !saved.contains("John"))
    #expect(await harness.library.hasPreviousVersion(of: document.id), "The version before the edit is kept")
    #expect(await harness.telemetry.events.contains("task.core.completed"))
  }

  @Test("Cancelling, or pressing Done without changing anything, leaves the file as it was")
  func cancel() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(try TextEditFixtures.invoice(), in: harness, picking: "John Smith")
    let url = try await harness.library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    reader.cancelTextEdit()
    #expect(reader.selectedTextRegion == nil && reader.isEditingText)
    try await pick("John Smith", in: reader)
    #expect(await !reader.commitTextEdit("  Customer: John Smith "))
    #expect(reader.selectedTextRegion == nil && !reader.canUndo)
    #expect(await !reader.commitTextEdit("Nothing picked"))
    await reader.endTextEditing()
    #expect(try Data(contentsOf: url) == original)
    #expect(await harness.index.stored[document.id] == nil, "Nothing changed, so nothing was indexed again")
  }

  @Test("An edit is undone and redone, and the saved file follows; not while text is being typed")
  func undo() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(try TextEditFixtures.invoice(), in: harness, picking: "John Smith")
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    try await pick("Materials", in: reader)
    await reader.undo()
    #expect(try await savedText(document, in: harness).contains("DavidSmith"), "Undo waits for the edit in hand")
    reader.cancelTextEdit()
    await reader.undo()
    #expect(try await savedText(document, in: harness).contains("JohnSmith") && reader.canRedo)
    await reader.redo()
    #expect(try await savedText(document, in: harness).contains("DavidSmith"))
  }

  @Test("A replacement that does not fit or cannot be drawn is explained, and what was typed is kept")
  func refusals() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(
      try TextEditFixtures.resume(hasRoom: false), in: harness, picking: "2024 Data Analyst")
    let url = try await harness.library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    #expect(await !reader.commitTextEdit("2025 Senior Data Scientist"))
    #expect(reader.textEditMessage == .tooLong && reader.selectedTextRegion != nil, "The editor stays open")
    #expect(await !reader.commitTextEdit("Analyst 👍"))
    #expect(reader.textEditMessage == .unsupportedCharacters && reader.selectedTextRegion != nil)
    #expect(try Data(contentsOf: url) == original && reader.errorMessage == nil && !reader.canUndo)
    // A shorter title fits, and the message goes.
    #expect(await reader.commitTextEdit("2025 Data Lead"))
    #expect(reader.textEditMessage == nil)
  }

  @Test("Scenario 5: a scanned page says it has images, not text, and offers to recognise it")
  func scanned() async throws {
    let harness = Harness()
    let (reader, _) = try await editing(
      try SyntheticPDF.makeImageOnly(pages: ["A scanned letter"]), in: harness, textLayer: false)
    #expect(reader.isEditingText && reader.textEditMessage == .pageIsImage && reader.canRecognizeText)
    let hint = TextEditHint(model: reader).frame(width: 390).environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: hint).uiImage != nil)
  }

  @Test("What the reader says follows the page on screen")
  func pageChanges() async throws {
    let harness = Harness()
    let text = try #require(PDFDocument(data: try TextEditFixtures.invoice()))
    let image = try #require(PDFDocument(data: try SyntheticPDF.makeImageOnly(pages: ["Scan"])))
    text.insert(try #require(image.page(at: 0)), at: 1)
    let (reader, _) = try await editing(try #require(text.dataRepresentation()), in: harness)
    #expect(reader.textEditMessage == nil)
    reader.controller?.goTo(pageIndex: 1)
    await reader.textEditingPageChanged()
    #expect(reader.textEditMessage == .pageIsImage)
    reader.controller?.goTo(pageIndex: 0)
    await reader.textEditingPageChanged()
    #expect(reader.textEditMessage == nil)
  }

  @Test("A document whose author does not allow changes cannot be edited, and says why")
  func restricted() async throws {
    let harness = Harness()
    let (reader, _) = try await editing(
      try TestPDFs.makeProtected(userPassword: nil, ownerPassword: "owner", permissions: [.allowsHighQualityPrinting]),
      in: harness)
    #expect(!reader.isEditingText && reader.errorMessage?.contains("doesn't allow") == true)
  }

  @Test("A signed document is edited only after the person agrees, and then in a copy")
  func signed() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(TestPDFs.makeSigned(.signed), in: harness, title: "Signed lease")
    let url = try await harness.library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    #expect(reader.confirmsEditingSigned && !reader.isEditingText)
    reader.confirmsEditingSigned = false
    await reader.confirmEditingSigned()
    #expect(reader.isEditingText && !reader.confirmsEditingSigned)
    try await pick("Signed agreement", in: reader)
    #expect(await reader.commitTextEdit("Signed contract"))
    #expect(try Data(contentsOf: url) == original, "The signed original is untouched")
    #expect(reader.document?.title == "Signed lease (edited)" && reader.notice != nil)
    let copy = try #require(reader.fileURL)
    #expect(try PDFDocumentController(url: copy).pageText(at: 0).contains("Signed contract"))
    // Entering again does not ask again.
    await reader.endTextEditing()
    await reader.beginTextEditing()
    #expect(reader.isEditingText && !reader.confirmsEditingSigned)
  }

  @Test("Text that can only be covered says so before Done, and covering it is not an edit of the text")
  func covering() async throws {
    let harness = Harness()
    let data = try TextEditFixtures.make(pages: [[]]) { context, _ in
      context.setAlpha(0.4)
      TextEditFixtures.draw(Line("Faded label", size: 24, at: CGPoint(x: 72, y: 500)), in: context)
    }
    let (reader, document) = try await editing(data, in: harness, picking: "Faded label")
    #expect(reader.textEditMessage == .coversOriginal)
    #expect(await reader.commitTextEdit("Clear label"))
    let url = try await harness.library.fileURL(for: document.id)
    let saved = try PDFDocumentController(url: url)
    #expect(saved.annotationCount(onPage: 0) == 2 && saved.pageText(at: 0).contains("Faded label"))
    await reader.endTextEditing()
    #expect(await harness.index.stored[document.id] == nil, "The page's own text did not change")
  }

  @Test("Search finds the new words once editing ends, not after every edit")
  func searchTextFollows() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(try TextEditFixtures.invoice(), in: harness, picking: "John Smith")
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    #expect(await harness.index.stored[document.id] == nil)
    await reader.endTextEditing()
    let indexed = try #require(await harness.index.stored[document.id]?.first?.text)
    #expect(indexed.contains("David Smith") && !indexed.contains("John"))
    // Closing the reader does the same for an edit made and left in editing mode.
    await reader.beginTextEditing()
    try await pick("Materials", in: reader)
    #expect(await reader.commitTextEdit("Timber"))
    await reader.saveBeforeClosing()
    #expect(await harness.index.stored[document.id]?.first?.text.contains("Timber") == true)
  }

  @Test("Undoing a note does not send the whole document to be indexed again")
  func annotationUndoDoesNotReindex() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document)
    await reader.load()
    await reader.addNote("A note")
    await reader.undo()
    await reader.saveBeforeClosing()
    #expect(await harness.index.stored[document.id] == nil)
  }

  @Test("Entering text editing puts down the markup tool, and drawing leaves text editing")
  func modes() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document)
    await reader.load()
    reader.startMarkupTool(.highlight)
    await reader.beginTextEditing()
    #expect(reader.isEditingText && reader.markupTool == nil)
    reader.setDrawing(true)
    #expect(reader.isDrawing && !reader.isEditingText)
  }

  @Test("The editor draws at a large text size, with and without the field in the bar")
  func draws() async throws {
    let harness = Harness()
    let (reader, _) = try await editing(try TextEditFixtures.invoice(), in: harness, picking: "John Smith")
    let draft = TextEditDraft()
    draft.text = "Customer: David Smith"
    for isInPlace in [nil, true, false] {
      draft.isInPlace = isInPlace
      let bar = TextEditBar(model: reader, draft: draft).frame(width: 390)
        .environment(\.dynamicTypeSize, .accessibility3)
      #expect(ImageRenderer(content: bar).uiImage != nil)
    }
    let selection = try #require(reader.selectedTextRegion)
    let layer = TextEditLayer(model: reader, selection: selection, draft: draft).frame(width: 390, height: 700)
    #expect(ImageRenderer(content: layer).uiImage != nil)
    #expect(!TextEditLayer.fitsInPlace(selection, frame: nil))
    #expect(TextEditLayer.fitsInPlace(selection, frame: CGRect(x: 40, y: 200, width: 200, height: 18)))
    #expect(!TextEditLayer.fitsInPlace(selection, frame: CGRect(x: 40, y: 200, width: 200, height: 6)))
    #expect(!TextEditLayer.isLight(selection.region))
    #expect(TextEditLayer.font(for: selection.region, scale: 1.5).fontName == "Georgia")
    #expect(TextEditLayer.color(for: selection.region).cgColor.components?.prefix(3).allSatisfy { $0 < 0.01 } == true)
    for message in [
      ReaderModel.TextEditMessage.pageIsImage, .pageNotEditable, .tooLong, .unsupportedCharacters, .cannotEdit,
      .fontMatched, .coversOriginal, .lookingForText, .noEditableText, .tookTooLong, .cannotEditOrCover,
    ] {
      #expect(ImageRenderer(content: TextEditMessageLabel(message: message).frame(width: 300)).uiImage != nil)
    }
    reader.cancelTextEdit()
    #expect(!reader.showsTextEditStartHint, "Once text has been picked, how to start is not said again")
  }

  @Test("A document that is loaded again is edited through its new controller")
  func reload() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(try TextEditFixtures.invoice(), in: harness)
    let first = try #require(reader.controller)
    await reader.endTextEditing()
    // Showing the reader again loads the document again, as going back to the library and
    // opening the same document does.
    await reader.load()
    let second = try #require(reader.controller)
    #expect(second !== first)
    await reader.beginTextEditing()
    #expect(reader.isEditingText && second.isEditingText && !first.isEditingText)
    try await pick("John Smith", in: reader)
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    #expect(try await savedText(document, in: harness).contains("DavidSmith"))
  }

  @Test("A page whose text cannot be offered says so instead of inviting taps")
  func nothingToEdit() async throws {
    let harness = Harness()
    // The page is said to have text, but nothing on it is offered, and PDFKit reads no line of it
    // that could be covered either.
    let blank = await harness.seed(TextEditFixtures.raw(content: ""), title: "Blank")
    let reader = harness.reader(for: blank, editor: StubEditor(regions: false))
    await reader.load()
    await reader.beginTextEditing()
    #expect(reader.isEditingText && reader.textEditMessage == .noEditableText)
  }

  @Test("Finding text that takes a while says it is looking, and past the limit says it took too long")
  func slowPage() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let gate = Gate()
    let reader = harness.reader(for: document, editor: StubEditor(find: gate))
    await reader.load()
    try #require(reader.controller).textFindLimit = .seconds(600)
    let entering = Task { await reader.beginTextEditing() }
    // The text is held back for as long as it takes the reader to say that it is looking.
    for _ in 0..<3000 where reader.textEditMessage != .lookingForText {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(reader.textEditMessage == .lookingForText)
    await gate.open()
    await entering.value
    #expect(reader.textEditMessage == nil, "Found in time: nothing to say")

    let held = Gate()
    let slow = harness.reader(for: document, editor: StubEditor(find: held))
    await slow.load()
    try #require(slow.controller).textFindLimit = .milliseconds(50)
    await slow.beginTextEditing()
    #expect(slow.textEditMessage == .tookTooLong)
    await held.open()
  }

  @Test("An edit that takes too long is refused, says so, and changes nothing")
  func slowEdit() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let gate = Gate()
    let reader = harness.reader(for: document, editor: StubEditor(edit: gate))
    await reader.load()
    let controller = try #require(reader.controller)
    controller.textFindLimit = .seconds(600)
    controller.textEditLimit = .milliseconds(50)
    await reader.beginTextEditing()
    try await pick("John Smith", in: reader)
    #expect(await reader.commitTextEdit("Customer: David Smith") == false)
    #expect(reader.textEditMessage == .tookTooLong)
    #expect(reader.selectedTextRegion != nil, "The editor stays open with what was typed")
    // The editor's answer arrives after the limit; it must not reach the document.
    await gate.open()
    await gate.answers(1)
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.pageText(at: 0).contains("John Smith") && !controller.hasUnsavedTextEdits)
    #expect(try await savedText(document, in: harness).contains("JohnSmith"))
  }

  @Test("The editing summary for a problem report holds counts and none of the document's words")
  func diagnostics() async throws {
    let harness = Harness()
    let log = TextEditingDiagnosticsLog()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document, diagnostics: log)
    await reader.load()
    #expect(log.summary().isEmpty, "Nothing is said before text is edited")
    await reader.beginTextEditing()
    let controller = try #require(reader.controller)
    let regions = await controller.pageText(onPage: 0).regions
    let target = try #require(regions.first { $0.text.contains("John Smith") })
    let middle = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
    #expect(await controller.selectTextRegion(at: middle, onPage: 0, reach: 4))
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    let summary = log.summary().joined(separator: "\n")
    #expect(summary.contains("Text editing page: text") && summary.contains("taps: 1, picked 1"))
    #expect(summary.contains("last edit: made"))
    // Every word of the summary is one the app chose; none can have come from the document.
    let vocabulary: Set<String> = [
      "text", "editing", "page", "regions", "direct", "matched", "font", "cover", "only", "find", "ms", "view",
      "bound", "not", "outlined", "pages", "taps", "picked", "last", "edit", "made", "too", "long", "refused",
      "proof", "rehearsal", "proven", "session", "covered",
    ]
    #expect(summary.contains("rehearsal: proven") && summary.contains("session: made 1, covered 0, refused 0"))
    let reasons = Set(
      TextEditRefusal.allCases.map { $0.rawValue.lowercased() }
        + TextEditProofFailure.Check.allCases.map { $0.rawValue.lowercased() })
    let said = summary.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
    #expect(said.allSatisfy { vocabulary.contains($0) || reasons.contains($0) || Int($0) != nil }, "\(said)")
    #expect(!summary.contains("Smith") && !summary.contains("David") && !summary.contains("Helvetica"))
  }

  @Test("The tip that points at Edit is offered only where a tap on Edit lets the person start at once")
  func editTip() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())

    let reader = harness.reader(for: document)
    #expect(!reader.offersEditTip, "Not before the document is open")
    await reader.load()
    #expect(reader.offersEditTip)
    #expect(await reader.currentPageHasEditableText())

    // Never for a feature that is locked or absent.
    for access in [TextEditingAccess.locked, .hidden] {
      let other = harness.reader(for: document, textEditing: access)
      await other.load()
      #expect(!other.offersEditTip, "\(access)")
    }

    // Never over something else, or while the reader is doing something else.
    reader.assistantTask = .summarize
    #expect(!reader.offersEditTip)
    reader.assistantTask = nil
    reader.showsPages = true
    #expect(!reader.offersEditTip)
    reader.showsPages = false
    reader.setDrawing(true)
    #expect(!reader.offersEditTip)
    reader.setDrawing(false)
    #expect(reader.offersEditTip)
    await reader.beginTextEditing()
    #expect(reader.isEditingText && !reader.offersEditTip)
    await reader.endTextEditing()

    // Not where Edit would answer with a refusal, a question or "this page is an image".
    let restricted = harness.reader(
      for: await harness.seed(
        try TestPDFs.makeProtected(
          userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsLowQualityPrinting]),
        title: "Restricted"))
    await restricted.load()
    #expect(!restricted.offersEditTip)
    let signed = harness.reader(for: await harness.seed(TestPDFs.makeSigned(.signed), title: "Signed"))
    await signed.load()
    #expect(!signed.offersEditTip)
    let scanned = harness.reader(
      for: await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["A scanned letter"]), textLayer: false))
    await scanned.load()
    #expect(await scanned.currentPageHasEditableText() == false)
  }

  @Test("The Edit button and its tip draw at every text size, in both appearances")
  func editButtonDraws() async throws {
    let harness = Harness()
    let reader = harness.reader(for: await harness.seed(try TextEditFixtures.invoice()))
    await reader.load()
    for scheme in [ColorScheme.light, .dark] {
      for size in [DynamicTypeSize.large, .accessibility5] {
        let button = EditTextButton(model: reader).environment(\.colorScheme, scheme)
          .environment(\.dynamicTypeSize, size)
        #expect(ImageRenderer(content: button).uiImage != nil)
        let tip = EditTipCardBody(title: Text(verbatim: "Edit this PDF"), message: Text(verbatim: "Tap Edit.")) {}
          .frame(width: 390).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
        #expect(ImageRenderer(content: tip).uiImage != nil)
      }
    }
  }

  @Test("An edit that cannot be proven is finished by covering, and the reader says so until it is told to stop")
  func coveredInstead() async throws {
    let harness = Harness()
    let log = TextEditingDiagnosticsLog()
    let document = await harness.seed(try TextEditFixtures.invoice())
    // The rehearsal passes, so the failure comes only after the person has typed.
    let reader = harness.reader(for: document, diagnostics: log, editor: RefusingEditor(rehearsalsFail: false))
    await reader.load()
    await reader.beginTextEditing()
    await reader.controller?.finishTextRehearsal(onPage: 0)
    try await pick("John Smith", in: reader)
    #expect(reader.textEditMessage != .coversOriginal, "As far as anyone knew, this text could be edited")

    #expect(await reader.commitTextEdit("Customer: David Smith"), "Done finishes: the typing is not lost")
    #expect(reader.textEditNotice == .coveredInstead && reader.textEditMessage == nil)
    #expect(reader.selectedTextRegion == nil && reader.canUndo)
    let controller = try #require(reader.controller)
    #expect(controller.annotationCount(onPage: 0) == 2)
    // It is a cover, and nothing pretends otherwise: the old words are still the page's words.
    let url = try await harness.library.fileURL(for: document.id)
    let saved = try PDFDocumentController(url: url)
    #expect(saved.annotationCount(onPage: 0) == 2 && saved.pageText(at: 0).contains("John Smith"))
    #expect(log.summary().contains("Text editing session: made 0, covered 1, refused 1"))
    #expect(log.summary().contains("Text editing proof: newTextMissing 0/-14"))
    let card = TextEditNoticeCard(model: reader).frame(width: 390).environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: card).uiImage != nil)
    #expect(ImageRenderer(content: TextEditHint(model: reader).frame(width: 390)).uiImage != nil)

    // The rest of the page now says so before anyone types.
    try await pick("Materials", in: reader)
    #expect(reader.textEditMessage == .coversOriginal && reader.textEditNotice == nil)
    reader.cancelTextEdit()

    // Undo from the notice takes the cover away again.
    try await pick("Invoice", in: reader)
    reader.cancelTextEdit()
    await reader.endTextEditing()
    #expect(await harness.index.stored[document.id] == nil, "The page's own text did not change")
  }

  @Test("The notice's Undo takes the cover back, and OK only puts the notice away")
  func coveredInsteadUndo() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document, editor: RefusingEditor(rehearsalsFail: false))
    await reader.load()
    await reader.beginTextEditing()
    try await pick("John Smith", in: reader)
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    let controller = try #require(reader.controller)
    reader.dismissTextEditNotice()
    #expect(reader.textEditNotice == nil && controller.annotationCount(onPage: 0) == 2, "OK keeps the cover")

    try await pick("Materials", in: reader)
    #expect(await reader.commitTextEdit("Timber"))
    #expect(reader.textEditNotice == nil, "This one said it would cover before it was typed")
    #expect(controller.annotationCount(onPage: 0) == 4)
  }

  @Test("Undo on the notice removes the cover")
  func coveredInsteadIsUndone() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document, editor: RefusingEditor(rehearsalsFail: false))
    await reader.load()
    await reader.beginTextEditing()
    try await pick("John Smith", in: reader)
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    await reader.undoCoverInstead()
    #expect(reader.textEditNotice == nil)
    #expect(try #require(reader.controller).annotationCount(onPage: 0) == 0)
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 0, "And the file is as it was")
  }

  @Test("On a page that cannot be edited, the editor says it will cover before a letter is typed")
  func unprovablePageSaysSoFirst() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document, editor: RefusingEditor(rehearsalsFail: true))
    await reader.load()
    await reader.beginTextEditing()
    #expect(reader.textEditMessage == nil, "The page still has text to tap")
    await reader.controller?.finishTextRehearsal(onPage: 0)
    try await pick("John Smith", in: reader)
    #expect(reader.textEditMessage == .coversOriginal)
    #expect(await reader.commitTextEdit("Customer: David Smith"))
    #expect(reader.textEditNotice == nil, "Nothing happened that the person was not told of first")
    #expect(try #require(reader.controller).annotationCount(onPage: 0) == 2)
  }

  @Test("An explanation is given once, not at every line")
  func explanationsAreGivenOnce() async throws {
    let harness = Harness()
    // Every line of this page is in a matched font.
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document, editor: RefusingEditor(rehearsalsFail: true))
    await reader.load()
    await reader.beginTextEditing()
    #expect(reader.showsTextEditStartHint, "How to start is shown until something is picked")
    await reader.controller?.finishTextRehearsal(onPage: 0)

    // Text that will be covered: the whole sentence the first time, a few words after that.
    try await pick("John Smith", in: reader)
    #expect(reader.textEditMessage == .coversOriginal && !reader.showsTextEditStartHint)
    reader.cancelTextEdit()
    try await pick("Materials", in: reader)
    #expect(reader.textEditMessage == .coversOriginalBriefly, "Still said, because it changes what Done does")
    reader.cancelTextEdit()
    #expect(!reader.showsTextEditStartHint)
    let label = TextEditMessageLabel(message: .coversOriginalBriefly).frame(width: 300)
    #expect(ImageRenderer(content: label).uiImage != nil)
  }

  @Test("The field sits over the text only where it can be seen above the keyboard")
  func fieldStaysInView() async throws {
    let harness = Harness()
    let (reader, _) = try await editing(try TextEditFixtures.invoice(), in: harness, picking: "John Smith")
    let selection = try #require(reader.selectedTextRegion)
    let high = CGRect(x: 40, y: 150, width: 200, height: 20)
    let low = CGRect(x: 40, y: 560, width: 200, height: 20)
    #expect(TextEditLayer.fitsInPlace(selection, frame: high, within: 800))
    #expect(!TextEditLayer.fitsInPlace(selection, frame: low, within: 800), "It would be under the keyboard")
    #expect(TextEditLayer.fitsInPlace(selection, frame: low), "With no height known, as before")
    // Then the field is in the bar, which is always in view.
    let draft = TextEditDraft()
    draft.isInPlace = false
    #expect(ImageRenderer(content: TextEditBar(model: reader, draft: draft).frame(width: 390)).uiImage != nil)
  }

  @Test("A line is moved to where it was dropped, saved, and can be undone")
  func movingText() async throws {
    let harness = Harness()
    let (reader, document) = try await editing(try TextEditFixtures.invoice(), in: harness)
    let controller = try #require(reader.controller)
    let region = try #require(await controller.pageText(onPage: 0).regions.first { $0.text.contains("John Smith") })
    let selection = TextRegionSelection(pageIndex: 0, region: region)
    #expect(reader.showsTextEditStartHint)

    #expect(await reader.moveText(selection, by: CGVector(dx: 30, dy: -220)))
    #expect(reader.textMoves == 1 && reader.textEditMessage == nil && reader.textEditNotice == nil)
    #expect(reader.selectedTextRegion == nil && reader.canUndo && !reader.showsTextEditStartHint)
    // In the saved file the line is where it was put, and it is still the page's own text.
    let url = try await harness.library.fileURL(for: document.id)
    let saved = try PDFDocumentController(url: url)
    saved.setEditingText(true)
    let moved = try #require(await saved.pageText(onPage: 0).regions.first { $0.text.contains("John Smith") })
    #expect(abs(moved.bounds.midY - region.bounds.midY + 220) < 2 && saved.annotationCount(onPage: 0) == 0)

    await reader.undo()
    #expect(
      await controller.pageText(onPage: 0).regions.contains {
        $0.text.contains("John Smith") && abs($0.bounds.midY - region.bounds.midY) < 2
      })
  }

  @Test("Text dropped onto other text is not moved, and the reader says there is no room")
  func movingOntoOtherText() async throws {
    let harness = Harness()
    let (reader, _) = try await editing(try TextEditFixtures.invoice(), in: harness)
    let controller = try #require(reader.controller)
    let regions = await controller.pageText(onPage: 0).regions
    let region = try #require(regions.first { $0.text.contains("John Smith") })
    let target = try #require(regions.first { $0.text.contains("INV-2026") })
    let onto = CGVector(dx: 0, dy: target.bounds.midY - region.bounds.midY)
    #expect(await reader.moveText(TextRegionSelection(pageIndex: 0, region: region), by: onto) == false)
    #expect(reader.textEditMessage == .somethingInTheWay && reader.textMoves == 0 && !reader.canUndo)
    #expect(controller.annotationCount(onPage: 0) == 0 && !controller.hasUnsavedTextEdits)
    let label = TextEditMessageLabel(message: .somethingInTheWay).frame(width: 300)
    #expect(ImageRenderer(content: label).uiImage != nil)
    #expect(ImageRenderer(content: TextEditHint(model: reader).frame(width: 390)).uiImage != nil)
  }

  @Test("Text that cannot be moved in the page is covered and placed, and the reader says so")
  func movingByCovering() async throws {
    let harness = Harness()
    let document = await harness.seed(try TextEditFixtures.invoice())
    let reader = harness.reader(for: document, editor: RefusingEditor(rehearsalsFail: false))
    await reader.load()
    await reader.beginTextEditing()
    let controller = try #require(reader.controller)
    await controller.finishTextRehearsal(onPage: 0)
    let region = try #require(await controller.pageText(onPage: 0).regions.first { $0.text.contains("John Smith") })
    #expect(await reader.moveText(TextRegionSelection(pageIndex: 0, region: region), by: CGVector(dx: 0, dy: -220)))
    #expect(reader.textEditNotice == .coveredInstead && controller.annotationCount(onPage: 0) == 2)
    await reader.undoCoverInstead()
    #expect(controller.annotationCount(onPage: 0) == 0)
  }

  @Test("The field over a line never runs off the screen, however long the line is when zoomed in")
  func fieldStaysOnScreen() {
    let screen: CGFloat = 393
    // A small line, zoomed in to be read: three times as wide as the screen.
    let long = TextEditLayer.fieldSpan(over: CGRect(x: 20, y: 300, width: 1200, height: 24), in: screen)
    #expect(long.x == 18 && long.x + long.width <= screen, "\(long)")
    #expect(long.width > 300, "It uses the room there is")
    // An ordinary line: from its start to the edge, with room to type more.
    let short = TextEditLayer.fieldSpan(over: CGRect(x: 40, y: 300, width: 120, height: 20), in: screen)
    #expect(short.x == 38 && short.x + short.width <= screen && short.width > 300)
    // A line that starts near the right edge keeps a usable width by starting further left.
    let late = TextEditLayer.fieldSpan(over: CGRect(x: 340, y: 300, width: 40, height: 20), in: screen)
    #expect(late.width >= TextEditLayer.minimumFieldWidth && late.x + late.width <= screen && late.x < 340)
    // And one that starts off the left of the screen starts at the screen's edge.
    let before = TextEditLayer.fieldSpan(over: CGRect(x: -200, y: 300, width: 900, height: 24), in: screen)
    #expect(before.x >= 0 && before.x + before.width <= screen)
    // A very narrow reader still gets a field that fits it.
    let narrow = TextEditLayer.fieldSpan(over: CGRect(x: 10, y: 0, width: 500, height: 20), in: 120)
    #expect(narrow.x >= 0 && narrow.x + narrow.width <= 120 && narrow.width > 0)
  }
}

private enum Failure: Error { case unexpected }

/// A recogniser that waits until the test lets it finish.
private actor GatedRecognizer: TextRecognizing {
  private(set) var isWaiting = false
  private var isOpen = false
  private var gate: CheckedContinuation<Void, Never>?

  func open() {
    isOpen = true
    gate?.resume()
    gate = nil
  }

  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    if !isOpen {
      isWaiting = true
      await withCheckedContinuation { gate = $0 }
    }
    return FakeRecognizer().lines
  }
}

@MainActor
@Suite("Recognition in the background (P8)")
struct RecognitionCoordinatorTests {
  private static let kept = [
    RecognizedLine(text: "Kept from before", bounds: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.05), confidence: 1)
  ]

  @Test("After the app was stopped, recognition resumes from the pages already done")
  func resumesFromCheckpoint() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One", "Two", "Three"]), textLayer: false)
    let url = try await harness.library.fileURL(for: document.id)
    let checkpoints = RecognitionCheckpoints(folder: harness.checkpoints)
    try await checkpoints.begin(document.id, version: FileVersion(url))
    await checkpoints.add(Self.kept, page: 0, for: document.id)
    let recognizer = CountingRecognizer()
    let background = BackgroundLog()
    let coordinator = harness.coordinator(recognizer: recognizer, keepAlive: background)

    await coordinator.resumePending()
    #expect(coordinator.isRecognizing(document.id))
    await coordinator.finished(document.id)

    #expect(await recognizer.count == 2, "Only the pages not done before are recognised")
    let texts = try #require(PDFDocument(url: url)).string ?? ""
    #expect(texts.contains("Kept from before") && texts.contains("Recognised text"))
    #expect(try await harness.library.document(withID: document.id)?.hasTextLayer == true)
    #expect(await checkpoints.pending().isEmpty)
    #expect(background.begun == 1 && background.ended == 1, "Background time is asked for and given back")
    #expect(coordinator.progress[document.id] == nil)
  }

  @Test("Recognition a person starts asks the system to keep it going, with progress (P8b)")
  func continuedWhenStartedByAPerson() async throws {
    let harness = Harness()
    let document = await harness.seed(
      try SyntheticPDF.makeImageOnly(pages: ["One", "Two"]), title: "Scanned lease", textLayer: false)
    let continued = ContinuedLog()
    let coordinator = harness.coordinator(continued: continued)
    coordinator.start(document.id, startedFor: document.title)
    await coordinator.finished(document.id)
    #expect(continued.begun.map(\.subtitle) == ["Scanned lease"])
    let handle = try #require(continued.handles.first)
    #expect(handle.finished == true)
    #expect(!handle.progress.isEmpty && handle.progress.allSatisfy { (0...1).contains($0) })
  }

  @Test("Continued work registers a handler under the task's own identifier before submitting it")
  func continuedWorkRegistersBeforeSubmitting() {
    let scheduler = SchedulerLog()
    let work = ContinuedProcessing(family: "com.example.app.recognition", scheduler: scheduler)
    #expect(work.begin(title: "Recognising", subtitle: "Lease") {} != nil)
    #expect(scheduler.calls.count == 2)
    let registered = scheduler.calls.first ?? ""
    // The family pattern is not an identifier: submitting one with no handler ends the app.
    #expect(registered.hasPrefix("register com.example.app.recognition.") && !registered.hasSuffix("*"))
    #expect(scheduler.calls.last == registered.replacingOccurrences(of: "register ", with: "submit "))
    // A second piece of work gets its own identifier and its own handler.
    _ = work.begin(title: "Recognising", subtitle: "Letter") {}
    #expect(Set(scheduler.calls).count == 4)

    // If the system refuses the handler, nothing is submitted and the work runs as it always has.
    let refusing = SchedulerLog()
    refusing.registers = false
    #expect(
      ContinuedProcessing(family: "com.example.app.recognition", scheduler: refusing).begin(title: "", subtitle: "") {}
        == nil)
    #expect(refusing.calls.count == 1 && refusing.calls.allSatisfy { $0.hasPrefix("register ") })
    // If it can't run the task now, there is no handle either.
    let busy = SchedulerLog()
    busy.submits = false
    #expect(
      ContinuedProcessing(family: "com.example.app.recognition", scheduler: busy).begin(title: "", subtitle: "") {}
        == nil)
  }

  @Test("Resuming at launch, or a system that says no, runs recognition as before")
  func noContinuedWork() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One"]), textLayer: false)
    let continued = ContinuedLog()
    continued.available = false
    let coordinator = harness.coordinator(continued: continued)
    coordinator.start(document.id)
    await coordinator.finished(document.id)
    #expect(continued.begun.isEmpty, "Not started by a person, so the system isn't asked")
    let other = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["Two"]), textLayer: false)
    coordinator.start(other.id, startedFor: "Other")
    await coordinator.finished(other.id)
    #expect(continued.begun.count == 1 && continued.handles.isEmpty)
    #expect(try await harness.library.document(withID: other.id)?.hasTextLayer == true)
  }

  @Test("Cancelling from the system's interface stops recognition and leaves the file as it was")
  func cancelledFromTheSystem() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One", "Two"]), textLayer: false)
    let url = try await harness.library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    let recognizer = GatedRecognizer()
    let continued = ContinuedLog()
    let coordinator = harness.coordinator(recognizer: recognizer, continued: continued)
    coordinator.start(document.id, startedFor: "Doc")
    continued.cancel?()
    await recognizer.open()
    await coordinator.finished(document.id)
    #expect(try Data(contentsOf: url) == original)
    #expect(continued.handles.first?.finished == false)
  }

  @Test("A checkpoint for a file that has changed since is discarded")
  func staleCheckpointIsDiscarded() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One", "Two"]), textLayer: false)
    let other = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
    try Data("another file".utf8).write(to: other)
    let checkpoints = RecognitionCheckpoints(folder: harness.checkpoints)
    try await checkpoints.begin(document.id, version: FileVersion(other))
    await checkpoints.add(Self.kept, page: 0, for: document.id)
    let recognizer = CountingRecognizer()
    let coordinator = harness.coordinator(recognizer: recognizer)

    await coordinator.resumePending()
    await coordinator.finished(document.id)

    #expect(await recognizer.count == 2, "Every page is recognised again")
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try #require(PDFDocument(url: url)).string?.contains("Kept from before") == false)
  }

  @Test("Each page is kept as soon as it is recognised, and stopping discards them")
  func pagesAreKeptAsTheyAreDone() async throws {
    let harness = Harness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One", "Two"]), textLayer: false)
    let recognizer = SecondPageGate()
    let coordinator = harness.coordinator(recognizer: recognizer)
    let checkpoints = RecognitionCheckpoints(folder: harness.checkpoints)

    coordinator.start(document.id)
    coordinator.start(document.id)
    for _ in 0..<200 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await checkpoints.pages(of: document.id).keys.sorted() == [0])
    #expect(await checkpoints.pending() == [document.id], "A stopped app would resume this")
    for _ in 0..<100 where coordinator.progress[document.id] != 0.5 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(coordinator.progress[document.id] == 0.5)

    coordinator.cancel(document.id)
    await recognizer.open()
    await coordinator.finished(document.id)
    #expect(await checkpoints.pending().isEmpty)
    #expect(!coordinator.isRecognizing(document.id))
  }
}

/// Counts the pages it is asked to recognise.
private actor CountingRecognizer: TextRecognizing {
  private(set) var count = 0

  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    count += 1
    return FakeRecognizer().lines
  }
}

/// Recognises the first page, then waits on the second until opened.
private actor SecondPageGate: TextRecognizing {
  private(set) var isWaiting = false
  private var calls = 0
  private var gate: CheckedContinuation<Void, Never>?

  func open() {
    gate?.resume()
    gate = nil
  }

  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    calls += 1
    if calls == 2 {
      isWaiting = true
      await withCheckedContinuation { gate = $0 }
    }
    return FakeRecognizer().lines
  }
}

/// A task scheduler that records the order of the calls made to it.
@MainActor
final class SchedulerLog: ContinuedTaskScheduling {
  var calls: [String] = []
  var registers = true
  var submits = true

  func register(identifier: String, handle: ContinuedProcessing.Handle) -> Bool {
    calls.append("register \(identifier)")
    return registers
  }

  func submit(identifier: String, title: String, subtitle: String) -> Bool {
    calls.append("submit \(identifier)")
    return submits
  }
}

/// Continued work that records what the coordinator asked of the system.
@MainActor
final class ContinuedLog: ContinuedWork {
  final class Handle: ContinuedWorkHandle {
    var progress: [Double] = []
    var finished: Bool?
    func report(progress: Double) { self.progress.append(progress) }
    func finish(success: Bool) { finished = success }
  }

  var available = true
  private(set) var begun: [(title: String, subtitle: String)] = []
  private(set) var handles: [Handle] = []
  private(set) var cancel: (@MainActor () -> Void)?

  func begin(title: String, subtitle: String, onCancel: @escaping @MainActor () -> Void) -> (any ContinuedWorkHandle)? {
    begun.append((title, subtitle))
    guard available else { return nil }
    cancel = onCancel
    let handle = Handle()
    handles.append(handle)
    return handle
  }
}

/// Records requests for background time, instead of asking iOS.
@MainActor
final class BackgroundLog {
  private(set) var begun = 0
  private(set) var ended = 0

  func begin(_ name: String) -> @MainActor () -> Void {
    begun += 1
    return { self.ended += 1 }
  }
}

/// A speech engine that records what it was asked to say and never touches the system voices.
@MainActor
private final class SilentSpeech: SpeechEngine {
  var onEnd: ((_ finished: Bool) -> Void)?
  private(set) var spoken: [String] = []
  private(set) var stops = 0

  func speak(_ text: String) { spoken.append(text) }
  func stop() { stops += 1 }
}

/// Counts file-change notifications in a test.
@MainActor
private final class Heard {
  var count = 0
}

/// A door the test opens: work waits at it for as long as the test likes, whatever the machine's
/// speed, and does not stop waiting when the caller gives up.
private actor Gate {
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  /// How many pieces of work have gone through and answered.
  private(set) var answered = 0

  func pass() async {
    if !isOpen { await withCheckedContinuation { waiting.append($0) } }
  }

  func open() {
    isOpen = true
    for waiter in waiting { waiter.resume() }
    waiting = []
  }

  func noteAnswer() { answered += 1 }

  /// Waits until work that was let through has answered.
  func answers(_ count: Int) async {
    while answered < count { await Task.yield() }
  }
}

/// An editor that waits at a gate, as a very large page or a slow device would make it, and
/// answers even after it was given up on.
private struct StubEditor: PDFTextEditing {
  var find: Gate?
  var edit: Gate?
  var regions = true

  func text(ofPage page: Data) async -> EditablePageText {
    await find?.pass()
    let text = await ContentStreamTextEditor().text(ofPage: page)
    await find?.noteAnswer()
    return regions ? text : EditablePageText(regions: [], kind: .text)
  }

  // A rehearsal is not the edit under test: it goes straight to the real editor.
  func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
    await ContentStreamTextEditor().rehearsing(region, onPage: page)
  }

  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult {
    await edit?.pass()
    let result = await ContentStreamTextEditor().applying(edits, toPage: page)
    await edit?.noteAnswer()
    return result
  }
}

/// An editor that finds a page's text and can never prove an edit to it.
private struct RefusingEditor: PDFTextEditing {
  /// Whether a rehearsal fails as the edit will, or passes so that the failure comes after typing.
  let rehearsalsFail: Bool

  private var refused: TextEditResult {
    TextEditResult(
      page: nil, outcomes: [.refused(.notVerified)],
      proofFailure: TextEditProofFailure(.newTextMissing, measured: 0, expected: -14))
  }

  func text(ofPage page: Data) async -> EditablePageText { await ContentStreamTextEditor().text(ofPage: page) }

  func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
    rehearsalsFail ? refused : await ContentStreamTextEditor().rehearsing(region, onPage: page)
  }

  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult { refused }
}
