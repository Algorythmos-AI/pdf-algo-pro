import XCTest

/// The subscription offer: when it shows, that it always closes at once, and when it stays away
/// (FR-ONB-004, FR-STORE-003, FR-STORE-008).
///
/// UI tests never reach the App Store: they buy from a fixture store with two made-up plans, and a
/// purchase there ends as the test asked (`-purchase`, `-trial`). What is checked is the app's own
/// journey: the triggers, Close, the plans and their selected state, the trial wording and when it
/// must be absent, and where each way a purchase can end leads. The App Store's own sheet, real
/// prices and real eligibility are checked on a device (the device smoke test).
@MainActor
final class PaywallUITests: UITestCase {
  /// Leaves first run by Skip.
  private func skipFirstRun(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: Self.settleTimeout))
    app.buttons["onboarding.skip"].tap()
  }

  func testTheOfferAfterFirstRunHasCloseAtOnceAndOneTapLeadsHome() throws {
    let app = launch([])
    skipFirstRun(app)
    let close = app.buttons["paywall.close"]
    XCTAssertTrue(close.waitForExistence(timeout: Self.settleTimeout), "The offer follows first run")
    XCTAssertTrue(close.isHittable, "Close can be tapped as soon as the offer is up")
    leave(by: close, for: app.buttons["library.home.sample"])
    XCTAssertFalse(close.exists, "One tap closes the offer")
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier].firstMatch
  }

  func testTheWholeJourneyFromFirstRunThroughAPurchaseToHome() throws {
    let app = launch([])
    let next = app.buttons["onboarding.continue"]
    tap(next, until: element("onboarding.page.sign", in: app))
    tap(next, until: element("onboarding.page.ask", in: app))
    let yearly = app.buttons["paywall.plan.yearly"]
    let weekly = app.buttons["paywall.plan.weekly"]
    leave(by: next, for: yearly)
    XCTAssertTrue(app.buttons["paywall.close"].isHittable, "Close is there from the first frame")
    XCTAssertTrue(yearly.isSelected && !weekly.isSelected, "The annual plan is the one recommended")
    XCTAssertTrue(element("paywall.terms.trial", in: app).exists, "An eligible account is shown the trial")
    try audit(app, onSheet: true)

    weekly.tap()
    XCTAssertTrue(element("paywall.terms", in: app).waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(weekly.isSelected && !yearly.isSelected)
    XCTAssertFalse(element("paywall.terms.trial", in: app).exists, "The weekly plan has no trial")
    yearly.tap()
    XCTAssertTrue(element("paywall.terms.trial", in: app).waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(yearly.isSelected && !weekly.isSelected)

    let welcome = element("paywall.welcome", in: app)
    leave(by: app.buttons["paywall.purchase"], for: welcome)
    XCTAssertTrue(element("paywall.welcome.trialEnd", in: app).exists, "The trial's end is said at once")
    try audit(app, onSheet: true)
    leave(by: app.buttons["paywall.start"], for: app.buttons["library.home.sample"])
    let plan = element("settings.subscription.plan", in: app)
    tap(app.buttons["library.sidebar.settings"], until: plan)
    XCTAssertTrue(plan.label.contains("Pro"), "Settings names the plan the purchase gave: \(plan.label)")
  }

  func testAnAccountWithNoTrialToTakeIsShownNone() throws {
    let app = launch(["-skip-onboarding", "-trial", "ineligible"])
    tap(app.buttons["library.sidebar.settings"], until: element("settings.subscription.plans", in: app))
    tap(element("settings.subscription.plans", in: app), until: app.buttons["paywall.plan.yearly"])
    XCTAssertTrue(element("paywall.terms", in: app).waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(element("paywall.terms.trial", in: app).exists, "No trial is promised that would not be given")
    leave(by: app.buttons["paywall.purchase"], for: element("paywall.welcome", in: app))
    XCTAssertFalse(element("paywall.welcome.trialEnd", in: app).exists, "A purchase without a trial has no trial end")
  }

  func testACancelledPurchaseLeavesTheOfferAsItWas() throws {
    let app = launch(["-purchase", "cancelled"])
    skipFirstRun(app)
    let buy = app.buttons["paywall.purchase"]
    XCTAssertTrue(buy.waitForExistence(timeout: Self.settleTimeout))
    buy.tap()
    XCTAssertTrue(buy.waitForExistence(timeout: Self.settleTimeout) && buy.isEnabled, "The offer is still there")
    XCTAssertFalse(element("paywall.welcome", in: app).exists)
    XCTAssertEqual(app.alerts.count, 0, "Changing one's mind needs no explaining")
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
  }

  func testAFailedPurchaseSaysSoAndCanBeTriedAgain() throws {
    let app = launch(["-purchase", "failed"])
    skipFirstRun(app)
    let alert = app.alerts["The purchase didn’t go through"]
    tap(app.buttons["paywall.purchase"], until: alert)
    alert.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["paywall.purchase"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(app.buttons["paywall.purchase"].isEnabled, "The button is ready for another try")
  }

  func testAPendingPurchaseIsExplained() throws {
    let app = launch(["-purchase", "pending"])
    skipFirstRun(app)
    let alert = app.alerts["Waiting for approval"]
    tap(app.buttons["paywall.purchase"], until: alert)
    alert.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(element("paywall.welcome", in: app).exists, "Nothing is unlocked until it is approved")
  }

  func testWithoutPlansTheOfferSaysSoAndOffersToAskAgain() throws {
    let app = launch(["-skip-onboarding", "-store", "unavailable"])
    tap(app.buttons["library.sidebar.settings"], until: element("settings.subscription.plans", in: app))
    tap(element("settings.subscription.plans", in: app), until: app.buttons["paywall.retry"])
    XCTAssertFalse(app.buttons["paywall.purchase"].exists, "There is nothing to buy")
    XCTAssertTrue(app.buttons["paywall.close"].isHittable)
    try audit(app, onSheet: true)
    app.buttons["paywall.retry"].tap()
    XCTAssertTrue(app.buttons["paywall.retry"].waitForExistence(timeout: Self.settleTimeout), "Still none, still asked")
  }

  func testSomeoneWithProIsToldSoAndSoldNothing() throws {
    let app = launch(["-skip-onboarding", "-entitlement", "subscribed"])
    tap(app.buttons["library.sidebar.settings"], until: element("settings.subscription.plans", in: app))
    tap(element("settings.subscription.plans", in: app), until: element("paywall.alreadyPro", in: app))
    XCTAssertFalse(app.buttons["paywall.purchase"].exists, "Nothing is sold to someone who has Pro")
    XCTAssertTrue(app.buttons["paywall.manage"].exists)
    try audit(app, onSheet: true)
    leave(by: app.buttons["paywall.continue"], for: app.buttons["library.home.sample"])
  }

  func testWithoutTheStoreFirstRunEndsOnHome() throws {
    let app = launch(["-store", "unavailable"])
    skipFirstRun(app)
    XCTAssertTrue(app.buttons["library.home.sample"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(app.buttons["paywall.close"].exists, "No offer without plans to show")
  }

  func testSomeoneWithProSeesNoOfferAndSettingsNamesThePlan() throws {
    let app = launch(["-entitlement", "subscribed"])
    skipFirstRun(app)
    XCTAssertTrue(app.buttons["library.home.sample"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(app.buttons["paywall.close"].exists, "No offer for someone who has Pro")
    let plan = app.descendants(matching: .any)["settings.subscription.plan"].firstMatch
    tap(app.buttons["library.sidebar.settings"], until: plan)
    XCTAssertTrue(plan.label.contains("Pro"), "Settings says the plan is Pro: \(plan.label)")
    try audit(app, onSheet: true)
  }

  func testNoOfferAtALaterLaunch() throws {
    let app = launch(["-skip-onboarding"])
    XCTAssertTrue(app.buttons["library.home.sample"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(app.buttons["paywall.close"].exists, "The offer never shows at launch")
  }

  func testWhenTheDaysScansAreUsedScanOpensTheOfferBeforeTheCamera() throws {
    let app = launch(["-skip-onboarding", "-allowance", "exhausted"])
    tap(app.buttons["library.home.scan"], until: app.buttons["paywall.close"])
    XCTAssertFalse(app.buttons["scan.photos"].exists, "The scanner did not open")
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
  }

  func testWithProTheScannerOpensWhateverWasUsed() throws {
    let app = launch(["-skip-onboarding", "-allowance", "exhausted", "-entitlement", "subscribed"])
    tap(app.buttons["library.home.scan"], until: app.buttons["scan.photos"])
    XCTAssertFalse(app.buttons["paywall.close"].exists, "Pro has no daily limit")
  }

  func testSettingsOpensThePlansAndCloseLeavesThem() throws {
    let app = launch(["-skip-onboarding"])
    let plans = app.descendants(matching: .any)["settings.subscription.plans"].firstMatch
    tap(app.buttons["library.sidebar.settings"], until: plans)
    let plan = app.descendants(matching: .any)["settings.subscription.plan"].firstMatch
    XCTAssertTrue(plan.label.contains("Free"), "Nobody is entitled in a UI test: \(plan.label)")
    for identifier in ["manage", "restore", "redeem"] {
      XCTAssertTrue(
        app.descendants(matching: .any)["settings.subscription.\(identifier)"].firstMatch.exists, identifier)
    }
    tap(plans, until: app.buttons["paywall.close"])
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
  }

  func testLockedTextEditingLeadsToThePlans() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "locked"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: Self.settleTimeout))
    let explanation = app.alerts["Editing text needs Pro"]
    tap(app.buttons["reader.edit"], until: explanation)
    explanation.buttons["See plans"].firstMatch.tap()
    XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(app.buttons["paywall.close"].isHittable)
  }
}
