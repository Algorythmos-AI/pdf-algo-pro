import CommerceTestSupport
import Foundation
import Synchronization
import Testing

@testable import Commerce

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 24 * 60 * 60

/// Counts kept in memory.
private final class MemoryAllowanceStore: AllowanceStoring {
  private let data = Mutex<Data?>(nil)
  init(_ initial: Data? = nil) { data.withLock { $0 = initial } }
  func load() -> Data? { data.withLock { $0 } }
  func save(_ new: Data) { data.withLock { $0 = new } }
}

/// A clock a test moves.
private final class Clock: Sendable {
  private let date: Mutex<Date>
  init(_ date: Date) { self.date = Mutex(date) }
  var now: Date { date.withLock { $0 } }
  func advance(by interval: TimeInterval) { date.withLock { $0 = $0.addingTimeInterval(interval) } }
}

private var utc: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
  return calendar
}

@Suite("The product catalogue")
struct ProductCatalogTests {
  @Test("Identifiers derive from the bundle identifier, so two apps never share one")
  func identifiers() {
    let production = ProductCatalog(bundleIdentifier: "com.example.app")
    let staging = ProductCatalog(bundleIdentifier: "com.example.app.staging")
    #expect(production.weekly == "com.example.app.pro.weekly")
    #expect(production.yearly == "com.example.app.pro.yearly")
    #expect(production.ordered == [production.yearly, production.weekly])
    #expect(production.productIDs == [production.weekly, production.yearly])
    #expect(production.productIDs.isDisjoint(with: staging.productIDs))
  }
}

@Suite("A fixed entitlement")
struct FixedEntitlementsTests {
  @Test("It reports the same entitlement, once")
  func fixed() async {
    let fixed = FixedEntitlements(.subscribed)
    #expect(await fixed.currentEntitlement() == .subscribed)
    var seen: [Entitlement] = []
    for await entitlement in fixed.entitlementUpdates() { seen.append(entitlement) }
    #expect(seen == [.subscribed])
  }
}

@Suite("A fixed store")
struct FixedStoreAccessTests {
  @Test("It answers the same every time", arguments: [true, false])
  func fixed(isAvailable: Bool) async {
    let store = FixedStoreAccess(isAvailable: isAvailable)
    #expect(await store.productsAreAvailable(["a", "b"]) == isAvailable)
    #expect(await store.restorePurchases() == isAvailable)
  }
}

@Suite("The free allowance (FR-STORE-001, FR-STORE-008)")
struct UsageAllowanceTests {
  private let limits = AllowanceLimits(scans: 2, intelligenceRequests: 3)

  private func allowance(
    store: any AllowanceStoring = MemoryAllowanceStore(), clock: Clock = Clock(now), isUnlimited: Bool = false
  ) -> UsageAllowance {
    UsageAllowance(limits: limits, store: store, calendar: utc, isUnlimited: isUnlimited) { clock.now }
  }

  @Test("Each action has its own limit")
  func limitsPerAction() {
    #expect(MeteredAction.allCases.count == 2)
    #expect(limits.limit(for: .scan) == 2)
    #expect(limits.limit(for: .intelligenceRequest) == 3)
    #expect(AllowanceLimits.free.scans > 0 && AllowanceLimits.free.intelligenceRequests > 0)
  }

  @Test("The gate allows a metered action below its limit, and always with Pro")
  func gate() {
    let pro: [Entitlement] = [.subscribed, .inGracePeriod, .trial(endsAt: now.addingTimeInterval(day))]
    let free: [Entitlement] = [
      .none, .expired, .revoked, .inBillingRetry, .trial(endsAt: now.addingTimeInterval(-day)),
    ]
    for action in MeteredAction.allCases {
      let limit = limits.limit(for: action)
      for entitlement in pro {
        #expect(FeatureGate.isAllowed(action, usedToday: limit + 9, limits: limits, entitlement: entitlement, now: now))
      }
      for entitlement in free {
        #expect(FeatureGate.isAllowed(action, usedToday: limit - 1, limits: limits, entitlement: entitlement, now: now))
        #expect(!FeatureGate.isAllowed(action, usedToday: limit, limits: limits, entitlement: entitlement, now: now))
      }
    }
  }

  @Test("Only a success is counted, and reaching the limit refuses the next start")
  func counting() async {
    let allowance = allowance()
    #expect(await allowance.isAllowed(.scan, entitlement: .none))
    #expect(await allowance.usedToday(.scan) == 0, "Asking costs nothing")
    await allowance.recordSuccess(.scan)
    #expect(await allowance.remainingToday(.scan) == 1)
    await allowance.recordSuccess(.scan)
    #expect(await allowance.remainingToday(.scan) == 0)
    #expect(await !allowance.isAllowed(.scan, entitlement: .none))
    #expect(await allowance.isAllowed(.intelligenceRequest, entitlement: .none), "The other meter is untouched")
    #expect(await allowance.isAllowed(.scan, entitlement: .subscribed), "Pro has no limit")
  }

  @Test("A new calendar day starts the counts again; setting the clock back does not")
  func days() async {
    let clock = Clock(now)
    let allowance = allowance(clock: clock)
    await allowance.recordSuccess(.scan)
    await allowance.recordSuccess(.scan)
    clock.advance(by: -2 * day)
    #expect(await allowance.usedToday(.scan) == 2)
    #expect(await !allowance.isAllowed(.scan, entitlement: .none))
    clock.advance(by: 3 * day)
    #expect(await allowance.usedToday(.scan) == 0)
    #expect(await allowance.isAllowed(.scan, entitlement: .none))
  }

  @Test("Counts outlive the object, and unreadable counts start from nothing")
  func storage() async {
    let store = MemoryAllowanceStore()
    await allowance(store: store).recordSuccess(.intelligenceRequest)
    #expect(await allowance(store: store).usedToday(.intelligenceRequest) == 1)
    #expect(await allowance(store: MemoryAllowanceStore(Data("not counts".utf8))).usedToday(.scan) == 0)
    let malformed = MemoryAllowanceStore(Data(#"{"day":[1],"used":{"scan":9}}"#.utf8))
    #expect(await allowance(store: malformed).usedToday(.scan) == 0)
  }

  @Test("Successes recorded at the same time are all counted")
  func concurrent() async {
    let allowance = UsageAllowance(
      limits: AllowanceLimits(scans: 100, intelligenceRequests: 100), store: MemoryAllowanceStore(), calendar: utc
    ) { now }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<50 { group.addTask { await allowance.recordSuccess(.scan) } }
    }
    #expect(await allowance.usedToday(.scan) == 50)
  }

  @Test("An unlimited allowance never refuses and never counts")
  func unlimited() async {
    let store = MemoryAllowanceStore()
    let allowance = allowance(store: store, isUnlimited: true)
    for _ in 0..<5 { await allowance.recordSuccess(.scan) }
    #expect(await allowance.isAllowed(.scan, entitlement: .none))
    #expect(await allowance.remainingToday(.scan) == .max)
    #expect(store.load() == nil)
  }

  @Test("The defaults store keeps what it is given")
  func defaultsStore() throws {
    let suite = "allowance-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsAllowanceStore(defaults: defaults)
    #expect(store.load() == nil)
    store.save(Data("x".utf8))
    #expect(store.load() == Data("x".utf8))
  }
}

@MainActor
@Suite("The entitlement store")
struct EntitlementStoreTests {
  /// Waits until a condition holds, giving other tasks the chance to run.
  private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<2_000 {
      if condition() { return true }
      await Task.yield()
    }
    return condition()
  }

  @Test("Nothing is known until the provider answers, and unknown is not Pro")
  func unknown() async {
    let store = EntitlementStore(provider: FakeEntitlements(.subscribed)) { now }
    #expect(store.entitlement == nil)
    #expect(!store.grantsPro)
    #expect(await store.resolved() == .subscribed)
    #expect(store.entitlement == .subscribed)
    #expect(store.grantsPro)
    #expect(await store.resolved() == .subscribed)
  }

  @Test("It follows the provider once started, and starting twice follows once")
  func follows() async {
    let fake = FakeEntitlements(.none)
    let store = EntitlementStore(provider: fake) { now }
    store.start()
    store.start()
    #expect(await eventually { store.entitlement == Entitlement.none })
    fake.set(.subscribed)
    #expect(await eventually { store.entitlement == .subscribed })
    fake.set(.expired)
    #expect(await eventually { store.entitlement == .expired })
    #expect(!store.grantsPro)
  }

  @Test("Once a trial's end has passed, it asks again, so Pro does not lapse until a restart")
  func trialEnd() async {
    let clock = Clock(now)
    let fake = FakeEntitlements(.trial(endsAt: now.addingTimeInterval(day)))
    let (waits, waiting) = AsyncStream.makeStream(of: TimeInterval.self)
    let (wakes, wake) = AsyncStream.makeStream(of: Void.self)
    let store = EntitlementStore(
      provider: fake, now: { clock.now },
      sleep: { seconds in
        waiting.yield(seconds)
        for await _ in wakes { break }
      })
    await store.refresh()
    #expect(store.grantsPro)
    var iterator = waits.makeAsyncIterator()
    #expect(await iterator.next() == day, "It waits for the trial's end")

    clock.advance(by: day + 1)
    #expect(!store.grantsPro, "The trial itself no longer grants Pro")
    fake.set(.subscribed)
    wake.yield()
    #expect(await eventually { store.entitlement == .subscribed })
    #expect(store.grantsPro)
  }

  @Test("A trial that has already ended waits for nothing")
  func endedTrial() async {
    let store = EntitlementStore(
      provider: FakeEntitlements(.trial(endsAt: now.addingTimeInterval(-day))), now: { now },
      sleep: { _ in Issue.record("It should not wait") })
    await store.refresh()
    #expect(!store.grantsPro)
  }
}
