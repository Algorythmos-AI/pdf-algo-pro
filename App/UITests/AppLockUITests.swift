import AccessibilityIDs
import XCTest

/// App Lock (FR-SET-002), with Face ID's answer scripted (`-app-lock confirms` or `refuses`): the real
/// Face ID prompt is checked on a phone (docs/process/device-smoke-test.md).
@MainActor
final class AppLockUITests: UITestCase {
  /// The lock asks once as the app opens; confirmed, the library is there and the cover is gone.
  func testAConfirmedUnlockOpensTheLibrary() throws {
    let app = launch(["-skip-onboarding", "-app-lock", "confirms"])
    let scan = app.buttons[AccessibilityID.Library.Home.scan]
    XCTAssertTrue(scan.waitForExistence(timeout: Self.settleTimeout), "Home is there")
    let unlock = app.buttons[AccessibilityID.AppLock.unlock]
    XCTAssertTrue(unlock.waitForNonExistence(timeout: Self.settleTimeout), "Confirming takes the cover away")
    XCTAssertTrue(scan.isHittable, "Home can be used once unlocked")
  }

  /// Refused, the documents stay covered, and Unlock asks again.
  func testARefusedUnlockKeepsTheDocumentsCovered() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-app-lock", "refuses"])
    let cover = app.descendants(matching: .any)[AccessibilityID.AppLock.cover].firstMatch
    XCTAssertTrue(cover.waitForExistence(timeout: Self.settleTimeout), "The documents are covered")
    let unlock = app.buttons[AccessibilityID.AppLock.unlock]
    if !unlock.waitForExistence(timeout: Self.settleTimeout) {
      keepEvidence(app, named: "no unlock button", notes: "The cover showed no Unlock button")
      XCTFail("The cover asks to unlock")
    }
    try audit(app)
    unlock.tap()
    XCTAssertTrue(unlock.waitForExistence(timeout: Self.settleTimeout), "A refusal keeps the cover")
    XCTAssertTrue(
      app.descendants(matching: .any)[AccessibilityID.AppLock.cover].firstMatch.exists, "The documents stay covered")
  }
}
