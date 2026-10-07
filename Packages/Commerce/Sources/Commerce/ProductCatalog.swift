/// The Pro subscription's products (ADR-0026).
///
/// Their identifiers derive from the app's bundle identifier, so the production app and the Staging
/// app each name their own products in App Store Connect and no identifier is shared between two
/// apps. Prices, the trial and the names people see are set in App Store Connect and never here.
public struct ProductCatalog: Sendable, Equatable {
  /// The weekly plan.
  public let weekly: String
  /// The annual plan, which carries the introductory offer (PAP-049).
  public let yearly: String

  /// The catalogue of the app with a bundle identifier.
  public init(bundleIdentifier: String) {
    weekly = "\(bundleIdentifier).pro.weekly"
    yearly = "\(bundleIdentifier).pro.yearly"
  }

  /// Both products, in the order the paywall lists them: the annual plan first.
  public var ordered: [String] { [yearly, weekly] }

  /// Both products, for telling a Pro purchase from any other.
  public var productIDs: Set<String> { [weekly, yearly] }
}
