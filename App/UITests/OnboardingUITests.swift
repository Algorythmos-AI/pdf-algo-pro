import AccessibilityIDs
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
    XCTAssertTrue(app.buttons[ID.Onboarding.skip].exists, "Skip is on the first page (FR-ONB-002)")
    try audit(app)
    let next = app.buttons[ID.Onboarding.continue]
    tap(next, until: headline("sign", in: app), from: headline("scan", in: app))
    XCTAssertTrue(app.buttons[ID.Onboarding.skip].exists, "And on the second")
    // The scripted intelligence is available, so the third page is about asking a document.
    tap(next, until: headline("ask", in: app), from: headline("sign", in: app))
    XCTAssertTrue(app.buttons[ID.Onboarding.skip].exists, "And on the third")
    try audit(app)
    // The offer follows the last page once; closing it leads to Home (FR-ONB-004).
    leave(by: next, for: app.buttons[ID.Paywall.close])
    leave(by: app.buttons[ID.Paywall.close], for: app.buttons[ID.Library.Home.sample])
    XCTAssertTrue(app.buttons[ID.Library.Home.sample].exists, "The introduction ends on Home")
  }

  /// Every new internal build replays the journey, with no reinstall (PAP-060): the same install is
  /// opened as build 24, as build 24 again, and as build 25.
  func testANewBuildReplaysFirstRunAndTheOfferWithoutReinstalling() throws {
    let install = ["-keep-state", UUID().uuidString]
    var app = launch(install + ["-first-run-build", "24"])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout), "A new install starts here")
    leave(by: app.buttons[ID.Onboarding.skip], for: app.buttons[ID.Paywall.close])
    leave(by: app.buttons[ID.Paywall.close], for: app.buttons[ID.Library.Home.sample])
    app.terminate()

    app = launch(install + ["-first-run-build", "24"])
    XCTAssertTrue(app.buttons[ID.Library.Home.sample].waitForExistence(timeout: Self.settleTimeout))
    XCTAssertFalse(headline("scan", in: app).exists, "The same build opens on Home")
    XCTAssertFalse(app.buttons[ID.Paywall.close].exists)
    app.terminate()

    app = launch(install + ["-first-run-build", "25"])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout), "The next build starts over")
    let next = app.buttons[ID.Onboarding.continue]
    tap(next, until: headline("sign", in: app), from: headline("scan", in: app))
    tap(next, until: headline("ask", in: app), from: headline("sign", in: app))
    leave(by: next, for: app.buttons[ID.Paywall.Plan.yearly])
    XCTAssertTrue(app.buttons[ID.Paywall.purchase].exists, "The offer is there to be tried again")
    leave(by: app.buttons[ID.Paywall.close], for: app.buttons[ID.Library.Home.sample])
  }

  func testAReplayShowsTheOfferToAnAccountThatHasProAndSaysSo() throws {
    let app = launch(["-keep-state", UUID().uuidString, "-first-run-build", "24", "-entitlement", "subscribed"])
    let note = app.descendants(matching: .any)[ID.Paywall.alreadyPro].firstMatch
    leave(by: app.buttons[ID.Onboarding.skip], for: note)
    XCTAssertFalse(app.buttons[ID.Paywall.purchase].exists, "Nothing is sold to an account that has Pro")
    XCTAssertTrue(app.buttons[ID.Paywall.manage].exists)
    leave(by: app.buttons[ID.Paywall.continue], for: app.buttons[ID.Library.Home.sample])
  }

  func testSkipLeadsToHomeFromTheFirstPage() throws {
    let app = launch([])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout))
    leave(by: app.buttons[ID.Onboarding.skip], for: app.buttons[ID.Paywall.close])
    leave(by: app.buttons[ID.Paywall.close], for: app.buttons[ID.Library.Home.sample])
    XCTAssertTrue(app.buttons[ID.Library.Home.sample].exists, "Skip, then Close: Home in two taps (FR-ONB-002)")
    XCTAssertTrue(
      app.buttons[ID.Library.Home.Primary.import].exists || app.buttons[ID.Library.Home.Primary.scan].exists,
      "With nothing chosen, Home shows its default actions (FR-ONB-003)")
  }

  func testWithoutOnDeviceIntelligenceTheThirdPageNeedsNone() throws {
    let app = launch(["-intelligence-unavailable"])
    let next = app.buttons[ID.Onboarding.continue]
    tap(next, until: headline("sign", in: app), from: headline("scan", in: app))
    tap(next, until: headline("organize", in: app), from: headline("sign", in: app))
    XCTAssertFalse(headline("ask", in: app).exists, "No page promises what this device cannot do (FR-ONB-006)")
    try audit(app)
  }
}
