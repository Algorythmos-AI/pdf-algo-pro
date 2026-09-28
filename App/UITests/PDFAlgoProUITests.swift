import XCTest

/// End-to-end journeys on the simulator.
///
/// Every run starts from a fresh, private state (temporary folders, throwaway settings and the scripted
/// intelligence router, via the Debug-only launch arguments in docs/testing-strategy.md), and every
/// top-level screen passes an accessibility audit (NFR-A11Y-001).
@MainActor
final class PDFAlgoProUITests: XCTestCase {
  private func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-disable-animations"] + arguments
    app.launch()
    return app
  }

  /// The accessibility audit on the current screen.
  ///
  /// Two kinds of finding are about views the system draws, not ours, and are excluded narrowly: issues on
  /// PDFKit's page view, and Dynamic Type findings on navigation-bar and toolbar buttons, whose size the
  /// system caps. Every other finding fails the test.
  private func audit(_ app: XCUIApplication) throws {
    let bars =
      app.navigationBars.allElementsBoundByIndex.map(\.frame) + app.toolbars.allElementsBoundByIndex.map(\.frame)
    try app.performAccessibilityAudit { issue in
      guard let element = issue.element else { return false }
      if element.identifier == "reader.pages" { return true }
      if issue.auditType == .dynamicType, bars.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(element.frame) }) {
        return true
      }
      return false
    }
  }

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

  func testTheSampleOpensInTheReaderWithoutAPaywall() throws {
    let app = launch(["-skip-onboarding"])
    let sample = app.buttons["library.empty.sample"]
    XCTAssertTrue(sample.waitForExistence(timeout: 10))
    try audit(app)
    sample.tap()
    XCTAssertTrue(
      app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15), "The sample opens in the reader")
    XCTAssertTrue(app.buttons["reader.ask"].exists)
    XCTAssertFalse(app.buttons["Subscribe"].exists, "No paywall before value (FR-ONB-004)")
  }

  func testAnswersCiteTheirPageAndTheCitationOpensIt() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Ask a question"].tap()
    let question = app.textFields["assistant.question"]
    XCTAssertTrue(question.waitForExistence(timeout: 10))
    question.tap()
    question.typeText("What is the total due?\n")
    XCTAssertTrue(app.staticTexts["assistant.answer"].waitForExistence(timeout: 10), "A grounded answer (FR-AI-002)")
    try audit(app)
    let citation = app.buttons["Source: page 2"]
    XCTAssertTrue(citation.exists, "The answer cites page 2")
    citation.tap()
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 10))
    expectation(for: NSPredicate(format: "label CONTAINS %@", "2 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: 10)
  }

  func testQuestionsTheDocumentCannotAnswerSaySo() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Ask a question"].tap()
    let question = app.textFields["assistant.question"]
    XCTAssertTrue(question.waitForExistence(timeout: 10))
    question.tap()
    question.typeText("Who won the match?\n")
    XCTAssertTrue(
      app.staticTexts["Not found in this document"].waitForExistence(timeout: 10), "No guessing (FR-AI-010)")
  }

  func testUnavailableIntelligenceIsExplained() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-intelligence-unavailable"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Summarise"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Document intelligence isn't available"].waitForExistence(timeout: 10), "FR-ONB-006")
    try audit(app)
  }

  func testScannerOffersImagesWithoutACamera() throws {
    let app = launch(["-skip-onboarding"])
    let scan = app.buttons["library.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: 10))
    scan.tap()
    XCTAssertTrue(app.buttons["scan.images"].waitForExistence(timeout: 5))
    try audit(app)
  }

  func testSettingsCanHideAI() throws {
    let app = launch(["-skip-onboarding"])
    let settings = app.buttons["library.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    XCTAssertTrue(app.descendants(matching: .any)["settings.hideAI"].firstMatch.waitForExistence(timeout: 5))
    try audit(app)
  }
}
