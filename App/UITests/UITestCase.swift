import XCTest

/// The base of every end-to-end journey on the simulator: launching and the accessibility audit.
///
/// Every run starts from a fresh, private state (temporary folders, throwaway settings and the scripted
/// intelligence router, via the Debug-only launch arguments in docs/testing-strategy.md), and every
/// top-level screen passes an accessibility audit (NFR-A11Y-001). Journeys live in one file per feature.
@MainActor
class UITestCase: XCTestCase {
  /// How long a journey waits for an AI result (an answer, "not found", or unavailability).
  ///
  /// The scripted router answers at once, but on a loaded runner the sheet, the keyboard and each
  /// accessibility query over a page's text can take seconds; an answer arrived after a 10-second wait
  /// (issue #81). A real regression still fails, only later.
  static let answerTimeout: TimeInterval = 30

  func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-disable-animations"] + arguments
    app.launch()
    return app
  }

  /// A point in an element, as a coordinate relative to the app.
  ///
  /// The element's frame is read once. A coordinate relative to the element looks the element up again
  /// for every event of a gesture, which on a busy runner takes seconds, because a page's text makes the
  /// accessibility tree large, and stretched a drag until it drew nothing (issue #68).
  func point(_ dx: CGFloat, _ dy: CGFloat, in element: XCUIElement, of app: XCUIApplication) -> XCUICoordinate {
    let frame = element.frame
    return app.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.minX + frame.width * dx, dy: frame.minY + frame.height * dy))
  }

  /// Waits, for up to four seconds, until three screenshots taken a quarter of a second apart match, so
  /// the screen has been still for half a second.
  ///
  /// An element exists before it has finished appearing: at launch the system cross-fades from the
  /// launch screen, and a sheet slides in. An audit taken then measures half-drawn text (issue
  /// #69). A sheet's bar buttons sit on glass that finishes appearing after the sheet, and a single
  /// quarter-second match could fall between those two steps (issue #76). A screen that never stops
  /// changing, such as one with a blinking caret, is audited after the four seconds.
  private func waitUntilStill(_ app: XCUIApplication) {
    var previous = app.screenshot().pngRepresentation
    var matches = 0
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
      Thread.sleep(forTimeInterval: 0.25)
      let current = app.screenshot().pngRepresentation
      matches = current == previous ? matches + 1 : 0
      if matches == 2 { return }
      previous = current
    }
  }

  /// Taps a control and waits for what it opens, tapping once more if the first tap was lost.
  ///
  /// A tap that arrives while the screen is still settling, for example while a sheet is closing, can be
  /// swallowed: a menu stays closed (issue #76), or Settings never opens after the scan sheet is
  /// cancelled.
  func tap(
    _ control: XCUIElement, until target: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(control.waitForExistence(timeout: 10), "The control exists", file: file, line: line)
    control.tap()
    if !target.waitForExistence(timeout: 3) {
      control.tap()
      XCTAssertTrue(target.waitForExistence(timeout: 5), "The tap opens what it should", file: file, line: line)
    }
  }

  /// Opens a menu and taps one of its items (see `tap(_:until:)`).
  func tapMenuItem(_ item: XCUIElement, in menu: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    tap(menu, until: item, file: file, line: line)
    item.tap()
  }

  /// The accessibility audit on the current screen.
  ///
  /// Five kinds of finding are excluded narrowly everywhere, and a sixth on sheets (below):
  /// - issues on PDFKit's page view and the nodes it exposes for the text on a page, which are not ours
  ///   to change;
  /// - Dynamic Type and clipped-text findings in navigation bars and toolbars, whose titles and buttons
  ///   the system sizes and truncates, and on a navigation bar's title wherever the audit reports it
  ///   (at accessibility sizes it can report the title away from the bar);
  /// - contrast findings on text scrolled behind a bottom action bar (identifier ending `.actionBar`),
  ///   which hides it, so the pixels the audit measures are the bar's (the bar's own controls are still
  ///   audited);
  /// - contrast findings on content partly behind the search field that floats at the bottom of the
  ///   screen, which scrolling brings out; at large text sizes, the end of a screen rests there (the
  ///   field itself is still audited);
  /// - contrast findings on disabled controls, which are dimmed on purpose to show they are inactive;
  ///   WCAG 1.4.3 sets no contrast requirement for inactive controls. The same control is audited
  ///   again once it is enabled. On CI the audit sometimes reports these findings without their
  ///   element, and then this exclusion cannot apply, so text buttons that start disabled use
  ///   `readableWhenDisabled()` rather than rely on it.
  ///
  /// Every other finding fails the test. All findings on the screen are collected and
  /// reported together, with the element each one is about, instead of stopping at the first.
  ///
  /// On a sheet (`onSheet`), "Dynamic Type font sizes are partially unsupported" findings are excluded
  /// (issue #44). The audit changes the text size and measures at once, and a sheet redraws a moment
  /// later, so the finding came and went on text that uses standard styles. The large-text journeys
  /// (`LargeTextUITests`) and the large-text snapshots check every sheet at an accessibility size
  /// instead. Text that doesn't scale at all still fails, on sheets too.
  ///
  /// Quarantined (issue #76, flaky): contrast findings on buttons inside a navigation bar, measured while a
  /// sheet's glass bar buttons are still appearing (the accent colour is about 7:1 once drawn), and
  /// "Potentially inaccessible text" findings that come without an element. Contrast anywhere else still
  /// fails.
  ///
  /// Quarantined (issue #53, flaky): the audit itself sometimes gives up with "Audit failed to complete in
  /// time" on a loaded runner. That timeout is recorded the same way; the journey goes on.
  func audit(
    _ app: XCUIApplication, onSheet: Bool = false, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    waitUntilStill(app)
    let bars =
      app.navigationBars.allElementsBoundByIndex.map(\.frame) + app.toolbars.allElementsBoundByIndex.map(\.frame)
    let actionBars = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier ENDSWITH %@", ".actionBar")).allElementsBoundByIndex.map(\.frame)
    let searchFields = app.searchFields.allElementsBoundByIndex.map(\.frame)
    let barTitles = Set(app.navigationBars.allElementsBoundByIndex.map(\.identifier).filter { !$0.isEmpty })
    var findings: [String] = []
    var appearing: [String] = []
    // How long each audit takes, as a named activity in the CI log, for the timeouts in issue #53.
    let started = Date()
    defer {
      let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
      let place = "\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)"
      XCTContext.runActivity(named: "Accessibility audit at \(place) took \(seconds) s") { _ in }
    }
    do {
      try runAudit(
        app, onSheet: onSheet, bars: bars, barTitles: barTitles, actionBars: actionBars, searchFields: searchFields,
        findings: &findings, appearing: &appearing)
    } catch let error as NSError
      where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    {
      // Findings collected before the timeout are still reported below.
      recordQuarantined(
        "Quarantined flaky audit timeout, issue #53", details: error.localizedDescription, file: file, line: line)
    }
    if !appearing.isEmpty {
      recordQuarantined(
        "Quarantined flaky audit finding, issue #76",
        details: "\(appearing.count) quarantined finding(s):\n" + appearing.joined(separator: "\n"), file: file,
        line: line)
    }
    if !findings.isEmpty {
      XCTFail(
        "\(findings.count) accessibility finding(s):\n" + findings.joined(separator: "\n"), file: file, line: line)
    }
  }

  private func runAudit(
    _ app: XCUIApplication, onSheet: Bool, bars: [CGRect], barTitles: Set<String>, actionBars: [CGRect],
    searchFields: [CGRect], findings: inout [String], appearing: inout [String]
  ) throws {
    let navigationBars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
    var collected: [String] = []
    var settling: [String] = []
    defer {
      findings += collected
      appearing += settling
    }
    try app.performAccessibilityAudit { issue in
      if let element = issue.element {
        if element.identifier == "reader.pages" { return true }
        // PDFKit's own accessibility nodes for the text on a page: part of PDFKit's page view.
        if issue.detailedDescription.contains("UICGPDFNode") { return true }
        if issue.auditType == .contrast, !element.isEnabled { return true }
        if issue.auditType == .dynamicType || issue.auditType == .textClipped,
          bars.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(element.frame) })
            || (element.elementType == .staticText && barTitles.contains(element.label))
        {
          return true
        }
        if issue.auditType == .contrast, element.elementType == .staticText,
          actionBars.contains(where: { $0.intersects(element.frame) })
        {
          return true
        }
        if issue.auditType == .contrast,
          searchFields.contains(where: { $0.intersects(element.frame) && !$0.contains(element.frame) })
        {
          return true
        }
        if issue.auditType == .contrast, element.elementType == .button,
          navigationBars.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(element.frame) })
        {
          settling.append(Self.describe(issue))
          return true
        }
      } else if issue.auditType == .elementDetection {
        // "Potentially inaccessible text" without an element (issue #76).
        settling.append(Self.describe(issue))
        return true
      }
      if onSheet, issue.auditType == .dynamicType,
        issue.compactDescription.localizedCaseInsensitiveContains("partially")
      {
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
