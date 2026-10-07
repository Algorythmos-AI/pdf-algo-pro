import Foundation

/// What the annual plan saves against paying for the weekly plan every week of a year (PAP-049).
///
/// It is worked out from the two prices StoreKit gives for the person's storefront, never written
/// into the app, because the saving differs from one storefront to the next. The percentage is
/// rounded down so the offer never claims more than the person saves.
public struct YearlySaving: Sendable, Equatable {
  /// The saving as a whole percentage of a year of weekly payments, rounded down.
  public let percent: Int
  /// The saving, in the currency of the prices.
  public let amount: Decimal

  /// The saving for a weekly and an annual price in the same currency; `nil` when either price is
  /// missing or the annual plan saves less than one percent.
  public init?(weeklyPrice: Decimal, yearlyPrice: Decimal) {
    guard weeklyPrice > 0, yearlyPrice > 0 else { return nil }
    let yearOfWeekly = weeklyPrice * 52
    let amount = yearOfWeekly - yearlyPrice
    guard amount > 0 else { return nil }
    var share = amount * 100 / yearOfWeekly
    var whole = Decimal()
    NSDecimalRound(&whole, &share, 0, .down)
    let percent = NSDecimalNumber(decimal: whole).intValue
    guard percent > 0 else { return nil }
    self.percent = percent
    self.amount = amount
  }
}
