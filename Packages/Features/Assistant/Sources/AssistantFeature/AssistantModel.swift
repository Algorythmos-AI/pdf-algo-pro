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
  /// Earlier questions and answers in this conversation, oldest first (FR-AI-014); a new task or a
  /// fresh start begins a new conversation.
  public private(set) var earlier: [Exchange] = []

  private let intelligence: any DocumentIntelligence
  private let pages: () async -> [PageText]
  private let telemetry: any TelemetryRecording
  private let onReveal: (Citation) -> Void
  private var request: Task<Void, Never>?
  /// Counts requests; only the latest may change what is shown (defect D8).
  private var generation = 0

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

  /// Whether a request is running; Ask waits until it finishes.
  public var isWorking: Bool { phase == .working }

  /// Starts the task: summaries, extraction and explanations run at once; Ask waits for a question.
  ///
  /// A request still running is cancelled, and its result, if it arrives anyway, is ignored.
  public func start() async {
    supersede()
    answeredQuestion = nil
    earlier = []
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

  /// Tries the failed request again.
  ///
  /// A question is asked again as it was, not thrown away.
  public func retry() async {
    guard task == .ask, answeredQuestion != nil else {
      await start()
      return
    }
    await run()
  }

  /// Asks the current question; ignored while a request is running.
  public func ask() async {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isWorking else { return }
    // The answer on screen becomes the context for this follow-up.
    if case .answered(let answer) = phase, answer.isGrounded, let previous = answeredQuestion {
      earlier.append(Exchange(question: previous, answer: answer))
    }
    answeredQuestion = trimmed
    question = ""
    await run()
  }

  /// Stops the running request, for example when the assistant closes, so generation does not go on
  /// unseen.
  public func cancel() {
    supersede()
    guard isWorking else { return }
    phase = .idle
    answeredQuestion = nil
  }

  private func supersede() {
    request?.cancel()
    request = nil
    generation += 1
  }

  private func run() async {
    supersede()
    let token = generation
    phase = .working
    let task = task
    let question = answeredQuestion ?? ""
    let earlier = earlier
    let request = Task {
      let outcome: Phase
      do {
        let pages = await self.pages()
        try Task.checkCancellation()
        switch task {
        case .summarize: outcome = .answered(try await intelligence.summarize(pages))
        case .ask: outcome = .answered(try await intelligence.answer(question, from: pages, after: earlier))
        case .extract: outcome = .extracted(try await intelligence.extractFields(from: pages))
        case .explainContract: outcome = .answered(try await intelligence.explainContract(pages))
        }
      } catch is CancellationError {
        return
      } catch IntelligenceError.unavailable(let reason) {
        outcome = .unavailable(reason)
      } catch IntelligenceError.noText {
        outcome = .noText
      } catch {
        outcome = .failed
      }
      // A model may finish after being cancelled: a newer request or a closed sheet wins (defect D8).
      guard token == generation, !Task.isCancelled else { return }
      phase = outcome
      switch outcome {
      case .answered, .extracted: await telemetry.record("intelligence.request.completed")
      case .failed: await telemetry.record("quality.operation.failed")
      default: break
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
    guard case .extracted(var extraction) = phase, let index = extraction.fields.firstIndex(where: { $0.key == key })
    else { return }
    extraction.fields[index].value = value
    phase = .extracted(extraction)
  }

  /// The text to copy or share: the answer, or the extraction as CSV.
  public var shareableText: String? {
    switch phase {
    case .answered(let answer) where answer.isGrounded:
      let pages = answer.citations.map { String(localized: "p. \($0.pageNumber)", bundle: .module) }.joined(
        separator: ", ")
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
