import Core
import CoreTestSupport
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine
@testable import ReaderFeature

// The iOS 27 SDK adds a SwiftUI type also called `Document`; here the name means ours.
private typealias Document = Core.Document

/// Saving and recognising text when a file or the library doesn't answer as expected, or another app
/// writes at the same moment (R1 review, wave 1).
@MainActor
@Suite("Reader: saving and recognition, when things overlap")
struct SaveAndRecognitionTests {
  @Test("A save whose file was written isn't reported as failed when the library's record can't be updated (#234)")
  func indexFailureAfterWriteIsNotASaveFailure() async throws {
    let harness = SaveHarness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    await harness.library.failRecordModified()
    reader.controller?.addNote("Kept", onPage: 0)
    #expect(await reader.save())
    #expect(reader.errorMessage == nil, "\(reader.errorMessage ?? "")")
    #expect(reader.canRestorePreviousVersion)
    let events = await harness.telemetry.events
    #expect(events.contains("task.core.completed") && !events.contains("quality.operation.failed"), "\(events)")
    let url = try await harness.base.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
  }

  @Test("Share explains a document file that has gone, or that the library can't name (#260)")
  func shareExplainsAMissingFile() async throws {
    let harness = SaveHarness()
    let document = await harness.seed(try SyntheticPDF.makeSample())
    let reader = harness.reader(for: document)
    await reader.load()
    // Moved or deleted in the Files app while the reader is open; the library still names it.
    try FileManager.default.removeItem(at: try #require(reader.fileURL))
    await reader.share()
    #expect(reader.sharing == nil, "Nothing to share")
    #expect(reader.errorMessage != nil, "and the reader says why")
    reader.errorMessage = nil
    await harness.base.failNext(with: .notFound)
    await reader.share()
    #expect(reader.sharing == nil && reader.errorMessage != nil, "The library can't name it either")
  }

  @Test("Reduce size with an unreadable file size makes no copy and says so (#262)")
  func reduceSizeWithAnUnknownSize() async throws {
    let harness = SaveHarness()
    let document = await harness.seed(try SyntheticPDF.makeSample(), title: "Report")
    let reader = harness.reader(for: document)
    await reader.load()
    try FileManager.default.removeItem(at: try #require(reader.fileURL))
    await reader.reduceSize(.email)
    let titles = try await harness.library.documents(in: .all, sortedBy: .title).map(\.title)
    #expect(!titles.contains("Report (smaller)"), "\(titles)")
    #expect(reader.errorMessage != nil && reader.notice == nil)
  }

  @Test("Recognition replaces the file with coordinated access, so file presenters hear it (#270)")
  func recognitionWriteIsCoordinated() async throws {
    let harness = SaveHarness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One"]), textLayer: false)
    let url = try await harness.base.fileURL(for: document.id)
    let presenter = OtherApp(url: url)
    presenter.start()
    defer { presenter.stop() }
    harness.coordinator.start(document.id)
    await harness.coordinator.finished(document.id)
    #expect(PDFDocument(url: url)?.string?.contains("Recognised text") == true)
    #expect(presenter.relinquished > 0, "A coordinated write asks the file's presenters first")
  }

  @Test("Opening a document marks each step by name, so a device run can name the slow one (#371)")
  func openingMarksEachStep() async throws {
    let harness = SaveHarness()
    let document = await harness.seed(try SyntheticPDF.makeSample(), title: "Not for a trace")
    let reader = harness.reader(for: document)
    let log = SpanLog()
    await log.watching { await reader.load() }
    #expect(reader.phase == .ready)
    #expect(
      log.names == [
        "Document.FirstPage", "Reader.Load.PreviousVersion", "Reader.Load.Record", "Reader.Load.FileURL",
        "Reader.Load.Open", "Reader.Load.Watch", "Reader.Load.Telemetry",
      ])
  }

  @Test("Between replacing the file and opening it, the reader says what it is doing (#371)")
  func waitAfterRecognitionHasWords() async throws {
    let gate = InspectionGate()
    let harness = SaveHarness(inspector: GatedInspector(gate: gate))
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One"]), textLayer: false)
    let reader = harness.reader(for: document)
    await reader.load()
    reader.recognizeText()
    // Held while search catches up with the new file, after the reader has let go of the old one.
    await gate.waitForArrival()
    #expect(reader.controller == nil)
    #expect(words(reader.phase, "en") == "Saving the searchable version…", "It said \(reader.phase)")
    #expect(words(reader.phase, "fr") == "Enregistrement de la version interrogeable…")
    await gate.open()
    await harness.coordinator.finished(document.id)
    #expect(reader.phase == .ready && reader.controller != nil)
  }

  @Test("Opening a document says so, in English and French (#371)")
  func openingHasWords() {
    #expect(words(.loading, "en") == "Opening…")
    #expect(words(.loading, "fr") == "Ouverture…")
    #expect(words(.ready, "en") == nil)
  }

  @Test("The recognition bar stops saying it is recognising once every page is read (#371)")
  func recognitionBarSaysWhatIsHappening() {
    func bar(_ progress: Double, _ language: String) -> String {
      var words = ReaderModel.recognitionWords(progress: progress)
      words.locale = Locale(identifier: language)
      return String(localized: words)
    }
    #expect(bar(0.5, "en") == "Recognising text on this device…")
    #expect(bar(0.5, "fr") == "Reconnaissance du texte sur cet appareil…")
    #expect(bar(1, "en") == "Saving the searchable version…")
    #expect(bar(1, "fr") == "Enregistrement de la version interrogeable…")
  }

  private func words(_ phase: ReaderModel.Phase, _ language: String) -> String? {
    guard var words = phase.waitingWords else { return nil }
    words.locale = Locale(identifier: language)
    return String(localized: words)
  }

  @Test("Recognition doesn't write over a version another app finishes while recognition waits to write (#270)")
  func recognitionDoesNotOverwriteAWriteItWaitedFor() async throws {
    let harness = SaveHarness()
    let document = await harness.seed(try SyntheticPDF.makeImageOnly(pages: ["One"]), textLayer: false)
    let url = try await harness.base.fileURL(for: document.id)
    let theirs = try SyntheticPDF.make(pages: ["Theirs"])
    let presenter = OtherApp(url: url, writesFirst: theirs)
    presenter.start()
    defer { presenter.stop() }
    harness.coordinator.start(document.id)
    await harness.coordinator.finished(document.id)
    #expect(try Data(contentsOf: url) == theirs, "Their version is still the file")
  }
}

/// A reader, its library and the app's recognition.
@MainActor
private struct SaveHarness {
  let base = FakeDocumentLibrary()
  let library: HeldLibrary
  let index = FakeIndex()
  let settings = InMemorySettingsStore()
  let telemetry = RecordingTelemetry()
  let checkpoints = FileManager.default.temporaryDirectory.appendingPathComponent("w1-save-checkpoints-\(UUID())")
  let coordinator: RecognitionCoordinator

  init(recognizer: any TextRecognizing = FakeRecognizer(), inspector: any PDFInspecting = PDFKitInspector()) {
    library = HeldLibrary(base)
    let intake = DocumentIntake(library: library, inspector: inspector, index: index)
    coordinator = RecognitionCoordinator(
      library: library, intake: intake, builder: SearchablePDFBuilder(recognizer: recognizer, renderPixelSize: 400),
      telemetry: telemetry, folder: checkpoints, keepAlive: BackgroundLog().begin)
  }

  var intake: DocumentIntake { DocumentIntake(library: library, inspector: PDFKitInspector(), index: index) }

  func reader(for document: Document) -> ReaderModel {
    ReaderModel(
      selection: document.id, library: library, intake: intake, index: index, settings: settings,
      telemetry: telemetry, recognition: coordinator, signatures: InMemorySignatureStore(),
      speech: SpeechReader(engine: QuietSpeech()), textEditing: FixedTextEditingAccess(.available))
  }

  func seed(_ data: Data, title: String = "Doc", textLayer: Bool = true) async -> Document {
    await base.seed(
      Document(title: title, fileName: "\(UUID()).pdf", addedAt: .distantPast, hasTextLayer: textLayer), data: data)
  }
}

/// The fake library, with an index update that can fail on its own.
private actor HeldLibrary: DocumentLibrary {
  let base: FakeDocumentLibrary
  private var failsRecordModified = false

  init(_ base: FakeDocumentLibrary) {
    self.base = base
  }

  func failRecordModified() { failsRecordModified = true }

  func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Document] {
    try await base.documents(in: section, sortedBy: sort)
  }
  func document(withID id: DocumentID) async throws -> Document? { try await base.document(withID: id) }
  func allTags() async throws -> [String] { try await base.allTags() }
  func fileURL(for id: DocumentID) async throws -> URL { try await base.fileURL(for: id) }
  func document(at url: URL) async throws -> Document? { try await base.document(at: url) }
  func importDocument(from url: URL) async throws -> Document { try await base.importDocument(from: url) }
  func addDocument(data: Data, title: String) async throws -> Document {
    try await base.addDocument(data: data, title: title)
  }
  func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws {
    try await base.updateInspection(inspection, for: id)
  }
  func rename(_ id: DocumentID, to title: String) async throws -> Document { try await base.rename(id, to: title) }
  func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws {
    try await base.setFavorite(isFavorite, for: id)
  }
  func setTags(_ tags: [String], for id: DocumentID) async throws { try await base.setTags(tags, for: id) }
  func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {
    try await base.recordOpened(id, pageIndex: pageIndex)
  }
  func resetReadingPosition(_ id: DocumentID) async throws { try await base.resetReadingPosition(id) }
  func recordModified(_ id: DocumentID) async throws {
    if failsRecordModified { throw LibraryError.fileAccessFailed }
    try await base.recordModified(id)
  }
  func moveToRecentlyDeleted(_ id: DocumentID) async throws { try await base.moveToRecentlyDeleted(id) }
  func restore(_ id: DocumentID) async throws { try await base.restore(id) }
  func deletePermanently(_ id: DocumentID) async throws { try await base.deletePermanently(id) }
  func purgeExpired(now: Date) async throws -> [DocumentID] { try await base.purgeExpired(now: now) }
  func reconcileWithFiles() async throws -> Reconciliation { try await base.reconcileWithFiles() }
  func previousVersionURL(for id: DocumentID) async throws -> URL? { try await base.previousVersionURL(for: id) }
  func hasPreviousVersion(of id: DocumentID) async -> Bool { await base.hasPreviousVersion(of: id) }
  func restorePreviousVersion(of id: DocumentID) async throws { try await base.restorePreviousVersion(of: id) }
  func versions(of id: DocumentID) async -> [DocumentVersion] { await base.versions(of: id) }
  func restore(_ version: DocumentVersion, of id: DocumentID) async throws {
    try await base.restore(version, of: id)
  }
}

/// A speech engine that says nothing.
@MainActor
private final class QuietSpeech: SpeechEngine {
  var onEnd: ((_ finished: Bool) -> Void)?
  func speak(_ text: String) {}
  func stop() {}
}

/// Another app with the file open: a file presenter that, asked to let a writer in, first finishes
/// writing its own version when it has one.
nonisolated private final class OtherApp: NSObject, NSFilePresenter, @unchecked Sendable {
  let presentedItemURL: URL?
  let presentedItemOperationQueue = OperationQueue()
  private let lock = NSLock()
  private var pending: Data?
  private var count = 0

  init(url: URL, writesFirst: Data? = nil) {
    presentedItemURL = url
    pending = writesFirst
  }

  /// How many writers it let in.
  var relinquished: Int { lock.withLock { count } }

  func start() { NSFileCoordinator.addFilePresenter(self) }
  func stop() { NSFileCoordinator.removeFilePresenter(self) }

  func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
    let data = lock.withLock {
      count += 1
      defer { pending = nil }
      return pending
    }
    if let data, let url = presentedItemURL { try? data.write(to: url) }
    writer(nil)
  }
}
