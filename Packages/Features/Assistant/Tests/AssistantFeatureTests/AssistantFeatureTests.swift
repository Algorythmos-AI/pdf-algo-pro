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
}

private enum Failure: Error { case unexpected }
