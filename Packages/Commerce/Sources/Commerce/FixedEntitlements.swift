/// An entitlement that never changes: for launch arguments, previews and builds without a store.
public struct FixedEntitlements: EntitlementProviding {
  private let entitlement: Entitlement

  /// Creates a provider that always reports the same entitlement.
  public init(_ entitlement: Entitlement) {
    self.entitlement = entitlement
  }

  /// The entitlement.
  public func currentEntitlement() async -> Entitlement { entitlement }

  /// The entitlement, once; it never changes.
  public func entitlementUpdates() -> AsyncStream<Entitlement> {
    AsyncStream { continuation in
      continuation.yield(entitlement)
      continuation.finish()
    }
  }
}
