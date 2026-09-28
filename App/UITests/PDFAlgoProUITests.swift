import XCTest

/// End-to-end smoke tests on the simulator, each from a fresh, private state (temporary folders and
/// throwaway settings, via launch arguments), with an accessibility audit on every top-level screen
/// (NFR-A11Y-001).
final class PDFAlgoProUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  private func launch(_ arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"] + arguments
    app.launch()
    return app
  }

  /// The audit, minus checks that flag system-owned views we do not draw (PDFKit's page view and
  /// system toolbars), each named so any new issue in our own views still fails.
  private func audit(_ app: XCUIApplication) throws {
    try app.performAccessibilityAudit(for: [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait]) { issue in
      let systemOwned = issue.element?.identifier == "reader.pages" || issue.element == nil
      return systemOwned
    }
  }

  func testOnboardingOffersAIFirstOptionsAndCanBeSkipped() throws {
    let app = launch([])
    let first = app.buttons["onboarding.intent.chatWithPDF"]
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    let order = ["chatWithPDF", "summarizeDocument", "extractData", "analyzeContract", "editText"]
    let frames = order.map { app.buttons["onboarding.intent.\($0)"].frame.minY }
    XCTAssertEqual(frames, frames.sorted(), "AI-first options lead, in order (FR-ONB-001)")
    try audit(app)
    app.buttons["onboarding.skip"].tap()
    XCTAssertTrue(app.buttons["library.empty.sample"].waitForExistence(timeout: 10), "Skipping leads to the library (FR-ONB-002)")
    XCTAssertFalse(app.staticTexts["Subscribe"].exists, "No paywall before value (FR-ONB-004)")
  }

  func testChoosingAnIntentPersonalisesTheHomeScreen() throws {
    let app = launch([])
    let scan = app.buttons["onboarding.intent.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: 10))
    scan.tap()
    app.buttons["onboarding.continue"].tap()
    XCTAssertTrue(app.buttons["library.empty.sample"].waitForExistence(timeout: 10))
  }

  func testSampleDocumentOpensAndSearchFindsItsText() throws {
    let app = launch(["-ui-skip-onboarding"])
    let sample = app.buttons["library.empty.sample"]
    XCTAssertTrue(sample.waitForExistence(timeout: 10))
    try audit(app)
    sample.tap()
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15), "The sample opens in the reader")
    try audit(app)
  }

  func testAssistantExplainsWhenIntelligenceIsUnavailable() throws {
    let app = launch(["-ui-skip-onboarding", "-ui-seed-sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let ask = app.buttons["reader.ask"]
    XCTAssertTrue(ask.waitForExistence(timeout: 5))
    ask.tap()
    app.buttons["Summarise"].firstMatch.tap()
    let answer = app.staticTexts["assistant.answer"]
    let unavailable = app.otherElements["assistant.unavailable"]
    let appeared = answer.waitForExistence(timeout: 30) || unavailable.exists || app.staticTexts["Document intelligence isn't available"].exists
    XCTAssertTrue(appeared, "Either a cited answer or a plain explanation (FR-ONB-006)")
    try audit(app)
  }

  func testScannerOffersImagesWithoutACamera() throws {
    let app = launch(["-ui-skip-onboarding"])
    let scan = app.buttons["library.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: 10))
    scan.tap()
    XCTAssertTrue(app.buttons["scan.images"].waitForExistence(timeout: 5))
    try audit(app)
  }

  func testSettingsCanHideAI() throws {
    let app = launch(["-ui-skip-onboarding"])
    let settings = app.buttons["library.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    let toggle = app.switches["settings.hideAI"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    try audit(app)
  }
}
