import Core
import CoreTestSupport
import Foundation
import PDFEngine
import SwiftUI
import Testing

@testable import ScanFeature

@MainActor
@Suite("Scan model")
struct ScanModelTests {
  private func makeModel(
    inspector: FakeInspector = FakeInspector(), recognizer: any TextRecognizing = FakeRecognizer()
  ) -> (ScanModel, FakeDocumentLibrary, RecordingTelemetry, Opened) {
    let library = FakeDocumentLibrary()
    let telemetry = RecordingTelemetry()
    let opened = Opened()
    let model = ScanModel(
      intake: DocumentIntake(library: library, inspector: inspector, index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: recognizer), telemetry: telemetry,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }, onFinish: { opened.document = $0 })
    return (model, library, telemetry, opened)
  }

  @Test("Scans become searchable documents in the library and open (FR-SCAN-002)")
  func scanning() async throws {
    let (model, library, telemetry, opened) = makeModel()
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    await model.process([image, image])
    guard case .finished(let document) = model.phase else { throw Failure.unexpected }
    #expect(opened.document?.id == document.id)
    #expect(document.title.hasPrefix("Scan "))
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 1)
    #expect(await telemetry.events == ["task.core.completed"])
  }

  @Test("Nothing to scan does nothing; failures save nothing")
  func emptyAndFailure() async throws {
    let (model, _, _, _) = makeModel()
    await model.process([])
    #expect(model.phase == .ready)
    let (failing, library, telemetry, opened) = makeModel(inspector: FakeInspector(fails: true))
    await failing.process([try #require(SyntheticPDF.makeTextImage("x"))])
    #expect(failing.phase == .failed)
    #expect(opened.document == nil)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
    #expect(await telemetry.events == ["quality.operation.failed"])
    failing.reset()
    #expect(failing.phase == .ready)
  }

  @Test func titlesCarryTheDate() {
    let (model, _, _, _) = makeModel()
    #expect(model.defaultTitle.hasPrefix("Scan "))
    #expect(model.defaultTitle.count > 8)
  }

  @Test func sheetRenders() {
    let (model, _, _, _) = makeModel()
    #expect(ImageRenderer(content: ScanView(model: model).frame(width: 390, height: 700)).uiImage != nil)
  }

  @Test("Cancelling, even on the last page, saves nothing and returns to the start")
  func cancelling() async throws {
    let recognizer = GatedRecognizer()
    let (model, library, _, opened) = makeModel(recognizer: recognizer)
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    let work = Task { await model.process([image]) }
    for _ in 0..<200 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    model.cancel()
    await recognizer.open()
    await work.value
    #expect(model.phase == .ready)
    #expect(opened.document == nil)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
  }

  @Test("Every phase draws at a large text size")
  func everyPhaseDraws() async throws {
    func draws(_ model: ScanModel) -> Bool {
      let view = ScanView(model: model).content
        .frame(width: 390, height: 700).environment(\.dynamicTypeSize, .accessibility3)
      return ImageRenderer(content: view).uiImage != nil
    }
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    let recognizer = GatedRecognizer()
    let (recognizing, _, _, _) = makeModel(recognizer: recognizer)
    #expect(draws(recognizing))
    let work = Task { await recognizing.process([image]) }
    for _ in 0..<200 where await !recognizer.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
    #expect(recognizing.phase == .recognizing(0))
    #expect(draws(recognizing))
    await recognizer.open()
    await work.value
    #expect(draws(recognizing))
    let (failing, _, _, _) = makeModel(inspector: FakeInspector(fails: true))
    await failing.process([image])
    #expect(failing.phase == .failed)
    #expect(draws(failing))
  }
}

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
private final class Opened {
  var document: Document?
}

private enum Failure: Error { case unexpected }
