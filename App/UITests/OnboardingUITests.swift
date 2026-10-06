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
    leave(by: next, for: app.buttons["library.home.sample"])
    XCTAssertTrue(app.buttons["library.home.sample"].exists, "The introduction ends on Home")
  }

  func testSkipLeadsToHomeFromTheFirstPage() throws {
    let app = launch([])
    XCTAssertTrue(headline("scan", in: app).waitForExistence(timeout: Self.settleTimeout))
    leave(by: app.buttons["onboarding.skip"], for: app.buttons["library.home.sample"])
    XCTAssertTrue(app.buttons["library.home.sample"].exists, "Skipping leads to Home (FR-ONB-002)")
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
