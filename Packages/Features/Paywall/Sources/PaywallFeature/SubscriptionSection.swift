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
  @State private var restoreFailed = false

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
      .accessibilityIdentifier("settings.subscription.plan")
      Button(action: onSeePlans) {
        Text("See plans", bundle: .module)
      }
      .accessibilityIdentifier("settings.subscription.plans")
      Button {
        managesSubscription = true
      } label: {
        Text("Manage subscription", bundle: .module)
      }
      .accessibilityIdentifier("settings.subscription.manage")
      Button {
        Task { restoreFailed = !(await restore()) }
      } label: {
        Text("Restore purchases", bundle: .module)
      }
      .accessibilityIdentifier("settings.subscription.restore")
      Button {
        redeemsCode = true
      } label: {
        Text("Redeem a code", bundle: .module)
      }
      .accessibilityIdentifier("settings.subscription.redeem")
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
    .alert(Text("Restore purchases", bundle: .module), isPresented: $restoreFailed) {
      Button {
      } label: {
        Text("OK", bundle: .module)
      }
    } message: {
      Text(
        "Nothing could be restored. Check that you are signed in to the App Store with the account that bought Pro.",
        bundle: .module)
    }
  }

  /// Asks the App Store again, then reads the entitlement that results.
  private func restore() async -> Bool {
    let hadPro = entitlements.grantsPro
    let answered = await store.restorePurchases()
    await entitlements.refresh()
    if let event = Self.event(answered: answered, hadPro: hadPro, hasPro: entitlements.grantsPro) {
      await telemetry?.record(event)
    }
    return answered
  }

  /// What a restore is recorded as; `nil` when it changed nothing worth counting.
  static func event(answered: Bool, hadPro: Bool, hasPro: Bool) -> String? {
    if !answered { return "commerce.restore.failed" }
    return !hadPro && hasPro ? "commerce.purchase.restored" : nil
  }

  /// The plan in words.
  ///
  /// Unknown, as at launch before the App Store has answered, reads as Free.
  static func status(of entitlement: Entitlement?, now: Date) -> Text {
    switch entitlement {
    case .trial(let endsAt) where endsAt > now:
      Text("Pro, trial until \(endsAt, format: .dateTime.day().month().year())", bundle: .module)
    case .subscribed: Text("Pro", bundle: .module)
    case .inGracePeriod, .inBillingRetry: Text("Pro, payment problem", bundle: .module)
    case .trial, .expired, .revoked, .none?, nil: Text("Free", bundle: .module)
    }
  }
}
