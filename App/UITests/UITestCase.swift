import AccessibilityIDs
import XCTest

/// The shared accessibility identifiers, by a short name: `ID.Reader.more`.
typealias ID = AccessibilityID

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
  /// How long to wait for a screen to appear after a tap.
  ///
  /// A hosted runner can take a minute over a test that takes seconds locally, and waits of 5 or 10
  /// seconds failed there (issue #132). A wait returns as soon as it is met, so a long limit costs
  /// nothing when things work.
  static let settleTimeout: TimeInterval = 30

  /// Whether a test in this process has launched the app yet: the first launch warms the simulator up.
  private static var hasLaunchedOnce = false

  func launch(_ arguments: [String]) -> XCUIApplication {
    continueAfterFailure = false
    // Every journey starts upright, whatever the one before it left. A test that stops on a failure
    // does not run its own clean-up: on CI (2026-10-09) the test after one that failed in landscape
    // ran in landscape, and audited its screen there. The device is asked to turn only when it is not
    // upright already: on a loaded runner the request itself timed out, "Timed out waiting for
    // confirmation of orientation change", and failed a journey before it began (issue #197). When the
    // request is needed and still times out, the journey goes on upright or not, and says so.
    if XCUIDevice.shared.orientation != .portrait {
      tolerating("Quarantined flaky orientation change, issue #197") { XCUIDevice.shared.orientation = .portrait }
    }
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-disable-animations"] + arguments
    if Self.hasLaunchedOnce {
      app.launch()
    } else {
      // The first launch of a run can time out while the simulator is still warming up (issue #126:
      // "Timed out while launching application via Xcode" after 75 seconds, then green on the next
      // run). That one launch is tried once more before the journey fails.
      Self.hasLaunchedOnce = true
      tolerating("Quarantined flaky first launch, issue #126") { app.launch() }
      if app.state != .runningForeground {
        app.terminate()
        app.launch()
      }
    }
    return app
  }

  /// Runs `body`, recording any failure it reports as a non-strict expected failure named `reason`, so
  /// a flake that is quarantined with an issue is visible in the results without failing the journey.
  func tolerating(_ reason: String, _ body: () -> Void) {
    let options = XCTExpectedFailure.Options()
    options.isStrict = false
    let stopsOnFailure = !continueAfterFailure
    continueAfterFailure = true
    XCTExpectFailure(reason, options: options, failingBlock: body)
    continueAfterFailure = !stopsOnFailure
  }

  /// Holds a finger on the middle of `element`, then drags it by `offset` slowly and holds before the
  /// finger lifts, so that nothing can glide and the drop lands where the finger stopped.
  ///
  /// The element's frame is read once it has kept still for a second, and the gesture runs on a
  /// coordinate relative to the app (see `point(_:_:in:of:)`): a coordinate relative to the element
  /// looks it up again for every event, which on a busy runner stretched a drag so that it drew
  /// nothing (issue #68), and a hold that began on a frame still settling dropped a moved line short of
  /// where it was dragged (issue #215). `holding` is how long the finger rests before it moves: long
  /// enough for a long press where the gesture needs one, short where it does not.
  /// - Returns: The frame the element had when the gesture began.
  @discardableResult
  func dragSlowly(
    _ element: XCUIElement, by offset: CGVector, holding: TimeInterval, in app: XCUIApplication
  ) -> CGRect {
    let frame = waitUntilSteady(element)
    let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    from.press(forDuration: holding, thenDragTo: from.withOffset(offset), withVelocity: .slow, thenHoldForDuration: 0.5)
    return frame
  }

  /// Taps the bar's back button and waits for `target`, the screen Back leads to; taps once more only
  /// while `leaving`, something of the screen being left, is still there.
  ///
  /// A back tap made while the screen is still settling can be lost (issue #211: Back from the list
  /// did not show Home). The screen behind has a back button of its own, so a second tap is made only
  /// when the first plainly did nothing: the screen being left is still showing.
  func goBack(
    in app: XCUIApplication, leaving: XCUIElement, to target: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
    XCTAssertTrue(
      back.waitForExistence(timeout: Self.settleTimeout), "The bar has a back button", file: file, line: line)
    back.tap()
    if !target.waitForExistence(timeout: 10), leaving.exists {
      app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }
    XCTAssertTrue(
      target.waitForExistence(timeout: Self.settleTimeout), "Back shows the screen before", file: file, line: line)
  }

  /// Keeps the screen as it is, for a failure about to be reported: a screenshot, and `notes` followed by
  /// the app's element tree, in `REPORTS_DIR/ui-evidence`.
  ///
  /// CI prints them into the shard's log, so a failure can be seen without downloading the result
  /// bundle. Three paywall audits and the text-editing journeys failed on some runners only
  /// (2026-10-09), and their screenshots were in the artifacts alone.
  func keepEvidence(_ app: XCUIApplication, named name: String, notes: String) {
    // In the result bundle too, so a run on a device, where there is no reports folder, keeps the screen.
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = name
    screen.lifetime = .keepAlways
    add(screen)
    guard let folder = ProcessInfo.processInfo.environment["REPORTS_DIR"], !folder.isEmpty else { return }
    let directory = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent("ui-evidence")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stem = "\(self.name) \(name)".replacingOccurrences(
      of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
    try? app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(stem + ".png"))
    try? (notes + "\n\n" + app.debugDescription).write(
      to: directory.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
  }

  /// Waits until `element` has the keyboard focus, so that typed text reaches it.
  ///
  /// A field exists before it takes the focus. On CI (run 37934833918) text typed at once after a line
  /// opened was lost: the field still read "Try these:".
  func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval = UITestCase.settleTimeout) -> Bool {
    let focused = NSPredicate(format: "hasKeyboardFocus == true")
    let expectation = XCTNSPredicateExpectation(predicate: focused, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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

  /// Waits until an element's frame has stayed the same for `steady` seconds, and returns that frame.
  ///
  /// After the screen turns, the app lays out again over several frames and then scrolls for what
  /// is being edited; a frame read at once can be one of the steps on the way (CI, 2026-10-09).
  /// Where the frame never settles within `timeout`, the last one read is returned, for the caller's
  /// own assertions to report.
  @discardableResult
  func waitUntilSteady(_ element: XCUIElement, for steady: TimeInterval = 1, timeout: TimeInterval = 10) -> CGRect {
    var frame = element.frame
    var since = Date()
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
      let current = element.frame
      if current != frame {
        frame = current
        since = Date()
      } else if Date().timeIntervalSince(since) >= steady {
        return frame
      }
    }
    return frame
  }

  /// Waits, for up to four seconds, until three screenshots taken a quarter of a second apart match, so
  /// the screen has been still for half a second.
  ///
  /// An element exists before it has finished appearing: at launch the system cross-fades from the
  /// launch screen, and a sheet slides in. An audit taken then measures half-drawn text (issue
  /// #69). A sheet's bar buttons sit on glass that finishes appearing after the sheet, and a single
  /// quarter-second match could fall between those two steps (issue #76). A screen that never stops
  /// changing, such as one with a blinking caret, is audited after the four seconds.
  func waitUntilStill(_ app: XCUIApplication) {
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
  ///
  /// For a control that stays on screen while the screen changes, such as Continue in the introduction,
  /// pass `origin`, something only the screen being left shows: the second tap is made only while it
  /// still shows. Otherwise a first tap that was merely slow and a second tap together skip a screen;
  /// on a loaded runner the introduction went from its first page straight to its third.
  ///
  /// Wait for something the screen always shows, such as its bar's Done, not a row of a list: at a
  /// large text size a row can be below the part of the list on screen, and then it doesn't exist.
  /// Where the target never appears, the screen and the element tree are kept (`keepEvidence`): a
  /// device run of issue #76 failed here and kept no screenshot.
  func tap(
    _ control: XCUIElement, until target: XCUIElement, from origin: XCUIElement? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(control.waitForExistence(timeout: Self.settleTimeout), "The control exists", file: file, line: line)
    control.tap()
    if !target.waitForExistence(timeout: 3) {
      if origin?.exists ?? true { control.tap() }
      if !target.waitForExistence(timeout: Self.settleTimeout) {
        let state =
          "Waited \(Int(Self.settleTimeout)) s for \(target). The control, \(control), "
          + "exists: \(control.exists), hittable: \(control.exists && control.isHittable)."
        keepEvidence(XCUIApplication(), named: "tap \(line)", notes: state)
        XCTFail("The tap opens what it should. \(state)", file: file, line: line)
      }
    }
  }

  /// Waits until `element` can be tapped: nothing covers it any more, such as a sheet sliding away.
  ///
  /// An element under a closing sheet exists before it can be tapped, and a tap on it then can be lost
  /// (issue #76: after the scan sheet was cancelled, Settings did not open on a device). Where it never
  /// becomes hittable, the screen and the element tree are kept.
  func waitUntilHittable(
    _ element: XCUIElement, in app: XCUIApplication, _ message: String, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let uncovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
    guard XCTWaiter.wait(for: [uncovered], timeout: Self.settleTimeout) != .completed else { return }
    let state = "\(element) exists: \(element.exists), hittable: \(element.exists && element.isHittable)."
    keepEvidence(app, named: "covered \(line)", notes: state)
    XCTFail("\(message). \(state)", file: file, line: line)
  }

  /// Taps a control that takes its own screen away, and waits for the screen that replaces it.
  ///
  /// On a slow runner a tap made while the screen is still settling after an audit can be lost, and the
  /// journey then waits on the old screen (seen once on onboarding, pull request 149). Unlike
  /// `tap(_:until:)`, the second tap is made only while the control is still there: once the first tap
  /// has worked the control is gone, however long the next screen takes to appear.
  func leave(
    by control: XCUIElement, for target: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(control.waitForExistence(timeout: Self.settleTimeout), "The control exists", file: file, line: line)
    control.tap()
    if !target.waitForExistence(timeout: 10), control.exists, control.isHittable { control.tap() }
    XCTAssertTrue(
      target.waitForExistence(timeout: Self.settleTimeout), "The tap opens what it should", file: file, line: line)
  }

  /// Opens All documents from Home, the screen the app starts on, and waits for the list's own bar.
  func openDocumentList(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    tap(
      app.descendants(matching: .any)[ID.Library.section("all")].firstMatch, until: app.buttons[ID.Library.scan],
      file: file, line: line)
  }

  /// Opens a menu, taps one of its items and waits for what the item opens (see `tap(_:until:)`).
  ///
  /// On a slow CI runner the tap on the item can be swallowed, or what it opens can take longer than a
  /// short wait allows: one run spent 30 seconds finding the item, then gave up on the sheet after 5.
  /// So this waits 10 seconds for `result` and, when it hasn't appeared, taps the item once more,
  /// opening the menu again if it has closed. The caller still asserts that `result` exists.
  func tapMenuItem(
    _ item: XCUIElement, in menu: XCUIElement, until result: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    open(menu, showing: item, file: file, line: line)
    item.tap()
    if result.waitForExistence(timeout: Self.settleTimeout) { return }
    if !item.exists { open(menu, showing: item, file: file, line: line) }
    item.tap()
    XCTAssertTrue(
      result.waitForExistence(timeout: Self.settleTimeout), "The menu item opens what it should", file: file, line: line
    )
  }

  /// Taps `menu` until `item` shows, up to three times, ten seconds apart.
  ///
  /// `tap(_:until:)` taps once more after three seconds. At a large text size on a loaded runner that
  /// second tap can come while the menu is still opening, and close it; nothing opened it again, and
  /// the item never showed in 33 seconds with More hittable (issue #324). A tap that closes the menu is
  /// followed by one that opens it again. Where the item never shows, the screen and the element tree
  /// are kept.
  private func open(_ menu: XCUIElement, showing item: XCUIElement, file: StaticString, line: UInt) {
    XCTAssertTrue(menu.waitForExistence(timeout: Self.settleTimeout), "The control exists", file: file, line: line)
    for _ in 0..<3 {
      menu.tap()
      if item.waitForExistence(timeout: 10) { return }
    }
    let app = XCUIApplication()
    let state =
      "Waited 30 s over three taps for \(item). The menu, \(menu), exists: \(menu.exists), "
      + "hittable: \(menu.exists && menu.isHittable); items shown (buttons in menus and lists): "
      + "\(app.collectionViews.buttons.count)."
    keepEvidence(app, named: "menu \(line)", notes: state)
    XCTFail("The menu opens and shows the item. \(state)", file: file, line: line)
  }

  /// An item of an open submenu (Markup › Shapes, Markup › Stamp): by its identifier where the system
  /// shows it, else by its title in English or French.
  ///
  /// On iOS 27 an open submenu's items carry no identifier, wherever the app sets it (on the item, its
  /// label or its text), while the top-level items of the same menu keep theirs (#292). A title is
  /// looked for only on an element with no identifier, so on iOS 26 the identifier still decides. The
  /// titles are the Reader catalog's, in both of the app's languages, since the tests don't fix the
  /// device's language.
  func submenuItem(_ identifier: String, titles: [String], in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "identifier == %@ OR (identifier == '' AND label IN %@)", identifier, titles)
    ).firstMatch
  }

  /// A shape in Markup › Shapes (`rectangle`, `oval` or `arrow`); see `submenuItem`.
  func shapeItem(_ tool: String, in app: XCUIApplication) -> XCUIElement {
    let titles = ["rectangle": ["Rectangle"], "oval": ["Oval", "Ovale"], "arrow": ["Arrow", "Flèche"]]
    return submenuItem(ID.Reader.Markup.shape(tool), titles: titles[tool] ?? [], in: app)
  }

  /// Tick in Markup › Stamp; see `submenuItem`.
  func tickItem(in app: XCUIApplication) -> XCUIElement {
    submenuItem(ID.Reader.Markup.Stamp.tick, titles: ["Tick", "Coche"], in: app)
  }

  /// The accessibility audit in light mode and in dark mode, then back to the appearance it started in.
  ///
  /// A colour can pass in one and fail in the other: on an iPhone in dark mode (2026-10-26) the Unlock
  /// button and the selection bar's Delete failed contrast, and the simulators CI runs are light.
  func auditInBothAppearances(
    _ app: XCUIApplication, onSheet: Bool = false, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    try audit(app, onSheet: onSheet, file: file, line: line)
    let original = XCUIDevice.shared.appearance
    XCUIDevice.shared.appearance = original == .dark ? .light : .dark
    defer { XCUIDevice.shared.appearance = original }
    try audit(app, onSheet: onSheet, file: file, line: line)
  }

  /// The accessibility audit on the current screen.
  ///
  /// Five kinds of finding are excluded narrowly everywhere, and a sixth on sheets (below):
  /// - issues on PDFKit's page view and the nodes it exposes for the text on a page, which are not ours
  ///   to change. On iOS 26 those nodes are `UICGPDFNode`s. On iOS 27 PDFKit exposes the page's
  ///   structure instead (headings, lists, list items) under other names, and the audit reports its
  ///   lines of text as hit areas too small to tap (#293). So the nodes are also recognised by where
  ///   they are: inside the scroll view in `reader.pages`, which is PDFKit's;
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
      // On a focused run (UI_EVIDENCE=all), quarantined findings keep the screen too: a finding the audit
      // reports without its element is quarantined (issue #76), and on run 37939544303 the paywall's
      // two such findings came with their elements, one of them the offer's explanation.
      if ProcessInfo.processInfo.environment["UI_EVIDENCE"] == "all" {
        keepEvidence(app, named: "audit \(line) quarantined", notes: appearing.joined(separator: "\n"))
      }
      recordQuarantined(
        "Quarantined flaky audit finding, issue #76",
        details: "\(appearing.count) quarantined finding(s):\n" + appearing.joined(separator: "\n"), file: file,
        line: line)
    }
    if !findings.isEmpty, findings.allSatisfy(Self.isMeasuredTooSoon) {
      // Contrast measured while a sheet still slides in fails on text drawn in the primary label colour
      // (issue #105), and text measured right after the audit changed its size, before it redrew, reads
      // as not scaling (issue #182). A real problem is still there once the screen has settled, so these
      // findings count only when a second audit, after another wait, finds them again.
      waitUntilStill(app)
      var again: [String] = []
      var ignored: [String] = []
      try? runAudit(
        app, onSheet: onSheet, bars: bars, barTitles: barTitles, actionBars: actionBars, searchFields: searchFields,
        findings: &again, appearing: &ignored)
      let passing = findings.filter { !again.contains($0) }
      if !passing.isEmpty {
        recordQuarantined(
          "Measured while the screen was moving, gone on a second audit (issues #105, #182)",
          details: passing.joined(separator: "\n"), file: file, line: line)
      }
      findings = findings.filter { again.contains($0) }
    }
    if !findings.isEmpty, ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
      // iOS 27's audit misreads contrast on glass (#294): measured on the screen instead (`ScreenContrast`).
      // An element less than half on the screen can't be measured there; on the device the audit flagged
      // a report's last row below the sheet's edge. CI's iOS 26 audit still checks such elements.
      let screen = app.screenshot()
      let shown = app.frame
      var measured: [String] = []
      findings = findings.filter { finding in
        guard finding.hasPrefix("- Contrast failed"), let frame = ScreenContrast.frame(in: finding) else {
          return true
        }
        let visible = frame.intersection(shown)
        let fraction = visible.isNull ? 0 : (visible.width * visible.height) / max(1, frame.width * frame.height)
        if fraction < 0.5 {
          let note = String(format: "\n    Mostly off the screen (%.0f%% shown), not measured", fraction * 100)
          measured.append(finding + note)
          return false
        }
        guard let ratio = ScreenContrast.ratio(of: frame, in: screen), ratio >= ScreenContrast.minimum else {
          return true
        }
        measured.append(finding + String(format: "\n    Measured on the screen: %.1f:1", ratio))
        return false
      }
      if !measured.isEmpty {
        keepEvidence(app, named: "audit \(line) contrast measured", notes: measured.joined(separator: "\n"))
        recordQuarantined(
          "Contrast the iOS 27 audit misreads on glass or off the screen, measured on the screen instead, issue #294",
          details: measured.joined(separator: "\n"), file: file, line: line)
      }
    }
    if !findings.isEmpty {
      keepEvidence(app, named: "audit \(line)", notes: findings.joined(separator: "\n"))
      XCTFail(
        "\(findings.count) accessibility finding(s):\n" + findings.joined(separator: "\n"), file: file, line: line)
    }
  }

  /// The nodes PDFKit exposes for the pages in view, as `nodeKey`s.
  ///
  /// Everything inside the scroll view in `reader.pages`, read in one snapshot. Empty where no reader is
  /// showing.
  private static func pdfPageNodes(in app: XCUIApplication) -> Set<String> {
    let pages = app.descendants(matching: .any)[ID.Reader.pages].firstMatch
    guard pages.exists, let scroll = try? pages.scrollViews.firstMatch.snapshot() else { return [] }
    var keys: Set<String> = []
    func collect(_ node: any XCUIElementSnapshot) {
      keys.insert(nodeKey(label: node.label, frame: node.frame))
      node.children.forEach(collect)
    }
    scroll.children.forEach(collect)
    return keys
  }

  /// A node's label and frame, rounded to whole points, so an audit finding can be matched to it.
  private static func nodeKey(label: String, frame: CGRect) -> String {
    let rounded = [frame.minX, frame.minY, frame.width, frame.height].map { Int($0.rounded()) }
    return "\(label)|\(rounded)"
  }

  /// Whether a finding is one the audit can make while the screen is still redrawing: contrast
  /// (issue #105), or text that seems not to scale with Dynamic Type (issue #182).
  private static func isMeasuredTooSoon(_ finding: String) -> Bool {
    finding.hasPrefix("- Contrast failed") || finding.hasPrefix("- Dynamic Type font sizes are partially unsupported")
  }

  private func runAudit(
    _ app: XCUIApplication, onSheet: Bool, bars: [CGRect], barTitles: Set<String>, actionBars: [CGRect],
    searchFields: [CGRect], findings: inout [String], appearing: inout [String]
  ) throws {
    let navigationBars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
    // A sheet covers the page, so its nodes aren't audited there and aren't read.
    let pageNodes = onSheet ? [] : Self.pdfPageNodes(in: app)
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
        if pageNodes.contains(Self.nodeKey(label: element.label, frame: element.frame)) { return true }
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
      } else if issue.auditType == .elementDetection || issue.auditType == .contrast {
        // "Potentially inaccessible text", or a contrast failure, without an element (issue #76): with no
        // element there is no frame to check again once the screen settles, and it has only ever been
        // seen on a sheet's bar while it appears.
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
  func recordQuarantined(_ reason: String, details: String, file: StaticString, line: UInt) {
    tolerating(reason) { XCTFail(details, file: file, line: line) }
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
