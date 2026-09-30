import Core
import CoreTestSupport
import SwiftUI
import Testing

@testable import AssistantFeature

@MainActor
private final class Revealed {
  var citations: [Citation] = []
}

@MainActor
private func makeModel(
  task: AssistantTask, intelligence: FakeIntelligence = FakeIntelligence(),
  telemetry: RecordingTelemetry = RecordingTelemetry()
) -> (AssistantModel, Revealed) {
  let revealed = Revealed()
  let model = AssistantModel(
    task: task, intelligence: intelligence, pages: { [PageText(pageIndex: 0, text: "testing")] }, telemetry: telemetry,
    onReveal: { revealed.citations.append($0) })
  return (model, revealed)
}

/// An intelligence whose results wait until the test releases them, and that finishes even when
/// cancelled, as an on-device model can.
private actor GatedIntelligence: DocumentIntelligence {
  private var waiting: [AssistantTask: CheckedContinuation<Void, Never>] = [:]

  func isWaiting(_ task: AssistantTask) -> Bool { waiting[task] != nil }
  func release(_ task: AssistantTask) { waiting.removeValue(forKey: task)?.resume() }

  func availability() async -> IntelligenceAvailability { .available(.onDevice) }
  func summarize(_ pages: [PageText]) async throws -> Answer {
    await gate(.summarize)
    return grounded("Summary")
  }
  func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
    await gate(.ask)
    return grounded(question)
  }
  func extractFields(from pages: [PageText]) async throws -> Extraction {
    await gate(.extract)
    return Extraction(fields: [], tier: .onDevice)
  }
  func explainContract(_ pages: [PageText]) async throws -> Answer {
    await gate(.explainContract)
    return grounded("Contract")
  }

  private func gate(_ task: AssistantTask) async {
    await withCheckedContinuation { waiting[task] = $0 }
  }

  private func grounded(_ text: String) -> Answer {
    Answer(text: text, citations: [Citation(pageIndex: 0, quote: "testing")], tier: .onDevice, isGrounded: true)
  }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async throws {
  for _ in 0..<400 {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("The condition never held")
}

@MainActor
@Suite("Assistant model")
struct AssistantModelTests {
  @Test("Summaries run straight away and cite their pages (FR-AI-001)")
  func summary() async throws {
    let telemetry = RecordingTelemetry()
    let (model, revealed) = makeModel(task: .summarize, telemetry: telemetry)
    await model.start()
    guard case .answered(let answer) = model.phase else { throw Failure.unexpected }
    #expect(answer.isGrounded && answer.citations.map(\.pageIndex) == [0])
    model.reveal(answer.citations[0])
    #expect(revealed.citations == answer.citations)
    #expect(model.shareableText == "The document is about testing.\n\nSources: p. 1")
    await model.recordKept()
    #expect(await telemetry.events == ["intelligence.request.completed", "intelligence.answer.kept"])
  }

  @Test("Ask waits for a question and ignores blank ones (FR-AI-002)")
  func ask() async throws {
    let intelligence = FakeIntelligence()
    let (model, _) = makeModel(task: .ask, intelligence: intelligence)
    await model.start()
    #expect(model.phase == .idle)
    model.question = "   "
    await model.ask()
    #expect(model.phase == .idle)
    model.question = " What is tested? "
    await model.ask()
    #expect(model.answeredQuestion == "What is tested?")
    #expect(await intelligence.questions == ["What is tested?"])
  }

  @Test("Not-found answers are not shareable (FR-AI-010)")
  func notFound() async {
    let intelligence = FakeIntelligence(answer: .notFound(tier: .onDevice))
    let (model, _) = makeModel(task: .summarize, intelligence: intelligence)
    await model.start()
    #expect(model.phase == .answered(.notFound(tier: .onDevice)))
    #expect(model.shareableText == nil)
  }

  @Test("Unavailable intelligence explains why (FR-ONB-006)", arguments: IntelligenceUnavailableReason.allCases)
  func unavailable(reason: IntelligenceUnavailableReason) async {
    let (model, _) = makeModel(task: .summarize, intelligence: FakeIntelligence(availability: .unavailable(reason)))
    await model.start()
    #expect(model.phase == .unavailable(reason))
    _ = AssistantView.explanation(for: reason)
  }

  @Test("Errors map to states the user can act on")
  func errors() async {
    let intelligence = FakeIntelligence()
    let (model, _) = makeModel(task: .explainContract, intelligence: intelligence)
    await intelligence.configure(error: .noText)
    await model.start()
    #expect(model.phase == .noText)
    await intelligence.configure(error: .unavailable(.requestTooLarge))
    await model.start()
    #expect(model.phase == .unavailable(.requestTooLarge))
    await intelligence.configure(error: .generationFailed)
    await model.start()
    #expect(model.phase == .failed)
  }

  @Test("Extracted values can be edited before export as CSV (FR-AI-003)")
  func extraction() async throws {
    let (model, _) = makeModel(task: .extract)
    await model.start()
    model.setValue("INV-9", forField: "invoiceNumber")
    model.setValue("ignored", forField: "missing")
    guard case .extracted(let extraction) = model.phase else { throw Failure.unexpected }
    #expect(extraction.fields.first?.value == "INV-9")
    #expect(model.shareableText == extraction.csv)
  }

  @Test("Changing the task starts it")
  func switchingTasks() async throws {
    let intelligence = FakeIntelligence()
    let (model, _) = makeModel(task: .ask, intelligence: intelligence)
    await model.start()
    model.task = .extract
    for _ in 0..<100 where model.phase == .idle || model.phase == .working {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await intelligence.tasks == [.extract])
  }

  @Test("A result that arrives late never replaces a newer one (defect D8)")
  func lateResultsAreIgnored() async throws {
    let gated = GatedIntelligence()
    let telemetry = RecordingTelemetry()
    let model = AssistantModel(
      task: .summarize, intelligence: gated, pages: { [PageText(pageIndex: 0, text: "testing")] },
      telemetry: telemetry, onReveal: { _ in })
    let first = Task { await model.start() }
    try await waitUntil { await gated.isWaiting(.summarize) }

    model.task = .extract
    try await waitUntil { await gated.isWaiting(.extract) }
    await gated.release(.extract)
    try await waitUntil { if case .extracted = model.phase { true } else { false } }
    await gated.release(.summarize)
    await first.value

    guard case .extracted = model.phase else { throw Failure.unexpected }
    #expect(await telemetry.events == ["intelligence.request.completed"])
  }

  @Test("Ask waits while a request runs, and closing the assistant stops it (defect D8)")
  func askWhileWorkingAndCancel() async throws {
    let gated = GatedIntelligence()
    let telemetry = RecordingTelemetry()
    let model = AssistantModel(
      task: .ask, intelligence: gated, pages: { [PageText(pageIndex: 0, text: "testing")] }, telemetry: telemetry,
      onReveal: { _ in })
    await model.start()
    model.question = "First question"
    let asking = Task { await model.ask() }
    try await waitUntil { await gated.isWaiting(.ask) }
    #expect(model.isWorking)
    model.question = "Second question"
    await model.ask()
    #expect(model.answeredQuestion == "First question", "Ask is ignored while working")

    model.cancel()
    #expect(model.phase == .idle && model.answeredQuestion == nil)
    await gated.release(.ask)
    await asking.value
    #expect(model.phase == .idle, "The cancelled answer is not shown")
    #expect(await telemetry.events.isEmpty)
    model.cancel()
    #expect(model.phase == .idle)
  }

  @Test("Copy exists for every task and field")
  func copy() {
    for task in AssistantTask.allCases { _ = AssistantView.title(for: task) }
    for key in ["documentType", "reference", "issueDate", "dueDate", "total", "seller", "buyer", "other"] {
      _ = AssistantView.fieldName(key)
    }
  }

  @Test func sheetRenders() {
    let (model, _) = makeModel(task: .explainContract)
    #expect(ImageRenderer(content: AssistantView(model: model).frame(width: 390, height: 700)).uiImage != nil)
  }

  @Test("Every phase draws at a large text size")
  func everyPhaseDraws() async {
    func draws(_ model: AssistantModel) -> Bool {
      let view = AssistantView(model: model).content
        .frame(width: 390).environment(\.dynamicTypeSize, .accessibility3)
      return ImageRenderer(content: view).uiImage != nil
    }
    let checked = Extraction(
      fields: [
        ExtractedField(key: "total", value: "120.00", pageIndex: nil),
        ExtractedField(key: "reference", value: "INV-1", pageIndex: 0),
      ], tier: .onDevice)
    let setups: [(AssistantTask, FakeIntelligence)] = [
      (.ask, FakeIntelligence()),
      (.summarize, FakeIntelligence()),
      (.summarize, FakeIntelligence(answer: .notFound(tier: .onDevice))),
      (
        .summarize,
        FakeIntelligence(
          answer: Answer(
            text: "Partly supported.", citations: [Citation(pageIndex: 0, quote: nil)], tier: .onDevice,
            isGrounded: true, omittedClaims: 2))
      ),
      (.extract, FakeIntelligence(extraction: checked)),
      (.extract, FakeIntelligence(extraction: Extraction(fields: [], tier: .onDevice))),
    ]
    for (task, intelligence) in setups {
      let (model, _) = makeModel(task: task, intelligence: intelligence)
      await model.start()
      #expect(draws(model), "\(task)")
    }
    let (asked, _) = makeModel(task: .ask)
    asked.question = "What is tested?"
    await asked.ask()
    #expect(draws(asked))
    for reason in IntelligenceUnavailableReason.allCases {
      let (model, _) = makeModel(task: .summarize, intelligence: FakeIntelligence(availability: .unavailable(reason)))
      await model.start()
      #expect(draws(model), "\(reason)")
    }
    let failing = FakeIntelligence()
    let (model, _) = makeModel(task: .summarize, intelligence: failing)
    for error in [IntelligenceError.noText, .generationFailed] {
      await failing.configure(error: error)
      await model.start()
      #expect(draws(model), "\(error)")
    }
  }
}

private enum Failure: Error { case unexpected }
