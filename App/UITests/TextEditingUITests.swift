import XCTest

/// Editing the text already in a PDF (FR-EDIT-001).
@MainActor
final class TextEditingUITests: UITestCase {
  /// A line of the page that holds some text, as PDFKit exposes it; a tap on it picks it for editing.
  private func line(containing text: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  func testEditingALineChangesTheWordsOnThePage() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let done = app.buttons["reader.doneEditingText"]
    tap(app.buttons["reader.edit"], until: done)
    XCTAssertTrue(
      app.descendants(matching: .any)["reader.textEdit.hint"].firstMatch.waitForExistence(timeout: 10),
      "Text editing says how to start")
    try audit(app)

    // One tap on a line opens its editor, with the line's text in it.
    let heading = line(containing: "Try these", in: app)
    XCTAssertTrue(heading.waitForExistence(timeout: 15), "Editable text is offered line by line")
    let field = app.textFields["reader.textEdit.field"]
    tap(heading, until: field)
    XCTAssertEqual(field.value as? String, "Try these:")
    XCTAssertFalse(done.isEnabled, "Leaving waits until the text in hand is finished or cancelled")
    field.typeText(" now")
    app.buttons["reader.textEdit.done"].tap()

    // The page now reads the new words, and the change can be undone.
    XCTAssertTrue(line(containing: "Try these: now", in: app).waitForExistence(timeout: 20), "The line was changed")
    let undo = app.buttons["reader.textEdit.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: 5) && undo.isEnabled, "The edit can be undone")
    undo.tap()
    XCTAssertTrue(line(containing: "Try these:", in: app).waitForExistence(timeout: 20))
    XCTAssertFalse(line(containing: "Try these: now", in: app).exists, "Undo put the old words back")

    // Cancel leaves the text as it was.
    tap(line(containing: "Try these", in: app), until: field)
    field.typeText(" never")
    app.buttons["reader.textEdit.cancel"].tap()
    XCTAssertFalse(field.waitForExistence(timeout: 2))
    XCTAssertFalse(line(containing: "never", in: app).exists)

    done.tap()
    XCTAssertTrue(app.buttons["reader.edit"].waitForExistence(timeout: 5), "Done leaves text editing")
  }

  func testEditingWorksInTheSinglePageLayout() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    app.buttons["reader.more"].tap()
    let layout = app.buttons["Layout"]
    XCTAssertTrue(layout.waitForExistence(timeout: 5))
    layout.tap()
    let single = app.buttons["Single page"]
    XCTAssertTrue(single.waitForExistence(timeout: 5))
    single.tap()

    tap(app.buttons["reader.edit"], until: app.buttons["reader.doneEditingText"])
    let heading = line(containing: "Try these", in: app)
    XCTAssertTrue(heading.waitForExistence(timeout: 15))
    let field = app.textFields["reader.textEdit.field"]
    tap(heading, until: field)
    field.typeText(" now")
    app.buttons["reader.textEdit.done"].tap()
    // The paged layout holds on to the page it was showing; the new page must take its place.
    XCTAssertTrue(line(containing: "Try these: now", in: app).waitForExistence(timeout: 20), "The page shows the edit")
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.label.contains("1 of 3"), "Still on the page that was edited")
  }

  func testEditingIsLockedWithoutProAndAbsentWhenTheBuildDoesNotHaveIt() throws {
    let locked = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "locked"])
    XCTAssertTrue(locked.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let explanation = locked.alerts["Editing text needs Pro"]
    tap(locked.buttons["reader.edit"], until: explanation)
    explanation.buttons["OK"].tap()
    XCTAssertFalse(locked.buttons["reader.doneEditingText"].exists, "Nothing was entered")
    locked.terminate()

    let hidden = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "hidden"])
    XCTAssertTrue(hidden.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    XCTAssertTrue(hidden.buttons["reader.markup"].waitForExistence(timeout: 5))
    XCTAssertFalse(hidden.buttons["reader.edit"].exists, "A build without the feature shows nothing of it")
  }
}
