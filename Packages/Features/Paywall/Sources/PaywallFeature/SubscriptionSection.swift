import AccessibilityIDs
import Commerce
import Core
import DesignSystem
import StoreKit
import SwiftUI

/// The subscription section at the top of Settings: the plan the person is on, the plans on offer,
/// and the system's own screens to manage, restore and redeem (FR-STORE-003).
///
/// The app hands it to Settings as a section, so Settings needs to know nothing of the store.
public struct SubscriptionSection: View {
  private let entitlements: EntitlementStore
  private let store: any StoreAccessing
  private let telemetry: (any TelemetryRecording)?
  private let now: @Sendable () -> Date
  private let onSeePlans: () -> Void
  @State private var managesSubscription = false
  @State private var redeemsCode = false
  @State private var restoreOutcome: RestoreOutcome?
  @State private var isRestoring = false

  /// Creates the section; `onSeePlans` opens the subscription offer, and `telemetry` hears of a
  /// restore that brought Pro back or could not be made.
  public init(
    entitlements: EntitlementStore, store: any StoreAccessing, telemetry: (any TelemetryRecording)? = nil,
    now: @escaping @Sendable () -> Date = { Date() }, onSeePlans: @escaping () -> Void
  ) {
    self.entitlements = entitlements
    self.store = store
    self.telemetry = telemetry
    self.now = now
    self.onSeePlans = onSeePlans
  }

  /// The section.
  public var body: some View {
    Section {
      LabeledContent {
        Self.status(of: entitlements.entitlement, now: now()).foregroundStyle(Color.ds.labelSecondary)
      } label: {
        TileLabel(Text("Plan", bundle: .module), systemImage: "crown")
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(AccessibilityID.Settings.Subscription.plan)
      Button(action: onSeePlans) {
        Text("See plans", bundle: .module)
      }
      .accessibilityIdentifier(AccessibilityID.Settings.Subscription.plans)
      Button {
        managesSubscription = true
      } label: {
        Text("Manage subscription", bundle: .module)
      }
      .accessibilityIdentifier(AccessibilityID.Settings.Subscription.manage)
      Button {
        Task { await restore() }
      } label: {
        Text("Restore purchases", bundle: .module)
      }
      // One restore at a time: a second tap would only ask the App Store again (#247).
      .disabled(isRestoring)
      .accessibilityIdentifier(AccessibilityID.Settings.Subscription.restore)
      Button {
        redeemsCode = true
      } label: {
        Text("Redeem a code", bundle: .module)
      }
      .accessibilityIdentifier(AccessibilityID.Settings.Subscription.redeem)
    } header: {
      Text("Subscription", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
    } footer: {
      Text(
        "Reading, signing, sharing and exporting your documents never need Pro. The free plan has a daily limit on new scans and on answers.",
        bundle: .module
      )
      .foregroundStyle(Color.ds.labelSecondary)
    }
    .manageSubscriptionsSheet(isPresented: $managesSubscription)
    .offerCodeRedemption(isPresented: $redeemsCode)
    .restoreAlert($restoreOutcome)
  }

  /// Asks the App Store again, then reads the entitlement that results and says how it ended.
  private func restore() async {
    guard !isRestoring else { return }
    isRestoring = true
    defer { isRestoring = false }
    let hadPro = entitlements.grantsPro
    let answer = await store.restorePurchases()
    await entitlements.refresh()
    restoreOutcome = RestoreOutcome.after(
      answer, hasPro: entitlements.grantsPro, paused: entitlements.entitlement == .inBillingRetry)
    if let event = Self.event(answer, hadPro: hadPro, hasPro: entitlements.grantsPro) {
      await telemetry?.record(event)
    }
  }

  /// What a restore is recorded as; `nil` when it changed nothing worth counting.
  static func event(_ answer: RestoreAnswer, hadPro: Bool, hasPro: Bool) -> String? {
    if answer != .synced { return "commerce.restore.failed" }
    return !hadPro && hasPro ? "commerce.purchase.restored" : nil
  }

  /// The plan in words.
  ///
  /// Unknown, as at launch before the App Store has answered, reads as Free. In the grace period Pro
  /// stays and the payment is the problem; in billing retry Pro is paused until the payment goes through
  /// (#248).
  static func status(of entitlement: Entitlement?, now: Date) -> Text {
    switch entitlement {
    case .trial(let endsAt) where endsAt > now:
      Text("Pro, trial until \(endsAt, format: .dateTime.day().month().year())", bundle: .module)
    case .subscribed: Text("Pro", bundle: .module)
    case .inGracePeriod: Text("Pro, payment problem", bundle: .module)
    case .inBillingRetry: Text("Pro paused, payment problem", bundle: .module)
    case .trial, .expired, .revoked, .none?, nil: Text("Free", bundle: .module)
    }
  }
}
