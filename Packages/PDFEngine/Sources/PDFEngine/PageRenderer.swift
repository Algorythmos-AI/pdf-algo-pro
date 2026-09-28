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
  /// - Throws: `PDFEngineError.unreadable` or `.renderFailed`.
  public static func render(pageIndex: Int, of url: URL, maximumPixelSize: Int) throws -> CGImage {
    guard let document = CGPDFDocument(url as CFURL) else { throw PDFEngineError.unreadable }
    guard !document.isEncrypted || document.isUnlocked else { throw PDFEngineError.passwordRequired }
    guard let page = document.page(at: pageIndex + 1) else { throw PDFEngineError.renderFailed }
    return try render(page, maximumPixelSize: maximumPixelSize)
  }

  /// Renders a Core Graphics page to an opaque bitmap on a white background.
  static func render(_ page: CGPDFPage, maximumPixelSize: Int) throws -> CGImage {
    let box = page.getBoxRect(.cropBox)
    let rotated = page.rotationAngle % 180 != 0
    let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
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
    let target = CGRect(x: 0, y: 0, width: width, height: height)
    context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw PDFEngineError.renderFailed }
    return image
  }
}

/// Library thumbnails, rendered once per file version and kept in memory.
public actor ThumbnailCache {
  private let cache = NSCache<NSString, CGImageBox>()

  /// Creates an empty cache.
  public init() {
    cache.countLimit = 300
  }

  /// The first page of a PDF as a thumbnail, or `nil` when it cannot be rendered (for example a
  /// locked document).
  public func thumbnail(for url: URL, version: Date, maximumPixelSize: Int = 240) -> CGImage? {
    let key = "\(url.path)|\(version.timeIntervalSince1970)|\(maximumPixelSize)" as NSString
    if let cached = cache.object(forKey: key) { return cached.image }
    guard let image = try? PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: maximumPixelSize) else {
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
