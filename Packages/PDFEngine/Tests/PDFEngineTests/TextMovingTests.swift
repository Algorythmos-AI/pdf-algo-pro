import CoreGraphics
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

@MainActor
@Suite("Text editing: moving text")
struct TextMovingTests {
  private typealias Line = TextEditFixtures.Line

  @Test("A line is moved in the page itself: gone from where it was, there where it was put, nothing else touched")
  func moved() async throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let editor = ContentStreamTextEditor()
    let before = await editor.text(ofPage: page).regions
    let region = try #require(before.first { $0.text.contains("John Smith") })
    let move = CGVector(dx: 60, dy: -200)
    let result = await editor.applying([TextEdit(region: region, replacement: region.text, offset: move)], toPage: page)
    #expect(result.outcomes.first?.isEdited == true, "\(String(describing: result.proofFailure))")
    let after = await editor.text(ofPage: try #require(result.page)).regions
    #expect(after.count == before.count)
    let moved = try #require(after.first { $0.text.contains("John Smith") })
    #expect(
      abs(moved.bounds.minX - region.bounds.minX - 60) < 1.5 && abs(moved.bounds.midY - region.bounds.midY + 200) < 1.5)
    // Every other line is where it was.
    for other in before where other.id != region.id {
      #expect(
        after.contains {
          $0.text == other.text && abs($0.bounds.minX - other.bounds.minX) < 1
            && abs($0.bounds.minY - other.bounds.minY) < 1
        })
    }
  }

  @Test("Text can be changed and moved in one edit")
  func changedAndMoved() async throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let editor = ContentStreamTextEditor()
    let region = try #require(await editor.text(ofPage: page).regions.first { $0.text.contains("John Smith") })
    let edit = TextEdit(region: region, replacement: "Customer: David Smith", offset: CGVector(dx: 0, dy: -180))
    #expect(edit.moves && !TextEdit(region: region, replacement: "x").moves)
    let result = await editor.applying([edit], toPage: page)
    #expect(result.outcomes.first?.isEdited == true)
    let read = PDFDocument(data: try #require(result.page))?.page(at: 0)?.string ?? ""
    #expect(read.contains("David Smith") && !read.contains("John Smith"))
  }

  @Test("Text is not moved onto other text, or off the page; nothing changes")
  func refusedWhereItCannotGo() async throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let editor = ContentStreamTextEditor()
    let regions = await editor.text(ofPage: page).regions
    let region = try #require(regions.first { $0.text.contains("John Smith") })
    let target = try #require(regions.first { $0.text.contains("INV-2026") })
    // Onto the line below it.
    let onto = CGVector(dx: 0, dy: target.bounds.midY - region.bounds.midY)
    let blocked = await editor.applying(
      [TextEdit(region: region, replacement: region.text, offset: onto)], toPage: page)
    #expect(blocked.page == nil && blocked.outcomes == [.refused(.overlapsOtherContent)])
    // Off the page's edge.
    let off = await editor.applying(
      [TextEdit(region: region, replacement: region.text, offset: CGVector(dx: 2000, dy: 0))], toPage: page)
    #expect(off.page == nil && off.outcomes == [.refused(.overlapsOtherContent)])
  }

  @Test("A right-aligned amount and a slanted stamp move like any other text")
  func alignedAndSlanted() async throws {
    let editor = ContentStreamTextEditor()
    let invoice = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let amount = try #require(await editor.text(ofPage: invoice).regions.first { $0.text == "$950.00" })
    let down = await editor.applying(
      [TextEdit(region: amount, replacement: amount.text, offset: CGVector(dx: -40, dy: -260))], toPage: invoice)
    #expect(down.outcomes.first?.isEdited == true, "\(String(describing: down.proofFailure))")

    let slanted = try TextEditFixtures.singlePage(
      TextEditFixtures.make(pages: [
        [Line("Received", font: "Helvetica-Bold", size: 28, at: CGPoint(x: 200, y: 400), angle: 0.18)]
      ]))
    let stamp = try #require(await editor.text(ofPage: slanted).regions.first)
    let up = await editor.applying(
      [TextEdit(region: stamp, replacement: stamp.text, offset: CGVector(dx: 30, dy: 150))], toPage: slanted)
    #expect(up.outcomes.first?.isEdited == true, "\(String(describing: up.proofFailure))")
  }

  @Test("In the open document, a line is moved without picking it, stays on the page, and undo puts it back")
  func movedInTheDocument() async throws {
    let controller = try PDFDocumentController(data: TextEditFixtures.invoice())
    // Not a test of the time limits; see `open` in the controller tests.
    controller.textFindLimit = .seconds(600)
    controller.textEditLimit = .seconds(600)
    controller.setEditingText(true)
    let regions = await controller.pageText(onPage: 0).regions
    let region = try #require(regions.first { $0.text.contains("John Smith") })
    let selection = TextRegionSelection(pageIndex: 0, region: region)
    // What is under a finger is found from what is already known, at once.
    let middle = CGPoint(x: region.bounds.midX, y: region.bounds.midY)
    #expect(controller.knownTextRegion(at: middle, onPage: 0, reach: 6) == region)
    #expect(controller.knownTextRegion(at: CGPoint(x: 300, y: 300), onPage: 0, reach: 6) == nil)
    // A move is kept on the page.
    let far = controller.offset(CGVector(dx: 5000, dy: -5000), keeping: region, onPage: 0)
    #expect(region.bounds.offsetBy(dx: far.dx, dy: far.dy).maxX <= 612 && region.bounds.minY + far.dy >= 0)
    #expect(controller.offset(CGVector(dx: 10, dy: -20), keeping: region, onPage: 0) == CGVector(dx: 10, dy: -20))

    #expect(await controller.moveText(selection, by: CGVector(dx: 40, dy: -220)).isEdited)
    #expect(controller.selectedTextRegion == nil && controller.hasUnsavedTextEdits && controller.undoManager.canUndo)
    let after = await controller.pageText(onPage: 0).regions
    let moved = try #require(after.first { $0.text.contains("John Smith") })
    #expect(
      abs(moved.bounds.minX - region.bounds.minX - 40) < 1.5 && abs(moved.bounds.midY - region.bounds.midY + 220) < 1.5)
    #expect(controller.annotationCount(onPage: 0) == 0, "It is the page's own text that moved, not a cover")

    controller.undoManager.undo()
    let restored = await controller.pageText(onPage: 0).regions
    #expect(restored.contains { $0.text.contains("John Smith") && abs($0.bounds.midY - region.bounds.midY) < 1.5 })
    // Not while text is picked, and not outside text editing.
    controller.selectTextRegion(region, onPage: 0)
    #expect(await controller.moveText(selection, by: CGVector(dx: 0, dy: -100)) == .refused(.stale))
    controller.setEditingText(false)
    #expect(await controller.moveText(selection, by: CGVector(dx: 0, dy: -100)) == .refused(.stale))
  }

  @Test("Text that can only be covered is covered where it was and placed where it was dropped")
  func coveredAndPlaced() async throws {
    let data = try TextEditFixtures.make(pages: [[]]) { context, _ in
      context.setAlpha(0.4)
      TextEditFixtures.draw(Line("Faded label", size: 24, at: CGPoint(x: 72, y: 500)), in: context)
    }
    let controller = try PDFDocumentController(data: data)
    controller.setEditingText(true)
    let region = try #require(await controller.pageText(onPage: 0).regions.first { $0.text.contains("Faded") })
    #expect(!region.capability.editsContent)
    let selection = TextRegionSelection(pageIndex: 0, region: region)
    #expect(
      controller.cover(selection, with: region.text, movedBy: CGVector(dx: 20, dy: -150)) == .edited(.visualReplacement)
    )
    let page = try #require(controller.document.page(at: 0))
    let cover = try #require(page.annotations.first { $0.type == "Square" })
    let label = try #require(page.annotations.first { $0.type == "FreeText" })
    #expect(cover.bounds.intersects(region.bounds), "The cover stays over the old text")
    #expect(abs(label.bounds.midY - region.bounds.midY + 150) < 3 && label.contents == "Faded label")
  }
}
