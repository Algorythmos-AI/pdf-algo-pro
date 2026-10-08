import XCTest

/// First run: the three-page introduction (FR-ONB-001, FR-ONB-002, FR-ONB-006).
@MainActor
final class OnboardingUITests: UITestCase {
  private func headline(_ page: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["onboarding.page.\(page)"].firstMatch
  }

  func testTheIntroductionShowsThreePagesAndEndsOnHome() throws {
    let app = launch([])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout), "Scanning leads")
    XCTAssertTrue(app.buttons["onboarding.skip"].exists, "Skip is on the first page (FR-ONB-002)")
    try audit(app)
    let next = app.buttons["onboarding.continue"]
    tap(next, until: headline("sign", in: app))
    XCTAssertTrue(app.buttons["onboarding.skip"].exists, "And on the second")
    // The scripted intelligence is available, so the third page is about asking a document.
    tap(next, until: headline("ask", in: app))
    XCTAssertTrue(app.buttons["onboarding.skip"].exists, "And on the third")
    try audit(app)
    // The offer follows the last page once; closing it leads to Home (FR-ONB-004).
    leave(by: next, for: app.buttons["paywall.close"])
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
    XCTAssertTrue(app.buttons["library.home.sample"].exists, "The introduction ends on Home")
  }

  /// Every new internal build replays the journey, with no reinstall (PAP-057): the same install is
  /// opened as build 24, as build 24 again, and as build 25.
  func testANewBuildReplaysFirstRunAndTheOfferWithoutReinstalling() throws {
    let install = ["-keep-state", UUID().uuidString]
    var app = launch(install + ["-first-run-build", "24"])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout), "A new install starts here")
    leave(by: app.buttons["onboarding.skip"], for: app.buttons["paywall.close"])
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
    app.terminate()

    app = launch(install + ["-first-run-build", "24"])
    XCTAssertTrue(app.buttons["library.home.sample"].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(headline("scan", in: app).exists, "The same build opens on Home")
    XCTAssertFalse(app.buttons["paywall.close"].exists)
    app.terminate()

    app = launch(install + ["-first-run-build", "25"])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout), "The next build starts over")
    let next = app.buttons["onboarding.continue"]
    tap(next, until: headline("sign", in: app))
    tap(next, until: headline("ask", in: app))
    leave(by: next, for: app.buttons["paywall.plan.yearly"])
    XCTAssertTrue(app.buttons["paywall.purchase"].exists, "The offer is there to be tried again")
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
  }

  func testAReplayShowsTheOfferToAnAccountThatHasProAndSaysSo() throws {
    let app = launch(["-keep-state", UUID().uuidString, "-first-run-build", "24", "-entitlement", "subscribed"])
    let note = app.descendants(matching: .any)["paywall.alreadyPro"].firstMatch
    leave(by: app.buttons["onboarding.skip"], for: note)
    XCTAssertFalse(app.buttons["paywall.purchase"].exists, "Nothing is sold to an account that has Pro")
    XCTAssertTrue(app.buttons["paywall.manage"].exists)
    leave(by: app.buttons["paywall.continue"], for: app.buttons["library.home.sample"])
  }

  func testSkipLeadsToHomeFromTheFirstPage() throws {
    let app = launch([])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout))
    leave(by: app.buttons["onboarding.skip"], for: app.buttons["paywall.close"])
    leave(by: app.buttons["paywall.close"], for: app.buttons["library.home.sample"])
    XCTAssertTrue(app.buttons["library.home.sample"].exists, "Skip, then Close: Home in two taps (FR-ONB-002)")
    XCTAssertTrue(
      app.buttons["library.home.primary.import"].exists || app.buttons["library.home.primary.scan"].exists,
      "With nothing chosen, Home shows its default actions (FR-ONB-003)")
  }

  func testWithoutOnDeviceIntelligenceTheThirdPageNeedsNone() throws {
    let app = launch(["-intelligence-unavailable"])
    let next = app.buttons["onboarding.continue"]
    tap(next, until: headline("sign", in: app))
    tap(next, until: headline("organize", in: app))
    XCTAssertFalse(headline("ask", in: app).exists, "No page promises what this device cannot do (FR-ONB-006)")
    try audit(app)
  }
}
