import CoreGraphics
import CoreText
import Foundation

/// Chooses the font new text is drawn in.
///
/// PDFKit rewrites every font as a subset holding only the letters already on the page, so the
/// document's font usually cannot spell new words. The order is therefore: the same font from the
/// device, then the document's embedded font if it happens to have every letter needed, then the
/// closest standard font. The fallback is deterministic: it depends only on the original font's
/// traits.
enum FontMatcher {
  /// A font to draw with, and whether it is the same typeface as the original.
  struct Match {
    let font: CTFont
    let isExact: Bool
  }

  /// The font on this device with exactly this PostScript name, if there is one.
  static func deviceFont(named name: String, size: CGFloat) -> CTFont? {
    // Names starting with a full stop are private system fonts, which must not be asked for by name.
    guard !name.isEmpty, !name.hasPrefix(".") else { return nil }
    let font = CTFontCreateWithName(name as CFString, size, nil)
    // Core Text answers an unknown name with a different font instead of failing.
    return CTFontCopyPostScriptName(font) as String == name ? font : nil
  }

  /// Whether the device has the font itself, so new text will match exactly.
  static func hasDeviceFont(for font: TextFont) -> Bool {
    deviceFont(named: font.postScriptName, size: 12) != nil
  }

  /// The font to draw `text` with in place of `font`.
  ///
  /// - Parameters:
  ///   - font: The document's font.
  ///   - size: The size to draw at, in points.
  ///   - text: The new words.
  ///   - original: The words the font is replacing and how wide they are set, in points at `size`,
  ///     when known. A substitute is then chosen by how closely it sets the same words.
  /// - Returns: The font, and whether it is the original typeface.
  static func match(
    _ font: TextFont, size: CGFloat, text: String, original: (text: String, width: Double)? = nil
  ) -> Match {
    if let device = deviceFont(named: font.postScriptName, size: size) { return Match(font: device, isExact: true) }
    if let program = font.program, let provider = CGDataProvider(data: program as CFData),
      let embedded = CGFont(provider)
    {
      let candidate = CTFontCreateWithGraphicsFont(embedded, size, nil, nil)
      if covers(candidate, text) { return Match(font: candidate, isExact: true) }
    }
    return Match(font: fallback(for: font, size: size, original: original), isExact: false)
  }

  /// Whether a font has a glyph for every character of a text.
  static func covers(_ font: CTFont, _ text: String) -> Bool {
    var characters = Array(text.utf16)
    guard !characters.isEmpty else { return true }
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    return CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
  }

  /// Families to substitute from, as PostScript names for regular, bold, italic and bold italic.
  ///
  /// The first of each list is the standard choice; the others ship with iOS and macOS too.
  private static let fixedPitch = [["Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique"]]
  private static let serif = [
    ["TimesNewRomanPSMT", "TimesNewRomanPS-BoldMT", "TimesNewRomanPS-ItalicMT", "TimesNewRomanPS-BoldItalicMT"],
    ["Georgia", "Georgia-Bold", "Georgia-Italic", "Georgia-BoldItalic"],
    ["Palatino-Roman", "Palatino-Bold", "Palatino-Italic", "Palatino-BoldItalic"],
  ]
  private static let sans = [
    ["Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique"],
    ["HelveticaNeue", "HelveticaNeue-Bold", "HelveticaNeue-Italic", "HelveticaNeue-BoldItalic"],
    ["ArialMT", "Arial-BoldMT", "Arial-ItalicMT", "Arial-BoldItalicMT"],
    ["Verdana", "Verdana-Bold", "Verdana-Italic", "Verdana-BoldItalic"],
    ["TrebuchetMS", "TrebuchetMS-Bold", "TrebuchetMS-Italic", "Trebuchet-BoldItalic"],
  ]

  /// The closest standard font: fixed-pitch for fixed-pitch text, serif for serif text, sans
  /// serif otherwise, in the original's weight and slant.
  ///
  /// Without `original` it is Courier, Times New Roman or Helvetica. With it, the family is the
  /// one of its kind that sets the original words closest to their original width: the new words
  /// then take about the room the old ones did, which is what makes a substitute look right and
  /// fit. It is deterministic: it depends only on the original font's traits and those words.
  static func fallback(
    for font: TextFont, size: CGFloat, original: (text: String, width: Double)? = nil
  ) -> CTFont {
    let lowered = font.postScriptName.lowercased()
    let serifNames = ["times", "georgia", "garamond", "cambria", "serif", "roman", "palatino", "baskerville", "book"]
    let families: [[String]]
    if font.isFixedPitch || lowered.contains("courier") || lowered.contains("mono") {
      families = fixedPitch
    } else if font.isSerif || (serifNames.contains(where: lowered.contains) && !lowered.contains("sans")) {
      families = serif
    } else {
      families = sans
    }
    let style = (font.isBold ? 1 : 0) + (font.isItalic ? 2 : 0)
    let standard = CTFontCreateWithName(families[0][style] as CFString, size, nil)
    guard let original, original.width > 0, !original.text.isEmpty, families.count > 1 else { return standard }
    var best = standard
    var smallest = Double.infinity
    for family in families {
      guard let candidate = deviceFont(named: family[style], size: size), covers(candidate, original.text) else {
        continue
      }
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(
          string: original.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): candidate]))
      let width = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
      let difference = abs(width - original.width)
      // The standard family wins a tie, and anything within half a percent of it.
      if difference < smallest - 0.005 * original.width {
        smallest = difference
        best = candidate
      }
    }
    return best
  }
}

/// New text for a region, laid out and ready to draw.
struct PlannedText {
  let region: TextRegion
  let text: String
  let line: CTLine
  /// Extra horizontal narrowing so slightly long text fits, as a fraction (1 is none).
  let fit: Double
  /// Where the text starts along the baseline, in the region's drawing units.
  let startDrawn: Double
  /// How wide the text is, in the region's drawing units.
  let widthDrawn: Double
  let mode: TextEditMode
  /// How far the text is moved from where the old text was, in page space.
  var offset = CGVector.zero

  /// Where the new text's ink falls, in page space.
  var bounds: CGRect { region.pageBox(fromDrawn: startDrawn, width: widthDrawn).offsetBy(dx: offset.dx, dy: offset.dy) }

  /// Where the new text's baseline starts, in page space.
  var baselineStart: CGPoint {
    let start = CGPoint(x: startDrawn, y: 0).applying(region.drawing)
    return CGPoint(x: start.x + offset.dx, y: start.y + offset.dy)
  }
}

/// Whether a replacement could be laid out.
enum TextPlanning {
  case planned(PlannedText)
  /// It could not; the outcome says why.
  case declined(TextEditOutcome)
}

/// Lays out replacement text with Core Text and draws it onto a page whose old text was erased.
enum TextRedrawer {
  /// The narrowest new text may be squeezed so that it fits.
  ///
  /// Assumption: 90% is not noticeable in body text; validated by the device test plan.
  static let minimumFit = 0.9
  /// How much a justified line may change in width and still be fitted margin to margin.
  ///
  /// Assumption: 3% is absorbed by word spacing without looking loose or tight; validated by the
  /// device test plan.
  static let justifiedTolerance = 0.03

  /// Lays out a region's replacement, or says why it cannot be drawn.
  ///
  /// - Parameters:
  ///   - region: The text to replace.
  ///   - replacement: The new words.
  ///   - move: How far to move the text, in page space. Moved text is set at its natural width
  ///     from where its line started: the room it had beside its old neighbours says nothing about
  ///     the new place, which the proof checks is clear.
  /// - Returns: The laid-out text, or why it could not be laid out.
  static func plan(_ region: TextRegion, replacement: String, offset move: CGVector = .zero) -> TextPlanning {
    let text = replacement.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.unicodeScalars.allSatisfy(TextScript.isSimple) else {
      return .declined(.refused(.unsupportedCharacters))
    }
    let size = CGFloat(region.pointSize)
    // The old words and their width tell a substitute font apart from its neighbours. A justified
    // line is wider than its words, and letter spacing widens them too, so those say nothing.
    let stretch = region.horizontalScale
    let spaced = abs(region.characterSpacingDrawn) > 0.01 * region.pointSize
    let oldWords =
      region.isJustified || spaced || stretch <= 0 ? nil : (text: region.text, width: region.widthDrawn / stretch)
    let match = FontMatcher.match(region.font, size: size, text: text, original: oldWords)
    var attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): match.font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(region.fill),
    ]
    if abs(region.characterSpacingDrawn) > 0.01 * region.pointSize {
      attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = region.characterSpacingDrawn
    }
    var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    guard CTLineGetGlyphCount(line) > 0 else { return .declined(.refused(.unsupportedCharacters)) }
    // Core Text draws a character the font lacks in another font. That is still real text, but it
    // is not the original typeface; a character no font has cannot be drawn at all.
    var substituted = false
    let whole = text as NSString
    var offset = 0
    for character in text {
      let length = String(character).utf16.count
      defer { offset += length }
      if FontMatcher.covers(match.font, String(character)) { continue }
      substituted = true
      let other = CTFontCreateForString(match.font, whole, CFRange(location: offset, length: length))
      if CTFontCopyPostScriptName(other) as String == "LastResort" {
        return .declined(.refused(.unsupportedCharacters))
      }
    }

    let natural = (CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)) * stretch
    guard natural.isFinite, natural > 0 else { return .declined(.refused(.unsupportedCharacters)) }
    let original = region.widthDrawn
    var fit = 1.0
    var start = 0.0
    var width = natural
    // A justified line is wider than its words set naturally, so the change is measured between
    // the old and new words, both set naturally.
    let before = CTLineCreateWithAttributedString(NSAttributedString(string: region.text, attributes: attributes))
    let naturalBefore =
      (CTLineGetTypographicBounds(before, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(before)) * stretch
    if region.isJustified, abs(natural - naturalBefore) <= justifiedTolerance * original, natural >= 0.7 * original,
      natural <= original * (1 + justifiedTolerance),
      let justified = CTLineCreateJustifiedLine(line, 1, original / stretch)
    {
      line = justified
      width = original
    } else if move != .zero {
      // Moved: nothing to fit against.
      start = 0
    } else {
      let room: Double =
        switch region.alignment {
        case .leading: original + region.roomAfter
        case .trailing: original + region.roomBefore
        case .centre: original + 2 * min(region.roomBefore, region.roomAfter)
        }
      if natural > room {
        guard natural * minimumFit <= room else { return .declined(.tooLong) }
        fit = room / natural
        width = room
      }
      start =
        switch region.alignment {
        case .leading: 0
        case .trailing: original - width
        case .centre: (original - width) / 2
        }
    }
    return .planned(
      PlannedText(
        region: region, text: text, line: line, fit: fit, startDrawn: start, widthDrawn: width,
        mode: match.isExact && !substituted ? .contentStream : .contentStreamWithFallbackFont, offset: move))
  }

  private static func color(_ components: [Double]) -> CGColor {
    switch components.count {
    case 3: CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
    case 4:
      CGColor(
        genericCMYKCyan: components[0], magenta: components[1], yellow: components[2], black: components[3],
        alpha: 1)
    default: CGColor(gray: components.first ?? 0, alpha: 1)
    }
  }

  /// Draws the erased page, then each planned text where the old text was.
  ///
  /// - Parameters:
  ///   - plans: The texts to draw.
  ///   - erased: A one-page PDF with the old text already removed from its content.
  /// - Returns: A new one-page PDF. Core Graphics embeds the fonts and writes ordinary text
  ///   operators, so the new text is real text in the page's content.
  /// - Throws: `PDFEngineError.unreadable` when the erased page cannot be read, or
  ///   `PDFEngineError.saveFailed` when the new page cannot be written.
  static func draw(_ plans: [PlannedText], over erased: Data) throws -> Data {
    guard let provider = CGDataProvider(data: erased as CFData), let document = CGPDFDocument(provider),
      let page = document.page(at: 1)
    else { throw PDFEngineError.unreadable }
    return try PDFWriter.makePDF(mediaBoxes: [page.getBoxRect(.mediaBox)]) { context, _, _ in
      context.drawPDFPage(page)
      for plan in plans {
        let across = plan.region.horizontalScale * plan.fit
        context.saveGState()
        context.translateBy(x: plan.offset.dx, y: plan.offset.dy)
        context.concatenate(plan.region.drawing)
        context.scaleBy(x: across, y: 1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: plan.startDrawn / across, y: 0)
        CTLineDraw(plan.line, context)
        context.restoreGState()
      }
    }
  }
}
