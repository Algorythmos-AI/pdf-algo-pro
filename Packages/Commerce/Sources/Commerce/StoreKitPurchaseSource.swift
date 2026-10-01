import StoreKit

/// Purchase records from the App Store.
///
/// Only transactions that StoreKit verified are used.
///
/// This type and the conformance below are the adapter alone: they need an App Store account or a
/// StoreKit test session, so unit tests do not run them. Everything they call is in
/// `PurchaseTransaction.swift` and is tested with a stand-in transaction.
struct StoreKitPurchaseSource: PurchaseRecordSource {
  func activeRecords() async -> [PurchaseRecord] {
    await PurchaseRecord.verified(in: Transaction.currentEntitlements)
  }

  func latestRecord(for productID: String) async -> PurchaseRecord? {
    guard let latest = await Transaction.latest(for: productID) else { return nil }
    return await PurchaseRecord(verified: latest)
  }

  func changes() -> AsyncStream<Void> {
    PurchaseRecord.changes(in: Transaction.updates)
  }
}

extension Transaction: PurchaseTransaction {
  var purchaseOffer: PurchaseRecord.Offer? {
    offer.map { PurchaseRecord.Offer(type: $0.type, paymentMode: $0.paymentMode) }
  }

  func renewalState() async -> PurchaseRecord.RenewalState? {
    await subscriptionStatus.flatMap { PurchaseRecord.RenewalState($0.state) }
  }
}
