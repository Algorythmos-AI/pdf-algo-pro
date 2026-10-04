import XCTest

/// The assistant: grounded answers, refusals and unavailability (FR-AI-002, FR-AI-010, FR-ONB-006).
@MainActor
final class AssistantUITests: UITestCase {
  func testAnswersCiteTheirPageAndTheCitationOpensIt() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Ask a question"].tap()
    let question = app.descendants(matching: .any)["assistant.question"].firstMatch
    XCTAssertTrue(question.waitForExistence(timeout: Self.settleTimeout))
    question.tap()
    question.typeText("What is the total due?\n")
    XCTAssertTrue(
      app.staticTexts["assistant.answer"].waitForExistence(timeout: Self.answerTimeout), "A grounded answer (FR-AI-002)"
    )
    try audit(app, onSheet: true)
    let citation = app.buttons["Source: page 2"]
    XCTAssertTrue(citation.exists, "The answer cites page 2")
    citation.tap()
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: Self.settleTimeout))
    expectation(for: NSPredicate(format: "label CONTAINS %@", "2 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: Self.settleTimeout)
  }

  func testQuestionsTheDocumentCannotAnswerSaySo() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Ask a question"].tap()
    let question = app.descendants(matching: .any)["assistant.question"].firstMatch
    XCTAssertTrue(question.waitForExistence(timeout: Self.settleTimeout))
    question.tap()
    question.typeText("Who won the match?\n")
    XCTAssertTrue(
      app.staticTexts["Not found in this document"].waitForExistence(timeout: Self.answerTimeout),
      "No guessing (FR-AI-010)")
  }

  func testUnavailableIntelligenceIsExplained() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-intelligence-unavailable"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.ask"].tap()
    app.buttons["Summarise"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Document intelligence isn't available"].waitForExistence(timeout: Self.answerTimeout),
      "FR-ONB-006")
    try audit(app, onSheet: true)
  }
}
