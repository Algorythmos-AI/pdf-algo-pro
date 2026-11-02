import CoreGraphics
import Foundation
import ImageIO

/// Renders pages to bitmaps with Core Graphics: thumbnails for the library, images for recognition.
public enum PageRenderer {
  /// Renders one page of a PDF to an opaque bitmap.
  ///
  /// - Parameters:
  ///   - pageIndex: The zero-based page.
  ///   - url: The PDF file.
  ///   - maximumPixelSize: The longest side of the result, in pixels.
  /// - Returns: The page as an opaque bitmap on white.
  /// - Throws: `PDFEngineError.unreadable`, `.passwordRequired` or `.renderFailed`.
  public static func render(pageIndex: Int, of url: URL, maximumPixelSize: Int) throws -> CGImage {
    guard let document = CGPDFDocument(url as CFURL) else { throw PDFEngineError.unreadable }
    guard !document.isEncrypted || document.isUnlocked else { throw PDFEngineError.passwordRequired }
    guard let page = document.page(at: pageIndex + 1) else { throw PDFEngineError.renderFailed }
    return try render(page, maximumPixelSize: maximumPixelSize)
  }

  /// Renders a Core Graphics page to an opaque bitmap on a white background.
  static func render(_ page: CGPDFPage, maximumPixelSize: Int) throws -> CGImage {
    let box = page.getBoxRect(.cropBox)
    let size = shownSize(of: box, rotation: page.rotationAngle)
    guard size.width > 0, size.height > 0 else { throw PDFEngineError.renderFailed }
    let scale = CGFloat(maximumPixelSize) / max(size.width, size.height)
    let width = max(1, Int((size.width * scale).rounded()))
    let height = max(1, Int((size.height * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw PDFEngineError.renderFailed }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.concatenate(
      pageTransform(box: box, rotation: page.rotationAngle, width: CGFloat(width), height: CGFloat(height)))
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw PDFEngineError.renderFailed }
    return image
  }

  /// A page's size as shown, with its rotation applied.
  static func shownSize(of box: CGRect, rotation: Int32) -> CGSize {
    rotation % 180 != 0 ? CGSize(width: box.height, height: box.width) : box.size
  }

  /// Maps a page's crop box, turned by its rotation, onto a bitmap.
  ///
  /// `getDrawingTransform` can't be used here: it only ever scales down, so a page smaller than the
  /// bitmap would sit in its middle, and what recognition reads from the bitmap wouldn't map back to
  /// the page (#373). The two scales differ only by the rounding of the bitmap's size.
  static func pageTransform(
    box: CGRect, rotation: Int32, width: CGFloat, height: CGFloat
  )
    -> CGAffineTransform
  {
    switch ((rotation % 360) + 360) % 360 {
    case 90:
      let (x, y) = (width / box.height, height / box.width)
      return CGAffineTransform(a: 0, b: -y, c: x, d: 0, tx: -box.minY * x, ty: box.maxX * y)
    case 180:
      let (x, y) = (width / box.width, height / box.height)
      return CGAffineTransform(a: -x, b: 0, c: 0, d: -y, tx: box.maxX * x, ty: box.maxY * y)
    case 270:
      let (x, y) = (width / box.height, height / box.width)
      return CGAffineTransform(a: 0, b: y, c: -x, d: 0, tx: box.maxY * x, ty: -box.minX * y)
    default:
      let (x, y) = (width / box.width, height / box.height)
      return CGAffineTransform(a: x, b: 0, c: 0, d: y, tx: -box.minX * x, ty: -box.minY * y)
    }
  }
}

/// Library thumbnails, rendered once per file version and kept in memory.
public actor ThumbnailCache {
  private let cache = NSCache<NSString, CGImageBox>()

  /// Creates an empty cache.
  public init() {
    cache.countLimit = 300
  }

  /// A page of a PDF as a thumbnail, or `nil` when it cannot be rendered (for example a locked
  /// document).
  public func thumbnail(for url: URL, pageIndex: Int = 0, version: Date, maximumPixelSize: Int = 240) -> CGImage? {
    let key = "\(url.path)|\(pageIndex)|\(version.timeIntervalSince1970)|\(maximumPixelSize)" as NSString
    if let cached = cache.object(forKey: key) { return cached.image }
    guard let image = try? PageRenderer.render(pageIndex: pageIndex, of: url, maximumPixelSize: maximumPixelSize) else {
      return nil
    }
    cache.setObject(CGImageBox(image), forKey: key)
    return image
  }
}

private final class CGImageBox: NSObject {
  let image: CGImage
  init(_ image: CGImage) { self.image = image }
}
