import Core
import CoreGraphics
import DocumentStore
import Foundation
import OCR
import PDFEngine
import Search
import XCTest

/// The engine budgets in docs/performance-budgets.md, measured by the Performance test plan (P9).
///
/// Each test is named after its budget row, and `scripts/ci/perf_gate.py` compares the median of
/// three iterations with that row. The fast pull-request plan skips this class. On the simulator the
/// numbers show trends, not device timings: running the same plan on the baseline iPhone from Xcode
/// gives those.
nonisolated final class EnginePerformanceTests: XCTestCase {
  private static var options: XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    return options
  }

  private static var manual: XCTMeasureOptions {
    let options = Self.options
    options.invocationOptions = [.manuallyStart, .manuallyStop]
    return options
  }

  private func write(pages count: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID()).pdf")
    try SyntheticPDF.make(pages: (1...count).map { "Page \($0). The invoice total is due on receipt." })
      .write(to: url)
    return url
  }

  /// Runs asynchronous work to completion inside a measured block.
  @MainActor private func run(_ work: @escaping @Sendable () async throws -> Void) {
    let done = expectation(description: "work finished")
    let failure = Failure()
    Task.detached {
      do { try await work() } catch { failure.error = error }
      done.fulfill()
    }
    wait(for: [done], timeout: 300)
    if let error = failure.error { XCTFail("\(error)") }
  }

  /// Budget: open a 20-page PDF to the first page visible.
  ///
  /// Measured as opening it and rendering the first page at the size of an iPhone screen.
  @MainActor func testOpenA20PagePDFToTheFirstPage() throws {
    let url = try write(pages: 20)
    measure(metrics: [XCTClockMetric()], options: Self.options) {
      XCTAssertNotNil(try? PDFDocumentController(url: url))
      XCTAssertNotNil(try? PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 1206))
    }
  }

  /// Budget: open a 500-page PDF to the first page visible.
  @MainActor func testOpenA500PagePDFToTheFirstPage() throws {
    let url = try write(pages: 500)
    measure(metrics: [XCTClockMetric()], options: Self.options) {
      XCTAssertNotNil(try? PDFDocumentController(url: url))
      XCTAssertNotNil(try? PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 1206))
    }
  }

  /// Budget: save after an edit in a 500-page PDF.
  ///
  /// Only the save is measured.
  @MainActor func testSaveAfterAnEditIn500Pages() throws {
    let url = try write(pages: 500)
    measure(metrics: [XCTClockMetric()], options: Self.manual) {
      let controller = try? PDFDocumentController(url: url)
      controller?.addNote("Checked", onPage: 250)
      startMeasuring()
      do { try controller?.save(to: url) } catch { XCTFail("\(error)") }
      stopMeasuring()
      XCTAssertNotNil(controller)
    }
  }

  /// Budget: edit a line of text in a 500-page PDF.
  ///
  /// Finding the page's text, making the edit and proving it, until the new page is in the document.
  /// The save is measured by `testSaveAfterAnEditIn500Pages`.
  @MainActor func testEditALineOfTextIn500Pages() throws {
    let url = try write(pages: 500)
    measure(metrics: [XCTClockMetric()], options: Self.manual) {
      let controller = try? PDFDocumentController(url: url)
      let edited = expectation(description: "edited")
      Task { @MainActor in
        defer { edited.fulfill() }
        guard let controller, let region = await controller.pageText(onPage: 250).regions.first else {
          XCTFail("no text to edit")
          return
        }
        startMeasuring()
        let outcomes = await controller.applyTextEdits(
          [TextEdit(region: region, replacement: "Edited line")], onPage: 250)
        stopMeasuring()
        XCTAssertEqual(outcomes.first?.isEdited, true)
      }
      wait(for: [edited], timeout: 60)
    }
  }

  /// Budget: the page thumbnail grid (100 pages) populated.
  ///
  /// Measured as rendering all 100 thumbnails at the grid's size, more than a screen shows at once.
  @MainActor func testRenderThe100PageThumbnailGrid() throws {
    let url = try write(pages: 100)
    measure(metrics: [XCTClockMetric()], options: Self.options) {
      let rendered = (0..<100).compactMap { try? PageRenderer.render(pageIndex: $0, of: url, maximumPixelSize: 256) }
      XCTAssertEqual(rendered.count, 100)
    }
  }

  /// Budget: search across a 1,000-document library, index warm.
  ///
  /// Indexing is not measured.
  @MainActor func testSearchA1000DocumentLibrary() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf-index-\(UUID())")
    let index = LocalSearchIndex(folder: folder)
    let documents = (0..<1_000).map {
      Document(title: "Document \($0)", fileName: "document-\($0).pdf", addedAt: Date(timeIntervalSince1970: 0))
    }
    run {
      for (number, document) in documents.enumerated() {
        let pages = (0..<3).map {
          PageText(pageIndex: $0, text: "Statement \(number), page \($0 + 1). Balance carried forward and fees.")
        }
        try await index.index(document, pages: pages)
      }
      _ = try await index.search("balance", in: documents)
    }
    measure(metrics: [XCTClockMetric()], options: Self.options) {
      run { _ = try await index.search("balance fees", in: documents) }
    }
  }

  /// Budget: scan to a searchable PDF, 10 pages, with on-device recognition.
  @MainActor func testScanTenPagesToASearchablePDF() throws {
    let images = (1...10).compactMap { SyntheticPDF.makeTextImage("Scanned page \($0)\nInvoice total 42.00") }
    XCTAssertEqual(images.count, 10)
    let builder = SearchablePDFBuilder(recognizer: VisionTextRecognizer())
    measure(metrics: [XCTClockMetric()], options: Self.options) {
      run { _ = try await builder.makeSearchablePDF(from: images) }
    }
  }

  /// Budget: save a 2-page camera scan to the first page visible.
  ///
  /// What happens between tapping Save and the page on screen (#371): bringing the pages down, writing
  /// the PDF, adding it to a library as the app does, opening it and drawing page 1. Recognition runs
  /// behind the open document, and has its own row. The reader's own steps are marked for a device run
  /// (`Reader.Load.*`).
  @MainActor func testSaveATwoPageCameraScanToTheFirstPage() throws {
    let images = (1...2).compactMap { Self.cameraPage("Scanned page \($0)\nInvoice total 42.00", seed: UInt64($0)) }
    XCTAssertEqual(images.count, 2)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf-scan-\(UUID())")
    let library = FileDocumentLibrary(
      documentsFolder: folder.appendingPathComponent("Documents"),
      deletedFolder: folder.appendingPathComponent("Deleted"),
      index: OpeningLibraryIndex(storeURL: folder.appendingPathComponent("Library.store")))
    let index = LocalSearchIndex(folder: folder.appendingPathComponent("Search"))
    let intake = DocumentIntake(library: library, inspector: PDFKitInspector(), index: index)
    let builder = SearchablePDFBuilder(recognizer: VisionDocumentRecognizer())
    let saved = SavedFile()
    measure(metrics: [XCTClockMetric()], options: Self.options) {
      run {
        let data = try await builder.makeImagePDF(from: images)
        let document = try await intake.add(data: data, title: "Scan")
        saved.url = try await library.fileURL(for: document.id)
      }
      guard let url = saved.url else { return XCTFail("nothing was saved") }
      XCTAssertNotNil(try? PDFDocumentController(url: url))
      XCTAssertNotNil(try? PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 1206))
    }
  }

  /// A page the size the document camera gives, generated, with the fine noise of a photograph.
  ///
  /// The noise matters: a flat page compresses to almost nothing, so writing its PDF would look far
  /// cheaper than writing a photograph's.
  private static func cameraPage(_ text: String, seed: UInt64) -> CGImage? {
    let (width, height) = (3024, 4032)
    guard let page = SyntheticPDF.makeTextImage(text, size: CGSize(width: width, height: height)),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    var state = seed
    for pixel in 0..<(width * height) {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let noise = Int(state >> 60) - 8
      for channel in 0..<3 {
        pixels[pixel * 4 + channel] = UInt8(clamping: Int(pixels[pixel * 4 + channel]) + noise)
      }
    }
    return context.makeImage()
  }
}

/// Where the saved scan's file is, handed back from asynchronous work.
nonisolated private final class SavedFile: @unchecked Sendable {
  var url: URL?
}

/// The error from asynchronous work, handed back to the test.
nonisolated private final class Failure: @unchecked Sendable {
  var error: (any Error)?
}
