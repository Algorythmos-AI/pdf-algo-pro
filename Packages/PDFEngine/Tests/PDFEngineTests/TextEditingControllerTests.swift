import Core
import CoreGraphics
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

private typealias Line = TextEditFixtures.Line

private func folder() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("text-edit-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

/// A document on disk, opened, as the reader has it.
@MainActor
private func open(
  _ data: Data, editor: any PDFTextEditing = ContentStreamTextEditor()
) throws
  -> (controller: PDFDocumentController, url: URL)
{
  let url = try folder().appendingPathComponent("doc.pdf")
  try data.write(to: url)
  return (try PDFDocumentController(url: url, textEditor: editor), url)
}

/// Picks the region containing some text and replaces it, as the reader does.
@MainActor
@discardableResult
private func edit(
  _ controller: PDFDocumentController, page: Int = 0, containing text: String, to replacement: String
) async throws -> TextEditOutcome {
  controller.setEditingText(true)
  let regions = await controller.pageText(onPage: page).regions
  let region = try #require(regions.first { $0.text.contains(text) }, "no region contains \(text)")
  controller.selectTextRegion(region, onPage: page)
  #expect(controller.selectedTextRegion?.region == region)
  return await controller.replaceSelectedText(with: replacement)
}

@MainActor
private func squeezed(_ controller: PDFDocumentController, page: Int = 0) -> String {
  EditProof.squeezed(controller.pageText(at: page))
}

/// An editor that does something to the document while an edit is being worked out, as a tap on
/// Undo or a reload could.
private struct InterferingEditor: PDFTextEditing {
  let interfere: @MainActor @Sendable () async -> Void

  func text(ofPage page: Data) async -> EditablePageText { await ContentStreamTextEditor().text(ofPage: page) }

  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult {
    let result = await ContentStreamTextEditor().applying(edits, toPage: page)
    await interfere()
    return result
  }
}

/// Holds a controller for an editor that has to be made before it.
@MainActor
private final class ControllerBox {
  var controller: PDFDocumentController?
  var outcomes: [TextEditOutcome] = []
}

@MainActor
@Suite("Text editing: the open document")
struct TextEditingControllerTests {
  @Test("Scenario 1: a name is changed, saved, and still changed when the file is opened again")
  func editSaveReopen() async throws {
    let (controller, url) = try open(TextEditFixtures.invoice())
    #expect(controller.textEditability == .editable)
    let outcome = try await edit(controller, containing: "John Smith", to: "Customer: David Smith")
    #expect(outcome == .edited(.contentStream))
    #expect(controller.hasUnsavedChanges && controller.selectedTextRegion == nil)
    #expect(squeezed(controller).contains("DavidSmith") && !squeezed(controller).contains("John"))

    let previous = url.deletingLastPathComponent().appendingPathComponent("previous.pdf")
    let original = try Data(contentsOf: url)
    try controller.save(to: url, keepingPreviousAt: previous)
    #expect(!controller.hasUnsavedChanges && controller.contentEditedPages.isEmpty)
    #expect(try Data(contentsOf: previous) == original, "The version before the edit is kept")

    let reopened = try PDFDocumentController(url: url)
    #expect(squeezed(reopened).contains("Customer:DavidSmith") && !squeezed(reopened).contains("John"))
    #expect(reopened.find("David Smith").count == 1 && reopened.find("John Smith").isEmpty)
    #expect(reopened.annotationCount(onPage: 0) == 0, "The text is in the page, not in an annotation")
    // Another reader sees the same: Core Graphics parses the file on its own.
    #expect(CGPDFDocument(url as CFURL)?.numberOfPages == 1)
    // And it can be edited again.
    #expect(try await edit(reopened, containing: "David Smith", to: "Customer: Dana Smith") == .edited(.contentStream))
  }

  @Test("An edit is undone and redone, alongside everything else")
  func undoRedo() async throws {
    let (controller, url) = try open(TextEditFixtures.invoice())
    try await edit(controller, containing: "John Smith", to: "Customer: David Smith")
    #expect(controller.undoManager.canUndo)
    controller.undoManager.undo()
    #expect(squeezed(controller).contains("JohnSmith") && !squeezed(controller).contains("David"))
    try controller.save(to: url)
    #expect(squeezed(try PDFDocumentController(url: url)).contains("JohnSmith"))
    controller.undoManager.redo()
    #expect(squeezed(controller).contains("DavidSmith") && !squeezed(controller).contains("John"))
    try controller.save(to: url)
    #expect(squeezed(try PDFDocumentController(url: url)).contains("DavidSmith"))
  }

  @Test("Edits, notes, markup and page changes undo and redo in order, each state as it was")
  func interleaved() async throws {
    let data = try TextEditFixtures.make(pages: [
      [Line("First page heading", at: CGPoint(x: 72, y: 700)), Line("First page body", at: CGPoint(x: 72, y: 680))],
      [Line("Second page heading", at: CGPoint(x: 72, y: 700))],
    ])
    let (controller, url) = try open(data)
    func state() -> [String] {
      (0..<controller.pageCount).map {
        "\(squeezed(controller, page: $0))|\(controller.annotationCount(onPage: $0))|\(controller.document.page(at: $0)?.rotation ?? 0)"
      }
    }
    // In the app each of these is its own event, so its own undo step; the test says so explicitly.
    controller.undoManager.groupsByEvent = false
    var states = [state()]
    func step(_ change: () async throws -> Void) async throws {
      controller.undoManager.beginUndoGrouping()
      try await change()
      controller.undoManager.endUndoGrouping()
      states.append(state())
    }
    try await step { try await edit(controller, containing: "First page heading", to: "Opening heading") }
    controller.setEditingText(false)
    try await step { controller.addNote("A comment", onPage: 0) }
    try await step { #expect(controller.markUp(text: "First page body", as: .highlight)) }
    try await step { try await edit(controller, page: 1, containing: "Second page heading", to: "Closing heading") }
    try await step { #expect(controller.rotatePages([1], by: 90)) }
    try await step { try await edit(controller, containing: "First page body", to: "Opening words") }
    try await step { #expect(controller.movePage(from: 0, to: 1)) }
    #expect(Set(states).count == states.count, "Every step changed something")

    for expected in states.dropLast().reversed() {
      controller.undoManager.undo()
      #expect(state() == expected)
    }
    #expect(!controller.undoManager.canUndo)
    for expected in states.dropFirst() {
      controller.undoManager.redo()
      #expect(state() == expected)
    }
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(
      squeezed(reopened, page: 1).contains("Openingheading") && squeezed(reopened, page: 1).contains("Openingwords"))
    #expect(reopened.annotationCount(onPage: 1) == controller.annotationCount(onPage: 1))
    #expect(squeezed(reopened, page: 0).contains("Closingheading"))
  }

  @Test("Scenario 4: highlights and notes on the page survive an edit, a save and reopening")
  func annotationsSurvive() async throws {
    let (controller, url) = try open(TextEditFixtures.lectureNotes())
    #expect(controller.markUp(text: "Ribosomes", as: .highlight))
    controller.addNote("Check this", onPage: 0)
    let before = controller.annotationSummaries()
    try await edit(
      controller, containing: "mitocondria", to: "The mitochondria is where the cell makes most of its energy.")
    #expect(controller.annotationSummaries() == before, "The same annotations, on the new page")
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(squeezed(reopened).contains("mitochondria") && !squeezed(reopened).contains("mitocondria"))
    let after = reopened.annotationSummaries()
    #expect(after.map(\.kind) == before.map(\.kind) && after.first { $0.kind == .note }?.text == "Check this")
    #expect(
      after.first { $0.kind == .highlight }?.text?.contains("Ribosomes") == true, "The highlight is still on its line")
  }

  @Test("Form fields keep their values and can still be filled after their page's text is edited")
  func formsSurvive() async throws {
    let (controller, url) = try open(TestPDFs.makeForm())
    for widget in controller.document.page(at: 0)?.annotations ?? [] where widget.fieldName == "name" {
      widget.widgetStringValue = "Ada Lovelace"
    }
    #expect(controller.hasChangedFormValues)
    #expect(try await edit(controller, containing: "Application form", to: "Membership form").isEdited)
    try controller.save(to: url)
    #expect(TestPDFs.storedValue(of: "name", in: url) == "Ada Lovelace")
    let reopened = try PDFDocumentController(url: url)
    #expect(squeezed(reopened).contains("Membershipform"))
    for widget in reopened.document.page(at: 0)?.annotations ?? [] where widget.fieldName == "name" {
      widget.widgetStringValue = "Grace Hopper"
    }
    try reopened.save(to: url)
    #expect(TestPDFs.storedValue(of: "name", in: url) == "Grace Hopper")
  }

  @Test("Scenario 3: bookmarks, the outline and the document's details survive an edit")
  func outlineAndMetadataSurvive() async throws {
    let (controller, url) = try open(TextEditFixtures.contract())
    #expect(controller.toggleBookmark(onPage: 0))
    let outline = controller.outline
    #expect(outline.contains { $0.title == "Agreement" && $0.pageIndex == 0 })
    let line = try #require(await controller.pageText(onPage: 0).regions.first { $0.text.contains("recieve") })
    try await edit(
      controller, containing: "recieve", to: line.text.replacingOccurrences(of: "recieve", with: "receive"))
    #expect(controller.outline == outline && controller.isBookmarked(0))
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(reopened.outline == outline && reopened.isBookmarked(0))
    #expect(squeezed(reopened).contains("receive") && !squeezed(reopened).contains("recieve"))
    let attributes = reopened.document.documentAttributes
    #expect(attributes?[PDFDocumentAttribute.titleAttribute] as? String == "Supply agreement")
    #expect(attributes?[PDFDocumentAttribute.authorAttribute] as? String == "Test author")
    #expect(squeezed(reopened, page: 1).contains("ScheduleA"), "The other page is untouched")
  }

  @Test("Links into an edited page still arrive there")
  func linksSurvive() async throws {
    let data = try TextEditFixtures.make(pages: [
      [Line("Target heading", at: CGPoint(x: 72, y: 700))], [Line("See the first page", at: CGPoint(x: 72, y: 700))],
    ])
    let document = try #require(PDFDocument(data: data))
    let link = PDFAnnotation(bounds: CGRect(x: 72, y: 695, width: 120, height: 16), forType: .link, withProperties: nil)
    link.destination = PDFDestination(page: try #require(document.page(at: 0)), at: CGPoint(x: 0, y: 792))
    document.page(at: 1)?.addAnnotation(link)
    let linked = try #require(document.dataRepresentation())
    let (controller, url) = try open(linked)
    try await edit(controller, containing: "Target heading", to: "Target title")
    try controller.save(to: url)
    let reopened = try #require(PDFDocument(url: url))
    let saved = try #require(reopened.page(at: 1)?.annotations.first { $0.type == "Link" })
    #expect(saved.destination?.page.map { reopened.index(for: $0) } == 0)
    // Undo sends the link back to the original page object.
    controller.undoManager.undo()
    let live = controller.document.page(at: 1)?.annotations.first { $0.type == "Link" }
    #expect(live?.destination?.page === controller.document.page(at: 0))
  }

  @Test("A password-protected document is edited in memory and stays protected on disk")
  func encrypted() async throws {
    let (controller, url) = try open(SyntheticPDF.makeEncrypted(pages: ["Secret: John Smith"], password: "open-sesame"))
    #expect(controller.textEditability == .restricted, "Locked: nothing can be read yet")
    #expect(await controller.pageText(onPage: 0).kind == .unreadable)
    #expect(controller.unlock(password: "open-sesame") && controller.textEditability == .editable)
    #expect(try await edit(controller, containing: "John Smith", to: "Secret: David Smith").isEdited)
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(reopened.isLocked && reopened.unlock(password: "open-sesame"))
    #expect(squeezed(reopened).contains("DavidSmith") && !squeezed(reopened).contains("John"))
  }

  @Test("A document whose author does not allow changes is refused, and nothing changes")
  func restricted() async throws {
    let (controller, _) = try open(
      TestPDFs.makeProtected(userPassword: nil, ownerPassword: "owner", permissions: [.allowsHighQualityPrinting]))
    #expect(controller.textEditability == .restricted)
    #expect(try await edit(controller, containing: "Protected", to: "Altered page") == .refused(.restricted))
    #expect(!controller.hasUnsavedChanges && squeezed(controller).contains("Protectedpage"))
    #expect(controller.coverSelectedText(with: "Altered") == .refused(.restricted))
    #expect(!controller.needsSaving, "Nothing to save")
  }

  @Test("A signed document says so, also when its signature could only be read after unlocking")
  func signed() throws {
    #expect(try open(TestPDFs.makeSigned(.signed)).controller.textEditability == .signed)
    #expect(try open(TestPDFs.makeSigned(.certified)).controller.textEditability == .signed)
    #expect(try open(TestPDFs.makeSigned(.unsigned)).controller.textEditability == .editable)
    let locked = try open(SyntheticPDF.makeEncrypted(pages: ["Locked"], password: "pw")).controller
    #expect(locked.digitalSignature == .none)
    #expect(locked.unlock(password: "pw") && locked.digitalSignature == .none)
  }

  @Test("Scenario 5: an image-only page says it has no text of its own")
  func scanned() async throws {
    let (controller, _) = try open(SyntheticPDF.makeImageOnly(pages: ["A scanned letter"]))
    controller.setEditingText(true)
    #expect(await controller.pageText(onPage: 0) == EditablePageText(regions: [], kind: .image))
    #expect(await !controller.selectTextRegion(at: CGPoint(x: 300, y: 400), onPage: 0, reach: 50))
    #expect(await controller.pageText(onPage: 9).kind == .unreadable, "No such page")
  }

  @Test("Text that cannot be edited is covered only when asked, and that is never called an edit")
  func coverAndReplace() async throws {
    let data = try TextEditFixtures.make(pages: [[Line("Plain line", at: CGPoint(x: 72, y: 700))]]) { context, _ in
      context.setAlpha(0.4)
      TextEditFixtures.draw(Line("Faded label", size: 24, at: CGPoint(x: 72, y: 500)), in: context)
    }
    let (controller, url) = try open(data)
    let outcome = try await edit(controller, containing: "Faded label", to: "Clear label")
    #expect(outcome == .refused(.unsupportedDrawing) && !controller.hasUnsavedChanges)
    #expect(controller.selectedTextRegion != nil, "The text stays picked so covering it can be offered")

    #expect(controller.coverSelectedText(with: "  ") == .refused(.unsupportedCharacters))
    #expect(controller.coverSelectedText(with: "Clear label") == .edited(.visualReplacement))
    #expect(controller.selectedTextRegion == nil && controller.annotationCount(onPage: 0) == 2)
    #expect(squeezed(controller).contains("Fadedlabel"), "The original text is still in the page")
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    let covering = reopened.annotationSummaries()
    #expect(Set(covering.map(\.kind)) == [.rectangle, .textBox] && covering.count == 2)
    #expect(covering.first { $0.kind == .textBox }?.text == "Clear label")
    // One undo removes the cover and the text together.
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0)

    // Text that can be edited directly is never covered.
    controller.setEditingText(true)
    let plain = try #require(await controller.pageText(onPage: 0).regions.first { $0.text == "Plain line" })
    controller.selectTextRegion(plain, onPage: 0)
    #expect(controller.coverSelectedText(with: "Other") == .refused(.unsupportedDrawing))
    controller.clearTextRegionSelection()
    #expect(controller.coverSelectedText(with: "Other") == .refused(.stale))
    #expect(await controller.replaceSelectedText(with: "Other") == .refused(.stale))
  }

  @Test("Several edits to a page are one undo step")
  func batchIsOneUndo() async throws {
    let (controller, _) = try open(TextEditFixtures.invoice())
    let regions = await controller.pageText(onPage: 0).regions
    let edits = [
      TextEdit(
        region: try #require(regions.first { $0.text.contains("John Smith") }), replacement: "Customer: David Smith"),
      TextEdit(region: try #require(regions.first { $0.text == "Materials" }), replacement: "Timber"),
    ]
    #expect(await controller.applyTextEdits(edits, onPage: 0) == [.edited(.contentStream), .edited(.contentStream)])
    #expect(squeezed(controller).contains("DavidSmith") && squeezed(controller).contains("Timber"))
    controller.undoManager.undo()
    #expect(squeezed(controller).contains("JohnSmith") && squeezed(controller).contains("Materials"))
    #expect(!controller.undoManager.canUndo)
    #expect(await controller.applyTextEdits([], onPage: 0).isEmpty)
    #expect(await controller.applyTextEdits(edits, onPage: 7) == [.refused(.stale), .refused(.stale)])
  }

  @Test("An edit worked out while the document changed underneath it is dropped, and nothing changes")
  func staleAfterAwait() async throws {
    let data = try TextEditFixtures.make(pages: [
      [Line("Customer: John Smith", at: CGPoint(x: 72, y: 700))], [Line("Second page", at: CGPoint(x: 72, y: 700))],
    ])
    let box = ControllerBox()
    let (controller, _) = try open(data, editor: InterferingEditor { box.controller?.movePage(from: 0, to: 1) })
    box.controller = controller
    #expect(try await edit(controller, containing: "John Smith", to: "Customer: David Smith") == .refused(.stale))
    #expect(squeezed(controller, page: 1).contains("JohnSmith") && !squeezed(controller, page: 1).contains("David"))
    #expect(controller.contentEditedPages.isEmpty)
  }

  @Test("A second edit started while one is being made is refused")
  func oneAtATime() async throws {
    let box = ControllerBox()
    let (controller, _) = try open(
      TextEditFixtures.invoice(),
      editor: InterferingEditor {
        guard let controller = box.controller else { return }
        let regions = controller.textPages.values.first?.text.regions ?? []
        guard let other = regions.first(where: { $0.text == "Materials" }) else { return }
        box.outcomes = await controller.applyTextEdits([TextEdit(region: other, replacement: "Timber")], onPage: 0)
      })
    box.controller = controller
    #expect(try await edit(controller, containing: "John Smith", to: "Customer: David Smith").isEdited)
    #expect(box.outcomes == [.refused(.stale)])
    #expect(squeezed(controller).contains("Materials"))
  }

  @Test("Text editing, drawing and annotation selection are separate modes")
  func modes() async throws {
    let (controller, _) = try open(TextEditFixtures.invoice())
    controller.addNote("A note", onPage: 0)
    let note = try #require(controller.document.page(at: 0)?.annotations.first)
    #expect(controller.selectAnnotation(at: CGPoint(x: note.bounds.midX, y: note.bounds.midY), onPage: 0))
    controller.setDrawing(true)
    controller.setEditingText(true)
    #expect(controller.isEditingText && !controller.isDrawing && controller.selection == nil)

    // A tap picks the nearest text within reach, and nothing further away.
    #expect(await !controller.selectTextRegion(at: CGPoint(x: 400, y: 300), onPage: 0, reach: 20))
    #expect(await controller.selectTextRegion(at: CGPoint(x: 80, y: 695), onPage: 0, reach: 20))
    #expect(controller.selectedTextRegion?.region.text == "Customer: John Smith")
    // While text is picked, another tap does not move the selection.
    #expect(await !controller.selectTextRegion(at: CGPoint(x: 80, y: 720), onPage: 0, reach: 20))
    #expect(controller.selectedTextRegion?.region.text == "Customer: John Smith")
    controller.clearTextRegionSelection()

    controller.setDrawing(true)
    #expect(controller.isDrawing && !controller.isEditingText)
    #expect(await !controller.selectTextRegion(at: CGPoint(x: 80, y: 672), onPage: 0, reach: 20))
    controller.linkTapped(try #require(URL(string: "https://example.com")))
    #expect(controller.tappedLink != nil)
    controller.dismissLink()
    controller.setEditingText(true)
    controller.linkTapped(try #require(URL(string: "https://example.com")))
    #expect(controller.tappedLink == nil, "A tap on linked text while editing does not follow the link")
  }

  @Test("On a page whose box does not start at the origin, text and annotations stay together")
  func offsetOrigin() async throws {
    let box = CGRect(x: 40, y: 60, width: 500, height: 700)
    let data = try TextEditFixtures.make(pages: [[Line("Offset origin text", at: CGPoint(x: 100, y: 600))]], box: box)
    let (controller, url) = try open(data)
    controller.setEditingText(true)
    let region = try #require(await controller.pageText(onPage: 0).regions.first)
    // Regions are in the live page's space, where the text was drawn.
    #expect(abs(region.bounds.minX - 100) < 0.5 && region.bounds.minY < 600 && region.bounds.maxY > 600)
    controller.setEditingText(false)
    #expect(controller.markUp(text: "Offset origin text", as: .highlight))
    let highlight = try #require(controller.document.page(at: 0)?.annotations.first)
    let gap = highlight.bounds.minX - region.bounds.minX

    try await edit(controller, containing: "Offset origin", to: "Offset origin words")
    let page = try #require(controller.document.page(at: 0))
    let moved = try #require(page.annotations.first)
    let words = try #require(page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine().first)
    #expect(abs((moved.bounds.minX - words.bounds(for: page).minX) - gap) < 1, "The highlight is still on the text")
    try controller.save(to: url)
    #expect(squeezed(try PDFDocumentController(url: url)).contains("Offsetoriginwords"))
    controller.undoManager.undo()
    #expect(abs((controller.document.page(at: 0)?.annotations.first?.bounds.minX ?? 0) - highlight.bounds.minX) < 0.01)
  }

  @Test("The save checks that an edited page reads in the written file as it does on screen")
  func stagedCheck() async throws {
    let (controller, _) = try open(TextEditFixtures.invoice())
    try await edit(controller, containing: "John Smith", to: "Customer: David Smith")
    let bytes = try #require(controller.document.dataRepresentation())
    let written = try #require(PDFDocument(data: bytes))
    #expect(controller.contentEdits(areIntactIn: written))
    let stale = try #require(PDFDocument(data: try TextEditFixtures.invoice()))
    #expect(!controller.contentEdits(areIntactIn: stale))
    #expect(!controller.contentEdits(areIntactIn: PDFDocument()))
  }

  @Test(
    "A save interrupted with a text edit pending leaves the original, or the new version and the kept one",
    arguments: PDFDocumentController.SaveStep.allCases)
  func interruptedSave(at step: PDFDocumentController.SaveStep) async throws {
    struct Injected: Error {}
    let (controller, url) = try open(TextEditFixtures.invoice())
    let previous = url.deletingLastPathComponent().appendingPathComponent("previous.pdf")
    let original = try Data(contentsOf: url)
    try await edit(controller, containing: "John Smith", to: "Customer: David Smith")

    PDFDocumentController.saveFault = { if $0 == step { throw Injected() } }
    defer { PDFDocumentController.saveFault = nil }
    #expect(throws: PDFEngineError.saveFailed) { try controller.save(to: url, keepingPreviousAt: previous) }
    #expect(controller.hasUnsavedChanges && !controller.contentEditedPages.isEmpty, "The edit is still there to save")
    if step == .replaced {
      #expect(squeezed(try PDFDocumentController(url: url)).contains("DavidSmith"))
      #expect(try Data(contentsOf: previous) == original)
    } else {
      #expect(try Data(contentsOf: url) == original, "The original is untouched")
    }
    PDFDocumentController.saveFault = nil
    try controller.save(to: url, keepingPreviousAt: previous)
    #expect(squeezed(try PDFDocumentController(url: url)).contains("DavidSmith"))
  }

  @Test("Editing one page of a long document costs about what it costs in a short one", .timeLimit(.minutes(3)))
  func longDocument() async throws {
    func time(pages: Int, page: Int) async throws -> Duration {
      let data = try TextEditFixtures.make(
        pages: (0..<pages).map { [Line("Customer: John Smith on page \($0)", at: CGPoint(x: 72, y: 700))] })
      let (controller, _) = try open(data)
      let clock = ContinuousClock()
      let start = clock.now
      #expect(try await edit(controller, page: page, containing: "John Smith", to: "Customer: David Smith").isEdited)
      return clock.now - start
    }
    let short = try await time(pages: 2, page: 1)
    let long = try await time(pages: 400, page: 250)
    // Finding the text and making the edit do not walk the document; only the save does.
    #expect(long < short * 4 + .seconds(1), "short \(short), long \(long)")
  }
}

/// Edited documents join the files that other readers check in CI (qpdf and PDFium).
extension GoldenCorpusTests {
  @MainActor
  @Test("Edited documents are exported for the independent readers")
  func editedDocumentsForValidation() async throws {
    let cases: [(String, Data, String, String, [String])] = [
      (
        "edited invoice", try TextEditFixtures.invoice(), "John Smith", "Customer: David Smith",
        ["Customer: David Smith", "$1,250.00"]
      ),
      (
        "edited resume", try TextEditFixtures.resume(hasRoom: true), "2024 Data Analyst", "2025 Senior Data Scientist",
        ["2025 Senior Data Scientist"]
      ),
      (
        "edited notes", try TextEditFixtures.lectureNotes(), "Ribosomes",
        "Ribosomes build proteins from amino acids, quickly.", ["quickly"]
      ),
    ]
    for (name, data, target, replacement, expected) in cases {
      let (controller, url) = try open(data)
      #expect(try await edit(controller, containing: target, to: replacement).isEdited)
      try controller.save(to: url)
      #expect(CGPDFDocument(url as CFURL)?.numberOfPages == controller.pageCount)
      try Self.exportForValidation(url, name: name, password: nil, expecting: expected)
    }
  }
}
