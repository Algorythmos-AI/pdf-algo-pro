import XCTest

/// Settings (FR-AI-009).
@MainActor
final class SettingsUITests: UITestCase {
  func testSettingsCanHideAI() throws {
    let app = launch(["-skip-onboarding"])
    tap(app.buttons["library.sidebar.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    try audit(app, onSheet: true)
  }

  /// About: the app's public pages stay reachable in the app, one row from Settings (PAP-038).
  func testAboutHoldsThePublicPagesAndWhoMakesTheApp() throws {
    let app = launch(["-skip-onboarding"])
    tap(app.buttons["library.sidebar.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    let about = app.descendants(matching: .any)["settings.about"].firstMatch
    for _ in 0..<6 where !about.isHittable { app.swipeUp() }
    tap(about, until: app.descendants(matching: .any)["settings.privacyPolicy"].firstMatch)
    try audit(app, onSheet: true)
    for identifier in ["settings.termsOfUse", "settings.support", "settings.share", "settings.company"] {
      XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.exists, identifier)
    }
  }

  /// The privacy report (FR-SET-005): its counts are text, and are audited like any other.
  func testThePrivacyReportOpensAndPassesTheAudit() throws {
    let app = launch(["-skip-onboarding"])
    tap(app.buttons["library.sidebar.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    let report = app.descendants(matching: .any)["settings.privacyReport"].firstMatch
    for _ in 0..<6 where !report.isHittable { app.swipeUp() }
    tap(report, until: app.descendants(matching: .any)["privacy.sentToCloud"].firstMatch)
    try audit(app, onSheet: true)
  }

  /// The live AI evaluation, in Debug and Staging builds only (bar item B6).
  ///
  /// UI tests use the scripted model, so this checks the screen, not the scores.
  /// "Show first run again", in Debug and Staging builds only: testers see what a new install sees
  /// without deleting the app.
  func testFirstRunCanBeShownAgainInInternalBuilds() throws {
    let app = launch(["-skip-onboarding", "-store", "unavailable"])
    tap(app.buttons["library.sidebar.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    let replay = app.buttons["internal.replayFirstRun"]
    for _ in 0..<8 where !replay.isHittable { app.swipeUp() }
    leave(by: replay, for: app.buttons["onboarding.continue"])
    XCTAssertTrue(app.buttons["onboarding.skip"].exists, "The introduction shows from its first page")
    try audit(app)
    // With no plans to show, leaving it ends on Home, as first run does.
    leave(by: app.buttons["onboarding.skip"], for: app.buttons["library.sidebar.settings"])
  }

  func testTheAIEvaluationRunsInInternalBuilds() throws {
    let app = launch(["-skip-onboarding"])
    tap(app.buttons["library.sidebar.settings"], until: app.descendants(matching: .any)["settings.hideAI"].firstMatch)
    let open = app.buttons["evaluation.open"]
    for _ in 0..<6 where !open.isHittable { app.swipeUp() }
    open.tap()
    let run = app.buttons["evaluation.run"]
    XCTAssertTrue(run.waitForExistence(timeout: Self.settleTimeout))
    try audit(app, onSheet: true)
    run.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["evaluation.result"].firstMatch.waitForExistence(timeout: 60),
      "The evaluation finishes and shows its result")
    try audit(app, onSheet: true)
  }
}
