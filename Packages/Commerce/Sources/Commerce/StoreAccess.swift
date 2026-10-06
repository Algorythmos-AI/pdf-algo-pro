import StoreKit

/// What the app asks the App Store outside a purchase: whether the products can be shown, and to
/// bring back purchases made elsewhere.
public protocol StoreAccessing: Sendable {
  /// Whether every product loaded, so a paywall has plans to show.
  ///
  /// It is `false` without a connection, and until the products exist in App Store Connect.
  func productsAreAvailable(_ productIDs: [String]) async -> Bool

  /// Asks the App Store for this account's purchases again (Restore Purchases).
  ///
  /// - Returns: Whether the App Store answered; `false` when the person cancelled or it failed.
  func restorePurchases() async -> Bool
}

/// The App Store.
///
/// This is the adapter alone: it needs an App Store account or a StoreKit test session, so unit tests
/// use `FixedStoreAccess` and the device smoke test covers this.
public struct StoreKitAccess: StoreAccessing {
  /// Creates the adapter.
  public init() {}

  /// Whether every product loaded.
  public func productsAreAvailable(_ productIDs: [String]) async -> Bool {
    guard let products = try? await Product.products(for: productIDs) else { return false }
    return Set(products.map(\.id)) == Set(productIDs)
  }

  /// Syncs purchases with the App Store.
  public func restorePurchases() async -> Bool {
    (try? await AppStore.sync()) != nil
  }
}

/// A store that always answers the same: for launch arguments, previews and tests.
public struct FixedStoreAccess: StoreAccessing {
  private let isAvailable: Bool

  /// Creates a store whose products are available, or not.
  public init(isAvailable: Bool) {
    self.isAvailable = isAvailable
  }

  /// The fixed answer.
  public func productsAreAvailable(_ productIDs: [String]) async -> Bool { isAvailable }

  /// The fixed answer.
  public func restorePurchases() async -> Bool { isAvailable }
}
