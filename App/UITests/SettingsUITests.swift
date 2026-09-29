import XCTest

/// Settings (FR-AI-009).
@MainActor
final class SettingsUITests: UITestCase {
  func testSettingsCanHideAI() throws {
    let app = launch(["-skip-onboarding"])
    let settings = app.buttons["library.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    XCTAssertTrue(app.descendants(matching: .any)["settings.hideAI"].firstMatch.waitForExistence(timeout: 5))
    try audit(app)
  }
}
