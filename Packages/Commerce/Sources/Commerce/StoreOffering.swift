import Foundation
import StoreKit

/// How long a plan runs before it renews.
public enum PlanTerm: Sendable, Equatable {
  /// One week.
  case week
  /// One year.
  case year

  /// The term of a subscription period; `nil` for any other length.
  ///
  /// The App Store gives a one-week plan as seven days, and may give a year as twelve months.
  public init?(unit: Product.SubscriptionPeriod.Unit, value: Int) {
    switch (unit, value) {
    case (.week, 1), (.day, 7): self = .week
    case (.year, 1), (.month, 12): self = .year
    default: return nil
    }
  }
}

/// What a product's introductory offer is, as the App Store describes it.
public struct IntroductoryTerms: Sendable, Equatable {
  /// A unit of time an offer is counted in.
  public enum Unit: Sendable, Equatable {
    case day, week, month, year
  }

  /// Whether nothing is charged while the offer runs.
  public let isFree: Bool
  /// How many units the offer lasts.
  public let length: Int
  /// The unit the length is counted in.
  public let unit: Unit

  /// Creates the terms.
  public init(isFree: Bool, length: Int, unit: Unit) {
    self.isFree = isFree
    self.length = length
    self.unit = unit
  }
}

/// A free trial this account can have now.
///
/// It exists only when the App Store has a free introductory offer on the plan **and** says this
/// account is eligible for it. Where there is no value there is no trial to speak of, so the offer
/// screen cannot promise one that the App Store would not give.
public struct TrialOffer: Sendable, Equatable {
  /// How many units the trial lasts.
  public let length: Int
  /// The unit the length is counted in.
  public let unit: IntroductoryTerms.Unit

  /// Creates a trial of a length; tests and fixtures use it.
  public init(length: Int, unit: IntroductoryTerms.Unit) {
    self.length = length
    self.unit = unit
  }

  /// The trial that a plan's introductory offer gives this account; `nil` without an offer, for an
  /// offer that is paid, for a length that is not positive, and for an account that is not eligible.
  public init?(introductory terms: IntroductoryTerms?, isEligible: Bool) {
    guard let terms, terms.isFree, terms.length > 0, isEligible else { return nil }
    self.init(length: terms.length, unit: terms.unit)
  }
}

/// One plan as the offer screen shows it: every figure is the App Store's, for this storefront.
public struct PlanOffer: Sendable, Equatable, Identifiable {
  /// The product identifier.
  public let id: String
  /// How long the plan runs before it renews.
  public let term: PlanTerm
  /// The plan's name, in the person's language, as set in App Store Connect.
  public let name: String
  /// The price of one period.
  public let price: Decimal
  /// How an amount in this plan's currency is written for this storefront.
  public let priceFormat: Decimal.FormatStyle.Currency
  /// The free trial this account can have on the plan, if any.
  public let trial: TrialOffer?

  /// Creates a plan.
  public init(
    id: String, term: PlanTerm, name: String, price: Decimal, priceFormat: Decimal.FormatStyle.Currency,
    trial: TrialOffer?
  ) {
    self.id = id
    self.term = term
    self.name = name
    self.price = price
    self.priceFormat = priceFormat
    self.trial = trial
  }

  /// The price of one period, written for the storefront.
  public var displayPrice: String { price.formatted(priceFormat) }

  /// An amount in this plan's currency, written for the storefront: a saving, or nothing due today.
  public func formatted(_ amount: Decimal) -> String { amount.formatted(priceFormat) }
}

/// How an attempt to buy a plan ended.
public enum PurchaseOutcome: Sendable, Equatable {
  /// The App Store verified the purchase, and the transaction is finished.
  case purchased
  /// The purchase waits for something outside the app, such as a parent's approval.
  case pending
  /// The person closed the App Store's sheet without buying.
  case cancelled
  /// The purchase could not be made, or the App Store's answer could not be verified.
  case failed
}

/// The plans on sale and the way to buy one: the App Store in the app, a fixture in tests.
///
/// It sells and nothing more. Who has Pro is `EntitlementStore`'s to say, from the App Store's own
/// record of transactions; nothing here keeps or reports a subscription's state.
public protocol StoreOffering: Sendable {
  /// The plans, in the order asked for; `nil` when any of them cannot be loaded or understood.
  func plans(for productIDs: [String]) async -> [PlanOffer]?

  /// Asks the App Store to sell a plan; the App Store shows its own confirmation.
  func purchase(_ planID: String) async -> PurchaseOutcome
}

/// The App Store, through StoreKit 2.
///
/// This is the adapter alone: it needs an App Store account or a StoreKit test session, so unit
/// tests use `FixedStoreOffering` and the device smoke test covers this.
public struct StoreKitOffering: StoreOffering {
  /// Creates the adapter.
  public init() {}

  /// The plans as the App Store has them for this account and storefront.
  public func plans(for productIDs: [String]) async -> [PlanOffer]? {
    guard let products = try? await Product.products(for: productIDs) else { return nil }
    var offers: [PlanOffer] = []
    for productID in productIDs {
      guard let product = products.first(where: { $0.id == productID }), let subscription = product.subscription,
        let term = PlanTerm(unit: subscription.subscriptionPeriod.unit, value: subscription.subscriptionPeriod.value)
      else { return nil }
      let terms = subscription.introductoryOffer.map(IntroductoryTerms.init)
      let trial = TrialOffer(introductory: terms, isEligible: await subscription.isEligibleForIntroOffer)
      offers.append(
        PlanOffer(
          id: product.id, term: term, name: product.displayName, price: product.price,
          priceFormat: product.priceFormatStyle, trial: trial))
    }
    return offers
  }

  /// Buys a plan.
  ///
  /// A verified transaction is finished here, so every transaction is finished inside this package:
  /// this one, and those that arrive later on `Transaction.updates`.
  public func purchase(_ planID: String) async -> PurchaseOutcome {
    guard let product = try? await Product.products(for: [planID]).first else { return .failed }
    do {
      switch try await product.purchase() {
      case .success(let verification):
        guard case .verified(let transaction) = verification else { return .failed }
        await transaction.finish()
        return .purchased
      case .pending: return .pending
      case .userCancelled: return .cancelled
      @unknown default: return .failed
      }
    } catch {
      return .failed
    }
  }
}

extension IntroductoryTerms {
  /// The terms of a StoreKit offer: its whole length is its period times the number of periods.
  init(_ offer: Product.SubscriptionOffer) {
    let unit: Unit =
      switch offer.period.unit {
      case .day: .day
      case .week: .week
      case .month: .month
      case .year: .year
      @unknown default: .day
      }
    self.init(isFree: offer.paymentMode == .freeTrial, length: offer.period.value * offer.periodCount, unit: unit)
  }
}

/// A store that always answers the same: for launch arguments, previews and tests.
public struct FixedStoreOffering: StoreOffering {
  private let offers: [PlanOffer]?
  private let outcome: PurchaseOutcome
  private let onPurchased: @Sendable (PlanOffer) -> Void

  /// Creates a store with plans (or none, as without a connection) and the way every purchase
  /// ends; `onPurchased` runs when one succeeds, which is where a test grants the entitlement.
  public init(
    plans: [PlanOffer]?, outcome: PurchaseOutcome = .purchased,
    onPurchased: @escaping @Sendable (PlanOffer) -> Void = { _ in }
  ) {
    offers = plans
    self.outcome = outcome
    self.onPurchased = onPurchased
  }

  /// The fixed plans.
  public func plans(for productIDs: [String]) async -> [PlanOffer]? { offers }

  /// The fixed outcome.
  public func purchase(_ planID: String) async -> PurchaseOutcome {
    if outcome == .purchased, let plan = offers?.first(where: { $0.id == planID }) { onPurchased(plan) }
    return outcome
  }

  /// Two plans with made-up figures, for tests and previews: a year and a week, in that order.
  ///
  /// The figures are test data and say nothing about prices.
  public static func fixturePlans(
    yearlyID: String = "yearly", weeklyID: String = "weekly", trial: TrialOffer? = TrialOffer(length: 3, unit: .day)
  ) -> [PlanOffer] {
    let format = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
    return [
      PlanOffer(id: yearlyID, term: .year, name: "Pro Yearly", price: 20, priceFormat: format, trial: trial),
      PlanOffer(id: weeklyID, term: .week, name: "Pro Weekly", price: 1, priceFormat: format, trial: nil),
    ]
  }
}
