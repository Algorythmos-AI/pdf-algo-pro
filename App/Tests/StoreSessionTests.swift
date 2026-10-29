import Commerce
import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import PDFAlgoPro

/// StoreKit's local test environment, as this test run finds it.
@MainActor
enum StoreTestEnvironment {
  /// What the environment did when it was tried.
  struct Probe: CustomStringConvertible {
    var sessionMade = false
    var productsLoaded = false
    var purchase = "not tried"
    var entitlement: Entitlement?

    /// Whether a test purchase reached the app as a verified entitlement.
    var answers: Bool { entitlement == .subscribed }

    var description: String {
      guard sessionMade else { return "no test session could be made" }
      let entitled = entitlement.map { "\($0)" } ?? "none read"
      return "products loaded: \(productsLoaded); test purchase: \(purchase); entitlement: \(entitled)"
    }
  }

  /// Whether a test purchase works from start to end: a session is made, the test products load,
  /// buying the weekly plan completes, and the app reads it back as a verified subscription.
  ///
  /// Loading the products is not enough: on a CI runner the environment can load them and still
  /// refuse every purchase (#352). What was found is written to the log.
  static func answers() async -> Bool {
    let probe = await probe()
    print("StoreKit test environment: \(probe); store session tests \(probe.answers ? "run" : "skipped")")
    return probe.answers
  }

  /// Tries the environment, each step bounded so a half-working one cannot hold the test run.
  static func probe() async -> Probe {
    var probe = Probe()
    guard let session = try? SKTestSession(configurationFileNamed: "Products") else { return probe }
    probe.sessionMade = true
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    defer { session.clearTransactions() }
    let catalog = ProductCatalog(bundleIdentifier: Bundle.main.bundleIdentifier ?? "")

    probe.productsLoaded =
      await bounded(.seconds(15)) { await StoreKitAccess().productsAreAvailable(catalog.ordered) } ?? false
    guard probe.productsLoaded else { return probe }

    let bought = await bounded(.seconds(15)) { () -> String in
      do {
        _ = try await session.buyProduct(identifier: catalog.weekly)
        return "completed"
      } catch {
        return "failed (\(error))"
      }
    }
    probe.purchase = bought ?? "no answer within 15 seconds"
    guard bought == "completed" else { return probe }

    let provider = StoreKitEntitlements(productIDs: catalog.productIDs)
    probe.entitlement = await bounded(.seconds(10)) { () -> Entitlement in
      for _ in 0..<50 {
        let entitlement = await provider.currentEntitlement()
        if entitlement == .subscribed { return entitlement }
        try? await Task.sleep(for: .milliseconds(200))
      }
      return await provider.currentEntitlement()
    }
    return probe
  }

  /// The result of `work`, or `nil` when it has not finished within `limit`; it is then cancelled.
  static func bounded<T>(_ limit: Duration, _ work: @escaping @MainActor () async -> T) async -> T? {
    let outcome = Outcome<T>()
    let task = Task { @MainActor in
      outcome.value = await work()
      outcome.isDone = true
    }
    let clock = ContinuousClock()
    let deadline = clock.now + limit
    while !outcome.isDone, clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(100))
    }
    guard outcome.isDone else {
      task.cancel()
      return nil
    }
    return outcome.value
  }

  /// Where bounded work leaves its result.
  @MainActor
  private final class Outcome<T> {
    var value: T?
    var isDone = false
  }
}

/// The store's real path, against StoreKit's local test environment: the products load, a purchase
/// reaches the app as a change of entitlement, and every transaction ends up finished (ADR-0026).
///
/// One session at a time: the test environment is shared by the whole process.
///
/// It runs where StoreKit's test environment can be reached, which today is a test run started from
/// Xcode. Under `xcodebuild test`, as in CI, the environment refuses calls ("Error saving
/// configuration file", `SKInternalErrorDomain` 3; a known limit of the tools), sometimes after
/// loading the products (#352), so the suite runs only once a test purchase has worked, and the log
/// line "StoreKit test environment:" says what was found. Buying is then covered by the device smoke
/// test. Each test has a minute: a purchase that never answers fails it, without holding the shard.
@MainActor
@Suite(
  "The store, against a StoreKit test session", .serialized, .timeLimit(.minutes(1)),
  .enabled("StoreKit's test environment does not complete a test purchase in this run") {
    await StoreTestEnvironment.answers()
  })
struct StoreSessionTests {

  private let catalog = ProductCatalog(bundleIdentifier: Bundle.main.bundleIdentifier ?? "")

  private func session() throws -> SKTestSession {
    let session = try SKTestSession(configurationFileNamed: "Products")
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    return session
  }

  /// Waits for the store to hold an entitlement the test accepts.
  private func eventually(_ store: EntitlementStore, _ accepts: (Entitlement?) -> Bool) async -> Bool {
    for _ in 0..<200 {
      if accepts(store.entitlement) { return true }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return accepts(store.entitlement)
  }

  @Test("The test data names the products this app asks for, and they load")
  func productsLoad() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    #expect(await StoreKitAccess().productsAreAvailable(catalog.ordered))
    #expect(await !StoreKitAccess().productsAreAvailable(catalog.ordered + ["not.a.product"]))
  }

  @Test("Buying the annual plan starts a trial, which grants Pro; expiring it takes Pro away")
  func yearlyTrial() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    let provider = StoreKitEntitlements(productIDs: catalog.productIDs)
    #expect(await provider.currentEntitlement() == Entitlement.none)
    let store = EntitlementStore(provider: provider)
    store.start()
    #expect(await eventually(store) { $0 == Entitlement.none })

    try await session.buyProduct(identifier: catalog.yearly)
    #expect(
      await eventually(store) {
        if case .trial = $0 { true } else { false }
      }, "The purchase arrives as a trial")
    #expect(store.grantsPro)
    var unfinished = 0
    for await _ in Transaction.unfinished { unfinished += 1 }
    #expect(unfinished == 0, "Every transaction was finished")

    try session.expireSubscription(productIdentifier: catalog.yearly)
    await store.refresh()
    #expect(await eventually(store) { $0 == .expired })
    #expect(!store.grantsPro)
  }

  @Test("The offering gives the plans in order, the annual one with its trial for an account that can have it")
  func plansOnOffer() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    let plans = try #require(await StoreKitOffering().plans(for: catalog.ordered))
    #expect(plans.map(\.id) == catalog.ordered && plans.map(\.term) == [.year, .week])
    #expect(plans[0].trial != nil, "Case A: an offer is configured and this account has not used it")
    #expect(plans[1].trial == nil, "Case C: the weekly plan has no introductory offer")
    #expect(await StoreKitOffering().plans(for: catalog.ordered + ["not.a.product"]) == nil)
  }

  @Test("Buying through the offering reaches the app as an entitlement, finished, and uses up the trial")
  func buyThroughTheOffering() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    let store = EntitlementStore(provider: StoreKitEntitlements(productIDs: catalog.productIDs))
    store.start()
    #expect(await eventually(store) { $0 == Entitlement.none })

    #expect(await StoreKitOffering().purchase(catalog.yearly) == .purchased)
    await store.refresh()
    #expect(
      await eventually(store) {
        if case .trial = $0 { true } else { false }
      }, "The purchase is read back as a trial")
    var unfinished = 0
    for await _ in Transaction.unfinished { unfinished += 1 }
    #expect(unfinished == 0, "The offering finished the transaction it was handed")

    let plans = try #require(await StoreKitOffering().plans(for: catalog.ordered))
    #expect(plans[0].trial == nil, "Case B: the offer is still configured, and this account has now used it")
  }

  @Test("Buying the weekly plan is a paid subscription, with no trial")
  func weekly() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    let store = EntitlementStore(provider: StoreKitEntitlements(productIDs: catalog.productIDs))
    store.start()
    try await session.buyProduct(identifier: catalog.weekly)
    #expect(await eventually(store) { $0 == .subscribed })
    #expect(store.grantsPro)
  }
}
