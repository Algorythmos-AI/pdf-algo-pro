import AccessibilityIDs
import XCTest

/// Scanning without a camera (FR-SCAN-001).
@MainActor
final class ScanUITests: UITestCase {
  func testScannerOffersImagesWithoutACamera() throws {
    let app = launch(["-skip-onboarding"])
    // From Home, then from the document list's bar: both start the same scanner.
    tap(app.buttons[ID.Library.Home.scan], until: app.buttons[ID.Scan.images])
    try audit(app, onSheet: true)
    app.buttons["Cancel"].firstMatch.tap()
    openDocumentList(app)
    tap(app.buttons[ID.Library.scan], until: app.buttons[ID.Scan.images])
  }
}
