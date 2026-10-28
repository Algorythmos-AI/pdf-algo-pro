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

  /// At the largest text size the selection bar stacks: Edit text, in words, across the bar, with
  /// More and Done below (#303).
  func testTheSelectionBarAtTheLargestTextSize() throws {
    try checkTheSelectionBarAtTheLargestTextSize(language: "en")
  }

  func testTheSelectionBarAtTheLargestTextSizeInFrench() throws {
    try checkTheSelectionBarAtTheLargestTextSize(language: "fr")
  }

  private func checkTheSelectionBarAtTheLargestTextSize(language: String) throws {
    let french = language == "fr"
    let app = launch([
      "-skip-onboarding", "-seed-library", "sample",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-AppleLanguages", "(\(language))", "-AppleLocale", french ? "fr_FR" : "en_US",
    ])
    XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15))
    let text = app.alerts.firstMatch.textFields.firstMatch
    tapMenuItem(app.buttons[ID.Reader.Markup.textBox], in: app.buttons[ID.Reader.markup], until: text)
    text.tap()
    text.typeText(french ? "Vérifier avec la comptabilité" : "Check with accounts")
    app.alerts.buttons[french ? "Ajouter" : "Add"].tap()
    let bar = app.descendants(matching: .any)[ID.Reader.Selection.actionBar].firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "A new text box is selected")
    let edit = app.buttons[ID.Reader.Selection.edit]
    XCTAssertTrue(edit.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(edit.isHittable, "Edit text is on the bar at the largest text size")
    XCTAssertEqual(edit.label, french ? "Modifier le texte" : "Edit text", "Edit text in its full words")
    XCTAssertTrue(app.buttons[ID.Reader.Selection.more].exists)
    XCTAssertTrue(app.buttons[ID.Reader.Selection.done].exists)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "selection-bar-ax5-\(language)"
    screen.lifetime = .keepAlways
    add(screen)
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
    // The list is under the scan sheet while it slides away, so Settings exists before it can be tapped,
    // and a tap then can be lost (issue #76: on a device, two taps and Settings never opened). Settings
    // is open once its bar's Done shows; Hide AI is checked apart from that, since it stays on the first
    // screen at every text size (PAP-048), and a failure then says which of the two went wrong.
    let settings = app.buttons[ID.Library.settings]
    waitUntilHittable(settings, in: app, "The scan sheet closes and uncovers Settings")
    tap(settings, until: app.buttons[ID.Settings.done])
    let hideAI = app.descendants(matching: .any)[ID.Settings.hideAI].firstMatch
    if !hideAI.waitForExistence(timeout: Self.settleTimeout) {
      keepEvidence(app, named: "hide AI", notes: "Settings is open, without Hide AI on its first screen")
      XCTFail("Hide AI is on the first screen of Settings at a large text size (PAP-048)")
    }
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
    // The sheet's own Cancel, which its bar always shows: the typed name is a row of the form, below
    // the signature pad, and at a large text size on a smaller screen it can be off the screen.
    tapMenuItem(
      app.buttons[ID.Reader.Markup.signature], in: app.buttons[ID.Reader.markup],
      until: app.buttons[ID.Signature.cancel])
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
