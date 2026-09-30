import XCTest

/// Every screen and sheet at an accessibility text size, each with an audit (NFR-A11Y-001, W3.6).
///
/// The other journeys run at the default size. Here the app starts at AX3 (Accessibility Extra Large),
/// the size the view tests also draw at, so text that clips, overlaps or stops scaling is caught on the
/// real screens, not only in isolated views.
@MainActor
final class LargeTextUITests: UITestCase {
  private func launchLarge(_ arguments: [String]) -> XCUIApplication {
    launch(arguments + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
  }

  func testOnboardingAtALargeTextSize() throws {
    let app = launchLarge([])
    XCTAssertTrue(app.buttons["onboarding.intent.chatWithPDF"].waitForExistence(timeout: 10))
    try audit(app)
  }

  func testTheLibraryScanningAndSettingsAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding"])
    XCTAssertTrue(app.buttons["library.empty.sample"].waitForExistence(timeout: 10))
    try audit(app)
    app.buttons["library.scan"].tap()
    XCTAssertTrue(app.buttons["scan.images"].waitForExistence(timeout: 5))
    try audit(app)
    app.buttons["Cancel"].firstMatch.tap()
    let settings = app.buttons["library.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(app.descendants(matching: .any)["settings.hideAI"].firstMatch.waitForExistence(timeout: 5))
    try audit(app)
  }

  func testTheReaderAndItsSheetsAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    try audit(app)
    app.buttons["reader.more"].tap()
    app.buttons["Contents"].tap()
    let contents = app.navigationBars["Contents"]
    XCTAssertTrue(contents.waitForExistence(timeout: 5))
    try audit(app)
    contents.buttons["Done"].tap()
    app.buttons["reader.more"].tap()
    app.buttons["Pages"].tap()
    XCTAssertTrue(app.buttons["Page 3"].waitForExistence(timeout: 5))
    try audit(app)
  }

  func testTheSignatureSheetAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.markup"].tap()
    app.buttons["Signature"].tap()
    XCTAssertTrue(app.textFields["signature.typedName"].waitForExistence(timeout: 5))
    try audit(app)
  }

  func testTheAssistantAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Ask a question"].tap()
    let question = app.descendants(matching: .any)["assistant.question"].firstMatch
    XCTAssertTrue(question.waitForExistence(timeout: 10))
    question.tap()
    question.typeText("What is the total due?\n")
    XCTAssertTrue(app.staticTexts["assistant.answer"].waitForExistence(timeout: 10))
    try audit(app)
  }
}
