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
