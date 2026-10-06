import XCTest

/// The library: Home, the empty state and the sample document (FR-ONB-004).
@MainActor
final class LibraryUITests: UITestCase {
  func testTheSampleOpensInTheReaderWithoutAPaywall() throws {
    let app = launch(["-skip-onboarding"])
    let sample = app.buttons["library.home.sample"]
    XCTAssertTrue(sample.waitForExistence(timeout: Self.settleTimeout), "The app opens on Home")
    try audit(app)
    sample.tap()
    XCTAssertTrue(
      app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15), "The sample opens in the reader")
    XCTAssertTrue(app.buttons["reader.ask"].exists)
    XCTAssertFalse(app.buttons["Subscribe"].exists, "No paywall before value (FR-ONB-004)")
    // The sample was filed in All documents, so that is where Back leads.
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["All documents"].waitForExistence(timeout: Self.settleTimeout))
  }

  /// The document list keeps its own empty state, one step in from Home.
  func testTheEmptyDocumentListOffersTheSampleToo() throws {
    let app = launch(["-skip-onboarding"])
    openDocumentList(app)
    let sample = app.buttons["library.empty.sample"]
    XCTAssertTrue(sample.waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    sample.tap()
    XCTAssertTrue(
      app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15), "The sample opens in the reader")
  }

  /// Home with a document in the library: each action does its own thing and nothing else, and a
  /// recent document opens and leads back to Recents.
  func testHomeOpensARecentDocumentAndEachActionStandsAlone() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let page = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(page.waitForExistence(timeout: 15))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["library.settings"].waitForExistence(timeout: Self.settleTimeout), "Back to the list")
    app.navigationBars.buttons.firstMatch.tap()
    let scan = app.buttons["library.home.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: Self.settleTimeout), "Back from the list shows Home")
    XCTAssertFalse(app.buttons["library.home.sample"].exists, "The sample is offered to an empty library only")
    try audit(app)
    // Several buttons share a row here: a tap on one must not press its neighbours.
    tap(scan, until: app.buttons["scan.images"])
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(scan.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(scan.isHittable, "Only the scanner opened: nothing else covers Home")
    let recent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.home.recent."))
      .firstMatch
    tap(recent, until: page)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(
      app.navigationBars["Recents"].waitForExistence(timeout: Self.settleTimeout),
      "Back from a recent document shows Recents")
  }

  /// The back button on the document list once did nothing: the list bounced straight back.
  func testADocumentOpensAgainAfterGoingBack() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let page = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(page.waitForExistence(timeout: 15))
    for _ in 0..<2 {
      app.navigationBars.buttons.firstMatch.tap()
      let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.document.")).firstMatch
      XCTAssertTrue(row.waitForExistence(timeout: Self.settleTimeout), "Back to the list")
      XCTAssertTrue(page.waitForNonExistence(timeout: Self.settleTimeout))
      row.tap()
      XCTAssertTrue(page.waitForExistence(timeout: Self.settleTimeout), "The same document opens again")
    }
  }

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
