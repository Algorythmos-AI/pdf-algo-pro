import XCTest

/// The library: the empty state and the sample document (FR-ONB-004).
@MainActor
final class LibraryUITests: UITestCase {
  func testTheSampleOpensInTheReaderWithoutAPaywall() throws {
    let app = launch(["-skip-onboarding"])
    let sample = app.buttons["library.empty.sample"]
    XCTAssertTrue(sample.waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    sample.tap()
    XCTAssertTrue(
      app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15), "The sample opens in the reader")
    XCTAssertTrue(app.buttons["reader.ask"].exists)
    XCTAssertFalse(app.buttons["Subscribe"].exists, "No paywall before value (FR-ONB-004)")
  }

  /// The back button on the document list once did nothing: the list bounced straight back.
  func testBackFromTheDocumentListShowsTheSectionsAndEachOpens() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let back = app.navigationBars.buttons.firstMatch
    back.tap()
    XCTAssertTrue(app.buttons["library.settings"].waitForExistence(timeout: Self.settleTimeout), "Back to the list")
    app.navigationBars.buttons.firstMatch.tap()
    let deleted = app.descendants(matching: .any)["library.section.deleted"].firstMatch
    XCTAssertTrue(deleted.waitForExistence(timeout: Self.settleTimeout), "Back from the list shows the sections")
    try audit(app)
    deleted.tap()
    XCTAssertTrue(app.navigationBars["Recently deleted"].waitForExistence(timeout: Self.settleTimeout))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(deleted.waitForExistence(timeout: Self.settleTimeout), "And back again")
  }
}
