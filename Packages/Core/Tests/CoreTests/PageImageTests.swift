import Core
import CoreGraphics
import Foundation
import Testing

@Suite("Page images")
struct PageImageTests {
  /// A white image with a black band across its top quarter.
  private func page(width: Int, height: Int, alpha: CGImageAlphaInfo = .noneSkipLast) -> CGImage? {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha.rawValue)
    context?.setFillColor(CGColor(gray: 1, alpha: 1))
    context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context?.setFillColor(CGColor(gray: 0, alpha: 1))
    context?.fill(CGRect(x: 0, y: height * 3 / 4, width: width, height: height / 4))
    return context?.makeImage()
  }

  /// How dark the image is at a height, from 0 at the bottom to 1 at the top.
  private func gray(of image: CGImage, atHeight fraction: Double) -> UInt8? {
    var pixel: [UInt8] = [0]
    let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      let height = CGFloat(image.height)
      context?.draw(image, in: CGRect(x: 0, y: -fraction * height, width: CGFloat(image.width), height: height))
      return context != nil
    }
    return drawn ? pixel[0] : nil
  }

  @Test("A large image comes down to the longest side, with its shape, upright")
  func largeImages() throws {
    let image = try #require(page(width: 3024, height: 4032))
    let smaller = try #require(PageImage.scaledDown(image, toLongestSide: 2200))
    #expect(smaller.width == 1650 && smaller.height == 2200)
    #expect(try #require(gray(of: smaller, atHeight: 0.9)) < 10, "The band stays at the top")
    #expect(try #require(gray(of: smaller, atHeight: 0.1)) > 245)
    #expect(smaller.colorSpace?.name == CGColorSpace.displayP3)
    let wide = try #require(page(width: 4000, height: 1000))
    let fitted = try #require(PageImage.scaledDown(wide, toLongestSide: 1000))
    #expect(fitted.width == 1000 && fitted.height == 250)
    let thin = try #require(page(width: 9000, height: 3))
    #expect(try #require(PageImage.scaledDown(thin, toLongestSide: 900)).height == 1, "Never no pixels at all")
  }

  @Test("An image no larger than the longest side is returned as it is")
  func smallImages() throws {
    let image = try #require(page(width: 1000, height: 2200))
    #expect(PageImage.scaledDown(image, toLongestSide: 2200) === image)
    #expect(PageImage.scaledDown(image, toLongestSide: 3000) === image, "Nothing is scaled up")
  }

  @Test("See-through stays see-through, so a chosen image doesn't turn black behind its text")
  func transparency() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 300, width: 400, height: 100))
    let image = try #require(context.makeImage())
    let smaller = try #require(PageImage.scaledDown(image, toLongestSide: 200))
    #expect(smaller.alphaInfo == .premultipliedLast)
    // Over white: the part with nothing on it shows the white.
    let over = try #require(
      CGContext(
        data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    over.setFillColor(CGColor(gray: 1, alpha: 1))
    over.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    over.draw(smaller, in: CGRect(x: 0, y: 0, width: 200, height: 200))
    let composed = try #require(over.makeImage())
    #expect(try #require(gray(of: composed, atHeight: 0.2)) > 245)
    #expect(try #require(gray(of: composed, atHeight: 0.9)) < 10)
  }

  @Test("A gray image comes down too")
  func grayImages() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
    let image = try #require(context.makeImage())
    let smaller = try #require(PageImage.scaledDown(image, toLongestSide: 100))
    #expect(smaller.width == 100 && smaller.height == 50)
    #expect(try #require(gray(of: smaller, atHeight: 0.5)) > 245)
  }
}
