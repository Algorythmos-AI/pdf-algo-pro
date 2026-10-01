import StoreKit

/// The parts of an App Store transaction that an entitlement depends on.
///
/// StoreKit's `Transaction` conforms; tests use a stand-in, since a `Transaction` cannot be made
/// outside the App Store.
protocol PurchaseTransaction: Sendable {
  /// The product that was bought.
  var productID: String { get }
  /// When the current period ends.
  var expirationDate: Date? { get }
  /// When the App Store revoked the purchase.
  var revocationDate: Date? { get }
  /// The offer the current period was bought with.
  var purchaseOffer: PurchaseRecord.Offer? { get }
  /// The subscription's renewal state, which the App Store may have to be asked for.
  func renewalState() async -> PurchaseRecord.RenewalState?
  /// Tells the App Store that the app has handled the transaction.
  func finish() async
}

extension PurchaseRecord {
  /// The record of a transaction.
  init(_ transaction: some PurchaseTransaction) async {
    self.init(
      productID: transaction.productID, expirationDate: transaction.expirationDate,
      revocationDate: transaction.revocationDate, offer: transaction.purchaseOffer,
      renewalState: await transaction.renewalState())
  }

  /// The record of a transaction that StoreKit verified; `nil` for one it did not.
  init?(verified result: VerificationResult<some PurchaseTransaction>) async {
    guard case .verified(let transaction) = result else { return nil }
    await self.init(transaction)
  }

  /// The records of the verified transactions in a sequence, such as the current entitlements.
  static func verified<Transactions: AsyncSequence, T: PurchaseTransaction>(
    in transactions: Transactions
  ) async -> [PurchaseRecord] where Transactions.Element == VerificationResult<T>, Transactions.Failure == Never {
    var records: [PurchaseRecord] = []
    for await result in transactions {
      if let record = await PurchaseRecord(verified: result) { records.append(record) }
    }
    return records
  }

  /// A value for each transaction in a sequence of updates.
  ///
  /// A verified one is finished first, so the App Store does not deliver it again; an unverified one
  /// is left alone.
  static func changes<Transactions: AsyncSequence & Sendable, T: PurchaseTransaction>(
    in transactions: Transactions
  ) -> AsyncStream<Void> where Transactions.Element == VerificationResult<T>, Transactions.Failure == Never {
    AsyncStream { continuation in
      let task = Task {
        for await update in transactions {
          if case .verified(let transaction) = update { await transaction.finish() }
          continuation.yield()
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

extension PurchaseRecord.Offer {
  /// The offer from StoreKit's offer type and payment mode.
  init(type: Transaction.OfferType, paymentMode: Transaction.Offer.PaymentMode?) {
    if type == .introductory {
      self = paymentMode == .freeTrial ? .freeTrial : .paidIntroductory
    } else {
      self = .other
    }
  }
}

extension PurchaseRecord.RenewalState {
  /// The state from StoreKit's renewal state; `nil` for one this version does not know.
  init?(_ state: Product.SubscriptionInfo.RenewalState) {
    switch state {
    case .subscribed: self = .subscribed
    case .inGracePeriod: self = .inGracePeriod
    case .inBillingRetryPeriod: self = .inBillingRetry
    case .expired: self = .expired
    case .revoked: self = .revoked
    default: return nil
    }
  }
}
