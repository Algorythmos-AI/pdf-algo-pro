import Foundation

/// Where purchase records come from; the App Store in the app, a fake in tests.
protocol PurchaseRecordSource: Sendable {
  /// A record for each purchase that currently entitles the user to something.
  func activeRecords() async -> [PurchaseRecord]
  /// The most recent purchase of a product, entitling or not.
  func latestRecord(for productID: String) async -> PurchaseRecord?
  /// A value each time a purchase is made, renewed, refunded or revoked.
  func changes() -> AsyncStream<Void>
}

/// The user's entitlement from StoreKit 2 (ADR-0011).
///
/// It reads `Transaction.currentEntitlements` and follows `Transaction.updates`. When no current
/// entitlement names a Pro product, it reads each product's latest transaction, which is how an
/// expired, revoked or billing-retry subscription is told apart from no purchase at all.
public struct StoreKitEntitlements: EntitlementProviding {
  private let productIDs: Set<String>
  private let source: any PurchaseRecordSource
  private let now: @Sendable () -> Date

  /// Creates a provider for the Pro subscription's product identifiers.
  public init(productIDs: Set<String>, now: @escaping @Sendable () -> Date = { Date() }) {
    self.init(productIDs: productIDs, source: StoreKitPurchaseSource(), now: now)
  }

  init(productIDs: Set<String>, source: any PurchaseRecordSource, now: @escaping @Sendable () -> Date) {
    self.productIDs = productIDs
    self.source = source
    self.now = now
  }

  /// The entitlement now.
  public func currentEntitlement() async -> Entitlement {
    // StoreKit lists a subscription among the current entitlements only while its renewal state is
    // subscribed or in the billing grace period
    // (https://developer.apple.com/documentation/storekit/transaction/currententitlements). A record
    // from there whose state could not be read (offline, a server error, a state this version does
    // not know) is therefore entitled on the App Store's own account, even after its period's end, as
    // during a grace period: it counts as subscribed, never as expired by the clock. Once StoreKit no
    // longer lists it, the latest transaction below decides, and there a passed end is an expiry.
    var records = await source.activeRecords().filter { productIDs.contains($0.productID) }.map { record in
      var record = record
      if record.renewalState == nil { record.renewalState = .subscribed }
      return record
    }
    if records.isEmpty {
      for productID in productIDs.sorted() {
        if let record = await source.latestRecord(for: productID) { records.append(record) }
      }
    }
    return Entitlement.resolve(records: records, productIDs: productIDs, now: now())
  }

  /// The entitlement now, then again after each change to the user's purchases.
  public func entitlementUpdates() -> AsyncStream<Entitlement> {
    AsyncStream { continuation in
      let task = Task {
        continuation.yield(await currentEntitlement())
        for await _ in source.changes() {
          continuation.yield(await currentEntitlement())
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
