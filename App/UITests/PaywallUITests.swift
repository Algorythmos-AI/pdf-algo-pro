import XCTest

/// The subscription offer: when it shows, that it always closes at once, and when it stays away
/// (FR-ONB-004, FR-STORE-003, FR-STORE-008).
///
/// UI tests never reach the App Store, so the plans themselves are not on screen here: StoreKit's
/// view says the subscription is unavailable. What is checked is everything around them, which is
/// the app's own: the triggers, the Close button and where closing leads. StoreKit shows the app's
/// headline only together with the plans, so which headline a trigger gives is checked in the unit
/// tests. Buying is covered by the StoreKit session tests and the device smoke test.
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
