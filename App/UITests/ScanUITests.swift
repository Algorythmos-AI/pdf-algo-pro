import XCTest

/// Scanning without a camera (FR-SCAN-001).
@MainActor
final class ScanUITests: UITestCase {
  func testScannerOffersImagesWithoutACamera() throws {
    let app = launch(["-skip-onboarding"])
    let scan = app.buttons["library.scan"]
    XCTAssertTrue(scan.waitForExistence(timeout: 10))
    scan.tap()
    XCTAssertTrue(app.buttons["scan.images"].waitForExistence(timeout: 5))
    try audit(app)
  }
}
