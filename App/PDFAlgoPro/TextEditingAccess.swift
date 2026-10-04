import Commerce
import Core
import Foundation

/// Decides whether editing existing text is offered: first whether this build has it at all (the
/// release flag), then whether this person does (the Pro entitlement).
///
/// This is the one place the two meet. The reader and the PDF engine see only the answer, so the
/// editor carries no subscription logic and packaging can change here alone (FR-STORE-001).
struct AppTextEditingAccess: TextEditingAccessProviding {
  /// Whether this build has the feature: the `textEditing` release flag.
  let isEnabled: Bool
  /// Whether this build gives the feature to everyone.
  ///
  /// Internal builds do: there is nothing to buy in them yet, and testers need to reach it.
  let isGranted: Bool
  let entitlements: any EntitlementProviding
  var now: @Sendable () -> Date = { Date() }

  func textEditingAccess() async -> TextEditingAccess {
    guard isEnabled else { return .hidden }
    if isGranted { return .available }
    let entitlement = await entitlements.currentEntitlement()
    return FeatureGate.isAllowed(.textEditing, entitlement: entitlement, now: now()) ? .available : .locked
  }

  /// Whether this is an internal build: Debug and Staging, never Release.
  static var isInternalBuild: Bool {
    #if INTERNAL_TOOLS
      true
    #else
      false
    #endif
  }

  /// The access for this build: on, and granted, in internal builds; the compiled default (off)
  /// in a Release build, which therefore shows nothing of the feature.
  static func forThisBuild(entitlements: any EntitlementProviding) -> AppTextEditingAccess {
    AppTextEditingAccess(
      isEnabled: isInternalBuild || ReleaseFlag.textEditing.compiledDefault, isGranted: isInternalBuild,
      entitlements: entitlements)
  }
}
