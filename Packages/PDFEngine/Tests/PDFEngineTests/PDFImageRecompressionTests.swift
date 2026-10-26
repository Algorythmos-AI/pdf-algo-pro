import Compression
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing

@testable import PDFEngine

/// The compression presets' own re-encoding of pictures, which iOS 27's PDFKit no longer does (#308).
///
/// The files here are made with Core Graphics or by hand, as PDFKit on iOS 27 writes them: pictures as
/// they were drawn. So the re-encoding is tested wherever the tests run, not only on iOS 27.
@Suite("Re-encoding pictures for compression (#308)")
struct PDFImageRecompressionTests {
  private let email = PDFImageRecompression.Settings(maximumSide: 1_600, quality: 0.5)
  private let balanced = PDFImageRecompression.Settings(maximumSide: nil, quality: 0.75)

  /// A noisy colour gradient, like a photographed page: Flate barely shrinks it.
  private func photo(width: Int, height: Int) throws -> CGImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    var seed: UInt32 = 7
    for index in 0..<(width * height) {
      seed = seed &* 1_664_525 &+ 1_013_904_223
      let value = UInt8(truncatingIfNeeded: (index % width) * 200 / width + Int(seed >> 28))
      pixels[index * 4] = value
      pixels[index * 4 + 1] = value / 2 &+ 60
      pixels[index * 4 + 2] = 255 &- value
    }
    return try #require(
      pixels.withUnsafeMutableBytes { buffer in
        CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?
          .makeImage()
      })
  }

  /// One page with a picture over all of it and a line of text on top, written by Core Graphics.
  private func scan(_ image: CGImage, text: String = "Invoice INV-2026-0042") throws -> Data {
    let box = CGRect(x: 0, y: 0, width: 595, height: 842)
    return try PDFWriter.makePDF(mediaBoxes: [box]) { context, _, box in
      context.draw(image, in: box)
      PDFWriter.drawText(text, in: CGRect(x: 40, y: 760, width: 500, height: 40), fontSize: 18, context: context)
    }
  }

  /// The average colour of the first page drawn at 64 by 64, each channel from 0 to 255.
  private func averageColour(_ data: Data) throws -> [Double] {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let page = try #require(CGPDFDocument(provider)?.page(at: 1))
    let side = 64
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try #require(
        CGContext(
          data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
      let box = page.getBoxRect(.mediaBox)
      context.scaleBy(x: CGFloat(side) / box.width, y: CGFloat(side) / box.height)
      context.drawPDFPage(page)
    }
    return (0..<3).map { channel in
      Double(stride(from: channel, to: pixels.count, by: 4).reduce(0) { $0 + Int(pixels[$1]) }) / Double(side * side)
    }
  }

  @Test("A scan's picture comes back as a JPEG, much smaller, with its page, its text and its look")
  func scanShrinks() throws {
    let original = try scan(photo(width: 1_200, height: 1_600))
    let result = try #require(
      PDFImageRecompression.recompressed(original, settings: email),
      "Nothing re-encoded in a \(original.count)-byte Core Graphics scan")
    #expect(result.count < original.count / 2, "\(original.count) bytes became \(result.count)")
    let document = try #require(PDFDocument(data: result))
    #expect(document.pageCount == 1)
    #expect(document.page(at: 0)?.string?.contains("INV-2026-0042") == true, "The text is kept")
    let text = String(decoding: result, as: UTF8.self)
    #expect(text.contains("/DCTDecode") && text.contains("/Width 1200"), "Kept its size, as JPEG")
    let before = try averageColour(original)
    let after = try averageColour(result)
    for channel in 0..<3 {
      #expect(abs(before[channel] - after[channel]) < 6, "Channel \(channel): \(before) became \(after)")
    }
    let printing = try #require(PDFImageRecompression.recompressed(original, settings: balanced))
    #expect(printing.count < original.count && printing.count > result.count)
  }

  @Test("Email scales a large picture to 1,600 pixels on its longest side; printing keeps its size")
  func largePictureScales() throws {
    let original = try scan(photo(width: 2_400, height: 1_800))
    let result = try #require(PDFImageRecompression.recompressed(original, settings: email))
    let text = String(decoding: result, as: UTF8.self)
    #expect(text.contains("/Width 1600") && text.contains("/Height 1200"))
    #expect(PDFDocument(data: result)?.pageCount == 1)
    let printing = try #require(PDFImageRecompression.recompressed(original, settings: balanced))
    #expect(String(decoding: printing, as: UTF8.self).contains("/Width 2400"))
  }

  @Test("A JPEG is made smaller only by scaling it, never by encoding it again at its size")
  func jpegsAreLeftAtTheirSize() throws {
    let jpeg = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try photo(width: 1_000, height: 800), nil)
    #expect(CGImageDestinationFinalize(destination))
    let provider = try #require(CGDataProvider(data: jpeg))
    let image = try #require(
      CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
    let original = try scan(image)
    #expect(String(decoding: original, as: UTF8.self).contains("/DCTDecode"), "Core Graphics keeps a JPEG")
    #expect(PDFImageRecompression.recompressed(original, settings: email) == nil)
    #expect(PDFImageRecompression.recompressed(original, settings: balanced) == nil)
    let smaller = PDFImageRecompression.Settings(maximumSide: 500, quality: 0.5)
    let result = try #require(PDFImageRecompression.recompressed(original, settings: smaller))
    #expect(String(decoding: result, as: UTF8.self).contains("/Width 500") && result.count < original.count)
  }

  @Test("Text and line art, encrypted files and what isn't a PDF are left alone")
  func leftAlone() throws {
    #expect(PDFImageRecompression.recompressed(try SyntheticPDF.makeSample(), settings: email) == nil)
    let document = try #require(PDFDocument(data: try scan(photo(width: 300, height: 400))))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("locked-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(document.write(to: url, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
    #expect(PDFImageRecompression.recompressed(try Data(contentsOf: url), settings: email) == nil)
    #expect(PDFImageRecompression.recompressed(Data("%PDF-1.7\nnot really".utf8), settings: email) == nil)
    #expect(PDFImageRecompression.recompressed(Data(), settings: email) == nil)
  }

  // MARK: - A file written by hand: grey, a PNG predictor, an indirect length and a soft mask

  /// Rows of grey samples written with each PNG filter in turn, as ISO 32000-1 7.4.4.4 describes.
  private func predicted(_ samples: [UInt8], width: Int, height: Int) -> [UInt8] {
    var output: [UInt8] = []
    for row in 0..<height {
      let filter = UInt8(row % 5)
      output.append(filter)
      for column in 0..<width {
        let value = Int(samples[row * width + column])
        let left = column > 0 ? Int(samples[row * width + column - 1]) : 0
        let up = row > 0 ? Int(samples[(row - 1) * width + column]) : 0
        let upLeft = row > 0 && column > 0 ? Int(samples[(row - 1) * width + column - 1]) : 0
        let predicted: Int
        switch filter {
        case 1: predicted = left
        case 2: predicted = up
        case 3: predicted = (left + up) / 2
        case 4:
          let estimate = left + up - upLeft
          let (toLeft, toUp, toUpLeft) = (abs(estimate - left), abs(estimate - up), abs(estimate - upLeft))
          predicted = toLeft <= toUp && toLeft <= toUpLeft ? left : (toUp <= toUpLeft ? up : upLeft)
        default: predicted = 0
        }
        output.append(UInt8(truncatingIfNeeded: value - predicted))
      }
    }
    return output
  }

  /// A zlib stream (RFC 1950): header, deflate, Adler-32.
  private func zlib(_ bytes: [UInt8]) throws -> [UInt8] {
    var deflated = [UInt8](repeating: 0, count: bytes.count + 1_024)
    let count = bytes.withUnsafeBufferPointer { source in
      deflated.withUnsafeMutableBufferPointer { destination in
        compression_encode_buffer(
          destination.baseAddress!, destination.count, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
      }
    }
    try #require(count > 0)
    var (low, high): (UInt32, UInt32) = (1, 0)
    for byte in bytes {
      low = (low + UInt32(byte)) % 65_521
      high = (high + low) % 65_521
    }
    let adler = high << 16 | low
    return [0x78, 0x9C] + deflated.prefix(count) + [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: adler >> $0) }
  }

  /// Noisy grey samples: a gradient with a little noise on every sample.
  private func greySamples(width: Int, height: Int) -> [UInt8] {
    var seed: UInt32 = 3
    return (0..<(width * height)).map { index in
      seed = seed &* 1_664_525 &+ 1_013_904_223
      return UInt8(truncatingIfNeeded: (index / width) * 180 / height + 30 + Int(seed >> 27))
    }
  }

  /// A one-page PDF of objects written by hand, with a classic cross-reference table.
  private func handWritten(_ objects: [[UInt8]]) -> Data {
    var data = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
      offsets.append(data.count)
      data += Data("\(index + 1) 0 obj\n".utf8) + Data(body) + Data("\nendobj\n".utf8)
    }
    let start = data.count
    data += Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f\r\n".utf8)
    for offset in offsets { data += Data(String(format: "%010d 00000 n\r\n", offset).utf8) }
    data += Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8)
    return data
  }

  @Test("The PNG predictor is undone exactly, for each of its five filters")
  func predictorUndone() throws {
    let (width, height) = (37, 23)
    let samples = greySamples(width: width, height: height)
    let stream = try zlib(predicted(samples, width: width, height: height))
    let inflated = try #require(PDFImageRecompression.inflate(stream[...], count: (width + 1) * height))
    #expect(PDFImageRecompression.unpredicted(inflated, width: width, height: height, components: 1) == samples)
    #expect(PDFImageRecompression.inflate(stream[...], count: (width + 1) * height + 1) == nil, "Too short")
    #expect(PDFImageRecompression.inflate([0x00, 0x01, 0x02][...], count: 3) == nil, "Not zlib")
  }

  @Test("A grey picture with a PNG predictor, an indirect length and a soft mask is re-encoded; the mask is not")
  func handWrittenFile() throws {
    let (width, height) = (800, 600)
    let samples = greySamples(width: width, height: height)
    let picture = try zlib(predicted(samples, width: width, height: height))
    // Noisy too, so it would come out smaller as a JPEG if it were re-encoded.
    let mask = try zlib(greySamples(width: 400, height: 300))
    let content = Array("q 400 0 0 300 0 0 cm /Im1 Do Q".utf8)
    let objects: [[UInt8]] = [
      Array("<< /Type /Catalog /Pages 2 0 R >>".utf8),
      Array("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Array("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] ".utf8)
        + Array("/Resources << /XObject << /Im1 5 0 R >> >> /Contents 4 0 R >>".utf8),
      Array("<< /Length \(content.count) >>\nstream\n".utf8) + content + Array("\nendstream".utf8),
      Array(
        "<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceGray /BitsPerComponent 8 /SMask 7 0 R /Filter [/FlateDecode] /DecodeParms [<< /Predictor 15 /Colors 1 /Columns \(width) >>] /Length 6 0 R >>\nstream\n"
          .utf8) + picture + Array("\nendstream".utf8),
      Array("\(picture.count)".utf8),
      Array(
        "<< /Type /XObject /Subtype /Image /Width 400 /Height 300 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length \(mask.count) >>\nstream\n"
          .utf8) + mask + Array("\nendstream".utf8),
    ]
    let original = handWritten(objects)
    #expect(PDFDocument(data: original)?.pageCount == 1, "The hand-written file opens")
    let result = try #require(PDFImageRecompression.recompressed(original, settings: email))
    #expect(result.count < original.count)
    #expect(PDFDocument(data: result)?.pageCount == 1)
    let text = String(decoding: result, as: UTF8.self)
    #expect(text.components(separatedBy: "/DCTDecode").count == 2, "Only the picture, not its mask")
    #expect(text.contains("/SMask 7 0 R"))
    let before = try averageColour(original)
    let after = try averageColour(result)
    #expect(abs(before[0] - after[0]) < 6, "\(before) became \(after)")
  }
}
