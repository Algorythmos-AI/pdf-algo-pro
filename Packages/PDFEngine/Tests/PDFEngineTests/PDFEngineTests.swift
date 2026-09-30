import Core
import CoreGraphics
import CoreTestSupport
import Foundation
import ImageIO
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

private func temporaryURL(_ name: String = "doc") -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).pdf")
}

private func write(_ data: Data) throws -> URL {
  let url = temporaryURL()
  try data.write(to: url)
  return url
}

@Suite("PDF inspection")
struct InspectorTests {
  @Test("A text PDF reports its pages and text layer")
  func textPDF() async throws {
    let url = try write(SyntheticPDF.makeSample())
    let inspection = try await PDFKitInspector().inspect(url)
    #expect(inspection.pageCount == 3)
    #expect(inspection.hasTextLayer && !inspection.isEncrypted)
    #expect(inspection.pages[1].text.contains("INV-2026-0042"))
  }

  @Test("A locked PDF is reported as encrypted, without text")
  func encryptedPDF() async throws {
    let url = try write(SyntheticPDF.makeEncrypted(pages: ["Secret"], password: "open-sesame"))
    let inspection = try await PDFKitInspector().inspect(url)
    #expect(inspection.isEncrypted && inspection.pages.isEmpty)
  }

  @Test("An image-only PDF has no text layer")
  func imageOnlyPDF() async throws {
    let url = try write(SyntheticPDF.makeImageOnly(pages: ["Scanned page"]))
    let inspection = try await PDFKitInspector().inspect(url)
    #expect(inspection.pageCount == 1 && !inspection.hasTextLayer)
  }

  @Test(
    "Damaged and non-PDF files are rejected, never crash (NFR-SEC-002)",
    arguments: [
      Data(), Data("hello".utf8), Data("%PDF-1.7\n%%EOF".utf8),
      Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }),
    ])
  func damagedFiles(data: Data) async throws {
    let url = try write(data)
    await #expect(throws: LibraryError.notAPDF) { try await PDFKitInspector().inspect(url) }
  }

  @Test func truncatedPDFDoesNotCrash() async throws {
    let sample = try SyntheticPDF.makeSample()
    let url = try write(sample.prefix(sample.count / 2))
    _ = try? await PDFKitInspector().inspect(url)
  }
}

@MainActor
@Suite("Document controller")
struct ControllerTests {
  @Test("One page's text is read without extracting the others")
  func singlePageText() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.make(pages: ["First page", "Second page"]))
    #expect(controller.pageText(at: 1).contains("Second page"))
    #expect(controller.pageText(at: 5).isEmpty)
  }

  @Test func textFindAndNavigation() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(controller.pageCount == 3 && !controller.isLocked)
    #expect(controller.pageTexts()[1].text.contains("Invoice number"))
    #expect(controller.find("inv-2026-0042").map(\.pageIndex) == [1])
    #expect(controller.find("   ").isEmpty)
    #expect(controller.outline.isEmpty)
    controller.goTo(pageIndex: 99)
    #expect(controller.currentPageIndex == 2)
    controller.goTo(pageIndex: -3)
    #expect(controller.currentPageIndex == 0)
  }

  @Test("Annotations undo, redo and survive a save (FR-ANN-001, FR-EDIT-007)")
  func annotationsRoundTrip() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(controller.markUp(text: "INV-2026-0042", as: .highlight))
    #expect(controller.annotationCount(onPage: 1) == 1 && controller.hasUnsavedChanges)
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 1) == 0)
    controller.undoManager.redo()
    #expect(controller.annotationCount(onPage: 1) == 1)
    controller.addNote("Check the date", onPage: 0)
    #expect(controller.annotationCount(onPage: 0) == 1)
    #expect(!controller.markUp(text: "not in this document", as: .underline))
    #expect(!controller.markUpSelection(.strikeThrough))

    let url = temporaryURL()
    try controller.save(to: url)
    #expect(!controller.hasUnsavedChanges)
    let reopened = try PDFDocumentController(url: url)
    #expect(reopened.annotationCount(onPage: 1) == 1)
    #expect(reopened.annotationCount(onPage: 0) == 1)
  }

  @Test("A save keeps the version from before it (FR-EDIT-008, first step)")
  func saveKeepsThePreviousVersion() throws {
    let url = try write(SyntheticPDF.makeSample())
    let before = try Data(contentsOf: url)
    let previous = temporaryURL("previous")
    try Data("stale".utf8).write(to: previous)
    let controller = try PDFDocumentController(url: url)
    controller.addNote("Check the date", onPage: 0)
    try controller.save(to: url, keepingPreviousAt: previous)
    #expect(try Data(contentsOf: previous) == before, "The kept version is the file as it was, replacing any older one")
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
  }

  @Test("A save without a kept version writes nothing else")
  func saveWithoutPreviousKeepsNothing() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("doc.pdf")
    try SyntheticPDF.makeSample().write(to: url)
    let controller = try PDFDocumentController(url: url)
    controller.addNote("Note", onPage: 0)
    let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    try controller.save(to: url)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == before)
  }

  @Test("A save needs room for the new file and a margin; unknown free space doesn't block it")
  func roomToSave() {
    let spare = PDFDocumentController.spareSpace
    #expect(PDFDocumentController.hasRoom(toWrite: 1_000, available: spare + 1_000))
    #expect(!PDFDocumentController.hasRoom(toWrite: 1_000, available: spare + 999))
    #expect(!PDFDocumentController.hasRoom(toWrite: 0, available: 0))
    #expect(PDFDocumentController.hasRoom(toWrite: 1_000_000_000, available: nil))
  }

  @Test("Form entries count as changes and are saved (defect D1)")
  func formEntriesAreSaved() throws {
    let controller = try PDFDocumentController(data: TestPDFs.makeForm())
    #expect(!controller.needsSaving, "Opening a form changes nothing")
    let widgets = try #require(controller.document.page(at: 0)?.annotations)
    let name = try #require(widgets.first { $0.fieldName == "name" })
    let agree = try #require(widgets.first { $0.fieldName == "agree" })

    name.widgetStringValue = "Ada Lovelace"
    #expect(controller.hasChangedFormValues && controller.needsSaving && !controller.hasUnsavedChanges)
    agree.buttonWidgetState = .onState
    controller.endEditing()
    let url = temporaryURL()
    try controller.save(to: url)
    #expect(!controller.needsSaving, "Saved values are the new baseline")

    #expect(TestPDFs.storedValue(of: "name", in: url) == "Ada Lovelace")
    #expect(TestPDFs.storedValue(of: "agree", in: url) == "Yes")
    let reopened = try PDFDocumentController(url: url)
    #expect(!reopened.needsSaving)
    let field = try #require(reopened.document.page(at: 0)?.annotations.first { $0.fieldName == "name" })
    field.widgetStringValue = "Ada Lovelace"
    #expect(!reopened.needsSaving, "Typing the same value again is not a change")
  }

  @Test("Documents without a form are not walked for fields")
  func noFormNoFields() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(controller.formValues.isEmpty && !controller.needsSaving)
    let locked = try PDFDocumentController(data: SyntheticPDF.makeEncrypted(pages: ["Secret"], password: "pw-123"))
    #expect(locked.formValues.isEmpty && !locked.needsSaving)
  }

  @Test("Drawn strokes become one standard ink annotation that survives a save and undoes (F2a)")
  func inkRoundTrip() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    let strokes = [
      [CGPoint(x: 100, y: 500), CGPoint(x: 160, y: 520), CGPoint(x: 220, y: 480)],
      [CGPoint(x: 120, y: 450), CGPoint(x: 200, y: 450)],
    ]
    #expect(!controller.addInk([[CGPoint(x: 1, y: 1)]], onPage: 0), "A dot is not a stroke")
    #expect(!controller.addInk(strokes, onPage: 99))
    #expect(controller.addInk(strokes, onPage: 0) && controller.hasUnsavedChanges)
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0)
    controller.undoManager.redo()

    let url = temporaryURL()
    try controller.save(to: url)
    let ink = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first { $0.type == "Ink" })
    #expect(ink.paths?.count == 2)
    #expect(ink.bounds.contains(CGPoint(x: 220, y: 480)) && ink.bounds.contains(CGPoint(x: 100, y: 500)))
  }

  @Test("Ink on a rotated page stays in page space, inside the page")
  func inkOnRotatedPage() throws {
    let document = try #require(PDFDocument(data: SyntheticPDF.make(pages: ["Rotated"])))
    document.page(at: 0)?.rotation = 90
    let controller = try PDFDocumentController(data: try #require(document.dataRepresentation()))
    #expect(controller.addInk([[CGPoint(x: 72, y: 72), CGPoint(x: 300, y: 600)]], onPage: 0))
    let url = temporaryURL()
    try controller.save(to: url)
    let page = try #require(PDFDocument(url: url)?.page(at: 0))
    let ink = try #require(page.annotations.first { $0.type == "Ink" })
    #expect(page.rotation == 90 && page.bounds(for: .mediaBox).contains(ink.bounds))
  }

  @Test("Strokes count only while drawing, and each one is reported")
  func drawingMode() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    var reported = 0
    controller.strokeEnded([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], onPage: 0)
    #expect(controller.annotationCount(onPage: 0) == 0, "Not drawing: ignored")
    controller.setDrawing(true) { reported += 1 }
    #expect(controller.isDrawing)
    controller.strokeEnded([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], onPage: 0)
    controller.strokeEnded([CGPoint(x: 10, y: 10)], onPage: 0)
    #expect(controller.annotationCount(onPage: 0) == 1 && reported == 1)
    controller.setDrawing(false)
    #expect(!controller.isDrawing)
  }

  @Test("A saved signature is placed as ink in the lower third of the page, the right way up (F1c)")
  func placeSignature() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    // A stroke from the top left to the bottom right of a signature twice as wide as it is tall.
    let signature = SavedSignature(strokes: [[.init(x: 0, y: 0), .init(x: 1, y: 1)]], aspectRatio: 2)
    #expect(!controller.placeSignature(signature, onPage: 9))
    #expect(controller.placeSignature(signature, onPage: 0, width: 200))
    let url = temporaryURL()
    try controller.save(to: url)
    let page = try #require(PDFDocument(url: url)?.page(at: 0))
    let ink = try #require(page.annotations.first { $0.type == "Ink" })
    #expect(ink.contents == PDFDocumentController.signatureContents)
    let box = page.bounds(for: .cropBox)
    #expect(abs(ink.bounds.midX - box.midX) < 1)
    #expect(ink.bounds.midY < box.midY, "Lower part of the page")
    #expect(abs(ink.bounds.width - (200 + PDFDocumentController.inkLineWidth * 4)) < 1)
    let path = try #require(ink.paths?.first)
    #expect(path.bounds.width > path.bounds.height, "Wider than tall, as drawn")
  }

  @Test("A typed name is placed as free text in a script font")
  func placeTypedSignature() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(!controller.placeTypedSignature("   ", onPage: 0))
    #expect(controller.placeTypedSignature(" Ada Lovelace ", onPage: 0))
    let url = temporaryURL()
    try controller.save(to: url)
    let text = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first { $0.type == "FreeText" })
    #expect(text.contents == "Ada Lovelace")
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0)
  }

  @Test(
    "Rectangles, ovals and arrows become standard annotations between the drag's ends (F2b)",
    arguments: [(DrawingTool.rectangle, "Square"), (.oval, "Circle"), (.arrow, "Line")])
  func shapes(tool: DrawingTool, type: String) throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(!controller.addShape(tool, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 101), onPage: 0))
    #expect(!controller.addShape(.pen, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), onPage: 0))
    #expect(controller.addShape(tool, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 400), onPage: 0))
    let url = temporaryURL()
    try controller.save(to: url)
    let shape = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first { $0.type == type })
    #expect(shape.bounds.contains(CGPoint(x: 200, y: 300)))
    #expect(shape.bounds.width >= 200 && shape.bounds.height >= 200)
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0)
  }

  @Test("The drawing tool decides what a stroke adds")
  func strokesFollowTheTool() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    controller.setDrawing(true, tool: .oval)
    #expect(controller.drawingTool == .oval)
    controller.strokeEnded([CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 120), CGPoint(x: 250, y: 200)], onPage: 0)
    #expect(controller.document.page(at: 0)?.annotations.first?.type == "Circle")
    controller.setDrawing(false)
  }

  @Test("A text box keeps its text and can be undone")
  func textBox() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(!controller.addTextBox("  ", onPage: 0))
    #expect(controller.addTextBox("Check this total\nwith accounts", onPage: 0))
    let url = temporaryURL()
    try controller.save(to: url)
    let box = try #require(PDFDocument(url: url)?.page(at: 0)?.annotations.first { $0.type == "FreeText" })
    #expect(box.contents == "Check this total\nwith accounts")
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0)
  }

  @Test("A tap selects the annotation under it; its text can be edited and it can be deleted, undoably (F3)")
  func selection() throws {
    // The note is saved and reopened, so the edits below are the only changes undo sees: in a test
    // every change happens in one run-loop event, which UndoManager groups together.
    let original = try PDFDocumentController(data: TestPDFs.makeForm())
    original.addNote("First", onPage: 0)
    let url = temporaryURL()
    try original.save(to: url)
    let controller = try PDFDocumentController(url: url)
    let box = try #require(controller.document.page(at: 0)?.bounds(for: .cropBox))
    let note = CGPoint(x: box.minX + 36, y: box.maxY - 36)
    #expect(controller.selectAnnotation(at: note, onPage: 0))
    #expect(controller.selection == AnnotationSelection(kind: .note, pageIndex: 0, text: "First"))
    #expect(controller.selection?.isTextEditable == true)

    #expect(!controller.setSelectionText("   "))
    #expect(controller.setSelectionText("Second") && controller.selection?.text == "Second")
    let annotation = try #require(controller.document.page(at: 0)?.annotations.first { $0.type == "Text" })
    #expect(annotation.contents == "Second")
    controller.undoManager.undo()
    #expect(annotation.contents == "First")

    let before = controller.annotationCount(onPage: 0)
    #expect(controller.deleteSelection() && controller.selection == nil)
    #expect(controller.annotationCount(onPage: 0) == before - 1)
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == before)
    #expect(!controller.deleteSelection(), "Nothing selected")

    #expect(!controller.selectAnnotation(at: CGPoint(x: 100, y: 610), onPage: 0), "Form fields are not selectable")
    #expect(!controller.selectAnnotation(at: CGPoint(x: box.midX, y: box.midY), onPage: 0))
    #expect(!controller.selectAnnotation(at: note, onPage: 9) && controller.selection == nil)
  }

  @Test("Every annotation type gets a kind")
  func annotationKinds() {
    let kinds: [(PDFAnnotationSubtype, AnnotationSelection.Kind)] = [
      (.highlight, .highlight), (.underline, .underline), (.strikeOut, .strikeThrough), (.text, .note), (.ink, .ink),
      (.square, .rectangle), (.circle, .oval), (.line, .line), (.freeText, .textBox), (.stamp, .stamp),
      (PDFAnnotationSubtype(rawValue: "/Caret"), .other),
    ]
    for (subtype, kind) in kinds {
      let annotation = PDFAnnotation(
        bounds: .init(x: 0, y: 0, width: 10, height: 10), forType: subtype, withProperties: nil)
      #expect(PDFDocumentController.kind(of: annotation) == kind, "\(subtype.rawValue)")
    }
    let link = PDFAnnotation(bounds: .init(x: 0, y: 0, width: 10, height: 10), forType: .link, withProperties: nil)
    #expect(!PDFDocumentController.isSelectable(link))
  }

  @Test("Every markup kind becomes a standard PDF annotation", arguments: TextMarkup.allCases)
  func markupKinds(markup: TextMarkup) throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(controller.markUp(text: "Your documents stay", as: markup))
    let url = temporaryURL()
    try controller.save(to: url)
    let page = try #require(PDFDocument(url: url)?.page(at: 2))
    #expect(!page.annotations.isEmpty)
  }

  @Test("A locked document opens only with the right password and stays encrypted when saved")
  func encryptedDocument() throws {
    let controller = try PDFDocumentController(
      data: SyntheticPDF.makeEncrypted(pages: ["Secret page"], password: "pw-123"))
    #expect(controller.isLocked)
    #expect(!controller.unlock(password: "wrong"))
    #expect(controller.unlock(password: "pw-123") && !controller.isLocked)
    #expect(controller.markUp(text: "Secret", as: .underline))
    let url = temporaryURL()
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(reopened.isLocked)
    #expect(reopened.unlock(password: "pw-123"))
    #expect(reopened.annotationCount(onPage: 0) == 1)
  }

  @Test("Restrictions set without an open password survive a save (defect D9)")
  func ownerOnlyRestrictionsSurvive() throws {
    let controller = try PDFDocumentController(
      data: TestPDFs.makeProtected(
        userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsCommenting, .allowsFormFieldEntry]))
    #expect(!controller.isLocked && controller.allowsAnnotating)
    #expect(controller.markUp(text: "Protected", as: .highlight))
    let url = temporaryURL()
    try controller.save(to: url)

    let reopened = try #require(PDFDocument(url: url))
    #expect(reopened.isEncrypted && !reopened.isLocked, "Still encrypted, still opens without a password")
    #expect(!reopened.allowsPrinting && !reopened.allowsCopying, "The author's restrictions are kept")
    #expect(reopened.page(at: 0)?.annotations.count == 1)
  }

  @Test("The user password never becomes the owner password (defect D9)")
  func userPasswordKeepsItsLimits() throws {
    let owner = "owner-\(UUID())"
    let controller = try PDFDocumentController(
      data: TestPDFs.makeProtected(
        userPassword: "user-pw", ownerPassword: owner, permissions: [.allowsCommenting, .allowsFormFieldEntry]))
    #expect(controller.unlock(password: "user-pw"))
    #expect(controller.markUp(text: "Protected", as: .underline))
    let url = temporaryURL()
    try controller.save(to: url)

    let reopened = try #require(PDFDocument(url: url))
    #expect(reopened.isLocked, "The user password is still needed to open it")
    #expect(reopened.unlock(withPassword: "user-pw"))
    #expect(reopened.permissionsStatus == .user && !reopened.allowsPrinting, "It grants no more than before")
    #expect(reopened.page(at: 0)?.annotations.count == 1)
  }

  @Test("A document opened with its owner password stays protected by it")
  func ownerPasswordProtectsTheSave() throws {
    let controller = try PDFDocumentController(
      data: TestPDFs.makeProtected(userPassword: "user-pw", ownerPassword: "owner-pw", permissions: []))
    #expect(controller.unlock(password: "owner-pw") && controller.allowsAnnotating)
    controller.addNote("Owner's note", onPage: 0)
    let url = temporaryURL()
    try controller.save(to: url)

    let reopened = try #require(PDFDocument(url: url))
    #expect(reopened.isLocked && reopened.unlock(withPassword: "owner-pw"))
    #expect(reopened.permissionsStatus == .owner)
  }

  @Test("Changes the author does not allow are refused and the file is left alone (defect D9)")
  func restrictedChangesAreRefused() throws {
    let data = try TestPDFs.makeProtected(
      userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsLowQualityPrinting])
    let url = try write(data)
    let controller = try PDFDocumentController(url: url)
    #expect(!controller.allowsAnnotating)
    controller.addNote("Not allowed", onPage: 0)
    #expect(throws: PDFEngineError.restricted) { try controller.save(to: url) }
    #expect(try Data(contentsOf: url) == data)
  }

  @Test("A failed save leaves the file as it was (NFR-REL-002)")
  func failedSaveKeepsFile() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    let missingFolder = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID())/doc.pdf")
    #expect(throws: PDFEngineError.saveFailed) { try controller.save(to: missingFolder) }
  }

  @Test("Metadata with a key that isn't UTF-8 is read without that key")
  func unreadableInfoKeyIsLeftOut() throws {
    let document = try #require(PDFDocument(data: TestPDFs.makeWithUnreadableInfoKey()))
    let attributes = document.readableAttributes
    #expect(attributes[PDFDocumentAttribute.titleAttribute.rawValue] as? String == "Damaged metadata")
    #expect(attributes[PDFDocumentAttribute.authorAttribute.rawValue] as? String == "Test author")
    #expect(attributes[PDFDocumentAttribute.keywordsAttribute.rawValue] as? [String] == ["corpus metadata"])
    #expect(attributes[PDFDocumentAttribute.creationDateAttribute.rawValue] is Date)
    #expect(attributes.count == 4)
  }

  @Test("A document whose metadata has a key that isn't UTF-8 saves, keeping the rest of its metadata")
  func unreadableInfoKeySaves() throws {
    let controller = try PDFDocumentController(data: TestPDFs.makeWithUnreadableInfoKey())
    controller.addNote("Checked", onPage: 0)
    let url = temporaryURL()
    try controller.save(to: url)
    let saved = try #require(PDFDocument(url: url))
    let attributes = saved.documentAttributes ?? [:]
    #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Damaged metadata")
    #expect(attributes[PDFDocumentAttribute.authorAttribute] as? String == "Test author")
    #expect(saved.page(at: 0)?.annotations.contains { $0.contents == "Checked" } == true)
    #expect(saved.string?.contains("Damaged metadata") == true)
  }

  @Test("Citations reveal their passage when it is on the cited page")
  func revealCitation() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(controller.reveal(Citation(pageIndex: 1, quote: "Invoice number: INV-2026-0042")))
    #expect(controller.currentPageIndex == 1)
    #expect(!controller.reveal(Citation(pageIndex: 0, quote: "Invoice number")))
    #expect(!controller.reveal(Citation(pageIndex: 2)))
    #expect(controller.currentPageIndex == 2)
  }

  @Test func unreadableDataThrows() {
    #expect(throws: PDFEngineError.unreadable) { try PDFDocumentController(data: Data("nope".utf8)) }
    #expect(throws: PDFEngineError.unreadable) { try PDFDocumentController(url: temporaryURL()) }
  }

  @Test func outlineIsFlattenedDepthFirst() throws {
    let document = try #require(PDFDocument(data: SyntheticPDF.make(pages: ["One", "Two", "Three"])))
    let root = PDFOutline()
    let chapter = PDFOutline()
    chapter.label = "Chapter"
    chapter.destination = PDFDestination(page: try #require(document.page(at: 1)), at: .zero)
    let section = PDFOutline()
    section.label = "Section"
    section.destination = PDFDestination(page: try #require(document.page(at: 2)), at: .zero)
    chapter.insertChild(section, at: 0)
    root.insertChild(chapter, at: 0)
    document.outlineRoot = root
    let controller = try PDFDocumentController(data: try #require(document.dataRepresentation()))
    #expect(controller.outline.map(\.title) == ["Chapter", "Section"])
    #expect(controller.outline.map(\.depth) == [0, 1])
    #expect(controller.outline.map(\.pageIndex) == [1, 2])
  }
}

@MainActor
@Suite("Toolkit: pages, flatten, images and passwords")
struct ToolkitTests {
  private func titles(_ controller: PDFDocumentController) -> [String] {
    controller.pageTexts().map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  private func three() throws -> PDFDocumentController {
    try PDFDocumentController(data: SyntheticPDF.make(pages: ["One", "Two", "Three"]))
  }

  @Test("Pages rotate, move and delete, each one undo step, and the result saves (FR-ORG-001)")
  func organise() throws {
    let controller = try three()
    // In the app each change is its own event, so its own undo step; here each is grouped by hand.
    controller.undoManager.groupsByEvent = false
    func step(_ change: () -> Bool) -> Bool {
      controller.undoManager.beginUndoGrouping()
      defer { controller.undoManager.endUndoGrouping() }
      return change()
    }
    #expect(step { controller.rotatePages([1], by: 90) })
    #expect(controller.document.page(at: 1)?.rotation == 90)
    #expect(step { controller.movePage(from: 2, to: 0) })
    #expect(titles(controller) == ["Three", "One", "Two"])
    #expect(step { controller.deletePages([1]) })
    #expect(titles(controller) == ["Three", "Two"])
    controller.undoManager.undo()
    #expect(titles(controller) == ["Three", "One", "Two"])
    controller.undoManager.undo()
    #expect(titles(controller) == ["One", "Two", "Three"])
    controller.undoManager.undo()
    #expect(controller.document.page(at: 1)?.rotation == 0)
    controller.undoManager.redo()
    #expect(controller.document.page(at: 1)?.rotation == 90)

    #expect(step { controller.movePage(from: 0, to: 2) })
    let url = temporaryURL()
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(titles(reopened) == ["Two", "Three", "One"])
    #expect(reopened.document.page(at: 0)?.rotation == 90)
  }

  @Test("Page changes that make no sense change nothing")
  func invalidPageChanges() throws {
    let controller = try three()
    #expect(!controller.deletePages([0, 1, 2]), "At least one page stays")
    #expect(!controller.deletePages([7]))
    #expect(!controller.deletePages([]))
    #expect(!controller.rotatePages([0], by: 45))
    #expect(!controller.rotatePages([0], by: 360))
    #expect(!controller.movePage(from: 0, to: 3))
    #expect(!controller.movePage(from: 1, to: 1))
    #expect(!controller.hasUnsavedChanges)
  }

  @Test("A document whose author forbids assembly can't be organised")
  func assemblyRestricted() throws {
    let controller = try PDFDocumentController(
      data: TestPDFs.makeProtected(userPassword: nil, ownerPassword: "owner-pw", permissions: []))
    #expect(!controller.allowsOrganizing)
    #expect(!controller.deletePages([0]))
    #expect(throws: PDFEngineError.restricted) { try controller.extractPages([0]) }
  }

  @Test("Extracted pages keep the document's order and their annotations")
  func extract() throws {
    let controller = try three()
    controller.addNote("Keep me", onPage: 2)
    let data = try controller.extractPages([2, 0])
    let extracted = try PDFDocumentController(data: data)
    #expect(titles(extracted) == ["One", "Three"])
    #expect(extracted.annotationCount(onPage: 1) == 1)
    #expect(controller.pageCount == 3, "The document itself is unchanged")
  }

  @Test("Flattening draws annotations into the page and keeps the text (FR-ORG-006)")
  func flatten() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    controller.addNote("Flattened", onPage: 0)
    #expect(controller.markUp(text: "INV-2026-0042", as: .highlight))
    let flat = try PDFDocumentController(data: controller.flattenedData())
    #expect(flat.pageCount == controller.pageCount)
    #expect((0..<flat.pageCount).allSatisfy { flat.annotationCount(onPage: $0) == 0 })
    #expect(!flat.find("INV-2026-0042").isEmpty, "Text stays text")
  }

  @Test(
    "Pages export as PNG and JPEG at the asked scale (FR-ORG-007)",
    arguments: PDFDocumentController.ImageFormat.allCases)
  func images(format: PDFDocumentController.ImageFormat) throws {
    let controller = try three()
    let data = try controller.imageData(ofPage: 0, format: format, scale: 1)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 612 && image.height == 792)
    #expect(throws: PDFEngineError.renderFailed) { try controller.imageData(ofPage: 9, format: format) }
  }

  @Test("Pictures become a PDF, one page each, fitted to A4 (FR-ORG-008)")
  func pdfFromPictures() throws {
    let wide = try #require(SyntheticPDF.makeTextImage("Wide", size: CGSize(width: 2000, height: 1000)))
    let small = try #require(SyntheticPDF.makeTextImage("Small", size: CGSize(width: 300, height: 400)))
    let controller = try PDFDocumentController(data: ImagePDF.make(from: [wide, small]))
    #expect(controller.pageCount == 2)
    #expect(controller.document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 842, height: 421))
    #expect(controller.document.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 300, height: 400))
    #expect(throws: PDFEngineError.saveFailed) { try ImagePDF.make(from: []) }
  }

  /// A page-sized picture with photographic noise, which lossless compression can't shrink, as in a scan.
  private func photoPDF() throws -> Data {
    let width = 1200
    let height = 1600
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    var seed: UInt32 = 42
    for index in 0..<(width * height) {
      seed = seed &* 1_664_525 &+ 1_013_904_223
      let value = UInt8(truncatingIfNeeded: (index % width) / 6 + Int(seed >> 27))
      pixels[index * 4] = value
      pixels[index * 4 + 1] = value &+ 40
      pixels[index * 4 + 2] = value &+ 80
    }
    let image = try #require(
      pixels.withUnsafeMutableBytes { buffer in
        CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?
          .makeImage()
      })
    return try ImagePDF.make(from: [image])
  }

  @Test("The email preset shrinks a scan and keeps its pages; nothing bigger is ever returned (FR-ORG-004)")
  func compress() throws {
    let original = try photoPDF()
    let controller = try PDFDocumentController(data: original)
    let email = try #require(try controller.compressed(.email, comparedTo: original.count))
    #expect(email.count < original.count / 2)
    #expect(try PDFDocumentController(data: email).pageCount == 1)
    let balanced = try controller.compressed(.balanced, comparedTo: original.count)
    #expect(balanced.map { $0.count < original.count } ?? true)
    #expect(try controller.compressed(.email, comparedTo: 1) == nil, "Never bigger than the original")
  }

  @Test("Compressing keeps text searchable")
  func compressKeepsText() throws {
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    let data = try #require(try controller.compressed(.email, comparedTo: .max))
    #expect(!(try PDFDocumentController(data: data)).find("INV-2026-0042").isEmpty)
  }

  @Test("A password can be added, and removed with the owner password only (FR-EDIT-006)")
  func passwords() throws {
    let controller = try three()
    #expect(!controller.canRemovePassword && !controller.removePassword())
    #expect(!controller.setPassword(""))
    #expect(controller.setPassword("secret") && controller.needsSaving)
    let url = temporaryURL()
    try controller.save(to: url)
    let locked = try PDFDocumentController(url: url)
    #expect(locked.isLocked)
    #expect(locked.unlock(password: "secret"))
    #expect(locked.canRemovePassword)
    #expect(locked.removePassword())
    try locked.save(to: url)
    let open = try PDFDocumentController(url: url)
    #expect(!open.isLocked && !open.document.isEncrypted)
    #expect(titles(open) == ["One", "Two", "Three"])
    locked.addNote("After", onPage: 0)
    try locked.save(to: url)
    #expect(try !PDFDocumentController(url: url).document.isEncrypted, "Later saves stay unencrypted")
  }

  @Test("A password that only opens the document can't remove the author's protection")
  func userPasswordCannotRemove() throws {
    let controller = try PDFDocumentController(
      data: TestPDFs.makeProtected(userPassword: "user-pw", ownerPassword: "owner-pw", permissions: []))
    #expect(controller.unlock(password: "user-pw"))
    #expect(!controller.canRemovePassword && !controller.removePassword())
    #expect(!controller.setPassword("mine"))
  }
}

/// The Trust suite's first promise: a save never loses the original (plan §4.1).
///
/// A save is interrupted at each step. Throwing there leaves the disk exactly as a crash at that point
/// would, because every step before the replace works on the staged copy and the replace is atomic.
@MainActor
@Suite("Trust: saves never lose the original", .serialized)
struct SaveFaultTests {
  struct Injected: Error {}

  @Test(
    "A save interrupted at any step leaves the original, or the new version and the kept one",
    arguments: PDFDocumentController.SaveStep.allCases)
  func interrupted(at step: PDFDocumentController.SaveStep) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trust-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("doc.pdf")
    let previous = folder.appendingPathComponent("previous.pdf")
    try SyntheticPDF.makeSample().write(to: url)
    let original = try Data(contentsOf: url)
    let controller = try PDFDocumentController(url: url)
    controller.addNote("Interrupted", onPage: 0)

    PDFDocumentController.saveFault = { if $0 == step { throw Injected() } }
    defer { PDFDocumentController.saveFault = nil }
    #expect(throws: PDFEngineError.saveFailed) { try controller.save(to: url, keepingPreviousAt: previous) }
    #expect(controller.hasUnsavedChanges, "The edit is still there to save again")

    let onDisk = try PDFDocumentController(url: url)
    if step == .replaced {
      #expect(onDisk.annotationCount(onPage: 0) == 1, "The new version is complete")
      #expect(try Data(contentsOf: previous) == original, "and the one before it is kept")
    } else {
      #expect(try Data(contentsOf: url) == original, "The original is untouched")
    }
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("save-") }
    #expect(leftovers.isEmpty, "No staged file is left behind")

    PDFDocumentController.saveFault = nil
    try controller.save(to: url, keepingPreviousAt: previous)
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1, "Saving again works")
  }

  @Test("Saving to a file that doesn't exist yet creates it")
  func newFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("new-\(UUID().uuidString).pdf")
    let controller = try PDFDocumentController(data: SyntheticPDF.makeSample())
    controller.addNote("New", onPage: 0)
    try controller.save(to: url, keepingPreviousAt: url.appendingPathExtension("previous"))
    #expect(try PDFDocumentController(url: url).annotationCount(onPage: 0) == 1)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("previous").path))
  }

  @Test("A saved file keeps every page, and the check reads it without loading it whole")
  func largeSaveKeepsPages() throws {
    let url = try write(SyntheticPDF.make(pages: (1...200).map { "Page \($0)" }))
    let controller = try PDFDocumentController(url: url)
    controller.addNote("Big", onPage: 199)
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(reopened.pageCount == 200 && reopened.annotationCount(onPage: 199) == 1)
  }
}

@Suite("Digital signatures")
struct DigitalSignatureTests {
  @Test("Signed, certified and unsigned documents are told apart (plan item H9)")
  func status() throws {
    #expect(DigitalSignatureStatus.of(data: TestPDFs.makeSigned(.signed)) == .signed)
    #expect(DigitalSignatureStatus.of(data: TestPDFs.makeSigned(.certified)) == .certified)
    #expect(DigitalSignatureStatus.of(data: TestPDFs.makeSigned(.unsigned)) == .none)
    #expect(DigitalSignatureStatus.of(data: try SyntheticPDF.makeSample()) == .none)
    #expect(DigitalSignatureStatus.of(data: Data("not a pdf".utf8)) == .none)
    let url = try write(TestPDFs.makeSigned(.signed))
    #expect(DigitalSignatureStatus.of(fileAt: url).isSigned)
  }

  @MainActor
  @Test("The controller reports the status of the file it opened")
  func controller() throws {
    #expect(try PDFDocumentController(url: write(TestPDFs.makeSigned(.certified))).digitalSignature == .certified)
    #expect(try PDFDocumentController(data: TestPDFs.makeSigned(.signed)).digitalSignature == .signed)
    #expect(try PDFDocumentController(data: SyntheticPDF.makeSample()).digitalSignature == .none)
  }

  @Test("Malformed files never hang or crash the check", arguments: GoldenCorpus.malformed())
  func malformed(_ item: GoldenCorpus.Malformed) {
    _ = DigitalSignatureStatus.of(data: item.data)
  }
}

@Suite("Document details (FR-LIB-008)")
struct DocumentDetailsTests {
  @Test("Metadata, version, pages, size and permissions are read")
  func details() throws {
    let url = try write(TestPDFs.makeWithUnreadableInfoKey())
    let details = try #require(DocumentDetails.of(fileAt: url))
    #expect(details.author == "Test author" && details.pageCount == 1 && details.version == "1.7")
    let size = try Data(contentsOf: url).count
    #expect(details.created != nil && details.fileSize == size)
    #expect(!details.isEncrypted && details.allowsPrinting && details.allowsCopying)
  }

  @Test("A locked document shows its protection and no pages; a non-PDF has no details")
  func lockedAndBroken() throws {
    let locked = try write(
      TestPDFs.makeProtected(userPassword: "pw", ownerPassword: "owner", permissions: []))
    let details = try #require(DocumentDetails.of(fileAt: locked))
    #expect(details.isEncrypted && details.pageCount == 0)
    #expect(DocumentDetails.of(fileAt: try write(Data("not a pdf".utf8))) == nil)
  }

  @Test("Malformed files never crash the details", arguments: GoldenCorpus.malformed())
  func malformed(_ item: GoldenCorpus.Malformed) throws {
    _ = DocumentDetails.of(fileAt: try write(item.data))
  }
}

@Suite("Merging (FR-LIB-009)")
struct MergeTests {
  @Test("Documents merge in order with their pages and annotations; locked or broken ones stop it")
  @MainActor
  func merge() throws {
    let first = try write(SyntheticPDF.make(pages: ["One", "Two"]))
    let annotated = try PDFDocumentController(data: SyntheticPDF.make(pages: ["Three"]))
    annotated.addNote("Kept", onPage: 0)
    let second = temporaryURL()
    try annotated.save(to: second)
    let merged = try PDFDocumentController(data: PDFMerge.merge([first, second]))
    #expect(
      merged.pageTexts().map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } == ["One", "Two", "Three"])
    #expect(merged.annotationCount(onPage: 2) == 1)
    let locked = try write(TestPDFs.makeProtected(userPassword: "pw", ownerPassword: "o", permissions: []))
    #expect(throws: PDFEngineError.passwordRequired) { try PDFMerge.merge([first, locked]) }
    #expect(throws: PDFEngineError.unreadable) { try PDFMerge.merge([first, try write(Data("x".utf8))]) }
    #expect(throws: PDFEngineError.saveFailed) { try PDFMerge.merge([]) }
  }
}

@Suite("Rendering")
struct RenderingTests {
  @Test func pagesRenderAtTheRequestedSize() throws {
    let url = try write(SyntheticPDF.makeSample())
    let image = try PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 400)
    #expect(image.height == 400 && image.width < 400)
    #expect(throws: PDFEngineError.renderFailed) {
      try PageRenderer.render(pageIndex: 7, of: url, maximumPixelSize: 100)
    }
    #expect(throws: PDFEngineError.unreadable) {
      try PageRenderer.render(pageIndex: 0, of: temporaryURL(), maximumPixelSize: 100)
    }
  }

  @Test func lockedPagesDoNotRender() throws {
    let url = try write(SyntheticPDF.makeEncrypted(pages: ["x"], password: "pw"))
    #expect(throws: PDFEngineError.passwordRequired) {
      try PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 100)
    }
  }

  @Test func thumbnailsAreCachedPerVersion() async throws {
    let url = try write(SyntheticPDF.makeSample())
    let cache = ThumbnailCache()
    let first = await cache.thumbnail(for: url, version: .distantPast)
    let second = await cache.thumbnail(for: url, version: .distantPast)
    #expect(first != nil && first === second)
    #expect(await cache.thumbnail(for: temporaryURL(), version: .now) == nil)
  }
}

@Suite("Searchable PDFs")
struct SearchablePDFTests {
  private struct ScriptedRecognizer: TextRecognizing {
    func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
      [
        RecognizedLine(
          text: "Quarterly report", bounds: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.04), confidence: 0.95)
      ]
    }
  }

  @Test("Scans become PDFs whose text can be found and selected (FR-SCAN-002)")
  func scansGetATextLayer() async throws {
    let images = try [
      #require(SyntheticPDF.makeTextImage("Page one")), #require(SyntheticPDF.makeTextImage("Page two")),
    ]
    let progress = ProgressLog()
    let result = try await SearchablePDFBuilder(recognizer: ScriptedRecognizer()).makeSearchablePDF(from: images) {
      progress.append($0)
    }
    let document = try #require(PDFDocument(data: result.data))
    #expect(document.pageCount == 2)
    #expect(document.page(at: 1)?.string?.contains("Quarterly report") == true)
    #expect(result.pages.map(\.text) == ["Quarterly report", "Quarterly report"])
    #expect(progress.values == [0.5, 1])
  }

  @Test("Image-only PDFs gain a text layer and keep their pages (FR-SCAN-003)")
  func imageOnlyPDFsGainText() async throws {
    let url = try write(SyntheticPDF.makeImageOnly(pages: ["One", "Two", "Three"]))
    let result = try await SearchablePDFBuilder(recognizer: FakeRecognizer(), renderPixelSize: 600).addTextLayer(
      toPDFAt: url)
    let document = try #require(PDFDocument(data: result.data))
    #expect(document.pageCount == 3)
    #expect(document.string?.contains("Recognised text") == true)
    let inspection = try await PDFKitInspector().inspect(try write(result.data))
    #expect(inspection.hasTextLayer)
  }

  @Test("Adding a text layer keeps annotations, links, rotation, the outline and the metadata")
  func textLayerKeepsWhatWasAdded() async throws {
    let source = try #require(PDFDocument(data: SyntheticPDF.makeImageOnly(pages: ["One", "Two"])))
    let first = try #require(source.page(at: 0))
    let second = try #require(source.page(at: 1))
    let note = PDFAnnotation(bounds: CGRect(x: 40, y: 40, width: 24, height: 24), forType: .text, withProperties: nil)
    note.contents = "Check the total"
    first.addAnnotation(note)
    let link = PDFAnnotation(bounds: CGRect(x: 80, y: 80, width: 100, height: 20), forType: .link, withProperties: nil)
    link.destination = PDFDestination(page: second, at: CGPoint(x: 0, y: 500))
    first.addAnnotation(link)
    second.rotation = 90
    let outline = PDFOutline()
    let entry = PDFOutline()
    entry.label = "Totals"
    entry.destination = PDFDestination(page: second, at: .zero)
    outline.insertChild(entry, at: 0)
    source.outlineRoot = outline
    source.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Invoice"]
    let url = try write(try #require(source.dataRepresentation()))

    let result = try await SearchablePDFBuilder(recognizer: FakeRecognizer(), renderPixelSize: 600).addTextLayer(
      toPDFAt: url)

    let document = try #require(PDFDocument(data: result.data))
    let page = try #require(document.page(at: 0))
    #expect(document.string?.contains("Recognised text") == true)
    #expect(page.annotations.contains { $0.type == "Text" && $0.contents == "Check the total" })
    let movedLink = try #require(page.annotations.first { $0.type == "Link" })
    #expect(movedLink.destination?.page.map { document.index(for: $0) } == 1)
    #expect(document.page(at: 1)?.rotation == 90)
    let movedEntry = try #require(document.outlineRoot?.child(at: 0))
    #expect(movedEntry.label == "Totals" && movedEntry.destination?.page.map { document.index(for: $0) } == 1)
    #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Invoice")
  }

  @Test("Adding a text layer to a document whose metadata has a key that isn't UTF-8 keeps the rest")
  func textLayerWithUnreadableInfoKey() async throws {
    let url = try write(TestPDFs.makeWithUnreadableInfoKey())
    let result = try await SearchablePDFBuilder(recognizer: FakeRecognizer(), renderPixelSize: 600).addTextLayer(
      toPDFAt: url)
    let document = try #require(PDFDocument(data: result.data))
    #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Damaged metadata")
  }

  @Test("Recognition resumes: pages already done are reused, and each new page is handed back (P8)")
  func textLayerResumes() async throws {
    let url = try write(SyntheticPDF.makeImageOnly(pages: ["One", "Two", "Three"]))
    let kept = [
      RecognizedLine(text: "Kept from before", bounds: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.05), confidence: 1)
    ]
    let handedBack = PageLog()
    let progress = ProgressLog()
    let result = try await SearchablePDFBuilder(recognizer: FakeRecognizer(), renderPixelSize: 400).addTextLayer(
      toPDFAt: url, resuming: [1: kept], onPage: { index, _ in handedBack.append(index) },
      progress: { progress.append($0) })
    #expect(handedBack.values == [0, 2], "Only the pages not done before are recognised")
    #expect(result.pages.map(\.text) == ["Recognised text", "Kept from before", "Recognised text"])
    #expect(progress.values.last == 1)
  }

  @Test func lockedAndUnreadablePDFsAreRejected() async throws {
    let builder = SearchablePDFBuilder(recognizer: FakeRecognizer())
    let locked = try write(SyntheticPDF.makeEncrypted(pages: ["x"], password: "pw"))
    await #expect(throws: PDFEngineError.passwordRequired) { try await builder.addTextLayer(toPDFAt: locked) }
    await #expect(throws: PDFEngineError.unreadable) { try await builder.addTextLayer(toPDFAt: temporaryURL()) }
  }
  @Test("Encrypted PDFs are not given a text layer, which would drop their protection (defect D9)")
  func encryptedPDFsAreNotRebuilt() async throws {
    let url = try write(
      TestPDFs.makeProtected(userPassword: nil, ownerPassword: "owner-\(UUID())", permissions: [.allowsCommenting]))
    let builder = SearchablePDFBuilder(recognizer: FakeRecognizer(), renderPixelSize: 400)
    await #expect(throws: PDFEngineError.restricted) { try await builder.addTextLayer(toPDFAt: url) }
  }

  @Test("Cancelling stops recognition between pages")
  func cancellation() async throws {
    let image = try #require(SyntheticPDF.makeTextImage("x", size: CGSize(width: 100, height: 100)))
    let builder = SearchablePDFBuilder(recognizer: FakeRecognizer())
    let task = Task { try await builder.makeSearchablePDF(from: Array(repeating: image, count: 50)) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}

private final class ProgressLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Double] = []
  var values: [Double] { lock.withLock { storage } }
  func append(_ value: Double) { lock.withLock { storage.append(value) } }
}

@MainActor
/// Serialized: the cases share the main actor, and the large round trips (500 and 1,000 pages) would
/// otherwise hold it while the malformed cases' time limits run (issue #111).
@Suite("Golden corpus", .serialized)
struct GoldenCorpusTests {
  @Test(
    "Every readable document opens, renders, searches, annotates and saves (W3.1, FR-READ-001)",
    arguments: GoldenCorpus.cases)
  func roundTrip(_ item: GoldenCorpus.Case) throws {
    try Self.check(item)
  }

  @Test(
    "Malformed and fuzzed files fail cleanly or open; none crashes or hangs", .timeLimit(.minutes(3)),
    arguments: GoldenCorpus.malformed())
  func malformed(_ item: GoldenCorpus.Malformed) async throws {
    let url = try write(item.data)
    _ = try? await PDFKitInspector().inspect(url)
    guard let controller = try? PDFDocumentController(url: url) else { return }
    _ = controller.pageTexts()
    _ = controller.find("page")
    _ = controller.outline
    for index in 0..<min(controller.pageCount, 3) {
      _ = try? PageRenderer.render(pageIndex: index, of: url, maximumPixelSize: 200)
    }
    guard controller.pageCount > 0, !controller.isLocked else { return }
    controller.addNote("Corpus note", onPage: 0)
    _ = try? controller.save(to: temporaryURL())
  }

  /// Copies a saved file for the independent checks in CI (plan §3 B2).
  ///
  /// qpdf then reads every file this suite saves. Only when `PDF_VALIDATION_OUT` names a folder; a
  /// password goes beside it.
  private static func exportForValidation(_ url: URL, name: String, password: String?) throws {
    guard let folder = ProcessInfo.processInfo.environment["PDF_VALIDATION_OUT"], !folder.isEmpty else { return }
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safe = name.map { $0.isLetter || $0.isNumber ? $0 : "-" }
    let target = directory.appendingPathComponent(String(safe) + ".pdf")
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.copyItem(at: url, to: target)
    if let password {
      try Data(password.utf8).write(to: target.deletingPathExtension().appendingPathExtension("password"))
    }
  }

  private static func check(_ item: GoldenCorpus.Case) throws {
    let url = try write(item.make())
    let controller = try PDFDocumentController(url: url)
    if let password = item.password {
      #expect(controller.isLocked)
      #expect(controller.unlock(password: password))
    } else {
      // Pages of a document with an open password render only after unlocking, which the renderer
      // does not do; `lockedPagesDoNotRender` covers that.
      for index in Set([0, item.pageCount - 1]) {
        let image = try PageRenderer.render(pageIndex: index, of: url, maximumPixelSize: 300)
        #expect(max(image.width, image.height) <= 300, "\(item.name), page \(index + 1)")
      }
    }
    #expect(!controller.isLocked && controller.pageCount == item.pageCount, "\(item.name)")
    if let word = item.searchable { #expect(!controller.find(word).isEmpty, "\(item.name): \(word)") }
    #expect(controller.allowsAnnotating == item.allowsAnnotating, "\(item.name)")
    guard item.allowsAnnotating else { return }

    let before = controller.annotationCount(onPage: 0)
    controller.addNote("Corpus note", onPage: 0)
    try controller.save(to: url)
    try exportForValidation(url, name: item.name, password: item.password)

    // A second, independent reader (plan §3 B2): Core Graphics parses the saved file page by page.
    let parsed = try #require(CGPDFDocument(url as CFURL), "\(item.name): Core Graphics can't open the saved file")
    if let password = item.password { #expect(parsed.unlockWithPassword(password), "\(item.name)") }
    #expect(parsed.numberOfPages == item.pageCount, "\(item.name)")
    for number in 1...max(parsed.numberOfPages, 1) where parsed.numberOfPages > 0 {
      let page = try #require(parsed.page(at: number), "\(item.name), page \(number)")
      #expect(!page.getBoxRect(.mediaBox).isEmpty, "\(item.name), page \(number)")
      #expect(page.dictionary != nil, "\(item.name), page \(number)")
    }

    let reopened = try PDFDocumentController(url: url)
    if let password = item.password { #expect(reopened.unlock(password: password)) }
    #expect(reopened.pageCount == item.pageCount, "\(item.name)")
    #expect(reopened.annotationCount(onPage: 0) == before + 1, "\(item.name)")
    #expect(reopened.document.isEncrypted == item.isEncrypted, "\(item.name)")
    if let word = item.searchable { #expect(!reopened.find(word).isEmpty, "\(item.name): \(word) after saving") }
  }
}

private final class PageLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Int] = []
  var values: [Int] { lock.withLock { storage } }
  func append(_ value: Int) { lock.withLock { storage.append(value) } }
}
