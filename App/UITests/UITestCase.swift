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
  /// Three kinds of finding are excluded narrowly, because they are not about anything a person sees:
  /// issues on PDFKit's page view; Dynamic Type findings on navigation-bar and toolbar buttons, whose size
  /// the system caps; and contrast findings on text scrolled behind a bottom action bar (identifier ending
  /// `.actionBar`), which hides it, so the pixels the audit measures are the bar's. The bar's own controls
  /// are still audited. Every other finding fails the test. All findings on the screen are collected and
  /// reported together, with the element each one is about, instead of stopping at the first.
  ///
  /// Quarantined (issue #44, flaky): "Dynamic Type font sizes are partially unsupported" on text in sheets
  /// appears on some runs and not others with the same code. Those findings are reported as a non-strict
  /// expected failure, visible in the results without failing the build (docs/testing-strategy.md, Flaky
  /// tests). Text that does not scale at all still fails.
  func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
    let bars =
      app.navigationBars.allElementsBoundByIndex.map(\.frame) + app.toolbars.allElementsBoundByIndex.map(\.frame)
    let actionBars = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier ENDSWITH %@", ".actionBar")).allElementsBoundByIndex.map(\.frame)
    var findings: [String] = []
    var quarantined: [String] = []
    try app.performAccessibilityAudit { issue in
      if let element = issue.element {
        if element.identifier == "reader.pages" { return true }
        if issue.auditType == .dynamicType,
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
        quarantined.append(Self.describe(issue))
        return true
      }
      findings.append(Self.describe(issue))
      return true
    }
    if !quarantined.isEmpty {
      let options = XCTExpectedFailure.Options()
      options.isStrict = false
      // Recorded without stopping the test, so the rest of the journey still runs and is checked.
      let stopsOnFailure = !continueAfterFailure
      continueAfterFailure = true
      XCTExpectFailure("Quarantined flaky audit finding, issue #44", options: options) {
        XCTFail(
          "\(quarantined.count) quarantined finding(s):\n" + quarantined.joined(separator: "\n"), file: file, line: line
        )
      }
      continueAfterFailure = !stopsOnFailure
    }
    if !findings.isEmpty {
      XCTFail(
        "\(findings.count) accessibility finding(s):\n" + findings.joined(separator: "\n"), file: file, line: line)
    }
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
