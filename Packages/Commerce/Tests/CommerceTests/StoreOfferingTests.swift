import Foundation
import StoreKit
import Synchronization
import Testing

@testable import Commerce

/// The plans on sale: what counts as a week or a year, when a free trial may be shown, and the
/// fixture store the UI tests buy from (ADR-0027).
@Suite("The plans on sale")
struct StoreOfferingTests {
  private let threeDaysFree = IntroductoryTerms(isFree: true, length: 3, unit: .day)

  @Test("A week is a week whether the App Store calls it one week or seven days, and a year likewise")
  func terms() {
    #expect(PlanTerm(unit: .week, value: 1) == .week)
    #expect(PlanTerm(unit: .day, value: 7) == .week, "As App Store Connect's one-week plan arrives")
    #expect(PlanTerm(unit: .year, value: 1) == .year)
    #expect(PlanTerm(unit: .month, value: 12) == .year)
    #expect(PlanTerm(unit: .month, value: 1) == nil && PlanTerm(unit: .day, value: 3) == nil)
    #expect(PlanTerm(unit: .week, value: 2) == nil)
  }

  @Test("Case A: an offer is configured and the account is eligible, so the trial is offered at its length")
  func trialOfferedWhenEligible() {
    #expect(TrialOffer(introductory: threeDaysFree, isEligible: true) == TrialOffer(length: 3, unit: .day))
    let week = IntroductoryTerms(isFree: true, length: 1, unit: .week)
    #expect(TrialOffer(introductory: week, isEligible: true) == TrialOffer(length: 1, unit: .week))
  }

  @Test("Case B: an offer is configured but the account is not eligible, so no trial is offered")
  func noTrialWhenIneligible() {
    #expect(TrialOffer(introductory: threeDaysFree, isEligible: false) == nil)
  }

  @Test("Case C: no introductory offer is configured, so no trial is offered, eligible or not")
  func noTrialWithoutAnOffer() {
    #expect(TrialOffer(introductory: nil, isEligible: true) == nil)
    #expect(TrialOffer(introductory: nil, isEligible: false) == nil)
  }

  @Test("A paid introductory price, or an offer of no length, is not a free trial")
  func paidOffersAreNotTrials() {
    let paid = IntroductoryTerms(isFree: false, length: 1, unit: .month)
    #expect(TrialOffer(introductory: paid, isEligible: true) == nil)
    let empty = IntroductoryTerms(isFree: true, length: 0, unit: .day)
    #expect(TrialOffer(introductory: empty, isEligible: true) == nil)
  }

  @Test("A plan writes its price, and any other amount, in its own currency")
  func formatting() {
    let plan = FixedStoreOffering.fixturePlans()[0]
    #expect(plan.displayPrice == "$20.00")
    #expect(plan.formatted(0) == "$0.00", "What is due today during a trial")
  }

  @Test("The fixture store gives its plans, or none, and ends every purchase as it was told to")
  func fixtureStore() async {
    let plans = FixedStoreOffering.fixturePlans(yearlyID: "y", weeklyID: "w")
    #expect(plans.map(\.id) == ["y", "w"] && plans.map(\.term) == [.year, .week])
    #expect(plans[0].trial != nil && plans[1].trial == nil, "The trial is on the annual plan")
    #expect(FixedStoreOffering.fixturePlans(trial: nil).allSatisfy { $0.trial == nil })

    let bought = Mutex<[String]>([])
    let store = FixedStoreOffering(plans: plans) { plan in bought.withLock { $0.append(plan.id) } }
    #expect(await store.plans(for: ["y", "w"]) == plans)
    #expect(await store.purchase("w") == .purchased)
    #expect(await store.purchase("unknown") == .purchased)
    #expect(bought.withLock { $0 } == ["w"], "Only a plan on sale is granted")

    for outcome in [PurchaseOutcome.pending, .cancelled, .failed] {
      let refusing = FixedStoreOffering(plans: plans, outcome: outcome) { plan in
        bought.withLock { $0.append(plan.id) }
      }
      #expect(await refusing.purchase("y") == outcome)
    }
    #expect(bought.withLock { $0 } == ["w"], "Nothing is granted unless the purchase succeeded")
    #expect(await FixedStoreOffering(plans: nil).plans(for: ["y"]) == nil)
  }

  @Test("A scripted entitlement reports what it was last told, to whoever is following")
  func scriptedEntitlements() async {
    let scripted = ScriptedEntitlements(.none)
    #expect(await scripted.currentEntitlement() == .none)
    var updates = scripted.entitlementUpdates().makeAsyncIterator()
    #expect(await updates.next() == Entitlement.none)
    scripted.set(.subscribed)
    #expect(await updates.next() == .subscribed)
    #expect(await scripted.currentEntitlement() == .subscribed)
  }
}
