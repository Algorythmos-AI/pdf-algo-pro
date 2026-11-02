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

  /// Recognise text on an image-only PDF: a page smaller than the render size has to fill the image
  /// recognition reads, or what it reports doesn't map back to the page (#373).
  @Test(
    "A text layer added to an image-only PDF lies over what was read (#373)",
    arguments: [
      // US Letter, the case measured: x 61, y 634, width 306.
      (CGSize(width: 612, height: 792), CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.04)),
      // A landscape page, and one larger than the render size, which was always scaled.
      (CGSize(width: 842, height: 595), CGRect(x: 0.55, y: 0.15, width: 0.3, height: 0.08)),
      (CGSize(width: 3000, height: 4000), CGRect(x: 0.2, y: 0.7, width: 0.5, height: 0.05)),
    ])
  func addedTextLayerLiesOverWhatWasRead(size: CGSize, block: CGRect) async throws {
    let picture = try #require(Self.image(size: CGSize(width: size.width * 2, height: size.height * 2), block: block))
    let box = CGRect(origin: .zero, size: size)
    let source = try PDFWriter.makePDF(mediaBoxes: [box]) { context, _, box in context.draw(picture, in: box) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("image-only-\(UUID()).pdf")
    try source.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let result = try await SearchablePDFBuilder(recognizer: BlockFinder()).addTextLayer(toPDFAt: url)
    let document = try #require(PDFDocument(data: result.data))
    let page = try #require(document.page(at: 0))
    let text = try #require(document.findString("Total", withOptions: []).first).bounds(for: page)
    for (found, expected) in [
      (text.minX / size.width, block.minX), (text.minY / size.height, block.minY),
      (text.width / size.width, block.width),
    ] {
      #expect(abs(found - expected) < 0.005, "\(text) on \(box): the block is at \(block)")
    }
  }

  @Test(
    "A page fills the bitmap at every rotation, with a crop box away from the origin (#373)",
    arguments: [0, 90, 180, 270])
  func pagesFillTheBitmap(rotation: Int) throws {
    let box = CGRect(x: 50, y: 100, width: 300, height: 400)
    // The block in page space, at the bottom left of the crop box.
    let block = CGRect(x: 80, y: 140, width: 60, height: 40)
    let data = try PDFWriter.makePDF(mediaBoxes: [box]) { context, _, _ in
      context.setFillColor(CGColor(gray: 0, alpha: 1))
      context.fill(block)
    }
    let document = try #require(PDFDocument(data: data))
    document.page(at: 0)?.rotation = rotation
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rotated-\(UUID()).pdf")
    #expect(document.write(to: url))
    defer { try? FileManager.default.removeItem(at: url) }
    let image = try PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 1600)
    #expect(max(image.width, image.height) == 1600)
    let found = try #require(BlockFinder.block(in: image))
    let (x, y) = ((block.minX - box.minX) / box.width, (block.minY - box.minY) / box.height)
    let (w, h) = (block.width / box.width, block.height / box.height)
    let expected: CGRect
    switch rotation {
    case 90: expected = CGRect(x: y, y: 1 - x - w, width: h, height: w)
    case 180: expected = CGRect(x: 1 - x - w, y: 1 - y - h, width: w, height: h)
    case 270: expected = CGRect(x: 1 - y - h, y: x, width: h, height: w)
    default: expected = CGRect(x: x, y: y, width: w, height: h)
    }
    for (a, b) in [
      (found.minX, expected.minX), (found.minY, expected.minY), (found.width, expected.width),
      (found.height, expected.height),
    ] {
      #expect(abs(a - b) < 0.005, "\(found), expected \(expected)")
    }
  }

  /// A rotated page's layer runs along the text as shown (#373).
  ///
  /// The picture is drawn turned the other way, so the page shows the block where `block` says once
  /// its rotation is applied.
  @Test(
    "A text layer added to a rotated image-only PDF lies over what was read (#373)",
    arguments: [90, 180, 270])
  func addedTextLayerFollowsRotation(rotation: Int) async throws {
    let block = CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.04)
    let shown = rotation == 180 ? CGSize(width: 612, height: 792) : CGSize(width: 792, height: 612)
    let box = CGRect(x: 0, y: 0, width: 612, height: 792)
    // The block in the page's own space, in fractions, for each rotation.
    let unturned: CGRect
    switch rotation {
    case 90:
      unturned = CGRect(
        x: 1 - block.minY - block.height, y: block.minX, width: block.height, height: block.width)
    case 180:
      unturned = CGRect(
        x: 1 - block.minX - block.width, y: 1 - block.minY - block.height, width: block.width,
        height: block.height)
    default:
      unturned = CGRect(
        x: block.minY, y: 1 - block.minX - block.width, width: block.height, height: block.width)
    }
    let picture = try #require(Self.image(size: CGSize(width: 1224, height: 1584), block: unturned))
    let source = try PDFWriter.makePDF(mediaBoxes: [box]) { context, _, box in context.draw(picture, in: box) }
    let original = try #require(PDFDocument(data: source))
    original.page(at: 0)?.rotation = rotation
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rotated-layer-\(UUID()).pdf")
    #expect(original.write(to: url))
    defer { try? FileManager.default.removeItem(at: url) }
    let result = try await SearchablePDFBuilder(recognizer: BlockFinder()).addTextLayer(toPDFAt: url)
    let document = try #require(PDFDocument(data: result.data))
    let page = try #require(document.page(at: 0))
    #expect(page.rotation == rotation)
    let text = try #require(document.findString("Total", withOptions: []).first).bounds(for: page)
    // The text's box, in fractions of the page as shown. Its height comes from its font, so only
    // the far edge across the text and the length along it are compared.
    let (x, y) = (text.minX / box.width, text.minY / box.height)
    let (w, h) = (text.width / box.width, text.height / box.height)
    let across = 0.02
    let found: (start: Double, across: Double, length: Double)
    let wanted: (start: Double, across: Double, length: Double)
    switch rotation {
    case 90:
      found = (y, x, h)
      wanted = (unturned.minY, unturned.minX, unturned.height)
    case 180:
      found = (x, y, w)
      wanted = (unturned.minX, unturned.minY, unturned.width)
    default:
      found = (y, x, h)
      wanted = (unturned.minY, unturned.minX, unturned.height)
    }
    #expect(abs(found.start - wanted.start) < 0.005, "\(text) on \(shown), block \(unturned)")
    #expect(abs(found.length - wanted.length) < 0.005, "\(text) on \(shown), block \(unturned)")
    #expect(abs(found.across - wanted.across) < across, "\(text) on \(shown), block \(unturned)")
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
