import Foundation

/// Decides what an entitlement allows, without state and without reading a clock.
public enum FeatureGate {
  /// Whether a Pro feature may be used: only while the entitlement grants Pro.
  public static func isAllowed(_ feature: ProFeature, entitlement: Entitlement, now: Date) -> Bool {
    entitlement.grantsPro(at: now)
  }

  /// Whether an operation on the user's own document may be done: always, whatever the entitlement.
  ///
  /// A lapse, a refund or the absence of any purchase never locks a document, including one that
  /// holds results made while Pro was active (FR-STORE-004).
  public static func isAllowed(_ operation: DocumentOperation, entitlement: Entitlement, now: Date) -> Bool {
    true
  }
}
