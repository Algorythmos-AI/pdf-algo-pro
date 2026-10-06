import Commerce
import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import PDFAlgoPro

/// The store's real path, against StoreKit's local test environment: the products load, a purchase
/// reaches the app as a change of entitlement, and every transaction ends up finished (ADR-0026).
///
/// One session at a time: the test environment is shared by the whole process.
@MainActor
@Suite("The store, against a StoreKit test session", .serialized)
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

  @Test("Buying the weekly plan starts a trial, which grants Pro; expiring it takes Pro away")
  func weeklyTrial() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    let provider = StoreKitEntitlements(productIDs: catalog.productIDs)
    #expect(await provider.currentEntitlement() == Entitlement.none)
    let store = EntitlementStore(provider: provider)
    store.start()
    #expect(await eventually(store) { $0 == Entitlement.none })

    try await session.buyProduct(identifier: catalog.weekly)
    #expect(
      await eventually(store) {
        if case .trial = $0 { true } else { false }
      }, "The purchase arrives as a trial")
    #expect(store.grantsPro)
    var unfinished = 0
    for await _ in Transaction.unfinished { unfinished += 1 }
    #expect(unfinished == 0, "Every transaction was finished")

    try session.expireSubscription(productIdentifier: catalog.weekly)
    await store.refresh()
    #expect(await eventually(store) { $0 == .expired })
    #expect(!store.grantsPro)
  }

  @Test("Buying the annual plan is a paid subscription, with no trial")
  func yearly() async throws {
    let session = try session()
    defer { session.clearTransactions() }
    let store = EntitlementStore(provider: StoreKitEntitlements(productIDs: catalog.productIDs))
    store.start()
    try await session.buyProduct(identifier: catalog.yearly)
    #expect(await eventually(store) { $0 == .subscribed })
    #expect(store.grantsPro)
  }
}
