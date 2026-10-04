import Core
import CoreTestSupport
import Foundation
import ImageIO
import PDFEngine
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import ScanFeature

// The iOS 27 SDK adds a SwiftUI type also called `Document`; here the name means ours.
private typealias Document = Core.Document

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

  @Test("Chosen files that aren't images are skipped, and the notice says how many")
  func skippedFiles() async throws {
    let (model, library, _, _) = makeModel()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let image = folder.appendingPathComponent("page.png")
    let destination = try #require(
      CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(SyntheticPDF.makeTextImage("Receipt")), nil)
    #expect(CGImageDestinationFinalize(destination))
    let text = folder.appendingPathComponent("notes.txt")
    try Data("not an image".utf8).write(to: text)
    await model.process(files: [image, text])
    #expect(model.notice?.contains("1") == true)
    #expect(model.phase == .reviewing && model.pages.count == 1, "Chosen images are reviewed first")
    await model.save()
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 1)
    await model.process(files: [image])
    #expect(model.notice == nil)
  }

  @Test("Review rotates, reorders and deletes pages, and saves under the suggested or typed name (FR-SCAN-006)")
  func review() async throws {
    let headline = RecognizedLine(
      text: "Example Stationery", bounds: CGRect(x: 0.1, y: 0.85, width: 0.6, height: 0.06), confidence: 0.9)
    let small = RecognizedLine(
      text: "Tax invoice number", bounds: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.02), confidence: 0.9)
    let library = FakeDocumentLibrary()
    let model = ScanModel(
      intake: DocumentIntake(library: library, inspector: FakeInspector(), index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: FakeRecognizer()), telemetry: RecordingTelemetry(),
      recognizer: FakeRecognizer(lines: [small, headline]), onFinish: { _ in })
    let wide = try #require(SyntheticPDF.makeTextImage("One", size: CGSize(width: 400, height: 200)))
    let tall = try #require(SyntheticPDF.makeTextImage("Two", size: CGSize(width: 200, height: 400)))
    await model.review([wide, tall])
    #expect(model.phase == .reviewing && model.title == "Example Stationery")
    model.rotatePage(at: 0)
    #expect(model.pages[0].width == 200 && model.pages[0].height == 400)
    model.movePage(at: 1, earlier: true)
    model.movePage(at: 0, earlier: true)
    model.deletePage(at: 1)
    model.deletePage(at: 0)
    #expect(model.pages.count == 1, "The last page stays")
    model.title = "  My receipt  "
    await model.save()
    #expect(try await library.documents(in: .all, sortedBy: .title).map(\.title) == ["My receipt"])
  }

  @Test("A typed name is kept, no title-like line gives no suggestion, and discarding saves nothing")
  func reviewEdges() async throws {
    #expect(
      ScanModel.suggestedTitle(from: [
        RecognizedLine(text: "12/03/2026 $120.00", bounds: CGRect(x: 0, y: 0.9, width: 1, height: 0.1), confidence: 1)
      ]) == nil)
    #expect(
      ScanModel.suggestedTitle(from: [
        RecognizedLine(text: "Footer text", bounds: CGRect(x: 0, y: 0.1, width: 1, height: 0.1), confidence: 1)
      ]) == nil)
    let (model, library, _, _) = makeModel()
    await model.review([try #require(SyntheticPDF.makeTextImage("x"))])
    #expect(model.title == model.defaultTitle, "Without a recogniser the date title stays")
    // The review screen draws with its pages, at a large text size.
    await model.review([try #require(SyntheticPDF.makeTextImage("x")), try #require(SyntheticPDF.makeTextImage("y"))])
    let review = ScanView(model: model).content.frame(width: 390, height: 700)
      .environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: review).uiImage != nil)
    model.discardReview()
    #expect(model.phase == .ready && model.pages.isEmpty)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
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
