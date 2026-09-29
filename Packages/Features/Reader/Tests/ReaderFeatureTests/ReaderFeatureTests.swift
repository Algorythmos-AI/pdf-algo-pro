import AVFoundation
import Core
import CoreTestSupport
import Foundation
import PDFEngineTestSupport
import SwiftUI
import Testing

@testable import PDFEngine
@testable import ReaderFeature

@MainActor
private struct Harness {
  let library = FakeDocumentLibrary()
  let index = FakeIndex()
  let settings = InMemorySettingsStore()
  let telemetry = RecordingTelemetry()

  func reader(
    for document: Document, pageIndex: Int? = nil, task: AssistantTask? = nil,
    recognizer: any TextRecognizing = FakeRecognizer()
  ) -> ReaderModel {
    ReaderModel(
      selection: document.id, pageIndex: pageIndex, task: task, library: library,
      intake: DocumentIntake(library: library, inspector: PDFKitInspector(), index: index), index: index,
      settings: settings, telemetry: telemetry,
      builder: SearchablePDFBuilder(recognizer: recognizer, renderPixelSize: 400))
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
    #expect(await !reader.markUpSelection(.highlight))
    #expect(reader.errorMessage != nil)
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
    #expect(reader.controller?.currentPageIndex == 1)
    await harness.index.seed(document.id, pages: [PageText(pageIndex: 0, text: "stored")])
    #expect(await context.pages().map(\.text) == ["stored"])
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
  func speechEnds() async throws {
    let speech = SpeechReader()
    let synthesizer = AVSpeechSynthesizer()
    speech.speak("One")
    speech.speechSynthesizer(synthesizer, didFinish: AVSpeechUtterance(string: "One"))
    for _ in 0..<100 where speech.isSpeaking { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!speech.isSpeaking)
    speech.speak("Two")
    speech.speechSynthesizer(synthesizer, didCancel: AVSpeechUtterance(string: "Two"))
    for _ in 0..<100 where speech.isSpeaking { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!speech.isSpeaking)
    speech.stop()
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
