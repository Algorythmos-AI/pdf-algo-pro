import Core
import CoreTestSupport
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing
import UIKit

@testable import PDFEngine
@testable import ReaderFeature

@MainActor
@Suite("Reader: scrolling direction, zoom limits and the page strip (FR-READ-002)")
struct ReadingControlsTests {
  /// A page view the size of a phone, showing a document, laid out.
  private func hosted(pages: [String] = ["One", "Two", "Three"]) throws -> (PDFDocumentController, PDFReaderHostView) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    try SyntheticPDF.make(pages: pages).write(to: url)
    let controller = try PDFDocumentController(url: url)
    let view = PDFReaderHostView()
    view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
    let container = UIView(frame: view.frame)
    container.addSubview(view)
    view.configure(for: controller)
    view.layoutIfNeeded()
    return (controller, view)
  }

  @Test("Zooming stops at the whole page and at ten times that, and the page still fits itself")
  func zoomLimits() throws {
    let (controller, view) = try hosted()
    let before = (min: view.minScaleFactor, max: view.maxScaleFactor)
    controller.limitsZoom = true
    view.layoutIfNeeded()
    let fit = view.scaleFactorForSizeToFit
    #expect(fit > 0)
    #expect(view.autoScales, "Limits do not stop the page fitting the reader")
    #expect(abs(view.minScaleFactor - fit) < fit * 0.01 && view.minScaleFactor <= fit)
    #expect(abs(view.maxScaleFactor - fit * PDFReaderHostView.largestZoom) < 0.001)
    // Small print still gets large enough to edit: 4 points becomes at least 15 on screen.
    #expect(4 * view.maxScaleFactor >= 15)
    // Zooming by hand stays inside the limits.
    for _ in 0..<30 { controller.zoomIn() }
    #expect(view.scaleFactor <= view.maxScaleFactor)
    for _ in 0..<60 { controller.zoomOut() }
    #expect(view.scaleFactor >= view.minScaleFactor)
    controller.zoomToFit()
    #expect(view.autoScales)
    // A reader of another size works its limits out again.
    view.frame.size = CGSize(width: 700, height: 393)
    view.layoutIfNeeded()
    #expect(abs(view.minScaleFactor - view.scaleFactorForSizeToFit) < view.scaleFactorForSizeToFit * 0.01)
    // Without the flag, PDFKit's own limits are left alone.
    let (_, plain) = try hosted()
    plain.layoutIfNeeded()
    #expect(plain.minScaleFactor == before.min && plain.maxScaleFactor == before.max)
  }

  @Test("A picked line is edited at the zoom the person chose, followed on screen, and scrolled clear of the keyboard")
  func editingFollowsTheLine() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    try TextEditFixtures.invoice().write(to: url)
    let controller = try PDFDocumentController(url: url)
    let view = PDFReaderHostView()
    view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
    let container = UIView(frame: view.frame)
    container.addSubview(view)
    view.configure(for: controller)
    view.layoutIfNeeded()
    #expect(view.autoScales)
    let zoom = view.scaleFactor

    controller.setEditingText(true)
    let regions = await controller.pageText(onPage: 0).regions
    let widest = try #require(regions.filter(\.isUpright).max { $0.bounds.width < $1.bounds.width })
    let first = try #require(regions.first { $0.isUpright && $0.id != widest.id })
    controller.selectTextRegion(first, onPage: 0)
    let anchor = try #require(controller.textEditAnchor, "The page view says where the line is")
    // The page is not zoomed: every line of it stays on screen, as before the line was picked.
    #expect(abs(view.scaleFactor - zoom) < 0.001, "Zoom \(zoom) became \(view.scaleFactor)")
    #expect(view.autoScales, "The page stopped fitting the screen")
    #expect(abs(anchor.scale - zoom) < 0.001, "The anchor's zoom is \(anchor.scale), the page's \(zoom)")
    #expect(anchor.selection.region == first)
    // The field may grow to the right edge of the page's text, not further.
    #expect(abs(anchor.columnFrame.minX - anchor.lineFrame.minX) < 0.5, "\(anchor)")
    #expect(anchor.columnFrame.maxX >= anchor.lineFrame.maxX - 0.5)
    #expect(anchor.columnFrame.maxX <= view.bounds.width + 0.5, "\(anchor.columnFrame)")

    // Scrolling the page for the keyboard moves the line, and the anchor with it, even where the
    // page has no more to scroll and room is made under it.
    let scroller = try #require(view.pageScroller, "PDFKit's page scroller was not found")
    scroller.layoutIfNeeded()
    let inset = scroller.contentInset
    let offsetBefore = scroller.contentOffset
    let scrollerState = "content \(scroller.contentSize), bounds \(scroller.bounds), inset \(inset)"
    let before = anchor.lineFrame.minY
    view.scrollPickedText(by: 120, animated: false)
    view.layoutIfNeeded()
    view.publishTextEditAnchor()
    let moved = try #require(controller.textEditAnchor)
    let shift = before - moved.lineFrame.minY
    #expect(
      shift > 60 && shift < 121,
      "The line moved up by \(shift) points: \(before) → \(moved.lineFrame.minY); \(scrollerState)")

    // Letting go stops following the line and takes the room away again.
    controller.clearTextRegionSelection()
    #expect(controller.textEditAnchor == nil, "The anchor outlived the selection")
    #expect(scroller.contentInset == inset, "Inset \(inset) became \(scroller.contentInset)")
    // Only the editor moved the page, so the page goes back to where it was.
    #expect(
      abs(scroller.contentOffset.y - offsetBefore.y) < 0.5,
      "The page was left at \(scroller.contentOffset), not put back at \(offsetBefore)")
    controller.setEditingText(false)
    #expect(view.autoScales, "The page stopped fitting the screen after editing")
    #expect(abs(view.scaleFactor - zoom) < 0.001, "Zoom \(zoom) became \(view.scaleFactor) after editing")
  }

  /// A page view showing the invoice fixture, with text editing on and its first upright line
  /// picked, as a tap on it would.
  private func editingInvoice() async throws -> (PDFDocumentController, PDFReaderHostView, UIScrollView) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    try TextEditFixtures.invoice().write(to: url)
    let controller = try PDFDocumentController(url: url)
    let view = PDFReaderHostView()
    view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
    let container = UIView(frame: view.frame)
    container.addSubview(view)
    view.configure(for: controller)
    view.layoutIfNeeded()
    controller.setEditingText(true)
    let regions = await controller.pageText(onPage: 0).regions
    let first = try #require(regions.first { $0.isUpright })
    controller.selectTextRegion(first, onPage: 0)
    let scroller = try #require(view.pageScroller, "PDFKit's page scroller was not found")
    scroller.layoutIfNeeded()
    return (controller, view, scroller)
  }

  @Test("A page the person moved while editing stays where they took it when the text is let go of")
  func personsPlaceIsKept() async throws {
    let (controller, view, scroller) = try await editingInvoice()
    let inset = scroller.contentInset
    // The editor makes room for the keyboard; then the person scrolls back up a little themselves.
    view.scrollPickedText(by: 120, animated: false)
    view.layoutIfNeeded()
    let theirs = CGPoint(x: scroller.contentOffset.x, y: scroller.contentOffset.y - 40)
    scroller.contentOffset = theirs
    controller.clearTextRegionSelection()
    #expect(scroller.contentInset == inset, "Inset \(inset) became \(scroller.contentInset)")
    // Kept, inside what can be scrolled to now the room under the page is gone.
    let highest = max(
      -scroller.adjustedContentInset.top,
      scroller.contentSize.height + scroller.adjustedContentInset.bottom - scroller.bounds.height)
    #expect(
      abs(scroller.contentOffset.y - min(theirs.y, highest)) < 0.5,
      "The page went to \(scroller.contentOffset), not where the person left it (\(theirs), highest \(highest))")
  }

  @Test("With a line open, scrolling and zooming no longer wait to see whether a press lifts a line")
  func openEditorDoesNotHoldUpScrolling() async throws {
    let (controller, view, scroller) = try await editingInvoice()
    let lift = try #require(
      view.gestureRecognizers?.first { $0.delegate is LiftGestureDelegate }, "The lift gesture is installed")
    let delegate = try #require(lift.delegate)
    let pan = scroller.panGestureRecognizer
    // A line is open: nothing can be lifted, so the page's own gestures start at once.
    #expect(delegate.gestureRecognizer?(lift, shouldBeRequiredToFailBy: pan) == false)
    if let pinch = scroller.pinchGestureRecognizer {
      #expect(delegate.gestureRecognizer?(lift, shouldBeRequiredToFailBy: pinch) == false)
    }
    // With no line open, they wait, so a held line can be carried without the page moving under it.
    controller.clearTextRegionSelection()
    #expect(delegate.gestureRecognizer?(lift, shouldBeRequiredToFailBy: pan) == true)
  }

  @Test("The next and previous page commands stop at the ends of the document")
  func paging() throws {
    let (controller, _) = try hosted()
    controller.showPreviousPage()
    #expect(controller.currentPageIndex == 0)
    controller.showNextPage()
    controller.showNextPage()
    controller.showNextPage()
    #expect(controller.currentPageIndex == 2)
    controller.showPreviousPage()
    #expect(controller.currentPageIndex == 1)
  }
}
