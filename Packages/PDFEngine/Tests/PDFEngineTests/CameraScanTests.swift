import Core
import CoreGraphics
import CoreTestSupport
import Foundation
import PDFKit
import Testing

@testable import PDFEngine

/// Camera pages are far larger than recognition or a page on screen needs, so they are brought down
/// to about the render size on their way in (#371).
@Suite("Searchable PDFs from camera images")
struct CameraScanTests {
  /// What the document camera gives on a 12-megapixel iPhone camera at most.
  private static let cameraSize = CGSize(width: 3024, height: 4032)

  @Test("Camera images reach recognition at the render size, with the same shape (#371)")
  func recognitionSeesTheRenderSize() async throws {
    let recognizer = SizeRecordingRecognizer()
    let image = try #require(SyntheticPDF.makeTextImage("Page one", size: Self.cameraSize))
    _ = try await SearchablePDFBuilder(recognizer: recognizer).makeSearchablePDF(from: [image, image])
    let sizes = await recognizer.sizes
    #expect(sizes == [CGSize(width: 1650, height: 2200), CGSize(width: 1650, height: 2200)])
  }

  @Test("The render size a builder is given is the one used (#371)")
  func theBuildersRenderSizeIsUsed() async throws {
    let recognizer = SizeRecordingRecognizer()
    let wide = try #require(SyntheticPDF.makeTextImage("Page one", size: CGSize(width: 2000, height: 1000)))
    _ = try await SearchablePDFBuilder(recognizer: recognizer, renderPixelSize: 800).makeSearchablePDF(from: [wide])
    #expect(await recognizer.sizes == [CGSize(width: 800, height: 400)])
  }

  @Test("Images no larger than the render size are left as they are")
  func smallImagesAreLeftAlone() async throws {
    let recognizer = SizeRecordingRecognizer()
    let image = try #require(SyntheticPDF.makeTextImage("Page one"))
    let result = try await SearchablePDFBuilder(recognizer: recognizer).makeSearchablePDF(from: [image])
    #expect(await recognizer.sizes == [CGSize(width: image.width, height: image.height)])
    #expect(try Self.imageSizes(inPageOf: result.data) == [CGSize(width: image.width, height: image.height)])
  }

  @Test("The PDF holds the smaller image, on a page of the same size (#371)")
  func thePDFHoldsTheSmallerImage() async throws {
    let image = try #require(SyntheticPDF.makeTextImage("Page one", size: Self.cameraSize))
    let result = try await SearchablePDFBuilder(recognizer: FakeRecognizer()).makeSearchablePDF(from: [image])
    #expect(try Self.imageSizes(inPageOf: result.data) == [CGSize(width: 1650, height: 2200)])
    let page = try #require(PDFDocument(data: result.data)?.page(at: 0))
    let box = page.bounds(for: .mediaBox)
    #expect(abs(box.width - PDFWriter.letter.width) < 0.5)
    #expect(abs(box.height - PDFWriter.letter.width * 4 / 3) < 0.5, "\(box)")
  }

  @Test("Each step of a scan is marked by name, so a device run can name the slow one (#371)")
  func stepsAreMarked() async throws {
    let image = try #require(SyntheticPDF.makeTextImage("Page one"))
    let builder = SearchablePDFBuilder(recognizer: FakeRecognizer())
    let log = SpanLog()
    try await log.watching { _ = try await builder.makeSearchablePDF(from: [image, image]) }
    let page = ["Scan.Downscale", "Scan.Recognize"]
    #expect(log.names == ["Scan.Searchable"] + page + page + ["Scan.WritePDF"])
  }

  /// The recogniser here finds the block in whatever image it is given, as Vision finds words, so
  /// this checks the whole way round: the text is laid where the page's picture shows the block.
  @Test(
    "Recognised text still lies over what was read on the page (#371)",
    arguments: [
      (CGSize(width: 3024, height: 4032), CGRect(x: 0.2, y: 0.7, width: 0.5, height: 0.05)),
      // Sizes that don't divide evenly, so the smaller image's shape is rounded.
      (CGSize(width: 3001, height: 4003), CGRect(x: 0.1, y: 0.15, width: 0.8, height: 0.04)),
      (CGSize(width: 4001, height: 2999), CGRect(x: 0.55, y: 0.45, width: 0.3, height: 0.1)),
    ])
  func textLiesOverWhatWasRead(size: CGSize, block: CGRect) async throws {
    let image = try #require(Self.image(size: size, block: block))
    let result = try await SearchablePDFBuilder(recognizer: BlockFinder()).makeSearchablePDF(from: [image])
    let document = try #require(PDFDocument(data: result.data))
    let page = try #require(document.page(at: 0))
    let box = page.bounds(for: .mediaBox)
    let text = try #require(document.findString("Total", withOptions: []).first).bounds(for: page)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("camera-scan-\(UUID()).pdf")
    try result.data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    // Smaller than the page, because `getDrawingTransform` only ever scales a page down.
    let picture = try PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 600)
    let drawn = try #require(BlockFinder.block(in: picture))
    // In fractions of the page: within half a percent of the block as drawn, and as it was made. By
    // its bottom left corner and width: the text's height comes from its font, not from the box.
    for (found, expected) in [
      (text.minX / box.width, drawn.minX), (text.minY / box.height, drawn.minY), (text.width / box.width, drawn.width),
      (drawn.minX, block.minX), (drawn.minY, block.minY), (drawn.width, block.width),
    ] {
      #expect(abs(found - expected) < 0.005, "\(text) on \(box): the block is at \(drawn)")
    }
  }

  /// A white page with a black block, given in fractions of the page from its bottom left.
  private static func image(size: CGSize, block: CGRect) -> CGImage? {
    let context = CGContext(
      data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    context?.setFillColor(CGColor(gray: 1, alpha: 1))
    context?.fill(CGRect(origin: .zero, size: size))
    context?.setFillColor(CGColor(gray: 0, alpha: 1))
    context?.fill(
      CGRect(
        x: block.minX * size.width, y: block.minY * size.height, width: block.width * size.width,
        height: block.height * size.height))
    return context?.makeImage()
  }

  /// The pixel size of each image the first page draws.
  private static func imageSizes(inPageOf data: Data) throws -> [CGSize] {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    return try withExtendedLifetime(document) {
      let page = try #require(document.page(at: 1)?.dictionary)
      var resources: CGPDFDictionaryRef?
      var objects: CGPDFDictionaryRef?
      guard CGPDFDictionaryGetDictionary(page, "Resources", &resources), let resources,
        CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects
      else { return [] }
      var sizes: [CGSize] = []
      withUnsafeMutablePointer(to: &sizes) { found in
        CGPDFDictionaryApplyBlock(
          objects,
          { _, value, context in
            var stream: CGPDFStreamRef?
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            if CGPDFObjectGetValue(value, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream), CGPDFDictionaryGetInteger(dictionary, "Width", &width),
              CGPDFDictionaryGetInteger(dictionary, "Height", &height)
            {
              context?.assumingMemoryBound(to: [CGSize].self).pointee.append(CGSize(width: width, height: height))
            }
            return true
          }, found)
      }
      return sizes
    }
  }
}

/// Keeps the size of each image it is asked to read.
private actor SizeRecordingRecognizer: TextRecognizing {
  private(set) var sizes: [CGSize] = []

  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    sizes.append(CGSize(width: image.width, height: image.height))
    return FakeRecognizer().lines
  }
}

/// Reads "Total" over the dark block in an image, in fractions of the image from its bottom left, as
/// Vision reports what it reads.
private struct BlockFinder: TextRecognizing {
  func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    guard let bounds = Self.block(in: image) else { return [] }
    return [RecognizedLine(text: "Total", bounds: bounds, confidence: 1)]
  }

  /// Where the dark pixels are.
  static func block(in image: CGImage) -> CGRect? {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { return nil }
    var (left, right, top, bottom) = (width, -1, height, -1)
    for row in 0..<height {
      for column in 0..<width where pixels[row * width + column] < 128 {
        (left, right) = (min(left, column), max(right, column))
        (top, bottom) = (min(top, row), max(bottom, row))
      }
    }
    guard right >= 0 else { return nil }
    // The context's memory starts at the image's top row.
    return CGRect(
      x: Double(left) / Double(width), y: Double(height - bottom - 1) / Double(height),
      width: Double(right - left + 1) / Double(width), height: Double(bottom - top + 1) / Double(height))
  }
}
