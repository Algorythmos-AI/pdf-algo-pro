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

  // A rehearsal is not the edit under test: it goes straight to the real editor.
  func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
    await ContentStreamTextEditor().rehearsing(region, onPage: page)
  }

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

  @Test(
    "Only a document whose author allows both changing it and adding to it can be edited",
    arguments: [
      (CGPDFAccessPermissions.allowsDocumentChanges.rawValue, true),
      (CGPDFAccessPermissions.allowsCommenting.rawValue, true),
      (CGPDFAccessPermissions([.allowsDocumentChanges, .allowsCommenting]).rawValue, true),
      (CGPDFAccessPermissions.allowsFormFieldEntry.rawValue, false),
      (CGPDFAccessPermissions.allowsDocumentAssembly.rawValue, false),
      (CGPDFAccessPermissions([.allowsHighQualityPrinting, .allowsContentCopying]).rawValue, false),
      (UInt32(0), false),
    ])
  func permissions(granted: UInt32, editable: Bool) throws {
    // Opened without the owner password, so the author's restrictions apply. Core Graphics grants
    // changing the document and commenting together, so either one arrives as both.
    let controller = try open(
      TestPDFs.makeProtected(
        userPassword: nil, ownerPassword: "owner", permissions: CGPDFAccessPermissions(rawValue: granted))
    ).controller
    #expect(controller.textEditability == (editable ? .editable : .restricted))
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

  @Test("Editing one page of a long document costs about what it costs in a short one", .timeLimit(.minutes(5)))
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
    let long = try await time(pages: 120, page: 90)
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

@MainActor
@Suite("Text editing: undo memory")
struct TextEditingUndoMemoryTests {
  @Test("The undo history is shortened once the pages it keeps pass the limit")
  func bounded() throws {
    let controller = try PDFDocumentController(data: TextEditFixtures.invoice())
    #expect(controller.undoManager.levelsOfUndo == 0, "Unlimited until there is a reason")
    controller.limitUndoMemory(adding: 1_000_000)
    #expect(controller.undoManager.levelsOfUndo == 0 && controller.textUndoBytes == 1_000_000)
    controller.limitUndoMemory(adding: PDFDocumentController.undoMemoryLimit)
    #expect(controller.undoManager.levelsOfUndo == 32)
    #expect(controller.textUndoBytes <= PDFDocumentController.undoMemoryLimit)
    for _ in 0..<10 { controller.limitUndoMemory(adding: PDFDocumentController.undoMemoryLimit) }
    #expect(controller.undoManager.levelsOfUndo == 4, "Never shorter than a few steps")
  }
}

/// A door the test opens: work waits at it for as long as the test likes, whatever the machine's
/// speed, and does not stop waiting when the caller gives up.
private actor Gate {
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  /// How many pieces of work have gone through and answered.
  private(set) var answered = 0

  func pass() async {
    if !isOpen { await withCheckedContinuation { waiting.append($0) } }
  }

  func open() {
    isOpen = true
    for waiter in waiting { waiter.resume() }
    waiting = []
  }

  func noteAnswer() { answered += 1 }

  /// Waits until work that was let through has answered.
  func answers(_ count: Int) async {
    while answered < count { await Task.yield() }
  }
}

/// An editor that waits at a gate and answers even after it was given up on, as work that cannot
/// be interrupted does.
private struct HeldEditor: PDFTextEditing {
  var find: Gate?
  var edit: Gate?
  var rehearsal: Gate?

  func text(ofPage page: Data) async -> EditablePageText {
    await find?.pass()
    let text = await ContentStreamTextEditor().text(ofPage: page)
    await find?.noteAnswer()
    return text
  }

  // A rehearsal is not the edit under test: it goes straight to the real editor, unless held.
  func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
    await rehearsal?.pass()
    return await ContentStreamTextEditor().rehearsing(region, onPage: page)
  }

  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult {
    await edit?.pass()
    let result = await ContentStreamTextEditor().applying(edits, toPage: page)
    await edit?.noteAnswer()
    return result
  }
}

/// An editor that finds a page's text but can never prove an edit to it, as the native editor
/// could not for some documents; it counts how often it was asked to try.
private struct UnprovableEditor: PDFTextEditing {
  let rehearsals = Gate()
  /// Whether a rehearsal is honest (fails, as the edit will) or passes, so the failure comes
  /// only after the person has typed.
  var rehearsalsFail = true

  private var refused: TextEditResult {
    TextEditResult(
      page: nil, outcomes: [.refused(.notVerified)],
      proofFailure: TextEditProofFailure(.newTextMissing, measured: 0, expected: -14))
  }

  func text(ofPage page: Data) async -> EditablePageText { await ContentStreamTextEditor().text(ofPage: page) }

  func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
    await rehearsals.noteAnswer()
    return rehearsalsFail ? refused : await ContentStreamTextEditor().rehearsing(region, onPage: page)
  }

  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult { refused }
}

@MainActor
@Suite("Text editing: staying dependable")
struct TextEditingDependabilityTests {
  @Test("Finding text that passes its time limit is reported, kept out of the cache, and tried again")
  func findLimit() async throws {
    let gate = Gate()
    let (controller, _) = try open(TextEditFixtures.invoice(), editor: HeldEditor(find: gate))
    controller.textFindLimit = .milliseconds(50)
    controller.setEditingText(true)
    let late = await controller.pageText(onPage: 0)
    #expect(late.kind == .tookTooLong && late.regions.isEmpty)
    #expect(controller.textPages.isEmpty && controller.textEditingDiagnostics.pageKind == .timedOut)
    // The answer that was given up on arrives; it is not taken for an answer to anything.
    await gate.open()
    await gate.answers(1)
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.textPages.isEmpty)
    controller.textFindLimit = .seconds(600)
    let found = await controller.pageText(onPage: 0)
    #expect(found.kind == .text && found.regions.contains { $0.text.contains("John Smith") })
    #expect(controller.textEditingDiagnostics.pageKind == .text && controller.textEditingDiagnostics.direct > 0)
  }

  @Test("An edit that passes its time limit is refused, and its late answer never reaches the document")
  func editLimit() async throws {
    let gate = Gate()
    let (controller, url) = try open(TextEditFixtures.invoice(), editor: HeldEditor(edit: gate))
    controller.textFindLimit = .seconds(600)
    controller.textEditLimit = .milliseconds(50)
    #expect(try await edit(controller, containing: "John Smith", to: "Customer: David Smith") == .refused(.timedOut))
    #expect(controller.selectedTextRegion != nil, "What was typed is not lost: the text stays picked")
    #expect(controller.textEditingDiagnostics.lastEdit == .refused("timedOut"))
    await gate.open()
    await gate.answers(1)
    try await Task.sleep(for: .milliseconds(100))
    #expect(squeezed(controller).contains("JohnSmith") && !squeezed(controller).contains("David"))
    #expect(controller.contentEditedPages.isEmpty && !controller.hasUnsavedChanges && !controller.undoManager.canUndo)
    // With time enough, the same edit goes through.
    controller.clearTextRegionSelection()
    controller.textEditLimit = .seconds(600)
    #expect(try await edit(controller, containing: "John Smith", to: "Customer: David Smith").isEdited)
    try controller.save(to: url)
    #expect(EditProof.squeezed(try PDFDocumentController(url: url).pageText(at: 0)).contains("DavidSmith"))
  }

  @Test("The time limit hands back whichever comes first and drops the other")
  func within() async {
    #expect(await PDFDocumentController.within(.seconds(600)) { 7 } == 7)
    let gate = Gate()
    let held = await PDFDocumentController.within(.milliseconds(50)) {
      await gate.pass()
      return 7
    }
    #expect(held == nil)
    await gate.open()
  }

  @Test("The native editor stops when the work is given up on")
  func cancellation() async throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let work = Task { await ContentStreamTextEditor().text(ofPage: page) }
    work.cancel()
    let text = await work.value
    #expect(text.regions.isEmpty && text.kind == .unreadable, "Cancelled work offers nothing rather than half a page")
    #expect(await ContentStreamTextEditor().text(ofPage: page).kind == .text)
  }

  @Test("Text is picked by a tap at a point with no page view at all, and misses are counted")
  func pickingNeedsNoView() async throws {
    let (controller, _) = try open(TextEditFixtures.invoice())
    #expect(controller.view == nil)
    controller.setEditingText(true)
    let regions = await controller.pageText(onPage: 0).regions
    let target = try #require(regions.first { $0.text.contains("John Smith") })
    let middle = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
    #expect(await controller.selectTextRegion(at: CGPoint(x: -500, y: -500), onPage: 0, reach: 10) == false)
    #expect(await controller.selectTextRegion(at: middle, onPage: 0, reach: 10))
    #expect(controller.selectedTextRegion?.region == target)
    let record = controller.textEditingDiagnostics
    #expect(record.taps == 2 && record.picks == 1 && !record.viewIsBound && record.outlinedPages == 0)
  }

  @Test("Edit, save and open again, three times over, and every edit is still there")
  func editSaveReopenRepeatedly() async throws {
    var (controller, url) = try open(TextEditFixtures.invoice())
    let names = ["David Smith", "Maria Jones", "Peter Brown"]
    var current = "John Smith"
    for name in names {
      #expect(try await edit(controller, containing: current, to: "Customer: \(name)").isEdited, "\(name)")
      try controller.save(to: url)
      controller = try PDFDocumentController(url: url)
      #expect(squeezed(controller).contains(name.filter { !$0.isWhitespace }), "\(name) was saved")
      #expect(!squeezed(controller).contains(current.filter { !$0.isWhitespace }), "\(current) is gone")
      current = name
    }
    #expect(squeezed(controller).contains("Materials"), "The rest of the page is as it was")
  }

  @Test("The record for a problem report counts the page's text and how the edit ended")
  func diagnostics() async throws {
    let (controller, _) = try open(TextEditFixtures.invoice())
    var handed: [TextEditingDiagnostics] = []
    controller.onTextEditingDiagnostics = { handed.append($0) }
    #expect(try await edit(controller, containing: "John Smith", to: "Customer: David Smith").isEdited)
    let record = controller.textEditingDiagnostics
    #expect(record.pageKind == .text && record.direct + record.limited + record.coverOnly.values.reduce(0, +) > 0)
    #expect(record.lastEdit == .edited && handed.last == record)
    // Looking at the page again, as the reader does after an edit, keeps how the edit ended.
    _ = await controller.pageText(onPage: 0)
    #expect(controller.textEditingDiagnostics.lastEdit == .edited)
    let text = record.lines.joined(separator: " ")
    #expect(!text.contains("Smith") && !text.contains("Customer") && !text.contains("Helvetica"))
  }

  @Test("A page that cannot be edited is found out by a rehearsal, and offered for covering before anyone types")
  func rehearsalMarksAnUnprovablePage() async throws {
    let editor = UnprovableEditor()
    let (controller, url) = try open(TextEditFixtures.invoice(), editor: editor)
    let before = try Data(contentsOf: url)
    controller.setEditingText(true)
    // The lines are offered at once; the rehearsal follows, and then they say they will be covered.
    #expect(await controller.pageText(onPage: 0).regions.contains { $0.capability.editsContent })
    await controller.finishTextRehearsal(onPage: 0)
    let text = await controller.pageText(onPage: 0)
    #expect(text.kind == .text && !text.regions.isEmpty)
    #expect(text.regions.allSatisfy { !$0.capability.editsContent }, "Every line says it will be covered")
    let record = controller.textEditingDiagnostics
    #expect(record.rehearsalUnproven > 0 && record.rehearsalProven == 0)
    #expect(record.proofCheck == "newTextMissing" && record.proofMeasured == 0 && record.proofExpected == -14)
    #expect(record.direct == 0 && record.limited == 0)
    #expect(record.coverOnly.values.reduce(0, +) == text.regions.count && (record.coverOnly["notVerified"] ?? 0) > 0)
    // It is tried on a few lines, once: asking for the page again asks nothing more of the editor.
    let asked = await editor.rehearsals.answered
    #expect((1...3).contains(asked))
    _ = await controller.pageText(onPage: 0)
    #expect(await editor.rehearsals.answered == asked)
    // And it changed nothing.
    #expect(!controller.hasUnsavedChanges && !controller.undoManager.canUndo)
    #expect(try Data(contentsOf: url) == before)

    // Such a line is covered, as it said it would be.
    let region = try #require(text.regions.first { $0.text.contains("John Smith") })
    controller.selectTextRegion(region, onPage: 0)
    #expect(controller.coverSelectedText(with: "Customer: David Smith") == .edited(.visualReplacement))
    #expect(controller.textEditingDiagnostics.covered == 1)
  }

  @Test("A page that can be edited is left as it is by the rehearsal")
  func rehearsalLeavesAProvablePage() async throws {
    let (controller, _) = try open(TextEditFixtures.invoice())
    controller.setEditingText(true)
    _ = await controller.pageText(onPage: 0)
    await controller.finishTextRehearsal(onPage: 0)
    let text = await controller.pageText(onPage: 0)
    #expect(text.regions.contains { $0.capability.editsContent })
    let record = controller.textEditingDiagnostics
    #expect(record.rehearsalProven == 1, "One line was enough to know")
    #expect(record.rehearsalProven > 0 && record.rehearsalUnproven == 0 && record.proofCheck == nil)
    #expect(!controller.hasUnsavedChanges && controller.contentEditedPages.isEmpty)
  }

  @Test("A rehearsal never holds back the page's lines, and one that takes too long is given up on")
  func rehearsalDoesNotHoldBackThePage() async throws {
    let gate = Gate()
    var editor = HeldEditor()
    editor.rehearsal = gate
    let (controller, _) = try open(TextEditFixtures.invoice(), editor: editor)
    controller.textEditLimit = .milliseconds(50)
    controller.setEditingText(true)
    // The rehearsal is held, and the lines are there all the same.
    let text = await controller.pageText(onPage: 0)
    #expect(text.kind == .text && text.regions.contains { $0.capability.editsContent })
    await controller.finishTextRehearsal(onPage: 0)
    #expect(await controller.pageText(onPage: 0).regions.contains { $0.capability.editsContent }, "Nothing was learnt")
    #expect(controller.textEditingDiagnostics.rehearsalUnproven == 0)
    await gate.open()
  }

  @Test("An edit that could not be made can be finished by covering, and the page then says so up front")
  func coveringInsteadOfEditing() async throws {
    var editor = UnprovableEditor()
    editor.rehearsalsFail = false
    let (controller, _) = try open(TextEditFixtures.invoice(), editor: editor)
    controller.setEditingText(true)
    _ = await controller.pageText(onPage: 0)
    await controller.finishTextRehearsal(onPage: 0)
    #expect(try await edit(controller, containing: "John Smith", to: "Customer: David Smith") == .refused(.notVerified))
    let record = controller.textEditingDiagnostics
    #expect(record.proofCheck == "newTextMissing" && record.refusals == 1 && record.made == 0)
    // The text stays picked, and is editable as far as the engine said, so plain covering is refused…
    #expect(controller.selectedTextRegion?.region.capability.editsContent == true)
    #expect(controller.coverSelectedText(with: "Customer: David Smith") == .refused(.unsupportedDrawing))
    // …but covering to finish the edit is not.
    controller.markTextCoverOnly(onPage: 0)
    #expect(
      controller.coverSelectedText(with: "Customer: David Smith", insteadOfEditing: true) == .edited(.visualReplacement)
    )
    #expect(controller.annotationCount(onPage: 0) == 2 && squeezed(controller).contains("JohnSmith"))
    #expect(await controller.pageText(onPage: 0).regions.allSatisfy { !$0.capability.editsContent })
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0, "One step takes the cover back")
  }

  #if canImport(UIKit)
    @Test("A page view given another controller follows it, and lets go of the one it had")
    func viewFollowsItsController() async throws {
      let (first, _) = try open(TextEditFixtures.invoice())
      let (second, _) = try open(TextEditFixtures.invoice())
      let host = PDFReaderHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      host.configure(for: first)
      let gestures = host.gestureRecognizers?.count ?? 0
      #expect(first.view === host && host.document === first.document)
      first.setEditingText(true)
      #expect(host.isInMarkupMode)

      // The reader loaded its document again: the view on screen is handed the new controller.
      host.configure(for: second)
      #expect(second.view === host && first.view == nil && host.document === second.document)
      #expect(!host.isInMarkupMode, "The mode shown is the new controller's")
      #expect(host.gestureRecognizers?.count == gestures, "Binding again adds no second set of gestures")
      host.configure(for: second)
      #expect(host.gestureRecognizers?.count == gestures)

      // What the new controller asks of the view now reaches it; the old one's requests do not.
      second.setEditingText(true)
      #expect(host.isInMarkupMode)
      first.setEditingText(false)
      #expect(host.isInMarkupMode)
      second.setEditingText(false)
      #expect(!host.isInMarkupMode)
    }

    @Test("An outline that was hidden and put away by PDFKit shows again once text is being edited")
    func outlinesCannotGoStale() async throws {
      let (controller, _) = try open(TextEditFixtures.invoice())
      let host = PDFReaderHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      host.configure(for: controller)
      let page = try #require(controller.document.page(at: 0))
      let overlay = try #require(host.textOverlays.pdfView(host, overlayViewFor: page) as? TextRegionOverlayView)
      #expect(
        overlay.isHidden && overlay.gestureRecognizers?.isEmpty != false, "It draws and shields; it does not pick")
      // PDFKit stops showing the page's overlay, and keeps the view to show again later.
      host.textOverlays.pdfView(host, willEndDisplayingOverlayView: overlay, for: page)
      controller.setEditingText(true)
      #expect(!overlay.isHidden, "Shown at once from the mode; the regions follow")
      for _ in 0..<200 where overlay.regions.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
      #expect(overlay.regions.contains { $0.text.contains("John Smith") })
      controller.setEditingText(false)
      #expect(overlay.isHidden && overlay.regions.isEmpty)
      // Shown again by PDFKit while editing: it is refreshed as it comes back.
      controller.setEditingText(true)
      overlay.isHidden = true
      host.textOverlays.pdfView(host, willDisplayOverlayView: overlay, for: page)
      #expect(!overlay.isHidden)
    }

    @Test("A tap on the page view picks the text under it, with no outline on screen")
    func tapPicksWithoutAnOutline() async throws {
      let (controller, _) = try open(TextEditFixtures.invoice())
      let host = PDFReaderHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      host.configure(for: controller)
      host.layoutIfNeeded()
      controller.setEditingText(true)
      let page = try #require(controller.document.page(at: 0))
      let regions = await controller.pageText(onPage: 0).regions
      let target = try #require(regions.first { $0.text.contains("John Smith") })
      #expect(host.textOverlays.shownCount == 0)
      host.pickText(at: host.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), from: page))
      for _ in 0..<200 where controller.selectedTextRegion == nil { try await Task.sleep(for: .milliseconds(20)) }
      #expect(controller.selectedTextRegion?.region == target)
    }
  #endif
}
