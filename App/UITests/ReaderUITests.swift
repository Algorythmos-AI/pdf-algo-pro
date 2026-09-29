import XCTest

/// The reader: navigation within a document (FR-READ-002).
@MainActor
final class ReaderUITests: UITestCase {
  func testContentsAndPagesFindTheirWayAround() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    app.buttons["reader.more"].tap()
    app.buttons["Contents"].tap()
    let contents = app.navigationBars["Contents"]
    XCTAssertTrue(contents.waitForExistence(timeout: 5), "The table of contents opens (FR-READ-002)")
    try audit(app)
    contents.buttons["Done"].tap()
    app.buttons["reader.more"].tap()
    app.buttons["Pages"].tap()
    let third = app.buttons["Page 3"]
    XCTAssertTrue(third.waitForExistence(timeout: 5), "The page grid shows every page (FR-READ-002)")
    try audit(app)
    third.tap()
    expectation(for: NSPredicate(format: "label CONTAINS %@", "3 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: 10)
  }
}
