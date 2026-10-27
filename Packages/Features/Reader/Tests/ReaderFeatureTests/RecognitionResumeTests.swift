import Core
import CoreTestSupport
import Foundation
import PDFKit
import Testing

@testable import PDFEngine
@testable import ReaderFeature

/// What recognition keeps when it is stopped before it finishes, and what it finds at the next
/// launch (P8, #253, #256).
@MainActor
@Suite("Recognition: stopping and resuming (P8)")
struct RecognitionResumeTests {
  private let library = FakeDocumentLibrary()
  private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoints-\(UUID())")
  private let index = FakeIndex()

  private var intake: DocumentIntake { DocumentIntake(library: library, inspector: PDFKitInspector(), index: index) }

  private func makeCoordinator(
    recognizer: any TextRecognizing = FakeRecognizer(), continued: (any ContinuedWork)? = nil
  ) -> RecognitionCoordinator {
    RecognitionCoordinator(
      library: library, intake: intake, builder: SearchablePDFBuilder(recognizer: recognizer, renderPixelSize: 400),
      telemetry: RecordingTelemetry(), folder: folder, keepAlive: BackgroundLog().begin, continued: continued)
  }

  private func makeReader(for id: DocumentID, recognition: RecognitionCoordinator) -> ReaderModel {
    ReaderModel(
      selection: id, library: library, intake: intake, index: index, settings: InMemorySettingsStore(),
      telemetry: RecordingTelemetry(), recognition: recognition, signatures: InMemorySignatureStore())
  }

  private func seedImageOnly(pages: [String]) async throws -> Core.Document {
    await library.seed(
      Core.Document(title: "Scan", fileName: "\(UUID()).pdf", addedAt: .distantPast, hasTextLayer: false),
      data: try SyntheticPDF.makeImageOnly(pages: pages))
  }

  /// What the checkpoint folder holds, for a failure message.
  private func checkpointFiles() -> [String] {
    (FileManager.default.subpaths(atPath: folder.path) ?? []).sorted()
  }

  @Test("Cancel in the Live Activity keeps the pages done and the file; the reader offers to resume from them (#253)")
  func systemStopKeepsTheCheckpoint() async throws {
    let document = try await seedImageOnly(pages: ["One", "Two", "Three"])
    let url = try await library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    let checkpoints = RecognitionCheckpoints(folder: folder)
    let recognizer = HeldOnSecondPage()
    let continued = ContinuedLog()
    let first = makeCoordinator(recognizer: recognizer, continued: continued)

    first.start(document.id, startedFor: "Scan")
    for _ in 0..<500 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    try #require(await recognizer.isWaiting, "Recognition reached the second page")
    // Cancel in the Live Activity, or the system ending the work: either runs the expiration handler,
    // which is the `onCancel` the coordinator gave.
    let stop = try #require(continued.cancel, "The coordinator asked the system to keep the work going")
    stop()
    await recognizer.open()
    await first.finished(document.id)

    #expect(try Data(contentsOf: url) == original, "Stopped before it finished, the file is left as it was")
    #expect(continued.handles.first?.finished == false, "The system hears the work did not finish")
    #expect(
      await checkpoints.pending() == [document.id],
      "The checkpoint must survive a stop from the system's interface; the folder holds: \(checkpointFiles())")
    // The second page may be kept too: its lines arrive as the stop is heard.
    let kept = await checkpoints.pages(of: document.id).keys.sorted()
    #expect(kept.first == 0, "The first page's lines must be kept; the folder holds: \(checkpointFiles())")

    // The next launch doesn't resume it: the file never changes after a Cancel without the person.
    let counting = CountingPages()
    let next = makeCoordinator(recognizer: counting)
    await next.resumePending()
    let resumedAtLaunch = next.isRecognizing(document.id)
    await next.finished(document.id)
    let recognizedAtLaunch = await counting.count
    let pendingAtLaunch = await checkpoints.pending()
    #expect(!resumedAtLaunch, "Recognition stopped from the system's interface was resumed at launch")
    #expect(
      try Data(contentsOf: url) == original, "The file changed after a Cancel; \(recognizedAtLaunch) pages recognised")
    #expect(
      next.isStopped(document.id) && pendingAtLaunch == [document.id],
      "Stopped: \(next.isStopped(document.id)); pending: \(pendingAtLaunch)")

    // The reader offers to resume, and resuming goes on from the pages kept.
    let reader = makeReader(for: document.id, recognition: next)
    await reader.load()
    #expect(
      reader.canResumeRecognition, "Resume recognising must be offered; can recognise: \(reader.canRecognizeText)")
    reader.recognizeText()
    for _ in 0..<500 where reader.recognitionProgress != nil { try await Task.sleep(for: .milliseconds(20)) }
    let recognizedAgain = await counting.count
    #expect(
      recognizedAgain == 3 - kept.count, "Kept pages \(kept); pages recognised on resuming: \(recognizedAgain)")
    #expect((PDFDocument(url: url)?.string ?? "").contains("Recognised text"))
    #expect(try await library.document(withID: document.id)?.hasTextLayer == true)
    #expect(!reader.canResumeRecognition && !next.isStopped(document.id))
    #expect(await checkpoints.pending().isEmpty, "The folder holds: \(checkpointFiles())")
    reader.stopWatching()
  }

  @Test("Cancel in the reader still discards the pages done so far, after the system tried to stop it too")
  func readerCancelDiscardsTheCheckpoint() async throws {
    let document = try await seedImageOnly(pages: ["One", "Two"])
    let checkpoints = RecognitionCheckpoints(folder: folder)
    let recognizer = HeldOnSecondPage()
    let continued = ContinuedLog()
    let coordinator = makeCoordinator(recognizer: recognizer, continued: continued)

    coordinator.start(document.id, startedFor: "Scan")
    for _ in 0..<500 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    try #require(await recognizer.isWaiting, "Recognition reached the second page")
    continued.cancel?()
    coordinator.cancel(document.id)
    await recognizer.open()
    await coordinator.finished(document.id)

    #expect(await checkpoints.pending().isEmpty, "The folder holds: \(checkpointFiles())")
    #expect(!coordinator.isStopped(document.id))
  }

  @Test("A file replaced just before the app stopped is not recognised again at the next launch (#256)")
  func resumeSkipsAFileThatAlreadyHasText() async throws {
    let document = try await seedImageOnly(pages: ["One", "Two"])
    let url = try await library.fileURL(for: document.id)
    // As a stop between the write and the checkpoint's removal leaves things: a checkpoint for the
    // image-only file, the searchable version on disk, and the library not yet told.
    let checkpoints = RecognitionCheckpoints(folder: folder)
    try await checkpoints.begin(document.id, version: FileVersion(url))
    let builder = SearchablePDFBuilder(recognizer: FakeRecognizer(), renderPixelSize: 400)
    let searchable = try await builder.addTextLayer(toPDFAt: url)
    try searchable.data.write(to: url, options: .atomic)
    let written = try Data(contentsOf: url)
    let counting = CountingPages()
    let coordinator = makeCoordinator(recognizer: counting)

    await coordinator.resumePending()
    let wasRecognizing = coordinator.isRecognizing(document.id)
    await coordinator.finished(document.id)
    let recognizedAgain = await counting.count

    #expect(!wasRecognizing, "A file that already has text must not be recognised again")
    #expect(recognizedAgain == 0, "Pages recognised again: \(recognizedAgain)")
    let text = PDFDocument(url: url)?.string ?? ""
    #expect(
      try Data(contentsOf: url) == written,
      "The file must be left as written; its text is now: \(text.debugDescription)")
    #expect(await checkpoints.pending().isEmpty, "The folder holds: \(checkpointFiles())")
    #expect(
      try await library.document(withID: document.id)?.hasTextLayer == true, "The library learns the file has text")
  }
}

/// Recognises the first page, then waits on the second until opened.
private actor HeldOnSecondPage: TextRecognizing {
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

/// Counts the pages it is asked to recognise.
private actor CountingPages: TextRecognizing {
  private(set) var count = 0

  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    count += 1
    return FakeRecognizer().lines
  }
}
