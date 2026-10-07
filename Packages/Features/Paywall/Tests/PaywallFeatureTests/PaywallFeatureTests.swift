import Commerce
import CommerceTestSupport
import Core
import CoreTestSupport
import Foundation
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
}

@MainActor
@Suite("The subscription offer")
struct PaywallModelTests {
  private func makeModel(
    _ entitlement: Entitlement = .none, trigger: PaywallTrigger = .onboarding
  ) -> (PaywallModel, FakeEntitlements, EntitlementStore, RecordingTelemetry, Flags) {
    let fake = FakeEntitlements(entitlement)
    let store = EntitlementStore(provider: fake) { now }
    let telemetry = RecordingTelemetry()
    let flags = Flags()
    let model = PaywallModel(
      trigger: trigger, productIDs: ["yearly", "weekly"], benefits: [.unlimitedScans, .unlimitedIntelligence],
      termsOfUse: URL(fileURLWithPath: "/terms"), privacyPolicy: URL(fileURLWithPath: "/privacy"),
      entitlements: store, telemetry: telemetry, now: { now },
      setReminder: { isOn, date in
        flags.reminders.append((isOn, date))
        return isOn && flags.reminderAnswer
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
    #expect(model.restoreFailed == !answers)
    #expect(model.grantsPro, "What the App Store now reports is read either way")
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
      #expect(ImageRenderer(content: header).uiImage != nil)
    }
    for entitlement in [Entitlement.subscribed, .trial(endsAt: now.addingTimeInterval(3 * day))] {
      let (model, fake, store, _, _) = makeModel()
      await model.appeared()
      await purchase(entitlement, fake, store)
      await model.entitlementChanged()
      let welcome = WelcomeProView(model: model).frame(width: 390, height: 844)
      #expect(ImageRenderer(content: welcome).uiImage != nil)
      #expect(ImageRenderer(content: welcome.dynamicTypeSize(.accessibility3)).uiImage != nil)
      #expect(ImageRenderer(content: PaywallFlowView(model: model).frame(width: 390, height: 844)).uiImage != nil)
    }
  }
}

@MainActor
@Suite("The subscription section in Settings")
struct SubscriptionSectionTests {
  @Test("The plan reads Free until Pro is known, and names a trial's end and a payment problem")
  func status() {
    let running = Entitlement.trial(endsAt: now.addingTimeInterval(day))
    let ended = Entitlement.trial(endsAt: now.addingTimeInterval(-day))
    let free: [Entitlement?] = [nil, Entitlement.none, .expired, .revoked, ended]
    for entitlement in free {
      #expect(SubscriptionSection.status(of: entitlement, now: now) == Text("Free", bundle: .module))
    }
    #expect(SubscriptionSection.status(of: .subscribed, now: now) == Text("Pro", bundle: .module))
    for entitlement in [Entitlement.inGracePeriod, .inBillingRetry] {
      #expect(SubscriptionSection.status(of: entitlement, now: now) == Text("Pro, payment problem", bundle: .module))
    }
    #expect(SubscriptionSection.status(of: running, now: now) != Text("Free", bundle: .module))
  }

  @Test("The section renders in a form")
  func renders() {
    let store = EntitlementStore(provider: FakeEntitlements(.subscribed)) { now }
    let form = Form {
      SubscriptionSection(entitlements: store, store: FixedStoreAccess(isAvailable: true)) {}
    }
    #expect(ImageRenderer(content: form.frame(width: 390, height: 600)).uiImage != nil)
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
