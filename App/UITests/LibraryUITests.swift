import AccessibilityIDs
import XCTest

/// The library: Home, the empty state and the sample document (FR-ONB-004).
@MainActor
final class LibraryUITests: UITestCase {
  func testTheSampleOpensInTheReaderWithoutAPaywall() throws {
    let app = launch(["-skip-onboarding"])
    let sample = app.buttons[ID.Library.Home.sample]
    XCTAssertTrue(sample.waitForExistence(timeout: Self.settleTimeout), "The app opens on Home")
    try audit(app)
    openSample(by: sample, in: app)
    XCTAssertTrue(app.buttons[ID.Reader.ask].exists)
    XCTAssertFalse(app.buttons["Subscribe"].exists, "No paywall before value (FR-ONB-004)")
    // The sample was filed in All documents, so that is where Back leads.
    goBack(in: app, leaving: app.staticTexts[ID.Reader.pageIndicator], to: app.navigationBars["All documents"])
  }

  /// Taps the sample and waits for the reader; taps again only if the first tap was lost, with the
  /// sample still on screen and no reader (CI, 2026-10-09: the reader never opened after one tap that
  /// followed an accessibility audit).
  private func openSample(by sample: XCUIElement, in app: XCUIApplication, line: UInt = #line) {
    let reader = app.staticTexts[ID.Reader.pageIndicator]
    sample.tap()
    if !reader.waitForExistence(timeout: 15), sample.exists, sample.isHittable {
      sample.tap()
    }
    XCTAssertTrue(reader.waitForExistence(timeout: 15), "The sample opens in the reader", line: line)
  }

  /// The document list keeps its own empty state, one step in from Home.
  func testTheEmptyDocumentListOffersTheSampleToo() throws {
    let app = launch(["-skip-onboarding"])
    openDocumentList(app)
    let sample = app.buttons[ID.Library.Empty.sample]
    XCTAssertTrue(sample.waitForExistence(timeout: Self.settleTimeout))
    try audit(app)
    openSample(by: sample, in: app)
  }

  /// Home with a document in the library: each action does its own thing and nothing else, and a
  /// recent document opens and leads back to Recents.
  func testHomeOpensARecentDocumentAndEachActionStandsAlone() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let page = app.staticTexts[ID.Reader.pageIndicator]
    XCTAssertTrue(page.waitForExistence(timeout: 15))
    let settings = app.buttons[ID.Library.settings]
    goBack(in: app, leaving: page, to: settings)
    let scan = app.buttons[ID.Library.Home.scan]
    goBack(in: app, leaving: settings, to: scan)
    XCTAssertFalse(app.buttons[ID.Library.Home.sample].exists, "The sample is offered to an empty library only")
    try audit(app)
    // Several buttons share a row here: a tap on one must not press its neighbours.
    tap(scan, until: app.buttons[ID.Scan.images])
    app.buttons["Cancel"].firstMatch.tap()
    // Home is under the sheet while it slides away, so the tile exists before it can be tapped: wait
    // for the sheet to go, as long as any screen is given to settle. A second sheet would stay.
    let uncovered = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: scan)
    XCTAssertEqual(
      XCTWaiter().wait(for: [uncovered], timeout: Self.settleTimeout), .completed,
      "Only the scanner opened: nothing else covers Home")
    let recent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.home.recent."))
      .firstMatch
    tap(recent, until: page)
    goBack(in: app, leaving: page, to: app.navigationBars["Recents"])
  }

  /// The back button on the document list once did nothing: the list bounced straight back.
  func testADocumentOpensAgainAfterGoingBack() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let page = app.staticTexts[ID.Reader.pageIndicator]
    XCTAssertTrue(page.waitForExistence(timeout: 15))
    let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.document.")).firstMatch
    for _ in 0..<2 {
      goBack(in: app, leaving: page, to: row)
      XCTAssertTrue(page.waitForNonExistence(timeout: Self.settleTimeout))
      // The list reloads as the reader goes; a row tapped while the rows are being replaced can be lost.
      waitUntilSteady(row)
      tap(row, until: page)
    }
  }

  func testBackFromTheDocumentListShowsTheSectionsAndEachOpens() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let page = app.staticTexts[ID.Reader.pageIndicator]
    XCTAssertTrue(page.waitForExistence(timeout: 15))
    // Each back tap is made again only while the screen being left is still showing (issue #211: the
    // tap from the list to Home was lost on a slow runner).
    let settings = app.buttons[ID.Library.settings]
    goBack(in: app, leaving: page, to: settings)
    let deleted = app.descendants(matching: .any)[ID.Library.section("deleted")].firstMatch
    goBack(in: app, leaving: settings, to: deleted)
    try audit(app)
    let recentlyDeleted = app.navigationBars["Recently deleted"]
    tap(deleted, until: recentlyDeleted)
    goBack(in: app, leaving: recentlyDeleted, to: deleted)
  }
}
