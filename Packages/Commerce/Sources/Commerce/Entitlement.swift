import Foundation

/// What the user's Pro subscription currently is.
public enum Entitlement: Sendable, Equatable {
  /// No purchase of Pro has been made on this account.
  case none
  /// A free trial that converts to a paid period, or ends, at `endsAt`.
  case trial(endsAt: Date)
  /// A paid subscription period is active.
  case subscribed
  /// A renewal failed and the App Store's billing grace period is running; Pro stays available.
  case inGracePeriod
  /// A renewal failed and the App Store is retrying the charge, with no grace period; Pro is paused.
  case inBillingRetry
  /// The subscription ended and was not renewed.
  case expired
  /// The App Store revoked the purchase, for a refund or a change in Family Sharing.
  case revoked

  /// Whether Pro features are available at a moment.
  ///
  /// A trial counts only until its end date: past it, the App Store reports a paid period, a retry or
  /// an expiry, and until that arrives the trial no longer grants Pro.
  public func grantsPro(at now: Date) -> Bool {
    switch self {
    case .trial(let endsAt): now < endsAt
    case .subscribed, .inGracePeriod: true
    case .none, .inBillingRetry, .expired, .revoked: false
    }
  }

  /// The entitlement that a set of purchase records adds up to.
  ///
  /// Records for products outside `productIDs` are ignored. With several records, the one that gives
  /// the user the most wins: subscribed, then trial, grace period, billing retry, expired, revoked.
  public static func resolve(records: [PurchaseRecord], productIDs: Set<String>, now: Date) -> Entitlement {
    records
      .filter { productIDs.contains($0.productID) }
      .map { $0.entitlement(at: now) }
      .max { $0.rank < $1.rank } ?? .none
  }

  private var rank: Int {
    switch self {
    case .none: 0
    case .revoked: 1
    case .expired: 2
    case .inBillingRetry: 3
    case .inGracePeriod: 4
    case .trial: 5
    case .subscribed: 6
    }
  }
}

/// One purchase of a subscription product, as plain values taken from an App Store transaction.
public struct PurchaseRecord: Sendable, Equatable {
  /// The offer a purchase was made with.
  public enum Offer: Sendable, Equatable {
    /// An introductory offer that is free for its period: the trial.
    case freeTrial
    /// An introductory offer the user pays for.
    case paidIntroductory
    /// A promotional, win-back or code offer.
    case other
  }

  /// The subscription's renewal state, as the App Store reports it.
  public enum RenewalState: Sendable, Equatable {
    /// The subscription is active.
    case subscribed
    /// A renewal failed and the billing grace period is running.
    case inGracePeriod
    /// A renewal failed and the App Store is retrying the charge.
    case inBillingRetry
    /// The subscription ended.
    case expired
    /// The App Store revoked the purchase.
    case revoked
  }

  /// The product that was bought.
  public var productID: String
  /// When the current period ends; `nil` for a product that does not expire.
  public var expirationDate: Date?
  /// When the App Store revoked the purchase; `nil` when it did not.
  public var revocationDate: Date?
  /// The offer the current period was bought with; `nil` at the standard terms.
  public var offer: Offer?
  /// The renewal state; `nil` when the App Store did not report one.
  public var renewalState: RenewalState?

  /// Creates a record.
  public init(
    productID: String, expirationDate: Date? = nil, revocationDate: Date? = nil, offer: Offer? = nil,
    renewalState: RenewalState? = nil
  ) {
    self.productID = productID
    self.expirationDate = expirationDate
    self.revocationDate = revocationDate
    self.offer = offer
    self.renewalState = renewalState
  }

  /// The entitlement this record alone gives at a moment.
  ///
  /// A revocation wins over everything. Then the reported renewal state decides; without one, a
  /// period whose end has passed is expired. An active period bought as a free trial is a trial.
  public func entitlement(at now: Date) -> Entitlement {
    if revocationDate != nil { return .revoked }
    switch renewalState {
    case .revoked: return .revoked
    case .expired: return .expired
    case .inGracePeriod: return .inGracePeriod
    case .inBillingRetry: return .inBillingRetry
    case .subscribed: break
    case nil:
      if let expirationDate, expirationDate <= now { return .expired }
    }
    if offer == .freeTrial, let expirationDate { return .trial(endsAt: expirationDate) }
    return .subscribed
  }
}
