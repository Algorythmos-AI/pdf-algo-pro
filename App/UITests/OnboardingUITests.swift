import XCTest

/// Onboarding: the first-run intent question (FR-ONB-001 to FR-ONB-003).
@MainActor
final class OnboardingUITests: UITestCase {
  func testOnboardingOffersAIFirstOptionsAndCanBeSkipped() throws {
    let app = launch([])
    let first = app.buttons["onboarding.intent.chatWithPDF"]
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    let order = ["chatWithPDF", "summarizeDocument", "extractData", "analyzeContract"]
    let positions = order.map { app.buttons["onboarding.intent.\($0)"].frame.minY }
    XCTAssertEqual(positions, positions.sorted(), "AI-first options lead, in order (FR-ONB-001)")
    try audit(app)
    app.buttons["onboarding.skip"].tap()
    XCTAssertTrue(
      app.buttons["library.empty.sample"].waitForExistence(timeout: 10), "Skipping leads to the library (FR-ONB-002)")
  }

  func testChoosingAnIntentPersonalisesTheHomeScreen() throws {
    let app = launch([])
    let scan = app.buttons["onboarding.intent.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: 10))
    scan.tap()
    app.buttons["onboarding.continue"].tap()
    XCTAssertTrue(
      app.buttons["library.empty.primary.scan"].waitForExistence(timeout: 10),
      "The chosen intent leads the home screen (FR-ONB-003)")
  }
}
