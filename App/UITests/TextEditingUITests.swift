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
    XCTAssertEqual(app.buttons["reader.edit"].label, "Edit", "The button says what it does")
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
    XCTAssertTrue(indicator.label.contains("1 of 3"), "Still on the page that was edited, not \(indicator.label)")
  }

  /// Opening a document a second time used to leave the page view bound to the first load, so
  /// Edit turned on with nothing outlined and every tap ignored.
  func testEditingWorksAfterTheDocumentIsOpenedAgain() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available"])
    let indicator = app.staticTexts["reader.pageIndicator"]
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
    // Leave on another page, so the document is opened again where it was left.
    tapMenuItem(app.buttons["Go to page"], in: app.buttons["reader.more"], until: app.alerts.firstMatch)
    let number = app.alerts.firstMatch.textFields.firstMatch
    number.tap()
    number.typeText("3")
    app.alerts.buttons["Go"].tap()
    XCTAssertTrue(line(containing: "Your documents stay", in: app).waitForExistence(timeout: 15))

    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(indicator.waitForNonExistence(timeout: 10), "Back in the library")
    let document = app.staticTexts["Welcome to PDF Algo Pro"].firstMatch
    XCTAssertTrue(document.waitForExistence(timeout: 10))
    document.tap()
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))

    app.buttons["reader.edit"].tap()
    XCTAssertTrue(app.buttons["reader.doneEditingText"].waitForExistence(timeout: 10))
    let target = line(containing: "Your documents stay", in: app)
    XCTAssertTrue(target.waitForExistence(timeout: 15))
    // One tap, and no second try: a tap that is ignored is exactly the defect.
    target.tap()
    XCTAssertTrue(
      app.textFields["reader.textEdit.field"].waitForExistence(timeout: 10), "A tap on a line opens its editor")
  }

  func testEditingGoesOnAfterAnEditAfterLeavingAndAfterTheAppWasAway() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let done = app.buttons["reader.doneEditingText"]
    let field = app.textFields["reader.textEdit.field"]
    tap(app.buttons["reader.edit"], until: done)

    // One edit, then another line straight after it.
    tap(line(containing: "Try these", in: app), until: field)
    field.typeText(" now")
    app.buttons["reader.textEdit.done"].tap()
    XCTAssertTrue(line(containing: "Try these: now", in: app).waitForExistence(timeout: 20))
    let paragraph = line(containing: "This sample shows", in: app)
    XCTAssertTrue(paragraph.waitForExistence(timeout: 15))
    paragraph.tap()
    XCTAssertTrue(field.waitForExistence(timeout: 10), "A second line can be picked after an edit")
    app.buttons["reader.textEdit.cancel"].tap()

    // The line that was edited can be edited again.
    tap(line(containing: "Try these: now", in: app), until: field)
    XCTAssertEqual(field.value as? String, "Try these: now")
    app.buttons["reader.textEdit.cancel"].tap()

    // Leaving text editing and coming back.
    done.tap()
    tap(app.buttons["reader.edit"], until: done)
    line(containing: "Try these: now", in: app).tap()
    XCTAssertTrue(field.waitForExistence(timeout: 10), "Text can be picked after leaving and coming back")
    app.buttons["reader.textEdit.cancel"].tap()

    // The app going away and coming back, still in text editing.
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(done.waitForExistence(timeout: 15), "Text editing is still on")
    line(containing: "Try these: now", in: app).tap()
    XCTAssertTrue(field.waitForExistence(timeout: 10), "Text can be picked after the app was away")
  }

  /// The tip that points at Edit, as it is on a first open.
  private func editTip(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "reader.editTip").firstMatch
  }

  /// Leaves the reader and opens the sample document again.
  private func reopen(_ app: XCUIApplication) {
    let indicator = app.staticTexts["reader.pageIndicator"]
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(indicator.waitForNonExistence(timeout: 10), "Back in the library")
    let document = app.staticTexts["Welcome to PDF Algo Pro"].firstMatch
    XCTAssertTrue(document.waitForExistence(timeout: 10))
    document.tap()
    XCTAssertTrue(indicator.waitForExistence(timeout: 15))
  }

  func testTheEditTipShowsOnceAndStopsOnceEditIsUsed() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available", "-show-tips"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let tip = editTip(in: app)
    XCTAssertTrue(tip.waitForExistence(timeout: 10), "A first open points at Edit")
    XCTAssertTrue(app.staticTexts["Edit this PDF"].exists)
    try audit(app)

    // The tip is not in the way: one tap on Edit enters text editing, and the tip is gone.
    app.buttons["reader.edit"].tap()
    let done = app.buttons["reader.doneEditingText"]
    XCTAssertTrue(done.waitForExistence(timeout: 10), "One tap on Edit, with the tip showing")
    XCTAssertTrue(tip.waitForNonExistence(timeout: 5))
    done.tap()
    XCTAssertTrue(app.buttons["reader.edit"].waitForExistence(timeout: 5))

    // It has done its work, and does not come back.
    reopen(app)
    XCTAssertFalse(tip.waitForExistence(timeout: 4), "The tip is shown no more once Edit has been used")
  }

  func testTheEditTipStaysClosedAndIsNeverShownForALockedOrAbsentFeature() throws {
    let app = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", "available", "-show-tips"])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let tip = editTip(in: app)
    XCTAssertTrue(tip.waitForExistence(timeout: 10))
    app.buttons["reader.editTip.close"].tap()
    XCTAssertTrue(tip.waitForNonExistence(timeout: 5), "Its close button closes it")
    reopen(app)
    XCTAssertFalse(tip.waitForExistence(timeout: 4), "A tip that was closed stays closed")
    app.terminate()

    for access in ["locked", "hidden"] {
      let other = launch(["-skip-onboarding", "-seed-library", "sample", "-text-editing", access, "-show-tips"])
      XCTAssertTrue(other.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
      XCTAssertFalse(editTip(in: other).waitForExistence(timeout: 4), "No tip when editing is \(access)")
      other.terminate()
    }
  }

  /// An edit the engine cannot prove used to end in "This text can't be changed" with a Done
  /// button that could only refuse again.
  func testAnEditThatCannotBeProvenIsFinishedByCoveringAndSaysSo() throws {
    let app = launch([
      "-skip-onboarding", "-seed-library", "sample", "-text-editing", "available", "-text-editor", "unprovable",
    ])
    XCTAssertTrue(app.staticTexts["reader.pageIndicator"].waitForExistence(timeout: 15))
    let done = app.buttons["reader.doneEditingText"]
    tap(app.buttons["reader.edit"], until: done)
    let field = app.textFields["reader.textEdit.field"]
    tap(line(containing: "Try these", in: app), until: field)
    field.typeText(" now")

    // One tap on Done finishes: the typing is not lost, and the reader says what it did.
    app.buttons["reader.textEdit.done"].tap()
    let notice = app.staticTexts["reader.textEdit.notice"]
    XCTAssertTrue(notice.waitForExistence(timeout: 20), "The reader says the text was covered")
    XCTAssertTrue(notice.label.contains("still in the file"))
    XCTAssertFalse(field.exists, "The editor is not left open on a dead end")
    try audit(app)

    // Undo takes the cover away, and the notice with it.
    app.buttons["reader.textEdit.notice.undo"].tap()
    XCTAssertTrue(notice.waitForNonExistence(timeout: 10))
    XCTAssertTrue(done.isEnabled, "Text editing goes on")
    XCTAssertFalse(
      app.staticTexts["Tap any text to change it"].exists, "How to start is not said again once text was picked")

    // The next line on this page says it will be covered before anything is typed.
    tap(line(containing: "This sample shows", in: app), until: field)
    let message = app.staticTexts["reader.textEdit.message"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    XCTAssertTrue(message.label.contains("cover"), "Said before typing")
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
