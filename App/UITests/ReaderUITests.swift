import XCTest

/// The reader: navigation within a document (FR-READ-002, FR-READ-003).
@MainActor
final class ReaderUITests: UITestCase {
  func testContentsAndPagesFindTheirWayAround() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    app.buttons["reader.more"].tap()
    app.buttons["Contents"].tap()
    let contents = app.navigationBars["Contents"]
    XCTAssertTrue(contents.waitForExistence(timeout: Self.settleTimeout), "The table of contents opens (FR-READ-002)")
    try audit(app, onSheet: true)
    contents.buttons["Done"].tap()
    app.buttons["reader.more"].tap()
    app.buttons["Pages"].tap()
    let third = app.buttons["Page 3"]
    XCTAssertTrue(third.waitForExistence(timeout: Self.settleTimeout), "The page grid shows every page (FR-READ-002)")
    try audit(app, onSheet: true)
    third.tap()
    expectation(for: NSPredicate(format: "label CONTAINS %@", "3 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: Self.settleTimeout)
  }

  /// A slow drag moves the page under the finger, and the page stays where the finger leaves it.
  ///
  /// The page's scrolling used to wait for a pinch that cannot fail while one finger is down, so the
  /// page did not follow a drag: it glided on after a flick, and a slow drag left it where it was
  /// (issue #188). The drag here is slow and held before the finger lifts, so nothing can glide.
  func testThePageFollowsASlowDrag() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    let pages = app.descendants(matching: .any)["reader.pages"].firstMatch
    XCTAssertTrue(pages.waitForExistence(timeout: Self.settleTimeout))
    // From low on the page, clear of the page strip along the bottom, to near its top: more than a
    // page's height, so the page under the finger at the end is no longer the first.
    let area = pages.frame
    let strip = app.descendants(matching: .any)["reader.pageStrip"].firstMatch
    let lowest = (strip.exists ? min(area.maxY, strip.frame.minY) : area.maxY) - 24
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let from = origin.withOffset(CGVector(dx: area.midX, dy: lowest))
    let to = origin.withOffset(CGVector(dx: area.midX, dy: area.minY + 40))
    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1)
    let pastTheFirst = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "2 of 3", "3 of 3")
    let moved = XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: pastTheFirst, object: indicator)], timeout: 5)
    if moved != .completed {
      keepEvidence(
        app, named: "not dragged",
        notes: "indicator \(indicator.label); pages \(area); dragged from y \(lowest) to y \(area.minY + 40)")
    }
    XCTAssertEqual(
      moved, .completed,
      "The page did not follow a slow drag from y \(lowest) to y \(area.minY + 40): "
        + "the indicator says \(indicator.label)")
  }

  /// With an annotation selected, a slow drag that starts off it still moves the page (issue #194).
  ///
  /// With a selection, the page's scrolling went on waiting for the pinch that resizes it, so that
  /// the page kept still under the pinch. A pinch that sees one finger cannot fail until the finger
  /// lifts, so the page did not follow a drag at all. A stamp is selected as it is placed.
  func testWithAStampSelectedThePageFollowsASlowDrag() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    let bar = app.descendants(matching: .any)["reader.selection.actionBar"].firstMatch
    tap(app.buttons["reader.markup"], until: app.buttons["Stamp"])
    tap(app.buttons["Stamp"], until: app.buttons["Tick"])
    app.buttons["Tick"].tap()
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "A stamp is selected as it is placed")

    // The stamp is near the top right of the first page; the drag keeps to the left of the pages.
    let drag = dragThePagesUpSlowly(app, evidence: "not dragged with a stamp selected")
    XCTAssertTrue(drag.moved, "With a stamp selected, the page did not follow a slow drag off it: \(drag.notes)")
    XCTAssertTrue(bar.exists, "Dragging the page does not let go of the stamp: \(drag.notes)")
  }

  /// One sitting with a selected shape: a finger on it moves it, two fingers on it resize it, the page
  /// keeps still under both, and a finger off it then moves the page (issue #194).
  ///
  /// The page's own drag no longer waits for the pinch that resizes the selection: the two run
  /// together, and the pinch stops the page's drag while it lasts. So this holds what that wait was
  /// for, the page keeping still under the pinch, and that the pinch gives the page's drag back.
  ///
  /// Nothing here reads the shape itself, which the page does not offer to a test. Where it is and
  /// how far it reaches is felt for with taps: a tap on it selects it, and the bar shows; a tap on
  /// bare page lets go of it, and the bar goes.
  func testASelectedShapeIsMovedWithOneFingerAndResizedWithTwoWhileThePageKeepsStill() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    app.buttons["reader.markup"].tap()
    app.buttons["Shapes"].tap()
    app.buttons["Rectangle"].tap()
    let area = app.descendants(matching: .any)["reader.drawing"].firstMatch
    XCTAssertTrue(area.waitForExistence(timeout: Self.settleTimeout))
    // A rectangle on bare page under the first page's text: a fifth of the screen wide.
    let frame = area.frame
    let origin = app.coordinate(withNormalizedOffset: .zero)
    func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { origin.withOffset(CGVector(dx: x, dy: y)) }
    let drawn = CGRect(
      x: frame.minX + frame.width * 0.4, y: frame.minY + frame.height * 0.22, width: frame.width * 0.2,
      height: frame.height * 0.1)
    at(drawn.minX, drawn.minY).press(forDuration: 0.1, thenDragTo: at(drawn.maxX, drawn.maxY))
    app.buttons["reader.doneDrawing"].tap()

    let pages = app.descendants(matching: .any)["reader.pages"].firstMatch
    XCTAssertTrue(pages.waitForExistence(timeout: Self.settleTimeout))
    let bar = app.descendants(matching: .any)["reader.selection.actionBar"].firstMatch
    let start = CGPoint(x: drawn.midX, y: drawn.midY)
    // The middle of the pages, where a pinch on them has its fingers either side of.
    let middle = CGPoint(x: pages.frame.midX, y: pages.frame.midY)
    // Beside the rectangle once it is in the middle: off it as drawn, on it once it has grown by half.
    let beside = CGPoint(x: middle.x + drawn.width * 0.75, y: middle.y)
    let places = "drawn \(drawn), pages \(pages.frame), middle \(middle), beside \(beside)"
    at(start.x, start.y).tap()
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "A tap on the rectangle selects it: \(places)")
    let rested = placeOfThePages(in: app)

    // One finger on it, slowly and held: the rectangle goes with the finger and the page stays.
    at(start.x, start.y).press(
      forDuration: 0.05, thenDragTo: at(middle.x, middle.y), withVelocity: .slow, thenHoldForDuration: 1)
    var place = placeOfThePages(in: app)
    if !isSame(place, rested) || !bar.exists {
      keepEvidence(app, named: "moved a shape", notes: "pages' place \(rested) -> \(place); \(places)")
    }
    XCTAssertTrue(bar.exists, "A drag on the rectangle keeps it selected: \(places)")
    XCTAssertTrue(
      isSame(place, rested),
      "The page moved under a drag that began on the selection: its place went from \(rested) to \(place); \(places)")
    at(start.x, start.y).tap()
    XCTAssertTrue(
      bar.waitForNonExistence(timeout: Self.settleTimeout), "The rectangle is still where it was drawn: \(places)")
    at(middle.x, middle.y).tap()
    XCTAssertTrue(
      bar.waitForExistence(timeout: Self.settleTimeout), "The rectangle did not go with the finger: \(places)")
    at(beside.x, beside.y).tap()
    XCTAssertTrue(
      bar.waitForNonExistence(timeout: Self.settleTimeout),
      "The rectangle already reaches the point that is to show it has grown: \(places)")
    at(middle.x, middle.y).tap()
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "The rectangle is selected again: \(places)")

    // Two fingers on it: the rectangle grows, and the page neither zooms nor moves.
    pages.pinch(withScale: 3, velocity: 1)
    place = placeOfThePages(in: app)
    if !isSame(place, rested) || !bar.exists {
      keepEvidence(app, named: "pinched a shape", notes: "pages' place \(rested) -> \(place); \(places)")
    }
    XCTAssertTrue(bar.exists, "A pinch on the rectangle keeps it selected: \(places)")
    XCTAssertTrue(
      isSame(place, rested),
      "The page zoomed or moved under a pinch on the selection: its place went from \(rested) to \(place); \(places)")
    app.buttons["reader.selection.done"].tap()
    XCTAssertTrue(bar.waitForNonExistence(timeout: Self.settleTimeout), "Done lets go of the rectangle")
    at(beside.x, beside.y).tap()
    if !bar.waitForExistence(timeout: Self.settleTimeout) {
      keepEvidence(app, named: "shape not resized", notes: places)
      XCTFail("The pinch did not make the rectangle larger: a tap beside where it was drawn finds nothing; \(places)")
    }

    // And the pinch gave the page back: a finger off the rectangle, which is selected, moves the page.
    let drag = dragThePagesUpSlowly(app, evidence: "not dragged after a pinch")
    XCTAssertTrue(
      drag.moved, "With a shape selected and resized, the page did not follow a slow drag off it: \(drag.notes)")
    XCTAssertTrue(bar.exists, "Dragging the page does not let go of the rectangle: \(drag.notes)")
  }

  /// Drags the pages up slowly, by about a page's height, holds before the finger lifts so that
  /// nothing can glide, and says whether the indicator left the first page.
  ///
  /// The drag runs along the left of the pages, clear of an annotation in the middle or on the right,
  /// and starts above whatever lies along the bottom: the page strip and the bar for a selection.
  private func dragThePagesUpSlowly(_ app: XCUIApplication, evidence: String) -> (moved: Bool, notes: String) {
    let indicator = app.staticTexts["reader.pageIndicator"]
    let area = app.descendants(matching: .any)["reader.pages"].firstMatch.frame
    let along = ["reader.pageStrip", "reader.selection.actionBar"]
      .map { app.descendants(matching: .any)[$0].firstMatch }.filter(\.exists).map(\.frame.minY)
    let lowest = (along + [area.maxY]).min()! - 24
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let from = origin.withOffset(CGVector(dx: area.minX + 40, dy: lowest))
    let to = origin.withOffset(CGVector(dx: area.minX + 40, dy: area.minY + 40))
    let before = placeOfThePages(in: app)
    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1)
    let pastTheFirst = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "2 of 3", "3 of 3")
    let moved =
      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: pastTheFirst, object: indicator)], timeout: 5)
      == .completed
    let notes =
      "the indicator says \(indicator.label); dragged from y \(lowest) to y \(area.minY + 40) at x \(area.minX + 40); "
      + "pages \(area); their place went from \(before) to \(placeOfThePages(in: app))"
    if !moved { keepEvidence(app, named: evidence, notes: notes) }
    return (moved, notes)
  }

  /// Where the pages are: the frame of PDFKit's own view of the document.
  ///
  /// That view is the first thing inside the pages' scroller. It moves when the pages are scrolled
  /// and grows when they are zoomed, so two readings that agree mean the page has done neither.
  private func placeOfThePages(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGRect {
    let pages = app.descendants(matching: .any)["reader.pages"].firstMatch
    let document = pages.scrollViews.firstMatch.children(matching: .any).firstMatch
    if !document.waitForExistence(timeout: Self.settleTimeout) {
      XCTFail("No view of the document inside the pages' scroller:\n\(pages.debugDescription)", file: file, line: line)
    }
    return document.frame
  }

  /// Whether two readings of the pages' place agree, to within a point.
  private func isSame(_ one: CGRect, _ other: CGRect) -> Bool {
    abs(one.minX - other.minX) < 1 && abs(one.minY - other.minY) < 1 && abs(one.width - other.width) < 1
      && abs(one.height - other.height) < 1
  }

  func testGoToPageJumpsToTheNumberTyped() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    app.buttons["reader.more"].tap()
    app.buttons["Go to page"].tap()
    // The alert's field has no identifier of its own: SwiftUI does not pass it to the system alert.
    let number = app.alerts.firstMatch.textFields.firstMatch
    XCTAssertTrue(number.waitForExistence(timeout: Self.settleTimeout), "Go to page asks for a number (FR-READ-002)")
    number.tap()
    number.typeText("2")
    app.alerts.buttons["Go"].tap()
    expectation(for: NSPredicate(format: "label CONTAINS %@", "2 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: Self.settleTimeout)
  }

  func testThePageStripMovesThroughTheDocumentAndStepsAsideForEditing() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    let strip = app.descendants(matching: .any)["reader.pageStrip"].firstMatch
    XCTAssertTrue(strip.waitForExistence(timeout: Self.settleTimeout), "A document of several pages has a page strip")
    try audit(app)

    // A tap on a small page shows that page, and again, back to the first.
    app.buttons["reader.pageStrip.3"].tap()
    expectation(for: NSPredicate(format: "label CONTAINS %@", "3 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: Self.settleTimeout)
    XCTAssertTrue(app.buttons["reader.pageStrip.3"].isSelected, "The strip marks the page in view")
    app.buttons["reader.pageStrip.1"].tap()
    expectation(for: NSPredicate(format: "label CONTAINS %@", "1 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: Self.settleTimeout)
    app.buttons["reader.pageStrip.2"].tap()
    expectation(for: NSPredicate(format: "label CONTAINS %@", "2 of 3"), evaluatedWith: indicator)
    waitForExpectations(timeout: Self.settleTimeout)

    // The strip steps aside while text is edited, and comes back after.
    let done = app.buttons["reader.doneEditingText"]
    tap(app.buttons["reader.edit"], until: done)
    XCTAssertFalse(strip.exists, "The strip leaves the bottom of the reader to the editor")
    let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Try these")).firstMatch
    let field = app.textViews["reader.textEdit.field"]
    tap(line, until: field)
    XCTAssertEqual(field.value as? String, "Try these:")
    app.buttons["reader.textEdit.cancel"].tap()
    done.tap()
    XCTAssertTrue(strip.waitForExistence(timeout: Self.settleTimeout), "The strip is back")

    // The strip can be put away.
    app.buttons["reader.more"].tap()
    let layout = app.buttons["Layout"]
    XCTAssertTrue(layout.waitForExistence(timeout: 5))
    layout.tap()
    let stripSwitch = app.buttons["Page strip"]
    XCTAssertTrue(stripSwitch.waitForExistence(timeout: 5))
    stripSwitch.tap()
    XCTAssertFalse(strip.waitForExistence(timeout: 2), "Switched off, the strip is gone")
  }

  func testWithoutTheReadingControlsTheReaderIsAsItWas() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-reading-controls", "off"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.descendants(matching: .any)["reader.pageStrip"].firstMatch.exists, "No page strip")
    app.buttons["reader.more"].tap()
    let layout = app.buttons["Layout"]
    XCTAssertTrue(layout.waitForExistence(timeout: 5))
    layout.tap()
    XCTAssertTrue(app.buttons["Single page"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Page strip"].exists, "No strip to switch")
  }

  func testDrawingAddsInkThatCanBeUndone() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let markup = app.buttons["reader.markup"]
    markup.tap()
    app.buttons["Draw"].tap()
    let done = app.buttons["reader.doneDrawing"]
    XCTAssertTrue(done.waitForExistence(timeout: Self.settleTimeout), "Drawing mode shows Done (F2a)")
    let area = app.descendants(matching: .any)["reader.drawing"].firstMatch
    XCTAssertTrue(area.waitForExistence(timeout: Self.settleTimeout))
    point(0.3, 0.4, in: area, of: app)
      .press(forDuration: 0.1, thenDragTo: point(0.7, 0.5, in: area, of: app))
    done.tap()
    markup.tap()
    let undo = app.buttons["Undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(undo.isEnabled, "The stroke was added and can be undone")
  }

  func testATypedSignatureIsPlacedOnThePage() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let markup = app.buttons["reader.markup"]
    let name = app.textFields["signature.typedName"]
    tapMenuItem(app.buttons["Signature"], in: markup, until: name)
    XCTAssertTrue(name.waitForExistence(timeout: Self.settleTimeout), "The signature sheet opens (F1c)")
    try audit(app, onSheet: true)
    name.tap()
    // Return closes the keyboard, so the audit measures the button rather than the keyboard over it.
    name.typeText("Ada Lovelace\n")
    try audit(app, onSheet: true)
    app.buttons["signature.placeTyped"].tap()
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: Self.settleTimeout))
    markup.tap()
    let undo = app.buttons["Undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(undo.isEnabled, "The signature was placed and can be undone")
  }

  /// A tester placed several arrows and found no way to take one back or to move one.
  func testAShapeIsUndoneFromTheBarAndSaysItCanBeMoved() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.markup"].tap()
    app.buttons["Shapes"].tap()
    app.buttons["Arrow"].tap()
    let area = app.descendants(matching: .any)["reader.drawing"].firstMatch
    XCTAssertTrue(area.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(app.staticTexts["Drag to draw. Drag a shape to move it."].waitForExistence(timeout: 5))
    let undo = app.buttons["reader.drawing.undo"]
    let redo = app.buttons["reader.drawing.redo"]
    XCTAssertTrue(undo.waitForExistence(timeout: 5), "Undo is in the bar while drawing")
    XCTAssertFalse(undo.isEnabled, "Nothing to undo yet")
    try audit(app)

    point(0.2, 0.6, in: area, of: app).press(forDuration: 0.1, thenDragTo: point(0.8, 0.6, in: area, of: app))
    XCTAssertTrue(waitUntil(undo, isEnabled: true), "The arrow can be undone")

    // A drag that starts on the arrow moves it: that is a second step to undo, not a second arrow.
    point(0.5, 0.6, in: area, of: app).press(forDuration: 0.2, thenDragTo: point(0.5, 0.75, in: area, of: app))
    XCTAssertTrue(
      app.staticTexts["Drag it to move it"].waitForExistence(timeout: 5), "The arrow was picked up, not drawn over")

    undo.tap()
    XCTAssertTrue(waitUntil(redo, isEnabled: true), "What was undone can be redone")
    undo.tap()
    XCTAssertTrue(waitUntil(undo, isEnabled: false), "Both steps are taken back")
    app.buttons["reader.doneDrawing"].tap()
    XCTAssertTrue(app.buttons["reader.markup"].waitForExistence(timeout: 5))
  }

  /// Waits for a control to become enabled or disabled.
  private func waitUntil(_ control: XCUIElement, isEnabled: Bool) -> Bool {
    let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: isEnabled))
    return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: control)], timeout: 10)
      == .completed
  }

  func testShapesAndTextBoxesAreAdded() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let markup = app.buttons["reader.markup"]
    markup.tap()
    app.buttons["Shapes"].tap()
    app.buttons["Rectangle"].tap()
    let area = app.descendants(matching: .any)["reader.drawing"].firstMatch
    XCTAssertTrue(area.waitForExistence(timeout: Self.settleTimeout), "Shapes are drawn like ink (F2b)")
    point(0.25, 0.3, in: area, of: app)
      .press(forDuration: 0.1, thenDragTo: point(0.7, 0.45, in: area, of: app))
    app.buttons["reader.doneDrawing"].tap()
    markup.tap()
    app.buttons["Text box"].tap()
    let text = app.alerts.firstMatch.textFields.firstMatch
    XCTAssertTrue(text.waitForExistence(timeout: Self.settleTimeout))
    text.tap()
    text.typeText("Check with accounts")
    app.alerts.buttons["Add"].tap()
    markup.tap()
    let undo = app.buttons["Undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.settleTimeout))
    XCTAssertTrue(undo.isEnabled, "The rectangle and the text box were added")
    // Undo alone doesn't prove the text box: the rectangle enables it too. The annotation list must
    // show the typed text, which it didn't while the prompt cleared its field too early.
    app.buttons["Highlight"].tap()
    app.buttons["reader.doneMarkup"].tap()
    let annotations = app.navigationBars["Annotations"]
    tapMenuItem(app.buttons["reader.annotations"], in: app.buttons["reader.more"], until: annotations)
    XCTAssertTrue(
      app.staticTexts["Check with accounts"].waitForExistence(timeout: Self.settleTimeout),
      "The text box carries what was typed")
  }

  func testDraggingAcrossTextWithTheHighlighterMarksItOnce() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    tapMenuItem(app.buttons["Highlight"], in: app.buttons["reader.markup"], until: app.buttons["reader.doneMarkup"])
    XCTAssertTrue(app.descendants(matching: .any)["reader.markupHint"].firstMatch.exists)
    let pages = app.descendants(matching: .any)["reader.pages"].firstMatch
    // Sideways across the top of the page, where its text is; twice, to show the marks don't stack.
    for _ in 0..<2 {
      point(0.1, 0.3, in: pages, of: app).press(forDuration: 0.1, thenDragTo: point(0.9, 0.42, in: pages, of: app))
    }
    XCTAssertTrue(app.buttons["reader.doneMarkup"].exists, "A sideways drag marks text; it doesn't leave the document")
    app.buttons["reader.doneMarkup"].tap()
    let annotations = app.navigationBars["Annotations"]
    tapMenuItem(app.buttons["reader.annotations"], in: app.buttons["reader.more"], until: annotations)
    let highlights = app.staticTexts.matching(NSPredicate(format: "label == %@", "Highlight"))
    XCTAssertTrue(highlights.firstMatch.waitForExistence(timeout: Self.settleTimeout), "The drag highlighted text")
    let count = highlights.count
    XCTAssertLessThanOrEqual(count, 12, "One mark a line, however often it is dragged over")
  }

  func testATappedAnnotationCanBeResizedAndDeleted() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.markup"].tap()
    app.buttons["Draw"].tap()
    let area = app.descendants(matching: .any)["reader.drawing"].firstMatch
    XCTAssertTrue(area.waitForExistence(timeout: Self.settleTimeout))
    point(0.3, 0.4, in: area, of: app)
      .press(forDuration: 0.1, thenDragTo: point(0.7, 0.44, in: area, of: app))
    app.buttons["reader.doneDrawing"].tap()
    let pages = app.descendants(matching: .any)["reader.pages"].firstMatch
    point(0.5, 0.42, in: pages, of: app).tap()
    let bar = app.descendants(matching: .any)["reader.selection.actionBar"].firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "Tapping the drawing selects it (F3)")
    try audit(app)
    tapMenuItem(app.buttons["Larger"], in: app.buttons["reader.selection.style"], until: bar)
    XCTAssertTrue(bar.waitForExistence(timeout: Self.settleTimeout), "Resizing keeps it selected (FR-ANN-005)")
    app.buttons["reader.selection.delete"].tap()
    XCTAssertFalse(bar.waitForExistence(timeout: 2), "Deleting clears the selection")
  }

  func testAWrongPasswordSaysSoAndTheRightOneOpensTheDocument() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "locked"])
    let field = app.secureTextFields["reader.password"]
    XCTAssertTrue(field.waitForExistence(timeout: 15), "A protected document asks for its password")
    field.tap()
    field.typeText("not-the-password\n")
    XCTAssertTrue(
      app.descendants(matching: .any)["reader.wrongPassword"].waitForExistence(timeout: Self.settleTimeout),
      "A wrong password says so and leaves the document closed")
    try audit(app)
    field.tap()
    field.typeText("open-sesame\n")
    XCTAssertTrue(
      app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: Self.settleTimeout), "The right one opens it")
  }

  func testADamagedFileSaysItCannotOpenAndNothingElseBreaks() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "damaged"])
    XCTAssertTrue(
      app.staticTexts["Can't open this document"].waitForExistence(timeout: 15),
      "A damaged file explains itself instead of crashing or showing a blank page")
    try audit(app)
  }
}
