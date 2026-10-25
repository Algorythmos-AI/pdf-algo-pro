import AccessibilityIDs
import XCTest

/// The App Store screenshots, taken from the build on a device (docs/app-store-strategy.md, Screenshots).
///
/// In no test plan CI runs (`scripts/ci/write_testplan.py` skips classes ending in StoreScreenshotTests).
/// Run on request on an iPhone with a 6.9-inch display, once per language:
///
///     TEST_RUNNER_STORE_LANGUAGE=fr xcodebuild test-without-building … \
///       -only-testing:PDFAlgoProUITests/StoreScreenshotTests
///
/// Each frame is attached to the result bundle as `store-<language>-<frame>`, and written to
/// `REPORTS_DIR/store-screenshots/<language>/` when that is set. The library is `-seed-library showcase`:
/// synthetic documents in the screenshots' language. The frames with answers use the device's own model
/// (`-intelligence live`), so they show what the app really answers (Guideline 2.3.3); on a device
/// without Apple Intelligence those frames are skipped, not faked. Frame numbers follow the storyboard;
/// frame 2 (scanning) and frame 4 (editing text) are not taken here.
@MainActor
final class StoreScreenshotTests: UITestCase {
  /// How long the device's own model may take to answer.
  private static let modelTimeout: TimeInterval = 120

  private var language: String { ProcessInfo.processInfo.environment["STORE_LANGUAGE"] ?? "en" }
  private var isFrench: Bool { language == "fr" }

  override func tearDown() {
    XCUIDevice.shared.appearance = .light
    super.tearDown()
  }

  // MARK: - Frames

  func test01AskAndSeeThePage() throws {
    let app = launchShowcase("showcase-invoice", live: true)
    let question = try openAssistant(ID.Reader.Ask.question, in: app)
    question.tap()
    question.typeText(isFrench ? "Quel est le total à payer ?\n" : "What is the total due?\n")
    try waitForAnswer(app.staticTexts[ID.Assistant.answer], in: app)
    shoot("01-ask", app)
  }

  func test03Summary() throws {
    let app = launchShowcase("showcase-report", live: true)
    _ = try openAssistant(ID.Reader.Ask.summarise, in: app)
    try waitForAnswer(app.staticTexts[ID.Assistant.answer], in: app)
    shoot("03-summary", app)
  }

  func test05Sign() throws {
    let app = launchShowcase("showcase-lease", live: false)
    // On the second page, where the lease is signed.
    app.buttons[ID.Reader.more].tap()
    app.buttons[ID.Reader.More.pages].tap()
    let second = app.buttons[ID.Pages.page(2)]
    XCTAssertTrue(second.waitForExistence(timeout: Self.settleTimeout))
    second.tap()
    let onSecond = NSPredicate(format: "label CONTAINS %@", isFrench ? "2 sur 2" : "2 of 2")
    XCTAssertEqual(
      XCTWaiter().wait(
        for: [XCTNSPredicateExpectation(predicate: onSecond, object: app.staticTexts[ID.Reader.pageIndicator])],
        timeout: Self.settleTimeout), .completed, "The second page shows")
    tapMenuItem(
      app.buttons[ID.Reader.Markup.signature], in: app.buttons[ID.Reader.markup],
      until: app.descendants(matching: .any)[ID.Signature.typedName].firstMatch)
    let name = app.descendants(matching: .any)[ID.Signature.typedName].firstMatch
    name.tap()
    name.typeText(isFrench ? "Locataire Échantillon" : "Sample Tenant")
    app.buttons[ID.Signature.placeTyped].tap()
    let bar = app.descendants(matching: .any)[ID.Reader.Selection.actionBar].firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "The signature is placed and selected")
    // Let go of it, so the frame shows the signed page.
    app.buttons[ID.Reader.Selection.done].tap()
    XCTAssertTrue(bar.waitForNonExistence(timeout: Self.settleTimeout), "Done lets go of the signature")
    shoot("05-sign", app)
  }

  func test06Extract() throws {
    let app = launchShowcase("showcase-invoice", live: true)
    _ = try openAssistant(ID.Reader.Ask.extract, in: app)
    try waitForAnswer(app.buttons[ID.Assistant.copyCSV], in: app)
    shoot("06-extract", app)
  }

  func test07Contract() throws {
    let app = launchShowcase("showcase-lease", live: true)
    _ = try openAssistant(ID.Reader.Ask.contract, in: app)
    try waitForAnswer(app.staticTexts[ID.Assistant.answer], in: app)
    shoot("07-contract", app)
  }

  func test08Markup() throws {
    let app = launchShowcase("showcase-report", live: false)
    mark(.highlight, isFrench ? "Le chiffre d'affaires" : "Revenue grew", in: app)
    mark(.underline, isFrench ? "- Deux nouveaux" : "- Two new stores", in: app)
    shoot("08-markup", app)
  }

  func test09Pages() throws {
    let app = launchShowcase("showcase-report", live: false)
    app.buttons[ID.Reader.more].tap()
    app.buttons[ID.Reader.More.pages].tap()
    let third = app.buttons[ID.Pages.page(3)]
    XCTAssertTrue(third.waitForExistence(timeout: Self.settleTimeout))
    tap(app.buttons[ID.Pages.select], until: app.buttons[ID.Pages.moveEarlier])
    app.buttons[ID.Pages.page(2)].tap()
    shoot("09-pages", app)
  }

  func test10HomeInDarkMode() throws {
    XCUIDevice.shared.appearance = .dark
    let app = launchShowcase("showcase", live: false, extra: ["-start", "home"])
    let title = isFrench ? "Contrat de location" : "Residential lease"
    XCTAssertTrue(
      app.descendants(matching: .any)[ID.Library.Home.recent(title)].firstMatch.waitForExistence(
        timeout: Self.settleTimeout), "Home shows the documents being read")
    shoot("10-home", app)
  }

  // MARK: - Helpers

  /// The app on the showcase library, subscribed, in the screenshots' language.
  private func launchShowcase(_ seed: String, live: Bool, extra: [String] = []) -> XCUIApplication {
    let locale =
      isFrench
      ? ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"] : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    let app = launch(
      ["-skip-onboarding", "-seed-library", seed, "-entitlement", "subscribed"] + locale
        + (live ? ["-intelligence", "live"] : []) + extra)
    if !extra.contains("home") {
      XCTAssertTrue(app.staticTexts[ID.Reader.pageIndicator].waitForExistence(timeout: 15), "The document opens")
    }
    return app
  }

  /// Opens a task from the reader's Ask menu, and the question field when it is the question.
  private func openAssistant(_ task: String, in app: XCUIApplication) throws -> XCUIElement {
    app.buttons[ID.Reader.ask].tap()
    app.buttons[task].firstMatch.tap()
    let question = app.descendants(matching: .any)[ID.Assistant.question].firstMatch
    if task == ID.Reader.Ask.question {
      XCTAssertTrue(question.waitForExistence(timeout: Self.settleTimeout))
    }
    return question
  }

  /// Waits for the device's model; skips the frame where the device has none, instead of faking it.
  private func waitForAnswer(_ answer: XCUIElement, in app: XCUIApplication) throws {
    let unavailable = app.descendants(matching: .any)[ID.Assistant.unavailable].firstMatch
    let deadline = Date().addingTimeInterval(Self.modelTimeout)
    while Date() < deadline {
      if answer.exists { return }
      if unavailable.exists { throw XCTSkip("This device has no Apple Intelligence; the frame needs its answer") }
      Thread.sleep(forTimeInterval: 1)
    }
    XCTFail("No answer from the device's model within \(Int(Self.modelTimeout)) seconds")
  }

  private enum Mark: String {
    case highlight, underline
  }

  /// Marks a line of the page's text, found by how it begins, with a tool from the Markup menu.
  private func mark(_ kind: Mark, _ beginning: String, in app: XCUIApplication) {
    tapMenuItem(
      app.buttons[ID.Reader.Markup.text(kind.rawValue)], in: app.buttons[ID.Reader.markup],
      until: app.buttons[ID.Reader.doneMarkup])
    // PDFKit names its text nodes by what they say; a paragraph's node can start with its heading, so
    // the smallest node that contains the words is the line.
    let nodes = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", beginning))
    XCTAssertTrue(nodes.firstMatch.waitForExistence(timeout: Self.settleTimeout), "\"\(beginning)\" is on the page")
    let frames = nodes.allElementsBoundByIndex.map(\.frame).filter { $0.height > 0 && $0.width > 0 }
    guard let frame = frames.min(by: { $0.height < $1.height }) else {
      XCTFail("No text node for \"\(beginning)\" has a size")
      return
    }
    let origin = app.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: frame.minX + 2, dy: frame.midY)).press(
      forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: frame.maxX - 2, dy: frame.midY)))
    app.buttons[ID.Reader.doneMarkup].tap()
  }

  /// Keeps the screen as it is, once it has stopped moving.
  private func shoot(_ frame: String, _ app: XCUIApplication) {
    waitUntilStill(app)
    let screen = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screen)
    attachment.name = "store-\(language)-\(frame)"
    attachment.lifetime = .keepAlways
    add(attachment)
    guard let folder = ProcessInfo.processInfo.environment["REPORTS_DIR"], !folder.isEmpty else { return }
    let directory = URL(fileURLWithPath: folder).appendingPathComponent("store-screenshots/\(language)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? screen.pngRepresentation.write(to: directory.appendingPathComponent("\(frame).png"))
  }
}
