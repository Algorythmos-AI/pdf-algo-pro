import CoreGraphics
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

private typealias Line = TextEditFixtures.Line

/// A page as it reads and as it draws.
private struct PageLook: Equatable {
  let text: String
  /// Grey levels of the page drawn small, top row first.
  let pixels: [UInt8]

  init(_ page: PDFPage?) {
    text = EditProof.squeezed(page?.string ?? "")
    pixels = Self.draw(page)
  }

  /// Whether anything is drawn on the page at all.
  var isInked: Bool { pixels.contains { $0 < 128 } }

  /// Whether two pages draw alike: fewer than one pixel in a hundred differs clearly.
  func drawsLike(_ other: PageLook) -> Bool {
    guard pixels.count == other.pixels.count else { return false }
    let differing = zip(pixels, other.pixels).filter { abs(Int($0) - Int($1)) > 48 }.count
    return differing * 100 < pixels.count
  }

  private static func draw(_ page: PDFPage?) -> [UInt8] {
    let (width, height) = (153, 198)
    guard let page,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return [] }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let box = page.bounds(for: .mediaBox)
    context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
    page.draw(with: .mediaBox, to: context)
    guard let data = context.data else { return [] }
    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
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
      #expect(look.isInked && look.drawsLike(wanted), "Page \(page + 1) draws as it should \(moment)")
    }
    // A page copied out, as extracting pages or saving without a password does, keeps its content.
    let extracted = try #require(PDFDocument(data: controller.extractPages(IndexSet(0..<controller.pageCount))))
    for (page, wanted) in expected.enumerated() {
      let look = PageLook(extracted.page(at: page))
      #expect(look.text == wanted.text && look.isInked, "Page \(page + 1) is copied out whole \(moment)")
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
    // Every edit passes a limit of nothing, so each halves the history: 32, 16, 8, then 4 steps.
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
      #expect(outcome == [.edited(.contentStream)])
      states.append(looks())
    }
    #expect(Set(states.map { $0.map(\.text) }).count == states.count, "Every edit changed something")
    #expect(controller.undoManager.levelsOfUndo == 4, "The history was shortened")
    try await expectWhole(controller, as: states[edits.count], "after the history was shortened")

    var undone = 0
    while controller.undoManager.canUndo, undone < edits.count {
      controller.undoManager.undo()
      undone += 1
    }
    #expect(undone == 4, "The history holds its newest four edits")
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
        #expect(look.isInked && look.drawsLike(wanted), "Page \(page + 1) draws as it did, \(moment)")
      }
    }
    try controller.save(to: url)
    try expectSaved(as: expected, password: "w1-343", "saved and reopened")
    #expect(controller.removePassword())
    try controller.save(to: url)
    try expectSaved(as: expected, password: nil, "saved without the password and reopened")
  }
}
