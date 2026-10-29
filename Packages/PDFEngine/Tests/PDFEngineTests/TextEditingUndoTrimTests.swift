import CoreGraphics
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

private typealias Line = TextEditFixtures.Line

/// A page as it reads and as it draws.
private struct PageLook {
  let text: String
  /// Grey levels of the page drawn small, top row first.
  let pixels: [UInt8]
  /// How the drawing went, for a failure's message: the page's box and rotation, and the pixels, or
  /// the step that stopped it.
  let drawing: String

  init(_ page: PDFPage?) {
    text = EditProof.squeezed(page?.string ?? "")
    (pixels, drawing) = Self.draw(page)
  }

  /// Whether anything is drawn on the page at all.
  var isInked: Bool { pixels.contains { $0 < 128 } }

  /// Whether two pages draw alike: fewer than one pixel in a hundred differs clearly.
  func drawsLike(_ other: PageLook) -> Bool {
    guard pixels.count == other.pixels.count else { return false }
    let differing = zip(pixels, other.pixels).filter { abs(Int($0) - Int($1)) > 48 }.count
    return differing * 100 < pixels.count
  }

  /// The page drawn small, as the engine draws one into a picture, in sRGB.
  private static func draw(_ page: PDFPage?) -> ([UInt8], String) {
    let (width, height) = (153, 198)
    guard let page else { return ([], "no page") }
    let box = page.bounds(for: .mediaBox)
    let about = "box \(box), rotation \(page.rotation)"
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return ([], "\(about): no bitmap context") }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
    page.draw(with: .mediaBox, to: context)
    guard let image = context.makeImage() else { return ([], "\(about): no image") }
    guard let data = image.dataProvider?.data as Data? else { return ([], "\(about): no image data") }
    let bytes = [UInt8](data)
    let pixels: [UInt8] = (0..<height).flatMap { row in
      (0..<width).map { column in
        let offset = row * image.bytesPerRow + column * 4
        guard offset + 2 < bytes.count else { return 255 }
        return UInt8((Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3)
      }
    }
    let darkest = pixels.min().map(String.init) ?? "none"
    let dark = pixels.count { $0 < 128 }
    let summary = "\(about): \(pixels.count) pixels from \(bytes.count) bytes, darkest \(darkest), \(dark) below 128"
    return (pixels, summary)
  }
}

@MainActor
@Suite("Text editing: undo after the history is shortened")
struct TextEditingUndoTrimTests {
  /// Every page of the document reads to the editor, reads and draws as `expected`, and is copied
  /// out whole.
  private func expectWhole(
    _ controller: PDFDocumentController, as expected: [PageLook], _ moment: String
  ) async throws {
    for (page, wanted) in expected.enumerated() {
      let regions = await controller.pageText(onPage: page).regions
      #expect(!regions.isEmpty, "Page \(page + 1) has text to edit \(moment)")
      let look = PageLook(controller.document.page(at: page))
      #expect(look.text == wanted.text, "Page \(page + 1) reads as it should \(moment)")
      #expect(
        look.isInked && look.drawsLike(wanted),
        "Page \(page + 1) draws as it should \(moment); drawn: \(look.drawing); wanted: \(wanted.drawing)")
    }
    // A page copied out, as extracting pages or saving without a password does, keeps its content.
    let extracted = try #require(PDFDocument(data: controller.extractPages(IndexSet(0..<controller.pageCount))))
    for (page, wanted) in expected.enumerated() {
      let look = PageLook(extracted.page(at: page))
      #expect(
        look.text == wanted.text && look.isInked,
        "Page \(page + 1) is copied out whole \(moment); drawn: \(look.drawing)")
    }
  }

  @Test("Once a shortened history lets go of edits, every page stays whole, through undo, saving and reopening (#343)")
  func undoAfterTrim() async throws {
    let data = try TextEditFixtures.make(
      pages: (1...3).map { number in
        [
          Line("Heading of page \(number)", at: CGPoint(x: 72, y: 700)),
          Line("Body of page \(number)", at: CGPoint(x: 72, y: 680)),
        ]
      },
      // A filled box beside the text, so a page's ink shows whatever the system makes of small text
      // drawn small: on the iOS simulator the lines alone drew too light to count as ink.
      decorate: { context, _ in
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 72, y: 600, width: 240, height: 48))
      })
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("w1-343-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    // Password-protected, so the last save, without the password, writes copies of the pages.
    let unprotected = try PDFDocumentController(data: data)
    #expect(unprotected.setPassword("w1-343"))
    try unprotected.save(to: url)
    let controller = try PDFDocumentController(url: url)
    #expect(controller.unlock(password: "w1-343"))
    controller.textFindLimit = .seconds(600)
    controller.textEditLimit = .seconds(600)
    // Every edit passes a limit of nothing, so the history keeps only the newest four text edits.
    controller.textUndoMemoryLimit = 0
    // In the app each edit is its own event, so its own undo step; the test says so explicitly.
    controller.undoManager.groupsByEvent = false
    controller.setEditingText(true)

    func looks() -> [PageLook] { (0..<controller.pageCount).map { PageLook(controller.document.page(at: $0)) } }
    var states = [looks()]
    // Seven edits; the history keeps the newest four. Page 1 is last edited by a step it lets go
    // of; pages 2 and 3 are edited again by steps it keeps, so undoing those brings back a page
    // made by a step it let go of.
    let edits = [
      (0, "Heading of page 1", "Title of page 1"), (1, "Heading of page 2", "Title of page 2"),
      (2, "Heading of page 3", "Title of page 3"), (1, "Body of page 2", "Words of page 2"),
      (2, "Body of page 3", "Words of page 3"), (1, "Title of page 2", "Name of page 2"),
      (2, "Title of page 3", "Name of page 3"),
    ]
    for (page, text, replacement) in edits {
      let regions = await controller.pageText(onPage: page).regions
      let region = try #require(regions.first { $0.text.contains(text) }, "no region contains \(text)")
      controller.undoManager.beginUndoGrouping()
      let outcome = await controller.applyTextEdits([TextEdit(region: region, replacement: replacement)], onPage: page)
      controller.undoManager.endUndoGrouping()
      // The history lets go of the oldest edits once the edit's undo group has closed.
      await controller.undoMemoryRelease?.value
      #expect(outcome == [.edited(.contentStream)])
      states.append(looks())
    }
    #expect(Set(states.map { $0.map(\.text) }).count == states.count, "Every edit changed something")
    #expect(controller.textUndoSteps.count == 4, "The history let go of the oldest text edits")
    #expect(controller.undoManager.levelsOfUndo == 0, "and nothing else (#339)")
    try await expectWhole(controller, as: states[edits.count], "after the history was shortened")

    var undone = 0
    while controller.undoManager.canUndo, undone < edits.count {
      controller.undoManager.undo()
      undone += 1
    }
    #expect(undone == 4, "The history holds its newest four edits; \(undone) undone")
    let expected = states[edits.count - undone]
    try await expectWhole(controller, as: expected, "after undoing back to the oldest edit held")
    // Redo brings back a page an edit made; then undo again, so what is saved is the state above.
    #expect(controller.undoManager.canRedo)
    controller.undoManager.redo()
    try await expectWhole(controller, as: states[edits.count - undone + 1], "after redoing one edit")
    controller.undoManager.undo()
    try await expectWhole(controller, as: expected, "after undoing the redone edit again")

    func expectSaved(as expected: [PageLook], password: String?, _ moment: String) throws {
      let reopened = try #require(PDFDocument(url: url))
      if let password { #expect(reopened.unlock(withPassword: password)) }
      #expect(reopened.isEncrypted == (password != nil))
      #expect(reopened.pageCount == expected.count)
      #expect(CGPDFDocument(url as CFURL)?.numberOfPages == expected.count, "Core Graphics reads the file")
      for (page, wanted) in expected.enumerated() {
        let look = PageLook(reopened.page(at: page))
        #expect(look.text == wanted.text, "Page \(page + 1) reads as it did, \(moment)")
        #expect(
          look.isInked && look.drawsLike(wanted),
          "Page \(page + 1) draws as it did, \(moment); drawn: \(look.drawing); wanted: \(wanted.drawing)")
      }
    }
    try controller.save(to: url)
    try expectSaved(as: expected, password: "w1-343", "saved and reopened")
    #expect(controller.removePassword())
    try controller.save(to: url)
    try expectSaved(as: expected, password: nil, "saved without the password and reopened")
  }

  @Test("Past the memory limit, undo still reaches annotation, page and bookmark changes made before text edits (#339)")
  func otherUndoStepsOutliveTheTextEditLimit() async throws {
    let data = try TextEditFixtures.make(
      pages: (1...2).map { number in
        [
          Line("Heading of page \(number)", at: CGPoint(x: 72, y: 700)),
          Line("Body of page \(number)", at: CGPoint(x: 72, y: 680)),
        ]
      })
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("w1-339-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    // A rectangle saved with the document, so undoing everything leaves it on the page.
    let first = try PDFDocumentController(data: data)
    #expect(first.addShape(.rectangle, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 400, y: 360), onPage: 0))
    try first.save(to: url)
    let controller = try PDFDocumentController(url: url)
    controller.textFindLimit = .seconds(600)
    controller.textEditLimit = .seconds(600)
    // In the app each change is its own event, so its own undo step; the test says so explicitly.
    controller.undoManager.groupsByEvent = false
    func step(_ change: () -> Void) {
      controller.undoManager.beginUndoGrouping()
      change()
      controller.undoManager.endUndoGrouping()
    }
    func rectangle(_ document: PDFDocument?) -> PDFAnnotation? {
      document?.page(at: 0)?.annotations.first { $0.type == "Square" }
    }
    let placed = try #require(rectangle(controller.document)).bounds

    // Changes that each keep the page they were made on: a move, a turned page and a bookmark.
    #expect(controller.selectAnnotation(at: CGPoint(x: placed.midX, y: placed.midY), onPage: 0))
    step { #expect(controller.moveSelection(by: CGSize(width: 40, height: -60))) }
    controller.clearSelection()
    step { #expect(controller.rotatePages([1], by: 90)) }
    step { #expect(controller.toggleBookmark(onPage: 0)) }
    #expect(rectangle(controller.document)?.bounds != placed && controller.bookmarkedPages == [0])

    // Then text edits on both pages, each past a memory limit of nothing.
    controller.textUndoMemoryLimit = 0
    controller.setEditingText(true)
    let edits = [
      (0, "Heading of page 1", "Title of page 1"), (1, "Heading of page 2", "Title of page 2"),
      (0, "Body of page 1", "Words of page 1"), (1, "Body of page 2", "Words of page 2"),
      (0, "Title of page 1", "Name of page 1"), (1, "Title of page 2", "Name of page 2"),
    ]
    for (page, text, replacement) in edits {
      let regions = await controller.pageText(onPage: page).regions
      let region = try #require(regions.first { $0.text.contains(text) }, "no region contains \(text)")
      controller.undoManager.beginUndoGrouping()
      let outcome = await controller.applyTextEdits([TextEdit(region: region, replacement: replacement)], onPage: page)
      controller.undoManager.endUndoGrouping()
      // The history lets go of the oldest edits once the edit's undo group has closed.
      await controller.undoMemoryRelease?.value
      #expect(outcome == [.edited(.contentStream)])
    }
    controller.setEditingText(false)

    var undone = 0
    while controller.undoManager.canUndo, undone < 40 {
      controller.undoManager.undo()
      undone += 1
    }
    // The text edits the history let go of stay made; every other change is undone, on the pages
    // in the document.
    let livePage = try #require(controller.document.page(at: 0))
    let moved = try #require(rectangle(controller.document), "The rectangle is on the page in the document")
    #expect(moved.page === livePage)
    #expect(moved.bounds == placed, "The move is undone: \(moved.bounds), placed at \(placed)")
    #expect(controller.document.page(at: 1)?.rotation == 0, "The turn is undone")
    #expect(controller.bookmarkedPages.isEmpty, "The bookmark is undone")
    #expect(controller.document.page(at: 0)?.string?.contains("Title of page 1") == true)

    try controller.save(to: url)
    let reopened = try #require(PDFDocument(url: url))
    #expect(reopened.pageCount == 2)
    #expect(reopened.page(at: 1)?.rotation == 0)
    let saved = try #require(rectangle(reopened), "The rectangle is saved")
    #expect(
      abs(saved.bounds.minX - placed.minX) < 0.5 && abs(saved.bounds.minY - placed.minY) < 0.5,
      "saved at \(saved.bounds), placed at \(placed)")
    #expect(reopened.page(at: 0)?.string?.contains("Title of page 1") == true)
    #expect(reopened.page(at: 1)?.string?.contains("Title of page 2") == true)
    #expect(try PDFDocumentController(url: url).bookmarkedPages.isEmpty)
  }
}
