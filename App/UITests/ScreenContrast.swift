import CoreGraphics
import Foundation
import XCTest

/// Contrast measured on the screen itself, for the findings iOS 27's audit misreads on glass (#294).
///
/// On iOS 27 the audit reports contrast failures for dark text on the reader's light glass capsules and
/// bars (the drawing hint, the selection and paste bars, the text-editing hint), where the screenshot
/// shows near-black text on near-white glass. So on iOS 27 a contrast finding is measured again from a
/// screenshot: the most common luminance in the element's frame is its background, and the luminance
/// of the pixel two in a hundred furthest from it is its text. A finding is excused only when that
/// measure reaches WCAG 1.4.3's 4.5:1; below that it still fails.
@MainActor
enum ScreenContrast {
  /// WCAG 1.4.3's minimum for normal text.
  static let minimum = 4.5

  /// The element's frame in a finding written by `UITestCase.describe`, in points.
  static func frame(in finding: String) -> CGRect? {
    guard
      let pattern = try? NSRegularExpression(pattern: #"frame=\((-?\d+),(-?\d+) (\d+)x(\d+)\)"#),
      let match = pattern.firstMatch(in: finding, range: NSRange(finding.startIndex..., in: finding))
    else { return nil }
    let numbers = (1...4).compactMap { index in
      Range(match.range(at: index), in: finding).flatMap { Double(finding[$0]) }
    }
    guard numbers.count == 4 else { return nil }
    return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
  }

  /// The contrast ratio between the text and the background inside `frame` on `screenshot`, or `nil`
  /// when the frame is off the screen.
  static func ratio(of frame: CGRect, in screenshot: XCUIScreenshot) -> Double? {
    let image = screenshot.image
    guard let picture = image.cgImage, image.size.width > 0 else { return nil }
    let scale = CGFloat(picture.width) / image.size.width
    let bounds = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
    let pixels = CGRect(
      x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale
    ).integral.intersection(bounds)
    guard !pixels.isEmpty, let crop = picture.cropping(to: pixels) else { return nil }
    let luminances = luminances(of: crop)
    guard !luminances.isEmpty else { return nil }
    let background = mostCommon(luminances)
    let furthest = luminances.sorted { abs($0 - background) > abs($1 - background) }
    let text = furthest[min(furthest.count - 1, furthest.count / 50)]
    return (max(background, text) + 0.05) / (min(background, text) + 0.05)
  }

  /// The relative luminance of every pixel of `image`, as WCAG defines it, in sRGB.
  private static func luminances(of image: CGImage) -> [Double] {
    let width = image.width
    let height = image.height
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return [] }
    func linear(_ byte: UInt8) -> Double {
      let value = Double(byte) / 255
      return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return stride(from: 0, to: bytes.count, by: 4).map { index in
      0.2126 * linear(bytes[index]) + 0.7152 * linear(bytes[index + 1]) + 0.0722 * linear(bytes[index + 2])
    }
  }

  /// The mean of the most common luminances, in steps of a two-hundredth.
  private static func mostCommon(_ luminances: [Double]) -> Double {
    let groups = Dictionary(grouping: luminances) { Int(($0 * 200).rounded()) }
    let largest = groups.max { $0.value.count < $1.value.count }?.value ?? luminances
    return largest.reduce(0, +) / Double(largest.count)
  }
}
