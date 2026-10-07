import Commerce
import Core
import Foundation
import LibraryFeature
import Synchronization
import Testing

@testable import PDFAlgoPro

/// An intelligence that answers, or fails, as a test says.
private final class StubIntelligence: DocumentIntelligence {
  private let failure: Mutex<IntelligenceError?>
  private let unavailable: IntelligenceUnavailableReason?
  private let requests = Mutex(0)

  init(failure: IntelligenceError? = nil, unavailable: IntelligenceUnavailableReason? = nil) {
    self.failure = Mutex(failure)
    self.unavailable = unavailable
  }

  var requestCount: Int { requests.withLock { $0 } }

  private func respond<Result>(_ result: Result) throws -> Result {
    requests.withLock { $0 += 1 }
    if let failure = failure.withLock({ $0 }) { throw failure }
    return result
  }

  func availability() async -> IntelligenceAvailability {
    unavailable.map(IntelligenceAvailability.unavailable) ?? .available(.onDevice)
  }
  func summarize(_ pages: [PageText]) async throws -> Answer {
    try respond(Answer(text: "summary", citations: [], tier: .onDevice, isGrounded: true))
  }
  func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
    try respond(Answer(text: "answer", citations: [], tier: .onDevice, isGrounded: true))
  }
  func extractFields(from pages: [PageText]) async throws -> Extraction {
    try respond(Extraction(fields: [], tier: .onDevice))
  }
  func explainContract(_ pages: [PageText]) async throws -> Answer {
    try respond(Answer(text: "contract", citations: [], tier: .onDevice, isGrounded: true))
  }
}

/// Counts kept in memory.
private final class MemoryStore: AllowanceStoring {
  private let data = Mutex<Data?>(nil)
  func load() -> Data? { data.withLock { $0 } }
  func save(_ new: Data) { data.withLock { $0 = new } }
}

// Inside the App suite, which is serialised: every `AppModel` attaches the one App Intents router.
extension AppTests {
  @MainActor
  @Suite("Document intelligence within the free allowance (FR-STORE-008)")
  struct MeteredIntelligenceTests {
    private func make(
      _ base: StubIntelligence = StubIntelligence(), limit: Int = 2, entitlement: Entitlement = .none
    ) -> (MeteredIntelligence, UsageAllowance) {
      let allowance = UsageAllowance(
        limits: AllowanceLimits(scans: 1, intelligenceRequests: limit), store: MemoryStore())
      return (MeteredIntelligence(base: base, allowance: allowance) { entitlement }, allowance)
    }

    @Test("Each kind of request counts as one, once it has succeeded")
    func counts() async throws {
      let base = StubIntelligence()
      let (metered, allowance) = make(base, limit: 10)
      _ = try await metered.summarize([])
      _ = try await metered.answer("q", from: [])
      _ = try await metered.answer("q", from: [], after: [])
      _ = try await metered.extractFields(from: [])
      _ = try await metered.explainContract([])
      #expect(await allowance.usedToday(.intelligenceRequest) == 5)
      #expect(base.requestCount == 5)
      #expect(await allowance.usedToday(.scan) == 0, "Scans are counted apart")
    }

    @Test("When the day's requests are used, the next is refused before it starts, and says why")
    func refuses() async throws {
      let base = StubIntelligence()
      let (metered, allowance) = make(base, limit: 2)
      #expect(await metered.availability() == .available(.onDevice))
      _ = try await metered.summarize([])
      _ = try await metered.summarize([])
      #expect(await metered.availability() == .unavailable(.dailyAllowanceUsed))
      await #expect(throws: IntelligenceError.unavailable(.dailyAllowanceUsed)) { _ = try await metered.summarize([]) }
      await #expect(throws: IntelligenceError.unavailable(.dailyAllowanceUsed)) {
        _ = try await metered.answer("q", from: [])
      }
      #expect(base.requestCount == 2, "The model was not asked again")
      #expect(await allowance.usedToday(.intelligenceRequest) == 2)
    }

    @Test("A request that fails costs nothing")
    func failuresAreFree() async {
      let (metered, allowance) = make(StubIntelligence(failure: .generationFailed))
      await #expect(throws: IntelligenceError.generationFailed) { _ = try await metered.summarize([]) }
      await #expect(throws: IntelligenceError.generationFailed) { _ = try await metered.extractFields(from: []) }
      #expect(await allowance.usedToday(.intelligenceRequest) == 0)
    }

    @Test("With Pro there is no limit, and nothing is refused")
    func pro() async throws {
      let (metered, _) = make(limit: 0, entitlement: .subscribed)
      #expect(await metered.availability() == .available(.onDevice))
      _ = try await metered.summarize([])
      _ = try await metered.explainContract([])
    }

    @Test("An intelligence that cannot run says its own reason, not the allowance")
    func ownReason() async {
      let (metered, _) = make(StubIntelligence(unavailable: .modelNotReady), limit: 0)
      #expect(await metered.availability() == .unavailable(.modelNotReady))
    }

    @Test("The app meters the assistant and the Siri summary, never first run or the evaluation")
    func composition() async {
      let used = AppContainer(
        environment: LaunchEnvironment(arguments: ["-ui-testing", "-skip-onboarding", "-allowance", "exhausted"]))
      #expect(await used.meteredIntelligence.availability() == .unavailable(.dailyAllowanceUsed))
      #expect(await used.intelligence.availability().isAvailable, "The plain one is not metered")
      let pro = AppContainer(
        environment: LaunchEnvironment(arguments: [
          "-ui-testing", "-allowance", "exhausted", "-entitlement", "subscribed",
        ]))
      #expect(await pro.meteredIntelligence.availability().isAvailable)
    }

    @Test("Closing the assistant to see the plans opens the offer once its sheet has gone")
    func assistantLeadsToThePlans() async {
      let app = AppModel(
        container: AppContainer(environment: LaunchEnvironment(arguments: ["-ui-testing", "-skip-onboarding"])))
      let reader = app.makeReader(for: DocumentSelection(id: DocumentID()))
      reader.assistantTask = .summarize
      let context = reader.assistantContext(for: .summarize)
      let assistant = app.makeAssistant(for: context)
      #expect(assistant.onSeePlans != nil)
      assistant.onSeePlans?()
      #expect(reader.assistantTask == nil, "The assistant closes first")
      #expect(app.sheet == nil, "Two sheets are never up at once")
      reader.assistantDismissed()
      #expect(app.sheet == .paywall && app.paywallTrigger == .allowanceReached)
      app.sheet = nil
      reader.assistantDismissed()
      #expect(app.sheet == nil, "Only once")
    }
  }
}
