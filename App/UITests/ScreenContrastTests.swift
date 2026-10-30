import CoreGraphics
import XCTest

/// `ScreenContrast` on pictures whose colours are known, with no app running (#76).
@MainActor
final class ScreenContrastTests: XCTestCase {
  private typealias Colour = (red: UInt8, green: UInt8, blue: UInt8)

  /// A background with a bar of text colour across a tenth of it, as a line of text covers a button.
  private func picture(text: Colour, on background: Colour) throws -> CGImage {
    let (width, height) = (100, 40)
    var bytes: [UInt8] = []
    for row in 0..<height {
      let colour = (18..<22).contains(row) ? text : background
      for _ in 0..<width { bytes += [colour.red, colour.green, colour.blue, 255] }
    }
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
    return try XCTUnwrap(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }

  private func hex(_ colour: Colour) -> String {
    String(format: "#%02X%02X%02X", colour.red, colour.green, colour.blue)
  }

  func testTheAccentOnWhiteReadsAboutSixToOne() throws {
    let accent: Colour = (0xC4, 0x12, 0x30)
    let reading = try XCTUnwrap(ScreenContrast.reading(of: picture(text: accent, on: (255, 255, 255))))
    XCTAssertEqual(reading.ratio, 6.04, accuracy: 0.1)
    XCTAssertEqual(reading.text, hex(accent))
    XCTAssertEqual(reading.background, hex((255, 255, 255)))
  }

  func testBlackOnWhiteReadsTwentyOneToOne() throws {
    let reading = try XCTUnwrap(ScreenContrast.reading(of: picture(text: (0, 0, 0), on: (255, 255, 255))))
    XCTAssertEqual(reading.ratio, 21, accuracy: 0.01)
  }

  func testGreyOnWhiteJustBelowTheMinimumIsBelowIt() throws {
    let reading = try XCTUnwrap(ScreenContrast.reading(of: picture(text: (0x77, 0x77, 0x77), on: (255, 255, 255))))
    XCTAssertLessThan(reading.ratio, ScreenContrast.minimum)
    XCTAssertEqual(reading.ratio, 4.48, accuracy: 0.05)
  }

  func testTheAccentOnDarkGlassReadsTheSameWhicheverIsLighter() throws {
    let reading = try XCTUnwrap(ScreenContrast.reading(of: picture(text: (255, 255, 255), on: (0xC4, 0x12, 0x30))))
    XCTAssertEqual(reading.ratio, 6.04, accuracy: 0.1)
  }
}
