/// Where the app learns the user's entitlement.
public protocol EntitlementProviding: Sendable {
  /// The entitlement now.
  func currentEntitlement() async -> Entitlement

  /// The entitlement now, then again each time it may have changed. Each call makes a new stream.
  func entitlementUpdates() -> AsyncStream<Entitlement>
}
