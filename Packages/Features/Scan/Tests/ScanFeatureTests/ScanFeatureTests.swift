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

  @Test("A scan opens without waiting for its text: recognition has not been asked for anything (#371)")
  func opensBeforeRecognition() async throws {
    let recognizer = GatedRecognizer()
    let (model, library, _, opened) = makeModel(recognizer: recognizer)
    await model.review([try #require(SyntheticPDF.makeTextImage("Receipt"))])
    // Never let through: a save that waited for recognition would hang here.
    await model.save()
    guard case .finished(let document) = model.phase else { throw Failure.unexpected }
    #expect(opened.document?.id == document.id)
    #expect(await !recognizer.isWaiting, "The save asked for the text")
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 1)
  }

  @Test("A title is suggested from a smaller copy of a camera page (#371)")
  func titleReadsASmallerPage() async throws {
    let sizes = SizeLog()
    let model = ScanModel(
      intake: DocumentIntake(library: FakeDocumentLibrary(), inspector: FakeInspector(), index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: FakeRecognizer()), telemetry: RecordingTelemetry(),
      recognizer: sizes, onFinish: { _ in })
    let page = try #require(SyntheticPDF.makeTextImage("Page", size: CGSize(width: 3024, height: 4032)))
    await model.review([page])
    let asked = await sizes.longest
    #expect(asked == [ScanModel.titlePixelSize], "Asked for \(asked)")
  }

  @Test("Scans become documents in the library and open (FR-SCAN-002)")
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
    // Photos from the library arrive as data: images are reviewed, anything else is counted as skipped.
    await model.process(photos: [try Data(contentsOf: image), Data("not an image".utf8)])
    #expect(model.phase == .reviewing && model.pages.count == 1)
    #expect(model.notice?.contains("1") == true)
  }

  @Test("Photos that didn't load are counted, and when none loaded the notice says so (#238)")
  func unloadablePhotosAreCounted() async throws {
    let (model, _, _, _) = makeModel()
    let encoded = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(SyntheticPDF.makeTextImage("Receipt")), nil)
    #expect(CGImageDestinationFinalize(destination))
    await model.process(photos: [encoded as Data], unreadable: 2)
    #expect(model.phase == .reviewing && model.pages.count == 1)
    #expect(model.notice?.contains("2") == true, "\(model.notice ?? "no notice")")
    model.discardReview()
    await model.process(photos: [], unreadable: 3)
    #expect(model.phase == .ready)
    #expect(model.notice?.contains("3") == true, "Nothing loaded: the notice says so")
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
    #expect(ViewRendering.draws(review))
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
    #expect(ViewRendering.draws(ScanView(model: model).frame(width: 390, height: 700)))
  }

  @Test("Cancelling saves nothing and returns to the start")
  func cancelling() async throws {
    let (model, library, _, opened) = makeModel()
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    let work = Task { await model.process([image]) }
    await Task.yield()
    model.cancel()
    await work.value
    #expect(model.phase == .ready)
    #expect(opened.document == nil)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
  }

  @Test("A save that fails keeps the scan, and Try again goes back to it (#371)")
  func failedSaveKeepsTheScan() async throws {
    let (model, library, _, opened) = makeModel(inspector: FakeInspector(fails: true))
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    await model.review([image, image])
    model.title = "My receipt"
    await model.save()
    #expect(model.phase == .failed)
    #expect(model.pages.count == 2, "The screen offers Try again, so the pages must still be there")
    #expect(opened.document == nil)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
    model.reset()
    #expect(model.phase == .reviewing, "Try again goes back to the pages, not to an empty scanner")
    #expect(model.title == "My receipt")
  }

  @Test("A save that is stopped keeps the scan (#371)")
  func stoppedSaveKeepsTheScan() async throws {
    let (model, library, _, opened) = makeModel()
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    await model.review([image, image])
    let work = Task { await model.save() }
    await Task.yield()
    model.cancel()
    await work.value
    #expect(model.phase == .reviewing, "Stop goes back to the pages")
    #expect(model.pages.count == 2)
    #expect(opened.document == nil)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
    // And the scan can still be saved.
    await model.save()
    guard case .finished = model.phase else { throw Failure.unexpected }
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 1)
  }

  @Test("The pages stay until the save has worked, and then they go (#371)")
  func pagesStayUntilTheSaveHasWorked() async throws {
    let gate = InspectionGate()
    let opened = Opened()
    let model = ScanModel(
      intake: DocumentIntake(library: FakeDocumentLibrary(), inspector: GatedInspector(gate: gate), index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: FakeRecognizer()), telemetry: RecordingTelemetry(),
      onFinish: { opened.document = $0 })
    await model.review([try #require(SyntheticPDF.makeTextImage("Receipt"))])
    let work = Task { await model.save() }
    await gate.waitForArrival()
    #expect(model.pages.count == 1, "Still needed if the save doesn't work")
    await gate.open()
    await work.value
    #expect(model.pages.isEmpty)
    #expect(opened.document != nil)
  }

  @Test("Tapping Save twice saves once (#371)")
  func savingTwiceSavesOnce() async throws {
    let gate = InspectionGate()
    let library = FakeDocumentLibrary()
    let model = ScanModel(
      intake: DocumentIntake(library: library, inspector: GatedInspector(gate: gate), index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: FakeRecognizer()), telemetry: RecordingTelemetry(), onFinish: { _ in })
    await model.review([try #require(SyntheticPDF.makeTextImage("Receipt"))])
    let first = Task { await model.save() }
    await gate.waitForArrival()
    // The second tap, before the screen has changed. The pages are kept now, so it must not save them.
    let second = Task { await model.save() }
    for _ in 0..<5 { await Task.yield() }
    await gate.open()
    await first.value
    await second.value
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 1)
  }

  @Test("While it is saved, the scan says it is saving, in English and French (#371)")
  func saysItIsSaving() async throws {
    let gate = InspectionGate()
    let model = ScanModel(
      intake: DocumentIntake(library: FakeDocumentLibrary(), inspector: GatedInspector(gate: gate), index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: FakeRecognizer()), telemetry: RecordingTelemetry(), onFinish: { _ in })
    await model.review([try #require(SyntheticPDF.makeTextImage("Receipt"))])
    let work = Task { await model.save() }
    // Held while the document is added to the library, the last step of the save.
    await gate.waitForArrival()
    #expect(words(model.phase, "en") == "Saving…", "It said \(model.phase)")
    #expect(words(model.phase, "fr") == "Enregistrement…")
    let view = ScanView(model: model).content.frame(width: 390, height: 700)
      .environment(\.dynamicTypeSize, .accessibility3)
    #expect(ViewRendering.draws(view))
    await gate.open()
    await work.value
    guard case .finished = model.phase else { throw Failure.unexpected }
    #expect(words(model.phase, "en") == "Opening…", "Saved, and on its way to the reader")
    #expect(words(model.phase, "fr") == "Ouverture…")
  }

  @Test("Adding a scan to the library is marked, so a device run can name it (#371)")
  func intakeIsMarked() async throws {
    let (model, _, _, _) = makeModel()
    await model.review([try #require(SyntheticPDF.makeTextImage("Receipt"))])
    let log = SpanLog()
    await log.watching { await model.save() }
    #expect(log.names.contains("Scan.Intake"), "\(log.names)")
  }

  private func words(_ phase: ScanModel.Phase, _ language: String) -> String? {
    guard var words = phase.waitingWords else { return nil }
    words.locale = Locale(identifier: language)
    return String(localized: words)
  }

  @Test("Every phase draws at a large text size")
  func everyPhaseDraws() async throws {
    func draws(_ model: ScanModel) -> Bool {
      let view = ScanView(model: model).content
        .frame(width: 390, height: 700).environment(\.dynamicTypeSize, .accessibility3)
      return ViewRendering.draws(view)
    }
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    let (saved, _, _, _) = makeModel()
    #expect(draws(saved))
    await saved.process([image])
    #expect(draws(saved))
    let (failing, _, _, _) = makeModel(inspector: FakeInspector(fails: true))
    await failing.process([image])
    #expect(failing.phase == .failed)
    #expect(draws(failing))
  }
}

/// Notes the longest side of each image it is given.
private actor SizeLog: TextRecognizing {
  private(set) var longest: [Int] = []

  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    longest.append(max(image.width, image.height))
    return []
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
