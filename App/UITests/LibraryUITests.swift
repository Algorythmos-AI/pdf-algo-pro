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
}
