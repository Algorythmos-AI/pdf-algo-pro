import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import PDFEngine

#if canImport(UIKit)
  import UIKit
#endif

@MainActor
@Suite("Drawing tools: moving what is on the page")
struct DrawingToolsTests {
  private func document() throws -> PDFDocumentController {
    try PDFDocumentController(data: SyntheticPDF.makeSample())
  }

  @Test("An arrow is hit along its length, not anywhere in the box it crosses")
  func arrowIsHitOnItsLine() throws {
    let controller = try document()
    #expect(controller.addShape(.arrow, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 400), onPage: 0))
    // On the line, and a fingertip beside it.
    #expect(controller.selectForMoving(at: CGPoint(x: 250, y: 250), onPage: 0))
    #expect(controller.selection?.kind == .line)
    #expect(controller.selectForMoving(at: CGPoint(x: 258, y: 246), onPage: 0))
    // In the arrow's box, far from the line: bare page, where a new shape can start.
    #expect(!controller.selectForMoving(at: CGPoint(x: 380, y: 120), onPage: 0))
    #expect(controller.selection == nil, "A touch on bare page lets go of the selection")
    // The ordinary tap, outside drawing, still takes the whole box.
    #expect(controller.selectAnnotation(at: CGPoint(x: 380, y: 120), onPage: 0))
  }

  @Test("An oval and a rectangle are hit on their outline, so a shape can be drawn inside them")
  func outlinesAreHit() throws {
    let controller = try document()
    #expect(controller.addShape(.oval, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 400, y: 500), onPage: 0))
    #expect(!controller.selectForMoving(at: CGPoint(x: 250, y: 400), onPage: 0), "The middle is empty")
    #expect(controller.selectForMoving(at: CGPoint(x: 250, y: 500), onPage: 0), "The top of the outline")
    #expect(controller.selection?.kind == .oval)
    #expect(controller.selectForMoving(at: CGPoint(x: 100, y: 400), onPage: 0), "Its left edge")
    #expect(!controller.selectForMoving(at: CGPoint(x: 105, y: 305), onPage: 0), "A corner of its box is outside it")

    let other = try document()
    #expect(other.addShape(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), onPage: 0))
    #expect(!other.selectForMoving(at: CGPoint(x: 200, y: 150), onPage: 0))
    #expect(other.selectForMoving(at: CGPoint(x: 200, y: 100), onPage: 0))
    #expect(other.selectForMoving(at: CGPoint(x: 300, y: 150), onPage: 0))
    // A small shape is all outline: anywhere on it takes it.
    #expect(other.addShape(.rectangle, from: CGPoint(x: 400, y: 400), to: CGPoint(x: 420, y: 420), onPage: 0))
    #expect(other.selectForMoving(at: CGPoint(x: 410, y: 410), onPage: 0))
    #expect(other.addShape(.oval, from: CGPoint(x: 450, y: 400), to: CGPoint(x: 470, y: 420), onPage: 0))
    #expect(other.selectForMoving(at: CGPoint(x: 460, y: 410), onPage: 0))
  }

  @Test("A pen stroke is hit on the stroke; a highlight is never picked up for moving")
  func strokesAndMarks() throws {
    let controller = try document()
    #expect(
      controller.addInk([[CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 300)]], onPage: 0))
    #expect(controller.selectForMoving(at: CGPoint(x: 200, y: 104), onPage: 0))
    #expect(controller.selection?.kind == .ink)
    #expect(
      !controller.selectForMoving(at: CGPoint(x: 150, y: 250), onPage: 0), "Inside the stroke's box, off the stroke")

    let highlight = PDFAnnotation(
      bounds: CGRect(x: 100, y: 500, width: 200, height: 14), forType: .highlight, withProperties: nil)
    let page = try #require(controller.document.page(at: 0))
    page.addAnnotation(highlight)
    #expect(!controller.selectForMoving(at: CGPoint(x: 200, y: 507), onPage: 0))
    #expect(!controller.selectForMoving(at: CGPoint(x: 200, y: 507), onPage: 99), "No such page")
  }

  @Test("What was picked up is moved, and Undo puts it back")
  func movingAndUndo() throws {
    let controller = try document()
    #expect(controller.addShape(.arrow, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), onPage: 0))
    #expect(controller.selectForMoving(at: CGPoint(x: 200, y: 100), onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let before = try #require(page.annotations.last).bounds
    #expect(controller.moveSelection(by: CGSize(width: 40, height: 60)))
    let after = try #require(page.annotations.last).bounds
    #expect(abs(after.minX - before.minX - 40) < 0.5 && abs(after.minY - before.minY - 60) < 0.5)
    // In the app the arrow and the move are separate touches, so separate steps. Here they are
    // made in one turn of the run loop, which the undo manager takes as one.
    controller.undoManager.undo()
    #expect(controller.annotationCount(onPage: 0) == 0, "Undo takes the move and the arrow back")
    controller.undoManager.redo()
    #expect(try #require(page.annotations.last).bounds == after, "And redo brings back the arrow where it was moved to")
  }

  #if canImport(UIKit)
    @Test("With a shape in hand, a touch on a shape is left for moving it; a touch on bare page draws")
    func drawingLayerHandsOverTouches() throws {
      let controller = try document()
      let host = PDFReaderHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      host.configure(for: controller)
      host.layoutIfNeeded()
      let page = try #require(controller.document.page(at: 0))
      #expect(controller.addShape(.arrow, from: CGPoint(x: 100, y: 500), to: CGPoint(x: 400, y: 500), onPage: 0))
      let onArrow = host.convert(CGPoint(x: 250, y: 500), from: page)
      let onPaper = host.convert(CGPoint(x: 250, y: 300), from: page)

      controller.setDrawing(true, tool: .arrow)
      let capture = try #require(host.subviews.compactMap { $0 as? InkCaptureView }.first)
      let shouldDraw = try #require(capture.shouldDraw)
      #expect(!shouldDraw(onArrow), "The arrow is picked up")
      #expect(controller.selection?.kind == .line)
      #expect(shouldDraw(onPaper), "Bare page is drawn on")
      #expect(controller.selection == nil)

      // With the pen, every touch draws: a line may well start on top of another.
      controller.setDrawing(true, tool: .pen)
      #expect(shouldDraw(onArrow) && controller.selection == nil)
      controller.setDrawing(false)
      #expect(host.subviews.compactMap { $0 as? InkCaptureView }.isEmpty)
    }

    @Test("The page's scrolling waits for the resize pinch only while an annotation is selected")
    func scrollingDoesNotWaitForAPinchWithNothingToResize() throws {
      let controller = try document()
      let host = PDFReaderHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
      host.configure(for: controller)
      host.layoutIfNeeded()
      let scroller = try #require(host.pageScroller)
      let ours = host.gestureRecognizers ?? []
      let pinch = try #require(ours.first { $0 is UIPinchGestureRecognizer && $0.delegate is TransformGestureDelegate })
      let pan = try #require(ours.first { $0 is UIPanGestureRecognizer && $0.delegate is TransformGestureDelegate })
      let delegate = try #require(pinch.delegate as? TransformGestureDelegate)
      let scroll = scroller.panGestureRecognizer

      // A pinch that sees one finger cannot fail until the finger lifts: a page that waited for it
      // would not follow a drag, only glide on after a flick (issue #188).
      #expect(
        !delegate.gestureRecognizer(pinch, shouldBeRequiredToFailBy: scroll),
        "With nothing selected, a drag on the page scrolls it at once")
      #expect(
        delegate.gestureRecognizer(pan, shouldBeRequiredToFailBy: scroll),
        "The move drag is still waited for: it fails at once off a selection")
      if let zoom = scroller.pinchGestureRecognizer {
        #expect(delegate.gestureRecognizer(pinch, shouldBeRequiredToFailBy: zoom), "Like waits for like")
      }
      #expect(!delegate.gestureRecognizer(pinch, shouldBeRequiredToFailBy: UITapGestureRecognizer()))

      #expect(controller.addShape(.arrow, from: CGPoint(x: 100, y: 500), to: CGPoint(x: 400, y: 500), onPage: 0))
      #expect(controller.selectForMoving(at: CGPoint(x: 250, y: 500), onPage: 0))
      #expect(
        delegate.gestureRecognizer(pinch, shouldBeRequiredToFailBy: scroll),
        "With an annotation selected the page keeps still while it is resized")
      controller.clearSelection()
      #expect(!delegate.gestureRecognizer(pinch, shouldBeRequiredToFailBy: scroll))
    }

    @Test("A stroke that may not start fails at once, so the touch goes to what waited for it")
    func strokeDeclines() {
      let recognizer = InkStrokeRecognizer()
      #expect(recognizer.canStart == nil)
      recognizer.canStart = { $0.x > 100 }
      #expect(
        recognizer.canStart?(CGPoint(x: 50, y: 0)) == false && recognizer.canStart?(CGPoint(x: 150, y: 0)) == true)
    }
  #endif
}
