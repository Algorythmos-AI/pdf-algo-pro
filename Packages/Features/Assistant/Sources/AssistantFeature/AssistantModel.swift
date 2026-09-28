import Core
import Foundation
import Observation

/// The document assistant: summarise, ask, extract and explain, always with page citations
/// (FR-AI-001 to FR-AI-011).
@MainActor
@Observable
public final class AssistantModel {
  /// What the assistant is showing.
  public enum Phase: Equatable {
    /// Waiting for the user (the Ask task before a question).
    case idle
    /// A request is running.
    case working
    /// A grounded answer, or a not-found answer.
    case answered(Answer)
    /// Extracted fields, editable before export.
    case extracted(Extraction)
    /// Intelligence cannot run; the reason says why.
    case unavailable(IntelligenceUnavailableReason)
    /// The document has no text yet.
    case noText
    /// The request failed; nothing was changed.
    case failed
  }

  /// The current task.
  public var task: AssistantTask {
    didSet { if task != oldValue { Task { await start() } } }
  }
  /// The question for the Ask task.
  public var question = ""
  /// What is shown.
  public private(set) var phase: Phase = .idle
  /// The question the current answer responds to.
  public private(set) var answeredQuestion: String?

  private let intelligence: any DocumentIntelligence
  private let pages: () async -> [PageText]
  private let telemetry: any TelemetryRecording
  private let onReveal: (Citation) -> Void
  private var request: Task<Void, Never>?

  /// Creates the assistant for a document's pages.
  public init(
    task: AssistantTask, intelligence: any DocumentIntelligence, pages: @escaping () async -> [PageText],
    telemetry: any TelemetryRecording, onReveal: @escaping (Citation) -> Void
  ) {
    self.task = task
    self.intelligence = intelligence
    self.pages = pages
    self.telemetry = telemetry
    self.onReveal = onReveal
  }

  /// Starts the task: summaries, extraction and explanations run at once; Ask waits for a question.
  public func start() async {
    request?.cancel()
    answeredQuestion = nil
    if case .unavailable(let reason) = await intelligence.availability() {
      phase = .unavailable(reason)
      return
    }
    guard task != .ask else {
      phase = .idle
      return
    }
    await run()
  }

  /// Asks the current question.
  public func ask() async {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    answeredQuestion = trimmed
    await run()
  }

  private func run() async {
    phase = .working
    let task = task
    let question = answeredQuestion ?? ""
    let request = Task {
      do {
        let pages = await self.pages()
        switch task {
        case .summarize: phase = .answered(try await intelligence.summarize(pages))
        case .ask: phase = .answered(try await intelligence.answer(question, from: pages))
        case .extract: phase = .extracted(try await intelligence.extractFields(from: pages))
        case .explainContract: phase = .answered(try await intelligence.explainContract(pages))
        }
        await telemetry.record("intelligence.request.completed")
      } catch is CancellationError {
        return
      } catch IntelligenceError.unavailable(let reason) {
        phase = .unavailable(reason)
      } catch IntelligenceError.noText {
        phase = .noText
      } catch {
        phase = .failed
        await telemetry.record("quality.operation.failed")
      }
    }
    self.request = request
    await request.value
  }

  /// Opens a cited page with its passage highlighted.
  public func reveal(_ citation: Citation) {
    onReveal(citation)
  }

  /// Edits an extracted value before export (FR-AI-003).
  public func setValue(_ value: String, forField key: String) {
    guard case .extracted(var extraction) = phase, let index = extraction.fields.firstIndex(where: { $0.key == key }) else { return }
    extraction.fields[index].value = value
    phase = .extracted(extraction)
  }

  /// The text to copy or share: the answer, or the extraction as CSV.
  public var shareableText: String? {
    switch phase {
    case .answered(let answer) where answer.isGrounded:
      let pages = answer.citations.map { String(localized: "p. \($0.pageNumber)", bundle: .module) }.joined(separator: ", ")
      return "\(answer.text)\n\n\(String(localized: "Sources: \(pages)", bundle: .module))"
    case .extracted(let extraction): return extraction.csv
    default: return nil
    }
  }

  /// Records that the user kept an answer (copied or shared it).
  public func recordKept() async {
    await telemetry.record("intelligence.answer.kept")
  }
}
