import Commerce
import Foundation

/// Lets a tester of an internal build have Pro without a purchase (ADR-0026).
///
/// Internal builds follow the sandbox store like any other, so the offer, the limits and the locked
/// states can all be seen. With the switch in Settings › Internal testing on, the entitlement reads
/// as subscribed whatever the store says. App Store builds do not contain the switch, and there this
/// type passes the store's answer through untouched.
struct InternalEntitlementOverride: EntitlementProviding {
  /// Where the switch is kept.
  static let key = "internal.entitlement.pro"

  let base: any EntitlementProviding
  var isOn: @Sendable () -> Bool = { UserDefaults.standard.bool(forKey: InternalEntitlementOverride.key) }

  func currentEntitlement() async -> Entitlement {
    isOn() ? .subscribed : await base.currentEntitlement()
  }

  func entitlementUpdates() -> AsyncStream<Entitlement> {
    AsyncStream { continuation in
      let task = Task {
        for await entitlement in base.entitlementUpdates() {
          continuation.yield(isOn() ? .subscribed : entitlement)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
