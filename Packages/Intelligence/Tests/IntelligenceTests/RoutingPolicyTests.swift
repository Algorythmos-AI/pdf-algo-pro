import Core
import Foundation
import Synchronization
import Testing

@testable import Intelligence

private let current = ConsentState.currentTextVersion

private func consent(_ status: ConsentState.Status, version: Int = current) -> ConsentState {
  ConsentState(status: status, textVersion: version, decidedAt: Date(timeIntervalSince1970: 0))
}

/// Facts for a tier that is built, reachable, capable, within budget and qualified.
private func ready(_ consent: ConsentState = .notAsked) -> TierFacts {
  TierFacts(isAvailable: true, consent: consent)
}

/// All three tiers ready, both cloud tiers with automatic consent.
private func allReady() -> [IntelligenceTier: TierFacts] {
  [.onDevice: ready(), .privateCloudCompute: ready(consent(.granted)), .claude: ready(consent(.granted))]
}

private func decide(
  task: IntelligenceTask = .ask, keepOnDevice: Bool = false, featureOff: Bool = false,
  needs: Set<TierCapability> = [], _ tiers: [IntelligenceTier: TierFacts]
) -> RouteDecision {
  RoutingPolicy.decide(
    RoutingInput(
      task: task, sizeBand: .m, keepOnDevice: keepOnDevice, isFeatureSwitchedOff: featureOff,
      requiredCapabilities: needs, tiers: tiers))
}

/// Trust suite: no document content goes to a cloud tier without the user's current consent.
@Suite("Routing policy: no cloud without consent")
struct NoCloudWithoutConsentTests {
  /// Every consent a tier can be in: each status, on the current consent text and on an older one.
  static let consents: [ConsentState] =
    ConsentState.Status.allCases.flatMap { [consent($0), consent($0, version: current - 1)] } + [.notAsked]

  @Test("Every decision that selects a cloud tier has a granted, current consent")
  func table() {
    var decisions = 0
    var cloudDecisions = 0
    for task in IntelligenceTask.allCases {
      for band in SizeBand.allCases {
        for keepOnDevice in [false, true] {
          for onDeviceAvailable in [true, false] {
            for onDeviceQualified in [true, false] {
              for pcc in Self.consents {
                for claude in Self.consents {
                  let tiers: [IntelligenceTier: TierFacts] = [
                    .onDevice: TierFacts(isAvailable: onDeviceAvailable, isQualified: onDeviceQualified),
                    .privateCloudCompute: ready(pcc),
                    .claude: ready(claude),
                  ]
                  let decision = RoutingPolicy.decide(
                    RoutingInput(task: task, sizeBand: band, keepOnDevice: keepOnDevice, tiers: tiers))
                  decisions += 1
                  guard let tier = decision.tier else {
                    #expect(decision.refusal != nil)
                    continue
                  }
                  guard tier.isCloud else {
                    #expect(!decision.needsConfirmation)
                    continue
                  }
                  cloudDecisions += 1
                  let given = tier == .claude ? claude : pcc
                  #expect(given.status == .granted || given.status == .askBeforeSending)
                  #expect(given.textVersion == current)
                  #expect(!keepOnDevice)
                  #expect(!(task == .explainContract && tier == .claude))
                  #expect(decision.needsConfirmation == (given.status == .askBeforeSending))
                }
              }
            }
          }
        }
      }
    }
    // 4 tasks x 4 bands x 2 x 2 x 2 x 9 x 9 consents; and the table does reach cloud tiers.
    #expect(decisions == 10368)
    #expect(cloudDecisions > 0)
  }

  @Test("A consent on older or newer consent text does not count", arguments: [current - 1, current + 1])
  func staleConsent(version: Int) {
    let decision = decide([.privateCloudCompute: ready(consent(.granted, version: version))])
    #expect(decision.refusal == .noConsent)
    #expect(decision.excluded[.privateCloudCompute] == .noConsent)
  }

  @Test("Revoked and never-asked consents remove the tier", arguments: [ConsentState.Status.revoked, .notAsked])
  func withoutConsent(status: ConsentState.Status) {
    #expect(decide([.claude: ready(consent(status))]).refusal == .noConsent)
  }

  @Test("Ask before sending keeps the tier and needs a confirmation")
  func askBeforeSending() {
    let decision = decide([.claude: ready(consent(.askBeforeSending))])
    #expect(decision.outcome == .use(tier: .claude, needsConfirmation: true, isReducedScope: false))
    #expect(!decide([.claude: ready(consent(.granted))]).needsConfirmation)
  }

  @Test("The on-device tier needs no consent and no confirmation")
  func onDevice() {
    let decision = decide([.onDevice: ready()])
    #expect(decision.outcome == .use(tier: .onDevice, needsConfirmation: false, isReducedScope: false))
  }
}

@Suite("Routing policy: the eight steps")
struct RoutingStepsTests {
  @Test("On device before Private Cloud Compute before Claude")
  func order() {
    var tiers = allReady()
    #expect(decide(tiers).tier == .onDevice)
    tiers[.onDevice] = nil
    #expect(decide(tiers).tier == .privateCloudCompute)
    tiers[.privateCloudCompute] = nil
    #expect(decide(tiers).tier == .claude)
    tiers[.claude] = nil
    #expect(decide(tiers).refusal == .unavailable)
  }

  @Test("Step 1: the kill switch removes a provider, or every tier for a feature")
  func switchedOff() {
    var tiers = allReady()
    tiers[.onDevice]?.isSwitchedOff = true
    let decision = decide(tiers)
    #expect(decision.tier == .privateCloudCompute)
    #expect(decision.excluded == [.onDevice: .switchedOff])

    let feature = decide(featureOff: true, allReady())
    #expect(feature.refusal == .switchedOff)
    #expect(feature.excluded.count == 3)
  }

  @Test("The kill switch only removes tiers: it never routes to a tier the policy would not allow without it")
  func killSwitchOnlyRemoves() {
    let states: [TierFacts] = [
      ready(consent(.granted)), ready(consent(.revoked)), TierFacts(isAvailable: false, consent: consent(.granted)),
      TierFacts(isAvailable: true, consent: consent(.granted), isWithinBudget: false),
      TierFacts(isAvailable: true, consent: consent(.askBeforeSending), isQualified: false),
    ]
    for device in states {
      for pcc in states {
        for claude in states {
          let base: [IntelligenceTier: TierFacts] = [.onDevice: device, .privateCloudCompute: pcc, .claude: claude]
          let unswitched = decide(base)
          let allowed = IntelligenceTier.allCases.filter { [nil, .notQualified].contains(unswitched.excluded[$0]) }
          for killed in IntelligenceTier.allCases {
            var tiers = base
            tiers[killed]?.isSwitchedOff = true
            let decision = decide(tiers)
            #expect(decision.tier != killed)
            if let tier = decision.tier {
              #expect(allowed.contains(tier))
              #expect(!tier.isCloud || (tiers[tier]?.consent.permitsSending() ?? false))
            }
          }
        }
      }
    }
  }

  @Test("Step 2: Keep on device removes every cloud tier")
  func keepOnDevice() {
    let decision = decide(keepOnDevice: true, allReady())
    #expect(decision.tier == .onDevice)
    #expect(decision.excluded == [.privateCloudCompute: .keepOnDevice, .claude: .keepOnDevice])

    var tiers = allReady()
    tiers[.onDevice]?.isAvailable = false
    #expect(decide(keepOnDevice: true, tiers).refusal == .unavailable)
  }

  @Test("Step 2: Analyse Contract never uses Claude (PAP-020)")
  func contractNeverUsesClaude() {
    let onlyClaude: [IntelligenceTier: TierFacts] = [.claude: ready(consent(.granted))]
    let decision = decide(task: .explainContract, onlyClaude)
    #expect(decision.tier == nil)
    #expect(decision.excluded[.claude] == .taskNotAllowed)
    #expect(decide(task: .explainContract, allReady()).tier == .onDevice)
    for task in IntelligenceTask.allCases where task != .explainContract {
      #expect(decide(task: task, onlyClaude).tier == .claude)
    }
  }

  @Test("Step 3: an unavailable tier is removed, and a tier without facts counts as not built")
  func unavailable() {
    var tiers = allReady()
    tiers[.onDevice]?.isAvailable = false
    let decision = decide(tiers)
    #expect(decision.tier == .privateCloudCompute)
    #expect(decision.excluded == [.onDevice: .unavailable])
    #expect(decide([:]).refusal == .unavailable)
  }

  @Test("Step 4: a cloud tier without consent is removed")
  func noConsent() {
    var tiers = allReady()
    tiers[.onDevice] = nil
    tiers[.privateCloudCompute]?.consent = .notAsked
    let decision = decide(tiers)
    #expect(decision.tier == .claude)
    #expect(decision.excluded[.privateCloudCompute] == .noConsent)
  }

  @Test("Step 5: a tier that lacks a needed capability is removed")
  func notCapable() {
    var tiers = allReady()
    tiers[.onDevice]?.capabilities = [.guidedGeneration, .documentLanguage]
    let decision = decide(needs: [.imageInput], tiers)
    #expect(decision.tier == .privateCloudCompute)
    #expect(decision.excluded == [.onDevice: .notCapable])
    #expect(decide(needs: [.guidedGeneration], tiers).tier == .onDevice)
  }

  @Test("Step 6: a tier over budget is removed")
  func overBudget() {
    var tiers = allReady()
    tiers[.onDevice]?.isWithinBudget = false
    tiers[.privateCloudCompute]?.isWithinBudget = false
    let decision = decide(tiers)
    #expect(decision.tier == .claude)
    #expect(decision.excluded == [.onDevice: .overBudget, .privateCloudCompute: .overBudget])
  }

  @Test("Step 7: only qualified tiers are kept when one qualifies")
  func notQualified() {
    var tiers = allReady()
    tiers[.onDevice]?.isQualified = false
    let decision = decide(tiers)
    #expect(decision.outcome == .use(tier: .privateCloudCompute, needsConfirmation: false, isReducedScope: false))
    #expect(decision.excluded == [.onDevice: .notQualified])
  }

  @Test("Step 8: with no qualified tier, the most private remaining tier answers with a reduced-scope label")
  func reducedScope() {
    var tiers = allReady()
    for tier in IntelligenceTier.allCases { tiers[tier]?.isQualified = false }
    let decision = decide(tiers)
    #expect(decision.outcome == .use(tier: .onDevice, needsConfirmation: false, isReducedScope: true))

    tiers[.onDevice]?.isAvailable = false
    tiers[.privateCloudCompute]?.consent = consent(.askBeforeSending)
    #expect(decide(tiers).outcome == .use(tier: .privateCloudCompute, needsConfirmation: true, isReducedScope: true))
  }

  @Test("A tier that fails several steps reports the earliest one")
  func earliestStepWins() {
    // Fails every step from 1 to 7; each line repairs the earliest failure.
    var facts = TierFacts(
      isSwitchedOff: true, isAvailable: false, consent: .notAsked, capabilities: [], isWithinBudget: false,
      isQualified: false)
    // The other tiers are not built, so each refusal below is theirs (unavailable, step 3) unless a
    // later step removed this tier.
    let kept = { decide(keepOnDevice: true, needs: [.imageInput], [.privateCloudCompute: facts]) }
    #expect(kept().excluded[.privateCloudCompute] == .switchedOff)
    facts.isSwitchedOff = false
    #expect(kept().excluded[.privateCloudCompute] == .keepOnDevice)
    let open = { decide(needs: [.imageInput], [.privateCloudCompute: facts]) }
    #expect(open().excluded[.privateCloudCompute] == .unavailable)
    #expect(open().refusal == .unavailable)
    facts.isAvailable = true
    #expect(open().excluded[.privateCloudCompute] == .noConsent)
    #expect(open().refusal == .noConsent)
    facts.consent = consent(.granted)
    #expect(open().excluded[.privateCloudCompute] == .notCapable)
    #expect(open().refusal == .notCapable)
    facts.capabilities = [.imageInput]
    #expect(open().excluded[.privateCloudCompute] == .overBudget)
    #expect(open().refusal == .overBudget)
    facts.isWithinBudget = true
    #expect(open().outcome == .use(tier: .privateCloudCompute, needsConfirmation: false, isReducedScope: true))
    facts.isQualified = true
    #expect(open().outcome == .use(tier: .privateCloudCompute, needsConfirmation: false, isReducedScope: false))
  }

  @Test("A refusal reports the step that removed the last tier")
  func refusalReason() {
    let tiers: [IntelligenceTier: TierFacts] = [
      .onDevice: TierFacts(isAvailable: false), .privateCloudCompute: ready(), .claude: ready(consent(.revoked)),
    ]
    let decision = decide(tiers)
    #expect(decision.refusal == .noConsent)
    #expect(decision.excluded == [.onDevice: .unavailable, .privateCloudCompute: .noConsent, .claude: .noConsent])
  }

  @Test("Today's build, with only the on-device tier, routes on device or refuses")
  func onDeviceOnly() {
    #expect(decide([.onDevice: ready()]).tier == .onDevice)
    #expect(decide([.onDevice: TierFacts(isAvailable: false)]).refusal == .unavailable)
  }
}

@Suite("Consent store")
struct ConsentStoreTests {
  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("consent-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("consent.json")
  }

  @Test("A decision survives reopening the store, per tier")
  func roundTrip() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let store = ConsentStore(url: url, appVersion: "1.0", now: { date })
    #expect(await store.consent(for: .claude) == .notAsked)
    await store.grant(.claude, askBeforeSending: true)
    await store.grant(.privateCloudCompute, askBeforeSending: false)

    let reopened = ConsentStore(url: url)
    #expect(await reopened.consent(for: .claude) == consent(.askBeforeSending).with(date))
    #expect(await reopened.consent(for: .privateCloudCompute) == consent(.granted).with(date))
    #expect(await reopened.hasCurrentConsent(for: .claude))
    #expect(await reopened.hasCurrentConsent(for: .privateCloudCompute))
    #expect(await reopened.history().map(\.tier) == [.claude, .privateCloudCompute])
    #expect(await reopened.history().first?.appVersion == "1.0")
  }

  @Test("The file is excluded from backups, after every write (H7)")
  func excludedFromBackup() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = ConsentStore(url: url)
    await store.grant(.claude, askBeforeSending: true)
    #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    await store.revoke(.claude)
    #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  }

  @Test("A file from a newer build is read as no consent and left untouched (H6)")
  func newerVersion() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let newer = Data(
      #"{"version":\#(ConsentStore.version + 1),"states":{"claude":{"status":"granted","textVersion":1}},"grants":[]}"#
        .utf8)
    try newer.write(to: url)

    let store = ConsentStore(url: url)
    #expect(await store.consent(for: .claude) == .notAsked)
    #expect(await !store.hasCurrentConsent(for: .claude))
    await store.grant(.privateCloudCompute, askBeforeSending: false)
    await store.revoke(.claude)
    #expect(try Data(contentsOf: url) == newer)
    // The decisions still hold for the session.
    #expect(await store.hasCurrentConsent(for: .privateCloudCompute))
  }

  @Test("An unreadable file is read as no consent")
  func unreadable() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    let store = ConsentStore(url: url)
    for tier in IntelligenceTier.allCases { #expect(await !store.hasCurrentConsent(for: tier)) }
  }

  @Test("A consent given on older consent text is kept on record but is not current")
  func olderTextVersion() async {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let old = ConsentStore(url: url, currentTextVersion: 1)
    await old.grant(.claude, askBeforeSending: false)
    #expect(await old.hasCurrentConsent(for: .claude))

    let updated = ConsentStore(url: url, currentTextVersion: 2)
    let state = await updated.consent(for: .claude)
    #expect(state.status == .granted)
    #expect(state.textVersion == 1)
    #expect(await !updated.hasCurrentConsent(for: .claude))
    // The policy refuses it too.
    let facts = TierFacts(isAvailable: true, consent: state, currentConsentTextVersion: 2)
    #expect(decide([.claude: facts]).refusal == .noConsent)

    await updated.grant(.claude, askBeforeSending: false)
    #expect(await updated.hasCurrentConsent(for: .claude))
  }

  @Test("Revoking applies at once, survives reopening, and stays in the history")
  func revoke() async {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = ConsentStore(url: url)
    await store.grant(.claude, askBeforeSending: false)
    await store.grant(.privateCloudCompute, askBeforeSending: false)
    await store.revoke(.claude)
    #expect(await store.consent(for: .claude).status == .revoked)
    #expect(await !store.hasCurrentConsent(for: .claude))
    #expect(await store.hasCurrentConsent(for: .privateCloudCompute))

    let reopened = ConsentStore(url: url)
    #expect(await !reopened.hasCurrentConsent(for: .claude))
    #expect(await reopened.history().map(\.state.status) == [.granted, .granted, .revoked])
  }

  @Test("The on-device tier takes no consent, and an in-memory store works without a file")
  func onDeviceAndInMemory() async {
    let store = ConsentStore(url: nil)
    await store.grant(.onDevice, askBeforeSending: false)
    #expect(await store.consent(for: .onDevice) == .notAsked)
    #expect(await store.history().isEmpty)
    await store.grant(.claude, askBeforeSending: true)
    #expect(await store.hasCurrentConsent(for: .claude))
  }
}

extension ConsentState {
  fileprivate func with(_ date: Date) -> ConsentState {
    ConsentState(status: status, textVersion: textVersion, decidedAt: date)
  }
}

/// A clock the test moves by hand.
private final class FakeClock: Sendable {
  private let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
  var now: Date { date.withLock { $0 } }
  func advance(_ seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

@Suite("Circuit breaker")
struct CircuitBreakerTests {
  private func breaker(_ clock: FakeClock) -> CircuitBreaker {
    CircuitBreaker(failureThreshold: 3, coolDown: 60, maximumCoolDown: 200, now: { clock.now })
  }

  @Test("Opens after the threshold of consecutive failures, not before")
  func opens() async {
    let breaker = breaker(FakeClock())
    #expect(await breaker.state() == .closed)
    await breaker.recordFailure()
    await breaker.recordFailure()
    #expect(await breaker.state() == .closed)
    #expect(await breaker.allowRequest())
    await breaker.recordFailure()
    #expect(await breaker.state() == .open)
    #expect(await !breaker.allowRequest())
    #expect(await !breaker.isAvailable())
  }

  @Test("A success resets the count of consecutive failures")
  func successResets() async {
    let breaker = breaker(FakeClock())
    await breaker.recordFailure()
    await breaker.recordFailure()
    await breaker.recordSuccess()
    await breaker.recordFailure()
    await breaker.recordFailure()
    #expect(await breaker.state() == .closed)
  }

  @Test("Half-open after the cool-down; one probe at a time; success closes")
  func halfOpenThenClosed() async {
    let clock = FakeClock()
    let breaker = breaker(clock)
    for _ in 0..<3 { await breaker.recordFailure() }
    clock.advance(59)
    #expect(await breaker.state() == .open)
    clock.advance(1)
    #expect(await breaker.state() == .halfOpen)
    #expect(await breaker.isAvailable())
    #expect(await breaker.allowRequest())
    #expect(await !breaker.allowRequest())
    #expect(await !breaker.isAvailable())
    await breaker.recordSuccess()
    #expect(await breaker.state() == .closed)
    #expect(await breaker.allowRequest())
    // The count starts again from zero.
    await breaker.recordFailure()
    #expect(await breaker.state() == .closed)
  }

  @Test("A failed probe reopens with the cool-down doubled, up to the maximum; a success resets it")
  func failedProbe() async {
    let clock = FakeClock()
    let breaker = breaker(clock)
    for _ in 0..<3 { await breaker.recordFailure() }
    clock.advance(60)
    #expect(await breaker.allowRequest())
    await breaker.recordFailure()
    #expect(await breaker.state() == .open)
    clock.advance(119)
    #expect(await breaker.state() == .open)
    clock.advance(1)
    #expect(await breaker.state() == .halfOpen)
    #expect(await breaker.allowRequest())
    await breaker.recordFailure()
    // 240 seconds is capped at the 200-second maximum.
    clock.advance(199)
    #expect(await breaker.state() == .open)
    clock.advance(1)
    #expect(await breaker.state() == .halfOpen)
    #expect(await breaker.allowRequest())
    await breaker.recordSuccess()
    for _ in 0..<3 { await breaker.recordFailure() }
    clock.advance(60)
    #expect(await breaker.state() == .halfOpen)
  }

  @Test("Failures reported while open do not extend the cool-down")
  func failuresWhileOpen() async {
    let clock = FakeClock()
    let breaker = breaker(clock)
    for _ in 0..<3 { await breaker.recordFailure() }
    clock.advance(30)
    await breaker.recordFailure()
    clock.advance(30)
    #expect(await breaker.state() == .halfOpen)
  }

  @Test("The defaults are the documented assumptions: 5 failures, 60 seconds")
  func defaults() async {
    let clock = FakeClock()
    let breaker = CircuitBreaker(now: { clock.now })
    for _ in 0..<4 { await breaker.recordFailure() }
    #expect(await breaker.state() == .closed)
    await breaker.recordFailure()
    #expect(await breaker.state() == .open)
    clock.advance(60)
    #expect(await breaker.state() == .halfOpen)
  }
}
