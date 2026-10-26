import AccessibilityIDs
import XCTest

/// The manual checklist's items a test can do for the owner on an iPhone (docs/process/device-test-run.md):
/// killing the app in the middle of a save, printing, and Report a problem.
///
/// In Device.xctestplan only (the class name ends in DeviceUITests): the print controller and Mail are a
/// real device's, and the kill has to land on a real save.
@MainActor
final class ManualChecklistDeviceUITests: UITestCase {
  private static let document = "Welcome to PDF Algo Pro"

  /// Item 6, and the release gate's data-safety row: the app is killed at once after a change that saves
  /// the document, ten times at different moments of the save, and the document always opens again,
  /// undamaged.
  func testADocumentKilledInTheMiddleOfASaveAlwaysOpensAgain() throws {
    let state = ["-skip-onboarding", "-keep-state", UUID().uuidString]
    var app = launch(state + ["-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15), "The sample opens")
    // From at once to well after the save, so some kills land before it, some during and some after.
    for (attempt, delay) in [0.0, 0.05, 0.1, 0.2, 0.3, 0.5, 0.8, 1.2, 1.8, 2.5].enumerated() {
      let more = app.buttons[ID.Reader.more]
      tap(more, until: app.buttons[ID.Reader.bookmark])
      app.buttons[ID.Reader.bookmark].tap()
      Thread.sleep(forTimeInterval: delay)
      app.terminate()

      app = launch(state)
      let row = app.staticTexts[Self.document].firstMatch
      XCTAssertTrue(
        row.waitForExistence(timeout: 15),
        "Attempt \(attempt + 1), killed \(delay) s after the change: the document is still in the library")
      tap(row, until: app.staticTexts[ID.Reader.pageIndicator])
      XCTAssertFalse(
        app.buttons[ID.Reader.restorePrevious].waitForExistence(timeout: 2),
        "Attempt \(attempt + 1), killed \(delay) s after the change: the document opens without offering the earlier version, so it isn't damaged"
      )
    }
  }

  /// Item 8: Print shows the print controller with the document's pages.
  func testPrintShowsThePrintController() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15))
    // What only the print panel shows: its printer row or its title, in English or French. Not "Print",
    // which the More menu's own item is called too.
    let panel = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label IN %@ OR identifier IN %@",
        ["Printer", "Imprimante", "No Printer Selected", "Aucune imprimante sélectionnée", "Print Options", "Options"],
        ["Print Options", "Options"])
    ).firstMatch
    // On iOS 27 a menu's items can lose their identifiers (#292): found by title when they do.
    let print = submenuItem(ID.Reader.More.print, titles: ["Print", "Imprimer"], in: app)
    tapMenuItem(print, in: app.buttons[ID.Reader.more], until: panel)
    keepEvidence(app, named: "print-controller", notes: "Item 8: the print controller")
    XCTAssertTrue(panel.exists, "The print controller is on screen")
    let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Annuler"])).firstMatch
    if cancel.exists { cancel.tap() }
  }

  /// Item 9: Report a problem opens Mail with the summary, which names no document.
  ///
  /// Nothing is sent: Mail is closed with the draft unsent. Without an email account the app's own alert
  /// is checked instead.
  func testReportAProblemOpensMailWithoutTheDocuments() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-start", "home"])
    let settings = app.buttons[ID.Library.Sidebar.settings]
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    // The row is far down the list, so it doesn't exist until scrolled to: wait for Settings itself.
    tap(settings, until: app.buttons[ID.Settings.done])
    let report = app.descendants(matching: .any)[ID.Settings.report].firstMatch
    for _ in 0..<12 where !(report.exists && report.isHittable) { app.swipeUp() }
    XCTAssertTrue(report.isHittable, "Report a problem is on screen")
    report.tap()

    let mail = XCUIApplication(bundleIdentifier: "com.apple.mobilemail")
    let noAccount = app.alerts.firstMatch
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline, mail.state != .runningForeground, !noAccount.exists { Thread.sleep(forTimeInterval: 0.5) }
    if noAccount.exists {
      keepEvidence(app, named: "report-without-mail", notes: "Item 9: no email account")
      XCTAssertFalse(noAccount.label.contains(Self.document), "The alert names no document")
      noAccount.buttons.element(boundBy: noAccount.buttons.count - 1).tap()
      return
    }
    XCTAssertEqual(mail.state, .runningForeground, "Report a problem opens Mail")
    let body = mail.textViews.firstMatch
    XCTAssertTrue(body.waitForExistence(timeout: 15), "Mail shows the draft")
    let text = (body.value as? String) ?? ""
    keepEvidence(mail, named: "report-in-mail", notes: "Item 9: the draft in Mail")
    XCTAssertFalse(text.isEmpty, "The draft has the summary")
    XCTAssertFalse(text.contains(Self.document), "The summary names no document: \(text.prefix(400))")
    // Closed, never sent: Mail is quit with the draft, which stays unsent.
    mail.terminate()
  }
}
