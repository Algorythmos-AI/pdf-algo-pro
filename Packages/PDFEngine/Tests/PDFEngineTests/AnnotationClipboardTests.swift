import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import PDFEngine

@MainActor
@Suite("Annotations: copy, cut and paste", .serialized)
struct AnnotationClipboardTests {
  private func document() throws -> PDFDocumentController {
    AnnotationClipboard.shared.annotation = nil
    return try PDFDocumentController(data: SyntheticPDF.makeSample())
  }

  @Test("A copied tick is pasted where each tap lands, as many times as wanted")
  func copyAndPasteATick() throws {
    let controller = try document()
    #expect(!controller.canPasteAnnotation)
    #expect(controller.addStamp(.tick, onPage: 0), "A stamp is selected as it is placed")
    let page = try #require(controller.document.page(at: 0))
    let tick = try #require(page.annotations.last)
    #expect(controller.copySelection())
    #expect(controller.canPasteAnnotation)
    controller.isPastingAnnotations = true
    #expect(controller.selection == nil, "Pasting starts with nothing selected, so a tap pastes")
    for point in [CGPoint(x: 120, y: 200), CGPoint(x: 120, y: 300), CGPoint(x: 120, y: 400)] {
      #expect(controller.pasteAnnotation(at: point, onPage: 0))
      let pasted = try #require(page.annotations.last)
      #expect(abs(pasted.bounds.midX - point.x) < 0.5 && abs(pasted.bounds.midY - point.y) < 0.5)
      #expect(pasted.bounds.size == tick.bounds.size)
      #expect(pasted.contents == tick.contents && PDFDocumentController.kind(of: pasted) == .stamp)
      #expect(pasted !== tick)
    }
    #expect(controller.annotationCount(onPage: 0) == 4)
    #expect(controller.hasUnsavedChanges)
  }

  @Test("A paste near the edge stays on the page")
  func pasteStaysOnThePage() throws {
    let controller = try document()
    #expect(controller.addStamp(.tick, onPage: 0))
    #expect(controller.copySelection())
    let page = try #require(controller.document.page(at: 0))
    let box = page.bounds(for: .cropBox)
    #expect(controller.pasteAnnotation(at: CGPoint(x: box.maxX + 50, y: box.minY - 50), onPage: 0))
    let pasted = try #require(page.annotations.last)
    #expect(box.contains(pasted.bounds))
    #expect(!controller.pasteAnnotation(at: .zero, onPage: 99), "No such page")
  }

  @Test("Cut removes the original and keeps it to paste")
  func cut() throws {
    let controller = try document()
    #expect(controller.addShape(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160), onPage: 0))
    #expect(controller.selectAnnotation(at: CGPoint(x: 150, y: 100), onPage: 0))
    let size = try #require(controller.document.page(at: 0)?.annotations.last).bounds.size
    #expect(controller.cutSelection())
    #expect(controller.annotationCount(onPage: 0) == 0 && controller.selection == nil)
    #expect(controller.canPasteAnnotation)
    #expect(controller.pasteAnnotation(at: CGPoint(x: 300, y: 300), onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let pasted = try #require(page.annotations.last)
    #expect(PDFDocumentController.kind(of: pasted) == .rectangle)
    #expect(pasted.bounds.size == size)
  }

  @Test("A pen drawing keeps its strokes when pasted, and changing the copy leaves the original as it was")
  func inkIsCopiedWhole() throws {
    let controller = try document()
    let stroke = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150), CGPoint(x: 260, y: 120)]
    #expect(controller.addInk([stroke], onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let original = try #require(page.annotations.last)
    let strokes = original.paths?.count ?? 0
    #expect(strokes > 0)
    #expect(controller.selectAnnotation(at: CGPoint(x: original.bounds.midX, y: original.bounds.midY), onPage: 0))
    #expect(controller.copySelection())
    #expect(controller.pasteAnnotation(at: CGPoint(x: 400, y: 500), onPage: 0))
    let pasted = try #require(page.annotations.last)
    #expect(pasted.paths?.count == strokes)
    #expect(controller.selectAnnotation(at: CGPoint(x: pasted.bounds.midX, y: pasted.bounds.midY), onPage: 0))
    #expect(controller.moveSelection(by: CGSize(width: 10, height: 10)))
    #expect(original.paths?.count == strokes)
    #expect(original.bounds.minX < 150, "The original did not move")
  }

  @Test("Duplicate puts a copy beside the original and selects it; Undo removes it")
  func duplicate() throws {
    let controller = try document()
    #expect(controller.addStamp(.cross, onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let original = try #require(page.annotations.last)
    #expect(controller.duplicateSelection())
    let copy = try #require(page.annotations.last)
    #expect(copy !== original)
    #expect(abs(copy.bounds.minX - original.bounds.minX) <= 16.5)
    #expect(controller.selection?.kind == .stamp)
    #expect(!controller.canPasteAnnotation, "Duplicate leaves the clipboard alone")
  }

  @Test("Marks on text are not copied, and nothing is pasted before anything was copied")
  func whatCannotBeCopied() throws {
    let controller = try document()
    #expect(!controller.pasteAnnotation(at: CGPoint(x: 100, y: 100), onPage: 0))
    controller.isPastingAnnotations = true
    #expect(!controller.isPastingAnnotations, "Pasting does not start with nothing to paste")
    let highlight = PDFAnnotation(
      bounds: CGRect(x: 100, y: 500, width: 200, height: 14), forType: .highlight, withProperties: nil)
    let page = try #require(controller.document.page(at: 0))
    page.addAnnotation(highlight)
    #expect(controller.selectAnnotation(at: CGPoint(x: 200, y: 507), onPage: 0))
    #expect(!controller.copySelection() && !controller.cutSelection() && !controller.duplicateSelection())
  }

  @Test("What was copied in one document is pasted in another")
  func acrossDocuments() throws {
    let first = try document()
    #expect(first.addStamp(.tick, onPage: 0))
    #expect(first.copySelection())
    let second = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(second.canPasteAnnotation)
    #expect(second.pasteAnnotationOnCurrentPage())
    #expect(second.annotationCount(onPage: 0) == 1 && second.selection?.kind == .stamp)
  }

  @Test("A stamp from the menu is picked up, not placed, and each tap puts one where it lands")
  func stampIsPickedUp() throws {
    let controller = try document()
    #expect(controller.pickUpStamp(.tick))
    #expect(controller.isPastingAnnotations && controller.annotationCount(onPage: 0) == 0)
    #expect(controller.pasteAnnotation(at: CGPoint(x: 300, y: 300), onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let tick = try #require(page.annotations.last)
    #expect(PDFDocumentController.kind(of: tick) == .stamp && tick.contents == "✓")
    #expect(abs(tick.bounds.midX - 300) < 0.5 && abs(tick.bounds.midY - 300) < 0.5)
    #expect(!controller.pickUpStamp(.text("  ")))
  }

  @Test("Placing, drawing, marking and editing text are one mode at a time")
  func oneModeAtATime() throws {
    let controller = try document()
    #expect(controller.pickUpStamp(.tick))
    controller.setDrawing(true)
    #expect(!controller.isPastingAnnotations, "Drawing ends placing")
    controller.isPastingAnnotations = true
    #expect(controller.isPastingAnnotations && !controller.isDrawing, "Placing ends drawing")
    controller.setMarkupTool(.highlight)
    #expect(!controller.isPastingAnnotations, "A marker ends placing")
    controller.isPastingAnnotations = true
    #expect(controller.markupTool == nil)
  }
}
