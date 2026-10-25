import AccessibilityIDs
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
    let headline = app.descendants(matching: .any)[ID.Onboarding.page("scan")].firstMatch
    XCTAssertTrue(headline.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(app.buttons[ID.Onboarding.continue].isHittable, "Continue stays on screen at a large text size")
    try audit(app)
  }

  func testTheLibraryScanningAndSettingsAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding"])
    XCTAssertTrue(app.buttons[ID.Library.Home.sample].waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    openDocumentList(app)
    XCTAssertTrue(app.buttons[ID.Library.Empty.sample].waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    app.buttons[ID.Library.scan].tap()
    XCTAssertTrue(app.buttons[ID.Scan.images].waitForExistence(timeout: Self.settleTimeout))
    try audit(app, onSheet: true)
    app.buttons["Cancel"].firstMatch.tap()
    tap(app.buttons[ID.Library.settings], until: app.descendants(matching: .any)[ID.Settings.hideAI].firstMatch)
    try audit(app, onSheet: true)
  }

  func testTheReaderAndItsSheetsAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15))
    try audit(app)
    let contents = app.navigationBars["Contents"]
    tapMenuItem(app.buttons[ID.Reader.More.contents], in: app.buttons[ID.Reader.more], until: contents)
    try audit(app, onSheet: true)
    contents.buttons["Done"].tap()
    let annotations = app.navigationBars["Annotations"]
    tapMenuItem(app.buttons[ID.Reader.annotations], in: app.buttons[ID.Reader.more], until: annotations)
    try audit(app, onSheet: true)
    annotations.buttons["Done"].tap()
    tapMenuItem(
      app.buttons[ID.Reader.More.pages], in: app.buttons[ID.Reader.more], until: app.buttons[ID.Pages.page(3)])
    try audit(app, onSheet: true)
  }

  func testTheSignatureSheetAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15))
    tapMenuItem(
      app.buttons[ID.Reader.Markup.signature], in: app.buttons[ID.Reader.markup],
      until: app.textFields[ID.Signature.typedName])
    try audit(app, onSheet: true)
  }

  func testTheAssistantAtALargeTextSize() throws {
    let app = launchLarge(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15))
    app.buttons[ID.Reader.ask].tap()
    app.buttons[ID.Reader.Ask.question].tap()
    let question = app.descendants(matching: .any)[ID.Assistant.question].firstMatch
    XCTAssertTrue(question.waitForExistence(timeout: Self.settleTimeout))
    question.tap()
    question.typeText("What is the total due?\n")
    XCTAssertTrue(app.staticTexts[ID.Assistant.answer].waitForExistence(timeout: Self.answerTimeout))
    try audit(app, onSheet: true)
  }
}
