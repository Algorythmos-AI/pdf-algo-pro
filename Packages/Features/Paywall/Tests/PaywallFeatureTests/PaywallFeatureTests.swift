import Commerce
import CommerceTestSupport
import Core
import CoreTestSupport
import Foundation
import StoreKit
import SwiftUI
import Testing

@testable import PaywallFeature

nonisolated private let now = Date(timeIntervalSince1970: 1_800_000_000)
nonisolated private let day: TimeInterval = 24 * 60 * 60

@MainActor
private final class Flags {
  var closed = 0
  var reminders: [(Bool, Date)] = []
  var reminderAnswer = true
  /// Why the reminder isn't set when `reminderAnswer` is false.
  var refusal = TrialReminderOutcome.notificationsDeclined
}

@MainActor
@Suite("The subscription offer")
struct PaywallModelTests {
  private func makeModel(
    _ entitlement: Entitlement = .none, trigger: PaywallTrigger = .onboarding,
    plans: [PlanOffer]? = FixedStoreOffering.fixturePlans(), outcome: PurchaseOutcome = .purchased
  ) -> (PaywallModel, FakeEntitlements, EntitlementStore, RecordingTelemetry, Flags) {
    let fake = FakeEntitlements(entitlement)
    // A purchase that succeeds grants what the App Store would: a trial where the plan has one.
    let offering = FixedStoreOffering(plans: plans, outcome: outcome) { plan in
      fake.set(plan.trial == nil ? .subscribed : .trial(endsAt: now.addingTimeInterval(3 * day)))
    }
    let store = EntitlementStore(provider: fake) { now }
    let telemetry = RecordingTelemetry()
    let flags = Flags()
    let model = PaywallModel(
      trigger: trigger, productIDs: ["yearly", "weekly"], benefits: [.unlimitedScans, .unlimitedIntelligence],
      termsOfUse: URL(fileURLWithPath: "/terms"), privacyPolicy: URL(fileURLWithPath: "/privacy"),
      offering: offering, entitlements: store, telemetry: telemetry, now: { now },
      setReminder: { isOn, date in
        flags.reminders.append((isOn, date))
        return isOn ? (flags.reminderAnswer ? .scheduled : flags.refusal) : .off
      }, onClose: { flags.closed += 1 })
    return (model, fake, store, telemetry, flags)
  }

  /// Makes the store hold what the provider now reports, as a purchase would.
  private func purchase(_ entitlement: Entitlement, _ fake: FakeEntitlements, _ store: EntitlementStore) async {
    fake.set(entitlement)
    await store.refresh()
  }

  @Test("It opens on the offer, records the view once, and closes when asked")
  func opens() async {
    let (model, _, _, telemetry, flags) = makeModel()
    #expect(model.phase == .offer && !model.grantsPro && model.trialEndsAt == nil)
    await model.appeared()
    await model.appeared()
    #expect(await telemetry.events == ["commerce.paywall.viewed"])
    model.close()
    #expect(flags.closed == 1)
  }

  @Test("A purchase moves the same presentation on to the confirmation (FR-STORE-007)")
  func purchase() async {
    let (model, fake, store, telemetry, _) = makeModel()
    await model.appeared()
    await purchase(.subscribed, fake, store)
    #expect(model.grantsPro)
    await model.entitlementChanged()
    #expect(model.phase == .welcome && model.trialEndsAt == nil)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.completed"])
    await model.entitlementChanged()
    #expect(await telemetry.events.count == 2, "It is recorded once")
  }

  @Test("A trial shows when it ends, and is recorded as a trial")
  func trial() async {
    let end = now.addingTimeInterval(3 * day)
    let (model, fake, store, telemetry, _) = makeModel()
    await model.appeared()
    await purchase(.trial(endsAt: end), fake, store)
    await model.entitlementChanged()
    #expect(model.phase == .welcome && model.trialEndsAt == end)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.trial.started"])
  }

  @Test(
    "A pending, cancelled or failed purchase leaves the offer as it is",
    arguments: [Entitlement.none, .expired, .revoked, .inBillingRetry, .trial(endsAt: now.addingTimeInterval(-day))])
  func noPurchase(entitlement: Entitlement) async {
    let (model, fake, store, telemetry, _) = makeModel()
    await model.appeared()
    await purchase(entitlement, fake, store)
    await model.entitlementChanged()
    #expect(model.phase == .offer && !model.grantsPro && model.trialEndsAt == nil)
    #expect(await telemetry.events == ["commerce.paywall.viewed"])
  }

  @Test("Someone who opens the plans with Pro already is not welcomed again")
  func alreadyPro() async {
    let (model, fake, store, telemetry, _) = makeModel(.subscribed, trigger: .settings)
    await model.appeared()
    await model.entitlementChanged()
    await purchase(.inGracePeriod, fake, store)
    await model.entitlementChanged()
    #expect(model.phase == .offer)
    #expect(await telemetry.events == ["commerce.paywall.viewed"])
  }

  @Test("A change before the offer has appeared is not taken for a purchase")
  func beforeAppearing() async {
    let (model, fake, store, _, _) = makeModel()
    await purchase(.subscribed, fake, store)
    await model.entitlementChanged()
    #expect(model.phase == .offer)
  }

  @Test("The reminder is set for the trial's end, and stays off when permission is declined")
  func reminder() async {
    let end = now.addingTimeInterval(3 * day)
    let (model, fake, store, _, flags) = makeModel()
    await model.appeared()
    await purchase(.trial(endsAt: end), fake, store)
    model.wantsReminder = true
    await model.reminderChanged()
    #expect(model.wantsReminder && flags.reminders.count == 1)
    #expect(flags.reminders.first?.0 == true && flags.reminders.first?.1 == end)
    model.wantsReminder = false
    await model.reminderChanged()
    #expect(!model.wantsReminder && flags.reminders.last?.0 == false)
    flags.reminderAnswer = false
    model.wantsReminder = true
    await model.reminderChanged()
    #expect(!model.wantsReminder, "Permission was declined")
    #expect(model.reminderProblem == .notificationsDeclined, "and the confirmation says why")
    // The switch going back off calls this again (onChange): the reason stays on screen.
    await model.reminderChanged()
    #expect(model.reminderProblem == .notificationsDeclined)
    flags.reminderAnswer = true
    model.wantsReminder = true
    await model.reminderChanged()
    #expect(model.wantsReminder && model.reminderProblem == nil, "Once it is on, there is nothing to explain")
  }

  @Test("With less than a day of the trial left, no reminder is offered: its day before has passed")
  func noReminderTooLate() async {
    let (model, fake, store, _, _) = makeModel()
    await model.appeared()
    await purchase(.trial(endsAt: now.addingTimeInterval(3 * day)), fake, store)
    #expect(model.canRemind)
    // A TestFlight trial, shortened, that ends the next day (a tester's report, 2026-10-26).
    await purchase(.trial(endsAt: now.addingTimeInterval(day / 2)), fake, store)
    #expect(model.trialEndsAt != nil && !model.canRemind)
  }

  @Test("Without a trial there is nothing to remind of")
  func noReminderWithoutATrial() async {
    let (model, _, _, _, flags) = makeModel(.subscribed)
    model.wantsReminder = true
    await model.reminderChanged()
    #expect(!model.wantsReminder && flags.reminders.isEmpty)
  }

  @Test("Restoring asks the store, then reads the entitlement again", arguments: [true, false])
  func restore(answers: Bool) async {
    let (model, fake, _, _, _) = makeModel()
    fake.set(.subscribed)
    await model.restore(using: FixedStoreAccess(isAvailable: answers))
    #expect(model.restoreOutcome == (answers ? .restored : .failed))
    #expect(model.grantsPro, "What the App Store now reports is read either way")
  }

  @Test("A restore that brings Pro back is recorded as a restore, not as a purchase")
  func restoredIsNotAPurchase() async {
    let (model, fake, _, telemetry, _) = makeModel()
    await model.appeared()
    fake.set(.subscribed)
    await model.restore(using: FixedStoreAccess(isAvailable: true))
    await model.entitlementChanged()
    #expect(model.phase == .welcome)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.restored"])
    await model.dismissed()
    #expect(await telemetry.events.count == 2, "The confirmation closing is not the offer closing")
  }

  @Test("A restore that could not be made is recorded, and the offer stays")
  func restoreFailed() async {
    let (model, _, _, telemetry, _) = makeModel()
    await model.appeared()
    await model.restore(using: FixedStoreAccess(isAvailable: false))
    #expect(model.restoreOutcome == .failed && model.phase == .offer)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.restore.failed"])
  }

  @Test("A restore that finds nothing to bring back says so, rather than nothing at all (#247)")
  func restoreFindsNothing() async {
    let (model, _, _, _, _) = makeModel()
    await model.appeared()
    await model.restore(using: FixedStoreAccess(isAvailable: true))
    #expect(model.restoreOutcome == .nothingFound)
    #expect(model.phase == .offer && !model.grantsPro)
  }

  @Test("Restoring on the offer with Pro already on says so; one that leads to the confirmation leaves it to it (#247)")
  func restoreWithProAlready() async {
    let (model, _, _, _, _) = makeModel(.subscribed, trigger: .settings)
    await model.appeared()
    await model.restore(using: FixedStoreAccess(isAvailable: true))
    #expect(model.restoreOutcome == .restored && model.phase == .offer)
    #expect(model.alertsAbout(.restored), "Nothing else on screen changes, so the alert says it")

    let (fresh, fake, _, _, _) = makeModel()
    await fresh.appeared()
    fake.set(.subscribed)
    await fresh.restore(using: FixedStoreAccess(isAvailable: true))
    #expect(!fresh.alertsAbout(.restored), "The confirmation follows and says it")
    #expect(fresh.alertsAbout(.failed) && fresh.alertsAbout(.nothingFound) && !fresh.alertsAbout(.cancelled))
  }

  @Test("A restore says whether it brought Pro back or could not reach the App Store (#247)")
  func restoreSaysWhichItWas() async {
    let (model, fake, _, _, _) = makeModel()
    await model.appeared()
    await model.restore(using: FixedStoreAccess(isAvailable: false))
    #expect(model.restoreOutcome == .failed)
    fake.set(.subscribed)
    await model.restore(using: FixedStoreAccess(isAvailable: true))
    #expect(model.restoreOutcome == .restored)
  }

  @Test(
    "A cancelled sign-in says nothing and is not blamed on the Apple Account; every other ending says something (#247)"
  )
  func restoreCancelled() async {
    let (model, _, _, telemetry, _) = makeModel()
    await model.appeared()
    await model.restore(using: FixedStoreAccess(isAvailable: true, restore: .cancelled))
    #expect(model.restoreOutcome == .cancelled && model.restoreOutcome?.message == nil)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.restore.failed"])
    for outcome in [RestoreOutcome.restored, .nothingFound, .failed] {
      #expect(outcome.message != nil)
    }
    #expect(!model.isRestoring)
  }

  @Test("The offer going away without a purchase is recorded once, and not before it appeared")
  func dismissed() async {
    let (model, _, _, telemetry, _) = makeModel()
    await model.dismissed()
    #expect(await telemetry.events.isEmpty)
    await model.appeared()
    await model.dismissed()
    await model.dismissed()
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.paywall.closed"])
  }

  @Test("Restoring from Settings is counted only when it changed something or failed")
  func settingsRestoreEvent() {
    #expect(SubscriptionSection.event(.failed, hadPro: false, hasPro: false) == "commerce.restore.failed")
    #expect(SubscriptionSection.event(.cancelled, hadPro: false, hasPro: false) == "commerce.restore.failed")
    #expect(SubscriptionSection.event(.synced, hadPro: false, hasPro: true) == "commerce.purchase.restored")
    #expect(SubscriptionSection.event(.synced, hadPro: true, hasPro: true) == nil)
    #expect(SubscriptionSection.event(.synced, hadPro: false, hasPro: false) == nil)
  }

  @Test("The plans load when the offer appears, with the annual plan selected")
  func plansLoad() async {
    let (model, _, _, _, _) = makeModel()
    #expect(model.plans == .loading && model.selectedPlan == nil)
    await model.appeared()
    #expect(model.plans == .loaded(FixedStoreOffering.fixturePlans()))
    #expect(model.selectedPlan?.term == .year && !model.alreadyHasPro)
    #expect(model.yearlySaving?.percent == 61, "52 weeks at 1 against 20: 32 of 52, rounded down")
  }

  @Test("Choosing a plan selects it and is recorded once; choosing it again, or an unknown one, is not")
  func selection() async {
    let (model, _, _, telemetry, _) = makeModel()
    await model.appeared()
    await model.select("weekly")
    #expect(model.selectedPlan?.term == .week)
    await model.select("weekly")
    await model.select("nothing")
    #expect(model.selectedPlan?.term == .week)
    await model.select("yearly")
    #expect(model.selectedPlan?.term == .year)
    #expect(
      await telemetry.events == ["commerce.paywall.viewed", "commerce.plan.selected", "commerce.plan.selected"])
  }

  @Test("Without plans the offer says so, sells nothing, and asks again on Retry")
  func unavailable() async {
    let (model, _, _, telemetry, _) = makeModel(plans: nil)
    await model.appeared()
    #expect(model.plans == .unavailable && model.selectedPlan == nil && model.yearlySaving == nil)
    await model.purchase()
    await model.retry()
    #expect(model.plans == .unavailable && model.phase == .offer)
    #expect(await telemetry.events == ["commerce.paywall.viewed"], "Nothing was started")
  }

  @Test("Buying the annual plan with its trial leads to the confirmation as a trial (case A)")
  func buyWithTrial() async {
    let (model, _, _, telemetry, _) = makeModel()
    await model.appeared()
    #expect(model.selectedPlan?.trial == TrialOffer(length: 3, unit: .day))
    await model.purchase()
    #expect(model.phase == .welcome && model.trialEndsAt != nil && !model.isPurchasing)
    #expect(
      await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.started", "commerce.trial.started"])
  }

  @Test("Where the account has no trial to take, none is offered and the purchase is a purchase (cases B and C)")
  func buyWithoutTrial() async {
    let (model, _, _, telemetry, _) = makeModel(plans: FixedStoreOffering.fixturePlans(trial: nil))
    await model.appeared()
    #expect(model.selectedPlan?.trial == nil)
    await model.purchase()
    #expect(model.phase == .welcome && model.trialEndsAt == nil)
    #expect(
      await telemetry.events == [
        "commerce.paywall.viewed", "commerce.purchase.started", "commerce.purchase.completed",
      ])
  }

  @Test("Buying the weekly plan, once chosen, is a purchase without a trial")
  func buyWeekly() async {
    let (model, _, _, _, _) = makeModel()
    await model.appeared()
    await model.select("weekly")
    await model.purchase()
    #expect(model.phase == .welcome && model.trialEndsAt == nil)
  }

  @Test("A cancelled purchase leaves the offer as it was, with nothing to tell")
  func cancelled() async {
    let (model, _, _, telemetry, _) = makeModel(outcome: .cancelled)
    await model.appeared()
    await model.purchase()
    #expect(model.phase == .offer && model.notice == nil && !model.isPurchasing && !model.grantsPro)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.started"])
  }

  @Test("A pending purchase is explained, and the offer stays")
  func pending() async {
    let (model, _, _, telemetry, _) = makeModel(outcome: .pending)
    await model.appeared()
    await model.purchase()
    #expect(model.phase == .offer && model.notice == .pending && !model.grantsPro)
    #expect(await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.started"])
  }

  @Test("A purchase waiting for approval is remembered, so a second tap sends no second request (#266)")
  func pendingIsRemembered() async {
    let (model, _, _, telemetry, _) = makeModel(outcome: .pending)
    await model.appeared()
    await model.purchase()
    model.notice = nil
    await model.purchase()
    #expect(model.phase == .offer && !model.grantsPro)
    #expect(
      await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.started"],
      "One request went to the App Store")
    #expect(model.selectedPlanIsWaiting && model.plansWaitingForApproval == ["yearly"])
    await model.select("weekly")
    #expect(!model.selectedPlanIsWaiting, "Another plan is a request of its own")
  }

  @Test("A failed purchase is explained and recorded, and can be tried again")
  func failed() async {
    let (model, _, _, telemetry, _) = makeModel(outcome: .failed)
    await model.appeared()
    await model.purchase()
    #expect(model.phase == .offer && model.notice == .failed && !model.grantsPro)
    model.notice = nil
    await model.purchase()
    #expect(model.notice == .failed)
    #expect(
      await telemetry.events == [
        "commerce.paywall.viewed", "commerce.purchase.started", "commerce.purchase.failed",
        "commerce.purchase.started", "commerce.purchase.failed",
      ])
  }

  @Test("A purchase the App Store took but StoreKit could not verify never says nothing was charged (#228)")
  func unverified() async {
    let (model, _, _, telemetry, _) = makeModel(outcome: .unverified)
    await model.appeared()
    await model.purchase()
    #expect(model.phase == .offer && model.notice == .unverified && !model.isPurchasing && !model.grantsPro)
    #expect(model.notice != .failed, "The failure notice says nothing has been charged")
    #expect(
      await telemetry.events == ["commerce.paywall.viewed", "commerce.purchase.started", "commerce.purchase.failed"])
  }

  @Test("An unverified purchase that StoreKit has verified by the time it is read again leads to the confirmation")
  func unverifiedThenVerified() async {
    let (model, fake, _, telemetry, _) = makeModel(outcome: .unverified)
    await model.appeared()
    fake.set(.subscribed)
    await model.purchase()
    #expect(model.phase == .welcome && model.notice == nil)
    #expect(
      await telemetry.events == [
        "commerce.paywall.viewed", "commerce.purchase.started", "commerce.purchase.completed",
      ])
  }

  @Test("Someone who has Pro is told so, and the offer sells them nothing")
  func alreadyProBuysNothing() async {
    let (model, _, _, telemetry, flags) = makeModel(.subscribed, trigger: .settings)
    await model.appeared()
    #expect(model.alreadyHasPro && model.plans == .loaded(FixedStoreOffering.fixturePlans()))
    await model.purchase()
    #expect(model.phase == .offer)
    #expect(await telemetry.events == ["commerce.paywall.viewed"], "No purchase was started")
    model.close()
    #expect(flags.closed == 1)
  }

  @Test("Someone whose Pro is paused in billing retry is sent to manage the subscription, and sold nothing (#248)")
  func billingRetryBuysNothing() async {
    let (model, _, _, telemetry, _) = makeModel(.inBillingRetry, trigger: .settings)
    await model.appeared()
    #expect(!model.alreadyHasPro, "Billing retry grants no Pro")
    #expect(model.paymentPaused, "The offer must say Pro is paused over a payment and offer Manage subscription")
    await model.select("weekly")
    #expect(model.selectedPlan?.term == .year, "While paused the plans can't be chosen")
    await model.purchase()
    #expect(model.phase == .offer)
    #expect(await telemetry.events == ["commerce.paywall.viewed"], "No purchase was started")
    for entitlement in [Entitlement.none, .subscribed, .inGracePeriod, .expired, .revoked] {
      let (other, _, _, _, _) = makeModel(entitlement)
      await other.appeared()
      #expect(!other.paymentPaused, "\(entitlement) is not paused over a payment")
    }
  }

  @Test("A payment recovered while the paused offer shows is not a purchase, and welcomes nobody (#248)")
  func recoveredPaymentIsNotASale() async {
    let (model, fake, store, telemetry, _) = makeModel(.inBillingRetry, trigger: .settings)
    await model.appeared()
    await purchase(.subscribed, fake, store)
    await model.entitlementChanged()
    let events = await telemetry.events
    #expect(model.phase == .offer, "The welcome screen is for a purchase; it showed after a recovered payment")
    #expect(events == ["commerce.paywall.viewed"], "A recovered payment was recorded: \(events)")
    #expect(model.alreadyHasPro && !model.paymentPaused, "The offer now says the account has Pro")
  }

  @Test("Billing retry that begins while the offer is up, then a recovered payment, is no purchase either (#248)")
  func pausedAfterAppearingIsNotASale() async {
    let (model, fake, store, telemetry, _) = makeModel(.none, trigger: .settings)
    await model.appeared()
    await purchase(.inBillingRetry, fake, store)
    await model.entitlementChanged()
    #expect(model.paymentPaused)
    await purchase(.subscribed, fake, store)
    await model.entitlementChanged()
    let events = await telemetry.events
    #expect(model.phase == .offer, "The welcome screen showed after a payment recovered from billing retry")
    #expect(events == ["commerce.paywall.viewed"], "A recovered payment was recorded: \(events)")
    #expect(model.alreadyHasPro, "The offer now says the account has Pro")
  }

  @Test("Billing retry that ends in expiry, then a purchase while the offer is up, is a purchase")
  func purchaseAfterRetryExpired() async {
    let (model, fake, store, telemetry, _) = makeModel(.inBillingRetry, trigger: .settings)
    await model.appeared()
    await purchase(.expired, fake, store)
    await model.entitlementChanged()
    #expect(!model.paymentPaused)
    await purchase(.subscribed, fake, store)
    await model.entitlementChanged()
    let events = await telemetry.events
    #expect(model.phase == .welcome, "A purchase after billing retry expired was taken for a recovered payment")
    #expect(events.contains("commerce.purchase.completed"), "The purchase was not recorded: \(events)")
  }

  @Test("A purchase from no Pro is still welcomed when billing retry was never seen")
  func purchaseStillWelcomed() async {
    let (model, fake, store, telemetry, _) = makeModel(.none)
    await model.appeared()
    await model.entitlementChanged()
    await purchase(.subscribed, fake, store)
    await model.entitlementChanged()
    #expect(model.phase == .welcome)
    #expect(await telemetry.events.contains("commerce.purchase.completed"))
  }

  @Test("Every trigger has a headline and a line under it", arguments: PaywallTrigger.allCases)
  func triggerCopy(trigger: PaywallTrigger) {
    _ = trigger.headline
    _ = trigger.explanation
    #expect(PaywallTrigger.allCases.count == 4)
  }

  @Test("Every benefit has a title, a line and a symbol", arguments: PaywallBenefit.allCases)
  func benefitCopy(benefit: PaywallBenefit) {
    _ = benefit.title
    _ = benefit.detail
    #expect(!benefit.symbol.isEmpty && benefit.id == benefit.rawValue)
  }

  @Test("The header and the confirmation render, with and without a trial")
  func renders() async {
    for trigger in PaywallTrigger.allCases {
      let header = PaywallHeader(trigger: trigger, benefits: PaywallBenefit.allCases).frame(width: 390)
      #expect(ViewRendering.draws(header))
      #expect(ViewRendering.draws(header.dynamicTypeSize(.accessibility3)))
    }
    let links = PaywallLinks(
      termsOfUse: URL(fileURLWithPath: "/terms"), privacyPolicy: URL(fileURLWithPath: "/privacy"), onRestore: {},
      onRedeem: {})
    #expect(ViewRendering.draws(links.frame(width: 390)))
    #expect(ViewRendering.draws(links.frame(width: 200)))
    for view in [AnyView(AlreadyProNote()), AnyView(PaymentPausedNote()), AnyView(PlansUnavailable {})] {
      #expect(ViewRendering.draws(view.frame(width: 390)))
    }
    let offers = FixedStoreOffering.fixturePlans()
    let saving = YearlySaving(weeklyPrice: offers[1].price, yearlyPrice: offers[0].price)
    for size in [DynamicTypeSize.large, .accessibility3] {
      let picker = PlanPicker(offers: offers, selectedID: offers[0].id, saving: saving) { _ in }
      #expect(ViewRendering.draws(picker.frame(width: 390).dynamicTypeSize(size)))
      let paused = PlanPicker(offers: offers, selectedID: offers[0].id, saving: saving, isPaused: true) { _ in }
      #expect(ViewRendering.draws(paused.frame(width: 390).dynamicTypeSize(size)))
    }
    for offer in offers {
      #expect(ViewRendering.draws(PurchaseTerms(plan: offer).frame(width: 390)))
    }
    for count in 1...PaywallBenefit.allCases.count {
      let tiles = BenefitTiles(benefits: Array(PaywallBenefit.allCases.prefix(count))).frame(width: 390)
      #expect(ViewRendering.draws(tiles))
    }
    for entitlement in [Entitlement.subscribed, .trial(endsAt: now.addingTimeInterval(3 * day))] {
      let (model, fake, store, _, _) = makeModel()
      await model.appeared()
      await purchase(entitlement, fake, store)
      await model.entitlementChanged()
      let welcome = WelcomeProView(model: model).frame(width: 390, height: 844)
      #expect(ViewRendering.draws(welcome))
      #expect(ViewRendering.draws(welcome.dynamicTypeSize(.accessibility3)))
      let flow = PaywallFlowView(model: model, store: FixedStoreAccess(isAvailable: true))
      #expect(ViewRendering.draws(flow.frame(width: 390, height: 844)))
    }
  }
}

@MainActor
@Suite("The subscription section in Settings")
struct SubscriptionSectionTests {
  @Test("The plan reads Free until Pro is known, and names a trial's end, a payment problem and a pause")
  func status() {
    let running = Entitlement.trial(endsAt: now.addingTimeInterval(day))
    let ended = Entitlement.trial(endsAt: now.addingTimeInterval(-day))
    let free: [Entitlement?] = [nil, Entitlement.none, .expired, .revoked, ended]
    for entitlement in free {
      #expect(SubscriptionSection.status(of: entitlement, now: now) == Text("Free", bundle: .module))
    }
    #expect(SubscriptionSection.status(of: .subscribed, now: now) == Text("Pro", bundle: .module))
    #expect(SubscriptionSection.status(of: .inGracePeriod, now: now) == Text("Pro, payment problem", bundle: .module))
    // Billing retry grants no Pro, so the plan does not read as Pro with a payment problem (#248).
    #expect(
      SubscriptionSection.status(of: .inBillingRetry, now: now) == Text("Pro paused, payment problem", bundle: .module),
      "In billing retry Pro is locked; the plan must say it is paused, not \"Pro, payment problem\"")
    #expect(SubscriptionSection.status(of: running, now: now) != Text("Free", bundle: .module))
  }

  @Test("The section renders in a form")
  func renders() {
    let store = EntitlementStore(provider: FakeEntitlements(.subscribed)) { now }
    let form = Form {
      SubscriptionSection(entitlements: store, store: FixedStoreAccess(isAvailable: true)) {}
    }
    #expect(ViewRendering.draws(form.frame(width: 390, height: 600)))
  }
}

@MainActor
@Suite("The annual plan's saving against paying weekly (PAP-049)")
struct YearlySavingTests {
  private func saving(weekly: String, yearly: String) throws -> YearlySaving? {
    YearlySaving(weeklyPrice: try #require(Decimal(string: weekly)), yearlyPrice: try #require(Decimal(string: yearly)))
  }

  // Test values only; real prices are set in App Store Connect and never appear in this repository.
  @Test(
    "It is worked out from the two prices and rounded down, never up",
    arguments: [
      ("2.00", "60.00", 42, "44.00"),  // 42.3%
      ("3.00", "100.00", 35, "56.00"),  // 35.9%
      ("1.00", "26.00", 50, "26.00"),  // exactly 50%
      ("4.10", "120.00", 43, "93.20"),  // 43.7%
    ])
  func storefronts(weekly: String, yearly: String, percent: Int, amount: String) throws {
    let result = try #require(try saving(weekly: weekly, yearly: yearly))
    #expect(result.percent == percent)
    #expect(result.amount == Decimal(string: amount))
  }

  @Test("There is no saving to show when the annual plan saves nothing, or under one percent")
  func noSaving() throws {
    #expect(try saving(weekly: "0.50", yearly: "26.00") == nil)
    #expect(try saving(weekly: "1.00", yearly: "60.00") == nil)
    #expect(try saving(weekly: "1.00", yearly: "51.80") == nil)
  }

  @Test("A missing price shows no saving")
  func missingPrice() throws {
    #expect(try saving(weekly: "0", yearly: "60.00") == nil)
    #expect(try saving(weekly: "2.00", yearly: "0") == nil)
  }
}
