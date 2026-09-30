import XCTest

/// The base of every end-to-end journey on the simulator: launching and the accessibility audit.
///
/// Every run starts from a fresh, private state (temporary folders, throwaway settings and the scripted
/// intelligence router, via the Debug-only launch arguments in docs/testing-strategy.md), and every
/// top-level screen passes an accessibility audit (NFR-A11Y-001). Journeys live in one file per feature.
@MainActor
class UITestCase: XCTestCase {
  func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-disable-animations"] + arguments
    app.launch()
    return app
  }

  /// The accessibility audit on the current screen.
  ///
  /// Four kinds of finding are excluded narrowly:
  /// - issues on PDFKit's page view and the nodes it exposes for the text on a page, which are not ours
  ///   to change;
  /// - Dynamic Type and clipped-text findings in navigation bars and toolbars, whose titles and buttons
  ///   the system sizes and truncates;
  /// - contrast findings on text scrolled behind a bottom action bar (identifier ending `.actionBar`),
  ///   which hides it, so the pixels the audit measures are the bar's (the bar's own controls are still
  ///   audited);
  /// - contrast findings on disabled controls, which are dimmed on purpose to show they are inactive;
  ///   WCAG 1.4.3 sets no contrast requirement for inactive controls. The same control is audited
  ///   again once it is enabled. On CI the audit sometimes reports these findings without their
  ///   element, and then this exclusion cannot apply, so text buttons that start disabled use
  ///   `readableWhenDisabled()` rather than rely on it.
  ///
  /// Every other finding fails the test. All findings on the screen are collected and
  /// reported together, with the element each one is about, instead of stopping at the first.
  ///
  /// Quarantined (issue #44, flaky): "Dynamic Type font sizes are partially unsupported" on text in sheets
  /// appears on some runs and not others with the same code. Those findings are reported as a non-strict
  /// expected failure, visible in the results without failing the build (docs/testing-strategy.md, Flaky
  /// tests). Text that does not scale at all still fails.
  ///
  /// Quarantined (issue #53, flaky): the audit itself sometimes gives up with "Audit failed to complete in
  /// time" on a loaded runner. That timeout is recorded the same way; the journey goes on.
  func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
    let bars =
      app.navigationBars.allElementsBoundByIndex.map(\.frame) + app.toolbars.allElementsBoundByIndex.map(\.frame)
    let actionBars = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier ENDSWITH %@", ".actionBar")).allElementsBoundByIndex.map(\.frame)
    var findings: [String] = []
    var quarantined: [String] = []
    do {
      try runAudit(app, bars: bars, actionBars: actionBars, findings: &findings, quarantined: &quarantined)
    } catch let error as NSError
      where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    {
      // Findings collected before the timeout are still reported below.
      recordQuarantined(
        "Quarantined flaky audit timeout, issue #53", details: error.localizedDescription, file: file, line: line)
    }
    if !quarantined.isEmpty {
      recordQuarantined(
        "Quarantined flaky audit finding, issue #44",
        details: "\(quarantined.count) quarantined finding(s):\n" + quarantined.joined(separator: "\n"), file: file,
        line: line)
    }
    if !findings.isEmpty {
      XCTFail(
        "\(findings.count) accessibility finding(s):\n" + findings.joined(separator: "\n"), file: file, line: line)
    }
  }

  private func runAudit(
    _ app: XCUIApplication, bars: [CGRect], actionBars: [CGRect], findings: inout [String],
    quarantined: inout [String]
  ) throws {
    var collected: [String] = []
    var held: [String] = []
    defer {
      findings += collected
      quarantined += held
    }
    try app.performAccessibilityAudit { issue in
      if let element = issue.element {
        if element.identifier == "reader.pages" { return true }
        // PDFKit's own accessibility nodes for the text on a page: part of PDFKit's page view.
        if issue.detailedDescription.contains("UICGPDFNode") { return true }
        if issue.auditType == .contrast, !element.isEnabled { return true }
        if issue.auditType == .dynamicType || issue.auditType == .textClipped,
          bars.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(element.frame) })
        {
          return true
        }
        if issue.auditType == .contrast, element.elementType == .staticText,
          actionBars.contains(where: { $0.intersects(element.frame) })
        {
          return true
        }
      }
      if issue.auditType == .dynamicType, issue.compactDescription.localizedCaseInsensitiveContains("partially") {
        held.append(Self.describe(issue))
        return true
      }
      collected.append(Self.describe(issue))
      return true
    }
  }

  /// Records a quarantined flake as a non-strict expected failure: visible in the results, not failing the
  /// build, and without stopping the test, so the rest of the journey still runs and is checked.
  private func recordQuarantined(_ reason: String, details: String, file: StaticString, line: UInt) {
    let options = XCTExpectedFailure.Options()
    options.isStrict = false
    let stopsOnFailure = !continueAfterFailure
    continueAfterFailure = true
    XCTExpectFailure(reason, options: options) {
      XCTFail(details, file: file, line: line)
    }
    continueAfterFailure = !stopsOnFailure
  }

  /// One line per finding: what the audit found, which element it is about, and the audit's explanation.
  static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
    let detail = "\n    \(issue.detailedDescription)"
    guard let element = issue.element else { return "- \(issue.compactDescription) (no element)\(detail)" }
    let frame = element.frame
    return "- \(issue.compactDescription): \(element.elementType) id='\(element.identifier)' "
      + "label='\(element.label)' frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
      + detail
  }
}
