import XCTest

/// Scanning without a camera (FR-SCAN-001).
@MainActor
final class ScanUITests: UITestCase {
  func testScannerOffersImagesWithoutACamera() throws {
    let app = launch(["-skip-onboarding"])
    // From Home, then from the document list's bar: both start the same scanner.
    tap(app.buttons["library.home.scan"], until: app.buttons["scan.images"])
    try audit(app, onSheet: true)
    app.buttons["Cancel"].firstMatch.tap()
    openDocumentList(app)
    tap(app.buttons["library.scan"], until: app.buttons["scan.images"])
  }
}
