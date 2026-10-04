import CoreGraphics
import Foundation

/// Where new text is anchored when it is not the same width as the text it replaces.
enum TextAlignment {
  case leading
  case centre
  case trailing
}

/// A region of a page as the editor works with it: its runs, where it is, and what limits an edit.
///
/// Lengths ending in "drawn" are in drawing units: page points measured against the text's own
/// height, so a font of `pointSize` drawn in them is the size the text is on the page whatever the
/// text matrix does to its width.
struct TextRegion {
  /// The index of the first run's operator: stable for the same content.
  let id: Int
  /// Indexes into the page's runs.
  let runs: [Int]
  /// The text as it reads, without spaces at either end.
  let text: String
  let font: TextFont
  /// The text's height on the page, in points.
  let pointSize: Double
  /// Drawing units to page space, with the origin at the start of the baseline.
  let drawing: CGAffineTransform
  /// The horizontal scaling of the text state (`Tz`), as a fraction.
  let horizontalScale: Double
  /// The ink's width in drawing units, without spaces at the end.
  let widthDrawn: Double
  let bounds: CGRect
  let fill: [Double]
  let characterSpacingDrawn: Double
  var alignment = TextAlignment.leading
  /// Whether the line runs margin to margin, so new text is fitted to the same width.
  var isJustified = false
  /// Free space before and after the ink along the baseline, in drawing units.
  var roomBefore = 0.0
  var roomAfter = 0.0
  /// Why the page's content cannot be edited for this region, if it cannot.
  var refusal: TextEditRefusal?

  /// The baseline's angle in page space.
  var angle: Double { atan2(Double(drawing.b), Double(drawing.a)) }

  /// A stretch of the baseline in the region's drawing units, as the box its text covers in page space.
  func pageBox(fromDrawn x: Double, width: Double) -> CGRect {
    Self.pageBox(font: font, pointSize: pointSize, drawing: drawing, fromDrawn: x, width: width)
  }

  /// The box text covers in page space: from the font's descent to its ascent along a stretch of
  /// the baseline.
  static func pageBox(
    font: TextFont, pointSize: Double, drawing: CGAffineTransform, fromDrawn x: Double, width: Double
  ) -> CGRect {
    let ascent = font.ascent / 1000 * pointSize
    let descent = font.descent / 1000 * pointSize
    return CGRect(x: x, y: descent, width: width, height: ascent - descent).applying(drawing)
  }
}

/// Groups a page's text runs into regions and decides what can be done with each.
enum TextRegionBuilder {
  private struct Placed {
    let index: Int
    let run: TextRun
    let font: TextFont
    let text: String
    let advance: Double
    let origin: CGPoint
    let across: CGVector
    let up: CGVector
    let scaleAcross: Double
    let scaleUp: Double
    var pointSize: Double { run.fontSize * scaleUp }
    var end: CGPoint {
      CGPoint(x: origin.x + across.dx * advance * scaleAcross, y: origin.y + across.dy * advance * scaleAcross)
    }
  }

  /// The regions of a page, in drawing order.
  static func regions(of content: PageContent, pageBox: CGRect) -> [TextRegion] {
    var groups: [[Placed]] = []
    var separators: [[Bool]] = []
    for (index, run) in content.runs.enumerated() {
      guard let placed = place(run, at: index) else {
        // Text that cannot be read or located ends the region before it.
        groups.append([])
        separators.append([])
        continue
      }
      if let last = groups.last?.last, let gap = gap(from: last, to: placed) {
        let needsSpace =
          gap > 0.18 * placed.pointSize && !last.text.hasSuffix(" ") && !placed.text.hasPrefix(" ")
        groups[groups.count - 1].append(placed)
        separators[separators.count - 1].append(needsSpace)
      } else {
        groups.append([placed])
        separators.append([false])
      }
    }
    var regions: [TextRegion] = []
    for (group, spaces) in zip(groups, separators) {
      if let region = region(from: group, spaces: spaces, content: content, pageBox: pageBox) {
        regions.append(region)
      }
    }
    return arranged(regions, content: content, pageBox: pageBox)
  }

  /// A run with the geometry needed to group it; `nil` when it cannot be part of a region.
  private static func place(_ run: TextRun, at index: Int) -> Placed? {
    guard let font = run.font, !font.isType3, let text = run.text, let advance = run.advance, run.positionIsKnown,
      run.renderingMode != 3, run.fontSize > 0, run.horizontalScale > 0
    else { return nil }
    let transform = run.transform
    let scaleAcross = hypot(Double(transform.a), Double(transform.b))
    let scaleUp = hypot(Double(transform.c), Double(transform.d))
    let values = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
    guard scaleAcross > 1e-6, scaleUp > 1e-6, values.allSatisfy(\.isFinite), advance.isFinite else { return nil }
    return Placed(
      index: index, run: run, font: font, text: text, advance: advance,
      origin: CGPoint(x: 0, y: run.rise).applying(transform),
      across: CGVector(dx: transform.a / scaleAcross, dy: transform.b / scaleAcross),
      up: CGVector(dx: transform.c / scaleUp, dy: transform.d / scaleUp), scaleAcross: scaleAcross,
      scaleUp: scaleUp)
  }

  /// The distance along the baseline from one run's end to the next run's start, when the next run
  /// carries on the same line in the same style; `nil` when it starts something new.
  private static func gap(from last: Placed, to next: Placed) -> Double? {
    let size = last.pointSize
    guard last.font.postScriptName == next.font.postScriptName, abs(next.pointSize - size) <= 0.02 * size,
      last.run.fill == next.run.fill, last.run.renderingMode == next.run.renderingMode,
      abs(last.run.horizontalScale - next.run.horizontalScale) < 0.001,
      abs(last.scaleAcross / last.scaleUp - next.scaleAcross / next.scaleUp) < 0.001,
      last.across.dx * next.across.dx + last.across.dy * next.across.dy > 0.9999,
      last.up.dx * next.up.dx + last.up.dy * next.up.dy > 0.9999
    else { return nil }
    let end = last.end
    let delta = CGVector(dx: next.origin.x - end.x, dy: next.origin.y - end.y)
    let along = delta.dx * last.across.dx + delta.dy * last.across.dy
    let off = -delta.dx * last.across.dy + delta.dy * last.across.dx
    guard abs(off) <= 0.1 * size, along >= -0.3 * size, along <= 0.6 * size else { return nil }
    return along
  }

  private static func region(
    from group: [Placed], spaces: [Bool], content: PageContent, pageBox: CGRect
  ) -> TextRegion? {
    guard let first = group.first, let last = group.last else { return nil }
    var text = ""
    for (placed, needsSpace) in zip(group, spaces) {
      if needsSpace { text += " " }
      text += placed.text
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Drawing units: one unit up is one page point; the text matrix's own stretch stays across.
    let transform = first.run.transform
    let drawing = CGAffineTransform(
      a: transform.a / first.scaleUp, b: transform.b / first.scaleUp, c: transform.c / first.scaleUp,
      d: transform.d / first.scaleUp, tx: first.origin.x, ty: first.origin.y)
    let end = last.end
    let lengthOnPage = hypot(end.x - first.origin.x, end.y - first.origin.y)
    let trailing = last.run.trailingSpace * last.scaleAcross
    let widthDrawn = max(0, lengthOnPage - trailing) / (first.scaleAcross / first.scaleUp)
    guard widthDrawn > 0 else { return nil }

    var region = TextRegion(
      id: first.run.operation, runs: group.map(\.index), text: trimmed, font: first.font,
      pointSize: first.pointSize, drawing: drawing, horizontalScale: first.run.horizontalScale,
      widthDrawn: widthDrawn,
      bounds: TextRegion.pageBox(
        font: first.font, pointSize: first.pointSize, drawing: drawing, fromDrawn: 0, width: widthDrawn),
      fill: first.run.fill ?? [0], characterSpacingDrawn: first.run.characterSpacing * first.scaleUp)
    region.refusal = refusal(for: region, group: group, content: content, pageBox: pageBox)
    return region
  }

  private static func refusal(
    for region: TextRegion, group: [Placed], content: PageContent, pageBox: CGRect
  ) -> TextEditRefusal? {
    for placed in group {
      let run = placed.run
      if run.renderingMode != 0 || run.fill == nil || run.hasTransparency || run.clipIsComplex || run.isInLayer {
        return .unsupportedDrawing
      }
      if let clip = run.clip, !clip.insetBy(dx: -1, dy: -1).contains(region.bounds) { return .unsupportedDrawing }
    }
    guard region.text.unicodeScalars.allSatisfy(TextScript.isSimple) else { return .unsupportedScript }
    // New text is drawn last, so text that something later is drawn over cannot keep its place.
    let lastOperation = group.map(\.run.operation).max() ?? 0
    let core = region.bounds.insetBy(dx: 0, dy: region.bounds.height * 0.2)
    if content.painted.contains(where: { $0.operation > lastOperation && $0.box.intersects(core) }) {
      return .overlapsOtherContent
    }
    guard pageBox.insetBy(dx: -1, dy: -1).contains(region.bounds) else { return .unsupportedDrawing }
    return nil
  }

  // MARK: - Alignment and room

  /// Works out, from the other regions, how each region is aligned and how much room it has.
  private static func arranged(_ regions: [TextRegion], content: PageContent, pageBox: CGRect) -> [TextRegion] {
    var result = regions
    for index in result.indices {
      var region = result[index]
      guard abs(region.angle) < 0.001, region.drawing.a > 0, region.drawing.d > 0 else {
        // Rotated text keeps exactly the space it has.
        continue
      }
      let others = regions.enumerated().filter { $0.offset != index && abs($0.element.angle) < 0.001 }
        .map(\.element.bounds)
      let box = region.bounds
      let sharesStart = others.contains { abs($0.minX - box.minX) < 1 }
      let sharesEnd = others.contains { abs($0.maxX - box.maxX) < 1 }
      let sharesMiddle = others.contains { abs($0.midX - box.midX) < 1 && abs($0.width - box.width) > 2 }
      // Regions that share only their end with this one, as amounts in a column do, and only
      // their start, as lines of a paragraph do.
      let endOnly = others.contains { abs($0.maxX - box.maxX) < 1 && abs($0.minX - box.minX) >= 1 }
      let startOnly = others.contains { abs($0.minX - box.minX) < 1 && abs($0.maxX - box.maxX) >= 1 }
      if sharesStart && sharesEnd && region.text.split(separator: " ").count >= 3 {
        region.isJustified = true
      } else if sharesEnd && (!sharesStart || (endOnly && !startOnly)) {
        region.alignment = .trailing
      } else if sharesMiddle && !sharesStart {
        region.alignment = .centre
      }

      // Obstacles on the same line: other text and anything painted.
      let band = box.insetBy(dx: 0, dy: box.height * 0.2)
      let obstacles = others + content.painted.map(\.box).filter { $0.width < pageBox.width * 0.9 }
      let margin = min(36, max(0, box.minX - pageBox.minX))
      var limitAfter = pageBox.maxX - margin
      var limitBefore = pageBox.minX + min(36, max(0, pageBox.maxX - box.maxX))
      for obstacle in obstacles where obstacle.maxY > band.minY && obstacle.minY < band.maxY {
        if obstacle.minX >= box.maxX - 0.5 { limitAfter = min(limitAfter, obstacle.minX - 0.25 * region.pointSize) }
        if obstacle.maxX <= box.minX + 0.5 { limitBefore = max(limitBefore, obstacle.maxX + 0.25 * region.pointSize) }
      }
      let unit = Double(region.drawing.a)
      region.roomAfter = max(0, Double(limitAfter - box.maxX)) / unit
      region.roomBefore = max(0, Double(box.minX - limitBefore)) / unit
      result[index] = region
    }
    return result
  }
}

/// Which characters text editing draws itself.
enum TextScript {
  /// Whether a character belongs to a script that needs no shaping and runs left to right: Latin,
  /// Greek, Cyrillic, punctuation, symbols and CJK.
  ///
  /// Right-to-left and shaped scripts are left to a fuller engine (ADR-0025).
  static func isSimple(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x20...0x58F, 0x1E00...0x20CF, 0x2100...0x2BFF, 0x3000...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF,
      0xFB00...0xFB06, 0xFF00...0xFFEF:
      true
    default:
      false
    }
  }
}
