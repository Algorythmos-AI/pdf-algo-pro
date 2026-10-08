import Commerce
import Core
import Foundation
import Observation

/// The subscription offer and the confirmation that follows a purchase (FR-STORE-003, FR-STORE-007).
///
/// The model shows the plans the App Store has and asks it to sell one (ADR-0027). It never decides
/// who has Pro: that is `EntitlementStore`'s, from the App Store's record of transactions. When the
/// entitlement comes to grant Pro while the offer is showing, the same presentation moves on to the
/// confirmation, whether the purchase was made here, approved later, or restored. A purchase that
/// is pending or cancelled changes nothing, so the offer simply stays.
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

  /// The plans, as far as the App Store has answered.
  public enum Plans: Sendable, Equatable {
    /// Asked for, not yet answered.
    case loading
    /// The plans, in the order they are listed.
    case loaded([PlanOffer])
    /// They could not be loaded: no connection, or the App Store does not have them.
    case unavailable
  }

  /// Something the person has to be told about a purchase.
  public enum Notice: String, Sendable, Identifiable {
    /// The purchase waits for approval; nothing has been charged.
    case pending
    /// The purchase could not be made; nothing has been charged.
    case failed

    /// The notice's name.
    public var id: String { rawValue }
  }

  /// What is showing.
  public private(set) var phase: Phase = .offer
  /// The plans on offer.
  public private(set) var plans: Plans = .loading
  /// The plan the button would buy.
  public private(set) var selectedPlanID: String?
  /// Whether the App Store's own sheet is up, or about to be.
  public private(set) var isPurchasing = false
  /// What to tell the person about the last purchase, if anything.
  public var notice: Notice?
  /// Whether the person already had Pro when the offer appeared: the offer then says so, and its
  /// button closes it and sells nothing.
  public private(set) var alreadyHasPro = false
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

  @ObservationIgnored private let offering: any StoreOffering
  @ObservationIgnored private let entitlements: EntitlementStore
  @ObservationIgnored private let telemetry: any TelemetryRecording
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let setReminder: (Bool, Date) async -> Bool
  @ObservationIgnored private let onClose: () -> Void
  /// Whether the person had Pro when the offer appeared; `nil` until it has appeared.
  @ObservationIgnored private var hadPro: Bool?
  /// Whether Pro arrived through Restore Purchases, so that it is not recorded as a purchase.
  @ObservationIgnored private var wasRestored = false
  /// Whether the offer's going away has been recorded.
  @ObservationIgnored private var hasRecordedClosing = false

  /// Creates the model.
  ///
  /// `setReminder` turns the trial reminder on or off for a trial ending at a date and returns
  /// whether it is now on, since asking for notification permission can be declined. `onClose`
  /// takes the presentation away.
  public init(
    trigger: PaywallTrigger, productIDs: [String], benefits: [PaywallBenefit], termsOfUse: URL, privacyPolicy: URL,
    offering: any StoreOffering, entitlements: EntitlementStore, telemetry: any TelemetryRecording,
    now: @escaping @Sendable () -> Date = { Date() },
    setReminder: @escaping (Bool, Date) async -> Bool = { _, _ in false }, onClose: @escaping () -> Void
  ) {
    self.trigger = trigger
    self.productIDs = productIDs
    self.benefits = benefits
    self.termsOfUse = termsOfUse
    self.privacyPolicy = privacyPolicy
    self.offering = offering
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
    let hasPro = await entitlements.resolved().grantsPro(at: now())
    hadPro = hasPro
    alreadyHasPro = hasPro
    await telemetry.record("commerce.paywall.viewed")
    await loadPlans()
  }

  /// The plan that is selected, once the plans have loaded.
  public var selectedPlan: PlanOffer? {
    guard case .loaded(let offers) = plans else { return nil }
    return offers.first { $0.id == selectedPlanID }
  }

  /// What the annual plan saves against paying weekly for a year, from the App Store's two prices;
  /// `nil` until both plans have loaded, and when the annual plan saves nothing.
  public var yearlySaving: YearlySaving? {
    guard case .loaded(let offers) = plans, let weekly = offers.first(where: { $0.term == .week }),
      let yearly = offers.first(where: { $0.term == .year })
    else { return nil }
    return YearlySaving(weeklyPrice: weekly.price, yearlyPrice: yearly.price)
  }

  /// Asks the App Store for the plans again, after they could not be loaded.
  public func retry() async {
    guard plans == .unavailable else { return }
    await loadPlans()
  }

  /// The person chose a plan.
  public func select(_ planID: String) async {
    guard case .loaded(let offers) = plans, offers.contains(where: { $0.id == planID }), planID != selectedPlanID
    else { return }
    selectedPlanID = planID
    await telemetry.record("commerce.plan.selected")
  }

  /// Asks the App Store to sell the selected plan, and acts on how that ends.
  ///
  /// The App Store confirms the purchase in its own sheet. A purchase that succeeds is read back
  /// as an entitlement, and it is the entitlement that leads to the confirmation.
  public func purchase() async {
    guard phase == .offer, !alreadyHasPro, !isPurchasing, let planID = selectedPlanID else { return }
    isPurchasing = true
    defer { isPurchasing = false }
    await telemetry.record("commerce.purchase.started")
    switch await offering.purchase(planID) {
    case .purchased:
      await entitlements.refresh()
      await entitlementChanged()
    case .pending:
      notice = .pending
    case .cancelled:
      break
    case .failed:
      notice = .failed
      await telemetry.record("commerce.purchase.failed")
    }
  }

  private func loadPlans() async {
    plans = .loading
    guard let offers = await offering.plans(for: productIDs), !offers.isEmpty else {
      plans = .unavailable
      return
    }
    plans = .loaded(offers)
    // The annual plan is the recommended one; it stays selected across a reload when still on offer.
    if !offers.contains(where: { $0.id == selectedPlanID }) {
      selectedPlanID = (offers.first { $0.term == .year } ?? offers[0]).id
    }
  }

  /// The entitlement changed while the presentation was up.
  ///
  /// Only a change from "no Pro" to "Pro" while the offer shows is a purchase. Someone who opened the
  /// plans from Settings with Pro already is not welcomed again.
  public func entitlementChanged() async {
    guard phase == .offer, hadPro == false, grantsPro else { return }
    phase = .welcome
    if wasRestored {
      await telemetry.record("commerce.purchase.restored")
    } else {
      await telemetry.record(trialEndsAt == nil ? "commerce.purchase.completed" : "commerce.trial.started")
    }
  }

  /// The presentation went away: by Close, by a swipe down, or because something replaced it.
  ///
  /// Recorded once, and only when the offer was still showing: after a purchase the confirmation
  /// is what closes.
  public func dismissed() async {
    guard phase == .offer, hadPro != nil, !hasRecordedClosing else { return }
    hasRecordedClosing = true
    await telemetry.record("commerce.paywall.closed")
  }

  /// Brings back purchases made elsewhere (Restore Purchases on the offer).
  public func restore(using store: any StoreAccessing) async {
    let answered = await store.restorePurchases()
    restoreFailed = !answered
    await entitlements.refresh()
    if !answered {
      await telemetry.record("commerce.restore.failed")
    } else if hadPro == false, grantsPro {
      // The confirmation follows, as after a purchase; it is recorded there as a restore.
      wasRestored = true
    }
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
