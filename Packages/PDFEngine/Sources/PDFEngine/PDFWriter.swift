import Core
import CoreGraphics
import CoreText
import Foundation

/// Writes PDFs with Core Graphics: synthetic documents, and scans with an invisible text layer.
enum PDFWriter {
  /// US Letter in points, the page size for generated documents.
  static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

  /// Creates a PDF, calling `drawPage` once per page with a context set up for that page.
  static func makePDF(
    mediaBoxes: [CGRect], auxiliaryInfo: [CFString: Any] = [:], drawPage: (CGContext, Int, CGRect) throws -> Void
  ) throws -> Data {
    let data = NSMutableData()
    var firstBox = mediaBoxes.first ?? letter
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &firstBox, auxiliaryInfo as CFDictionary)
    else { throw PDFEngineError.saveFailed }
    for (index, mediaBox) in mediaBoxes.enumerated() {
      var box = mediaBox
      let pageInfo = [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
      context.beginPDFPage(pageInfo)
      try drawPage(context, index, box)
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }

  /// Draws wrapped text inside a rectangle, top to bottom.
  static func drawText(_ text: String, in rect: CGRect, fontSize: CGFloat, context: CGContext) {
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let frame = CTFramesetterCreateFrame(
      framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    context.saveGState()
    context.textMatrix = .identity
    CTFrameDraw(frame, context)
    context.restoreGState()
  }

  /// Draws recognised lines as invisible text over a page, so the page becomes searchable and
  /// selectable without changing how it looks (FR-SCAN-002).
  ///
  /// A line that comes with its words is drawn word by word, each over its own box, so one word
  /// can be selected; a line without them is drawn as one piece stretched over the line's box.
  static func drawInvisibleText(_ lines: [RecognizedLine], in box: CGRect, context: CGContext) {
    context.saveGState()
    context.setTextDrawingMode(.invisible)
    for line in lines where !line.text.isEmpty {
      let frame = pageRect(line.bounds, in: box)
      guard frame.width > 1, frame.height > 1 else { continue }
      let words = (line.words ?? []).filter { !$0.text.isEmpty }
      // The words are used only when together they are the line: otherwise text would be lost.
      if !words.isEmpty, words.map(\.text).joined(separator: " ") == line.text {
        for (index, word) in words.enumerated() {
          let place = pageRect(word.bounds, in: box)
          // The line's height for every word, so the words of a line share one baseline and size.
          let rect = CGRect(x: place.minX, y: frame.minY, width: place.width, height: frame.height)
          // A space after each word but the last, so the line still reads as separate words.
          draw(word.text, trailing: index < words.count - 1 ? " " : "", over: rect, context: context)
        }
      } else {
        draw(line.text, trailing: "", over: frame, context: context)
      }
    }
    context.restoreGState()
  }

  /// A box given in fractions of a page, in the page's own units.
  private static func pageRect(_ bounds: CGRect, in box: CGRect) -> CGRect {
    CGRect(
      x: box.minX + bounds.minX * box.width, y: box.minY + bounds.minY * box.height,
      width: bounds.width * box.width, height: bounds.height * box.height)
  }

  /// The fonts tried for the text layer, in order: Helvetica, as always, then two more.
  static let layerFontNames = ["Helvetica", "Arial", "Times New Roman"]

  /// One font that has every letter of a piece of text.
  ///
  /// A font without one of the letters makes Core Text draw that letter from another font, in a
  /// run of its own. When none of the named fonts has every letter, the one Core Text suggests
  /// for the text is used.
  static func layerFont(for text: String, size: CGFloat) -> CTFont {
    let characters = Array(text.utf16)
    for name in layerFontNames {
      let font = CTFontCreateWithName(name as CFString, size, nil)
      var glyphs = [CGGlyph](repeating: 0, count: characters.count)
      if CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) { return font }
    }
    let base = CTFontCreateWithName(layerFontNames[0] as CFString, size, nil)
    return CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: characters.count))
  }

  /// Draws text stretched sideways to cover a box exactly, followed by `trailing` past its end.
  ///
  /// The stretch is put on the drawing space, not on the text matrix. Measured on 2026-10-08: a
  /// scale on the text matrix does not change how wide the text is drawn, and where the text is
  /// wider than its box, or has letters such as "ż" or "ř", it reads back in pieces ("Za ż ó łć").
  /// With the drawing space scaled, the text is as wide as its box and reads back whole.
  private static func draw(_ text: String, trailing: String, over frame: CGRect, context: CGContext) {
    guard frame.width > 0.5, frame.height > 1 else { return }
    let font = layerFont(for: text, size: frame.height * 0.85)
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let measured = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    var descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(measured, nil, &descent, nil))
    guard width > 0 else { return }
    let drawn =
      trailing.isEmpty
      ? measured : CTLineCreateWithAttributedString(NSAttributedString(string: text + trailing, attributes: attributes))
    context.saveGState()
    context.translateBy(x: frame.minX, y: frame.minY + descent)
    context.scaleBy(x: frame.width / width, y: 1)
    context.textMatrix = .identity
    context.textPosition = .zero
    CTLineDraw(drawn, context)
    context.restoreGState()
  }
}
