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

  @Test("A picked line is followed on screen, readable and fitted to the width, and the zoom comes back after")
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

    controller.setEditingText(true)
    let regions = await controller.pageText(onPage: 0).regions
    let widest = try #require(regions.filter(\.isUpright).max { $0.bounds.width < $1.bounds.width })
    controller.selectTextRegion(widest, onPage: 0)
    let anchor = try #require(controller.textEditAnchor, "The page view says where the line is")
    #expect(anchor.selection.region == widest && anchor.scale == view.scaleFactor)
    let onScreen = widest.style.pointSize * anchor.scale
    #expect(onScreen >= TextEditPlacement.legibleMinimum - 0.01 || anchor.scale == view.maxScaleFactor)
    // The whole line fits the view, unless that would make it too small to read; then it wraps.
    let readableSmallest = abs(onScreen - TextEditPlacement.legibleMinimum) < 0.01
    #expect(anchor.lineFrame.width <= view.bounds.width + 0.5 || readableSmallest, "\(anchor.lineFrame)")

    // Letting go stops following the line, and leaving puts the page back as it was.
    controller.clearTextRegionSelection()
    #expect(controller.textEditAnchor == nil)
    controller.setEditingText(false)
    #expect(view.autoScales, "The page fits the reader again")
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
