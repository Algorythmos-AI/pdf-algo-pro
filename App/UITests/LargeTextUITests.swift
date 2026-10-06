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
    XCTAssertTrue(app.buttons["onboarding.intent.chatWithPDF"].waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
  }

  func testTheLibraryScanningAndSettingsAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding"])
    XCTAssertTrue(app.buttons["library.home.sample"].waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    openDocumentList(app)
    XCTAssertTrue(app.buttons["library.empty.sample"].waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    app.buttons["library.scan"].tap()
    XCTAssertTrue(app.buttons["scan.images"].waitForExistence(timeout: Self.settleTimeout))
    try audit(app, onSheet: true)
    app.buttons["Cancel"].firstMatch.tap()
    tap(app.buttons["library.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    try audit(app, onSheet: true)
  }

  func testTheReaderAndItsSheetsAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    try audit(app)
    let contents = app.navigationBars["Contents"]
    tapMenuItem(app.buttons["Contents"], in: app.buttons["reader.more"], until: contents)
    try audit(app, onSheet: true)
    contents.buttons["Done"].tap()
    let annotations = app.navigationBars["Annotations"]
    tapMenuItem(app.buttons["reader.annotations"], in: app.buttons["reader.more"], until: annotations)
    try audit(app, onSheet: true)
    annotations.buttons["Done"].tap()
    tapMenuItem(app.buttons["Pages"], in: app.buttons["reader.more"], until: app.buttons["Page 3"])
    try audit(app, onSheet: true)
  }

  func testTheSignatureSheetAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    tapMenuItem(
      app.buttons["Signature"], in: app.buttons["reader.markup"], until: app.textFields["signature.typedName"])
    try audit(app, onSheet: true)
  }

  func testTheAssistantAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Ask a question"].tap()
    let question = app.descendants(matching: .any)["assistant.question"].firstMatch
    XCTAssertTrue(question.waitForExistence(timeout: Self.settleTimeout))
    question.tap()
    question.typeText("What is the total due?\n")
    XCTAssertTrue(app.staticTexts["assistant.answer"].waitForExistence(timeout: Self.answerTimeout))
    try audit(app, onSheet: true)
  }
}
