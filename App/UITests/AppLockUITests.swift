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
    try auditInBothAppearances(app)
    unlock.tap()
    XCTAssertTrue(unlock.waitForExistence(timeout: Self.settleTimeout), "A refusal keeps the cover")
    XCTAssertTrue(
      app.descendants(matching: .any)[AccessibilityID.AppLock.cover].firstMatch.exists, "The documents stay covered")
  }

  /// The lock screen's words grow with the text size.
  ///
  /// The lock screen has a window of its own, which redrew after the audit had measured: its title and
  /// Unlock were reported as "partially unsupported" on some runs and not on their retries (issue #344).
  /// The audit no longer judges that finding (issue #182); this compares the lock screen at the default
  /// size with the lock screen at an accessibility size (AX3) instead.
  func testTheLockScreenGrowsWithTheTextSize() throws {
    let arguments = ["-skip-onboarding", "-seed-library", "sample", "-app-lock", "refuses"]
    let regular = launch(arguments)
    let regularSizes = lockScreenHeights(in: regular)
    regular.terminate()
    let large = launch(arguments + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
    let largeSizes = lockScreenHeights(in: large)
    let notes =
      "Heights by default: title \(regularSizes.title) pt, Unlock \(regularSizes.unlock) pt; "
      + "at AX3: title \(largeSizes.title) pt, Unlock \(largeSizes.unlock) pt"
    if largeSizes.title < regularSizes.title * 1.3 || largeSizes.unlock < regularSizes.unlock * 1.3 {
      keepEvidence(large, named: "lock screen size", notes: notes)
      XCTFail("The lock screen's title and Unlock grow with the text size. \(notes)")
    }
    XCTAssertTrue(large.buttons[AccessibilityID.AppLock.unlock].isHittable, "Unlock can be tapped at AX3")
  }

  /// The heights of the lock screen's title and Unlock button, once they have kept still.
  private func lockScreenHeights(in app: XCUIApplication) -> (title: CGFloat, unlock: CGFloat) {
    let unlock = app.buttons[AccessibilityID.AppLock.unlock]
    XCTAssertTrue(unlock.waitForExistence(timeout: Self.settleTimeout), "The cover asks to unlock")
    // The title has no identifier of its own; the tests run in English.
    let title = app.staticTexts["Your documents are locked"]
    XCTAssertTrue(title.waitForExistence(timeout: Self.settleTimeout), "The cover says the documents are locked")
    return (waitUntilSteady(title).height, waitUntilSteady(unlock).height)
  }
}
