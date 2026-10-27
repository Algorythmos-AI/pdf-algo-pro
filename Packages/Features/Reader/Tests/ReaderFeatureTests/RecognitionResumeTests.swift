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

  private func coordinator(
    recognizer: any TextRecognizing = FakeRecognizer(), continued: (any ContinuedWork)? = nil
  ) -> RecognitionCoordinator {
    RecognitionCoordinator(
      library: library, intake: DocumentIntake(library: library, inspector: PDFKitInspector(), index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: recognizer, renderPixelSize: 400), telemetry: RecordingTelemetry(),
      folder: folder, keepAlive: BackgroundLog().begin, continued: continued)
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

  @Test("When the system ends recognition, the pages done so far are kept and the next launch resumes (#253)")
  func systemStopKeepsTheCheckpoint() async throws {
    let document = try await seedImageOnly(pages: ["One", "Two", "Three"])
    let url = try await library.fileURL(for: document.id)
    let original = try Data(contentsOf: url)
    let checkpoints = RecognitionCheckpoints(folder: folder)
    let recognizer = HeldOnSecondPage()
    let continued = ContinuedLog()
    let first = coordinator(recognizer: recognizer, continued: continued)

    first.start(document.id, startedFor: "Scan")
    for _ in 0..<500 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    try #require(await recognizer.isWaiting, "Recognition reached the second page")
    // The system ends the continued work: its expiration handler is the `onCancel` the coordinator gave.
    let stop = try #require(continued.cancel, "The coordinator asked the system to keep the work going")
    stop()
    await recognizer.open()
    await first.finished(document.id)

    #expect(try Data(contentsOf: url) == original, "Stopped before it finished, the file is left as it was")
    #expect(continued.handles.first?.finished == false, "The system hears the work did not finish")
    #expect(
      await checkpoints.pending() == [document.id],
      "The checkpoint must survive a system stop; the folder holds: \(checkpointFiles())")
    // The second page may be kept too: its lines arrive as the stop is heard.
    let kept = await checkpoints.pages(of: document.id).keys.sorted()
    #expect(kept.first == 0, "The first page's lines must be kept; the folder holds: \(checkpointFiles())")

    // The next launch resumes from the pages already done.
    let counting = CountingPages()
    let next = coordinator(recognizer: counting)
    await next.resumePending()
    await next.finished(document.id)
    let recognizedAgain = await counting.count
    #expect(
      recognizedAgain == 3 - kept.count, "Kept pages \(kept); pages recognised at the next launch: \(recognizedAgain)")
    #expect((PDFDocument(url: url)?.string ?? "").contains("Recognised text"))
    #expect(try await library.document(withID: document.id)?.hasTextLayer == true)
  }

  @Test("Cancel in the reader still discards the pages done so far, after the system tried to stop it too")
  func readerCancelDiscardsTheCheckpoint() async throws {
    let document = try await seedImageOnly(pages: ["One", "Two"])
    let checkpoints = RecognitionCheckpoints(folder: folder)
    let recognizer = HeldOnSecondPage()
    let continued = ContinuedLog()
    let coordinator = coordinator(recognizer: recognizer, continued: continued)

    coordinator.start(document.id, startedFor: "Scan")
    for _ in 0..<500 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    try #require(await recognizer.isWaiting, "Recognition reached the second page")
    continued.cancel?()
    coordinator.cancel(document.id)
    await recognizer.open()
    await coordinator.finished(document.id)

    #expect(await checkpoints.pending().isEmpty, "The folder holds: \(checkpointFiles())")
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
    let coordinator = coordinator(recognizer: counting)

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
