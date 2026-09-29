import Core
import CoreGraphics
import CoreTestSupport
import Foundation
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
