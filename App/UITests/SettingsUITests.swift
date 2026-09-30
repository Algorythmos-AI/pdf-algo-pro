import XCTest

/// Settings (FR-AI-009).
@MainActor
final class SettingsUITests: UITestCase {
  func testSettingsCanHideAI() throws {
    let app = launch(["-skip-onboarding"])
    tap(app.buttons["library.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    try audit(app, onSheet: true)
  }

  /// The live AI evaluation, in Debug and Staging builds only (bar item B6).
  ///
  /// UI tests use the scripted model, so this checks the screen, not the scores.
  func testTheAIEvaluationRunsInInternalBuilds() throws {
    let app = launch(["-skip-onboarding"])
    tap(app.buttons["library.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    let open = app.buttons["evaluation.open"]
    for _ in 0..<6 where !open.isHittable { app.swipeUp() }
    open.tap()
    let run = app.buttons["evaluation.run"]
    XCTAssertTrue(run.waitForExistence(timeout: 5))
    try audit(app, onSheet: true)
    run.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["evaluation.result"].firstMatch.waitForExistence(timeout: 60),
      "The evaluation finishes and shows its result")
    try audit(app, onSheet: true)
  }
}
