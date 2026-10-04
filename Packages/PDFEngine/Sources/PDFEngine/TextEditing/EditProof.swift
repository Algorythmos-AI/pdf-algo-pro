import CoreGraphics
import Foundation
import PDFKit

/// A page rendered to pixels, for comparing what an edit changed.
struct PageBitmap {
  let width: Int
  let height: Int
  /// Rows of red, green, blue and one unused byte, top row first.
  let pixels: [UInt8]
  let bytesPerRow: Int
  /// Pixels per page point.
  let scale: Double
  /// The page's media box.
  let box: CGRect

  /// Renders the one page of a PDF, unrotated, on white.
  static func render(_ data: Data) throws -> PageBitmap {
    guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
      let page = document.page(at: 1)
    else { throw PDFEngineError.unreadable }
    let box = page.getBoxRect(.mediaBox)
    guard box.width > 1, box.height > 1, box.width.isFinite, box.height.isFinite else {
      throw PDFEngineError.renderFailed
    }
    let scale = min(EditProof.renderScale, EditProof.maximumPixels / Double(max(box.width, box.height)))
    let width = max(1, Int((box.width * scale).rounded()))
    let height = max(1, Int((box.height * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw PDFEngineError.renderFailed }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.minX, y: -box.minY)
    context.drawPDFPage(page)
    guard let image = context.makeImage(), let bytes = image.dataProvider?.data as Data? else {
      throw PDFEngineError.renderFailed
    }
    return PageBitmap(
      width: width, height: height, pixels: [UInt8](bytes), bytesPerRow: image.bytesPerRow, scale: scale, box: box)
  }

  /// The pixel rectangle a page rectangle covers, grown by `padding` pixels and kept on the bitmap.
  func pixelRect(_ rect: CGRect, padding: Int) -> (columns: Range<Int>, rows: Range<Int>) {
    let left = Int(((rect.minX - box.minX) * scale).rounded(.down)) - padding
    let right = Int(((rect.maxX - box.minX) * scale).rounded(.up)) + padding
    let top = height - Int(((rect.maxY - box.minY) * scale).rounded(.up)) - padding
    let bottom = height - Int(((rect.minY - box.minY) * scale).rounded(.down)) + padding
    let columns = max(0, min(width, left))..<max(0, min(width, max(left, right)))
    let rows = max(0, min(height, top))..<max(0, min(height, max(top, bottom)))
    return (columns, rows)
  }

  /// The largest difference in any colour channel between this bitmap and another at one pixel.
  func difference(from other: PageBitmap, column: Int, row: Int) -> Int {
    let offset = row * bytesPerRow + column * 4
    let otherOffset = row * other.bytesPerRow + column * 4
    guard offset + 2 < pixels.count, otherOffset + 2 < other.pixels.count else { return 255 }
    var largest = 0
    for channel in 0..<3 {
      largest = max(largest, abs(Int(pixels[offset + channel]) - Int(other.pixels[otherOffset + channel])))
    }
    return largest
  }

  /// A pixel's colour, reduced to 4 bits a channel so nearly equal colours compare equal.
  func coarseColor(column: Int, row: Int) -> Int {
    let offset = row * bytesPerRow + column * 4
    guard offset + 2 < pixels.count else { return 0 }
    return Int(pixels[offset] >> 4) << 8 | Int(pixels[offset + 1] >> 4) << 4 | Int(pixels[offset + 2] >> 4)
  }
}

/// Proves an edit did what was asked and nothing else, before the edited page goes anywhere near
/// the document.
///
/// An edit that fails any check is refused; the document is untouched.
///
/// Assumption: the tolerances below separate real differences from rendering noise. They are
/// validated by the invariant tests over every fixture, and tuned from the device test plan.
enum EditProof {
  /// Pixels per page point for the comparison renders.
  static let renderScale = 2.0
  /// The longest side of a comparison render, in pixels.
  static let maximumPixels = 2400.0
  /// How far a colour channel may differ before a pixel counts as changed.
  static let channelTolerance = 48
  /// The share of pixels outside the edited regions that may differ.
  static let strayShare = 0.0002
  /// The share of the new text's box that may already hold other ink.
  static let occupiedShare = 0.03
  /// How far a region may move, in points, and still count as the same region.
  static let positionTolerance = 1.0

  /// Checks an edit.
  ///
  /// - Parameters:
  ///   - before: The page as it was.
  ///   - erased: The page with the old text removed.
  ///   - after: The finished page.
  ///   - plans: What was drawn.
  ///   - regions: The page's regions before the edit.
  /// - Returns: `nil` when the edit is proven; otherwise why it is refused.
  static func refusal(
    before: Data, erased: Data, after: Data, plans: [PlannedText], regions: [TextRegion]
  ) -> TextEditRefusal? {
    guard let result = try? PageAnalysis(after) else { return .notVerified }
    let edited = Set(plans.map(\.region.id))

    // The new text reads as typed, where it was put.
    var claimed: Set<Int> = []
    for plan in plans {
      let expected = plan.bounds
      let match = result.regions.first {
        !claimed.contains($0.id) && squeezed($0.text) == squeezed(plan.text)
          && abs($0.bounds.minX - expected.minX) <= positionTolerance + 0.02 * expected.width
          && abs($0.bounds.midY - expected.midY) <= positionTolerance
      }
      guard let match else { return .notVerified }
      claimed.insert(match.id)
    }
    // Every other region is still there, with the same text in the same place.
    let untouched = regions.filter { !edited.contains($0.id) }
    guard result.regions.count == untouched.count + plans.count else { return .notVerified }
    for region in untouched {
      let match = result.regions.first {
        !claimed.contains($0.id) && $0.text == region.text
          && abs($0.bounds.minX - region.bounds.minX) <= positionTolerance
          && abs($0.bounds.minY - region.bounds.minY) <= positionTolerance
          && abs($0.bounds.width - region.bounds.width) <= positionTolerance
      }
      guard let match else { return .notVerified }
      claimed.insert(match.id)
    }

    // PDFKit, which reads independently of this engine, finds the new text too.
    guard let document = PDFDocument(data: after), document.pageCount == 1,
      let text = document.page(at: 0)?.string
    else { return .notVerified }
    let read = squeezed(text)
    guard plans.allSatisfy({ read.contains(squeezed($0.text)) }) else { return .notVerified }

    // The picture changed only where the text did.
    guard let old = try? PageBitmap.render(before), let blank = try? PageBitmap.render(erased),
      let new = try? PageBitmap.render(after), old.width == new.width, old.height == new.height,
      blank.width == new.width, blank.height == new.height, old.box == new.box
    else { return .notVerified }
    return pictureRefusal(old: old, blank: blank, new: new, plans: plans)
  }

  private static func pictureRefusal(
    old: PageBitmap, blank: PageBitmap, new: PageBitmap, plans: [PlannedText]
  ) -> TextEditRefusal? {
    // Room around each box for antialiasing, accents and the overhang of italics.
    var excluded = [Bool](repeating: false, count: new.width * new.height)
    for plan in plans {
      let padding = 3 + Int((plan.region.pointSize * 0.3 * new.scale).rounded(.up))
      for rect in [plan.region.bounds, plan.bounds] {
        let area = new.pixelRect(rect, padding: padding)
        for row in area.rows {
          for column in area.columns { excluded[row * new.width + column] = true }
        }
      }
    }
    var stray = 0
    for row in 0..<new.height {
      for column in 0..<new.width where !excluded[row * new.width + column] {
        if new.difference(from: old, column: column, row: row) > channelTolerance { stray += 1 }
      }
    }
    guard Double(stray) <= max(24, strayShare * Double(new.width * new.height)) else { return .notVerified }

    for plan in plans {
      let area = new.pixelRect(plan.bounds, padding: 0)
      let total = area.columns.count * area.rows.count
      guard total > 0 else { return .notVerified }
      // Where the new text goes was clear once the old text was gone: it prints over nothing.
      var colors: [Int: Int] = [:]
      for row in area.rows {
        for column in area.columns { colors[blank.coarseColor(column: column, row: row), default: 0] += 1 }
      }
      let background = colors.values.max() ?? 0
      guard Double(total - background) <= occupiedShare * Double(total) else { return .overlapsOtherContent }
      // And the new text is really there to see.
      var inked = 0
      for row in area.rows {
        for column in area.columns where new.difference(from: blank, column: column, row: row) > channelTolerance {
          inked += 1
        }
      }
      guard inked >= 8 else { return .notVerified }
    }
    return nil
  }

  /// Text with all whitespace removed, so line breaking and spacing differences do not matter.
  static func squeezed(_ text: String) -> String {
    String(text.precomposedStringWithCanonicalMapping.unicodeScalars.filter { !$0.properties.isWhitespace })
  }
}
