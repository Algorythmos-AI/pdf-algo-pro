import Commerce
import Core
import Foundation
import Observation

/// The subscription offer and the confirmation that follows a purchase (FR-STORE-003, FR-STORE-007).
///
/// The model never buys anything. StoreKit's own view does, and the purchase reaches the app the way
/// every purchase does, as a change of entitlement (ADR-0026). When the entitlement comes to grant
/// Pro while the offer is showing, the same presentation moves on to the confirmation. A purchase
/// that is pending or cancelled changes nothing, so the offer simply stays.
@MainActor
@Observable
public final class PaywallModel {
  /// What the presentation shows.
  public enum Phase: Sendable, Equatable {
    /// The plans.
    case offer
    /// "Welcome to Pro", after a purchase.
    case welcome
  }

  /// What is showing.
  public private(set) var phase: Phase = .offer
  /// Whether the trial reminder is asked for on the confirmation.
  public var wantsReminder = false
  /// Whether the last restore found nothing to bring back or could not be made.
  public var restoreFailed = false

  /// Why the offer is showing.
  public let trigger: PaywallTrigger
  /// The plans, in the order they are listed.
  public let productIDs: [String]
  /// What Pro adds in this build.
  public let benefits: [PaywallBenefit]
  /// The terms of use.
  public let termsOfUse: URL
  /// The privacy policy.
  public let privacyPolicy: URL

  @ObservationIgnored private let entitlements: EntitlementStore
  @ObservationIgnored private let telemetry: any TelemetryRecording
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let setReminder: (Bool, Date) async -> Bool
  @ObservationIgnored private let onClose: () -> Void
  /// Whether the person had Pro when the offer appeared; `nil` until it has appeared.
  @ObservationIgnored private var hadPro: Bool?

  /// Creates the model.
  ///
  /// `setReminder` turns the trial reminder on or off for a trial ending at a date and returns
  /// whether it is now on, since asking for notification permission can be declined. `onClose`
  /// takes the presentation away.
  public init(
    trigger: PaywallTrigger, productIDs: [String], benefits: [PaywallBenefit], termsOfUse: URL, privacyPolicy: URL,
    entitlements: EntitlementStore, telemetry: any TelemetryRecording,
    now: @escaping @Sendable () -> Date = { Date() },
    setReminder: @escaping (Bool, Date) async -> Bool = { _, _ in false }, onClose: @escaping () -> Void
  ) {
    self.trigger = trigger
    self.productIDs = productIDs
    self.benefits = benefits
    self.termsOfUse = termsOfUse
    self.privacyPolicy = privacyPolicy
    self.entitlements = entitlements
    self.telemetry = telemetry
    self.now = now
    self.setReminder = setReminder
    self.onClose = onClose
  }

  /// Whether the person has Pro now; the view watches it to learn of a purchase.
  public var grantsPro: Bool { entitlements.entitlement?.grantsPro(at: now()) ?? false }

  /// When the trial ends, during a trial; `nil` otherwise.
  public var trialEndsAt: Date? {
    guard case .trial(let endsAt) = entitlements.entitlement, endsAt > now() else { return nil }
    return endsAt
  }

  /// The offer came on screen.
  public func appeared() async {
    guard hadPro == nil else { return }
    hadPro = await entitlements.resolved().grantsPro(at: now())
    await telemetry.record("commerce.paywall.viewed")
  }

  /// The entitlement changed while the presentation was up.
  ///
  /// Only a change from "no Pro" to "Pro" while the offer shows is a purchase. Someone who opened the
  /// plans from Settings with Pro already is not welcomed again.
  public func entitlementChanged() async {
    guard phase == .offer, hadPro == false, grantsPro else { return }
    phase = .welcome
    await telemetry.record(trialEndsAt == nil ? "commerce.purchase.completed" : "commerce.trial.started")
  }

  /// Brings back purchases made elsewhere (Restore Purchases in Settings; the offer has StoreKit's own).
  public func restore(using store: any StoreAccessing) async {
    restoreFailed = !(await store.restorePurchases())
    await entitlements.refresh()
  }

  /// The person switched the trial reminder on or off; it stays off when permission is declined.
  public func reminderChanged() async {
    guard let trialEndsAt else {
      wantsReminder = false
      return
    }
    let isOn = await setReminder(wantsReminder, trialEndsAt)
    if wantsReminder != isOn { wantsReminder = isOn }
  }

  /// Closes the presentation: the Close button on the offer, Start on the confirmation.
  public func close() {
    onClose()
  }
}
