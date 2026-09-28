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
    pageCount: Int, mediaBox: (Int) -> CGRect, auxiliaryInfo: [CFString: Any] = [:],
    drawPage: (CGContext, Int, CGRect) throws -> Void
  ) throws -> Data {
    let data = NSMutableData()
    var firstBox = mediaBox(0)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &firstBox, auxiliaryInfo as CFDictionary)
    else { throw PDFEngineError.saveFailed }
    for index in 0..<pageCount {
      var box = mediaBox(index)
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
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    context.saveGState()
    context.textMatrix = .identity
    CTFrameDraw(frame, context)
    context.restoreGState()
  }

  /// Draws recognised lines as invisible text over a page, so the page becomes searchable and
  /// selectable without changing how it looks (FR-SCAN-002).
  static func drawInvisibleText(_ lines: [RecognizedLine], in box: CGRect, context: CGContext) {
    context.saveGState()
    context.setTextDrawingMode(.invisible)
    for line in lines where !line.text.isEmpty {
      let frame = CGRect(
        x: box.minX + line.bounds.minX * box.width, y: box.minY + line.bounds.minY * box.height,
        width: line.bounds.width * box.width, height: line.bounds.height * box.height)
      guard frame.width > 1, frame.height > 1 else { continue }
      let font = CTFontCreateWithName("Helvetica" as CFString, frame.height * 0.85, nil)
      let attributed = NSAttributedString(
        string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
      let ctLine = CTLineCreateWithAttributedString(attributed)
      var descent: CGFloat = 0
      let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, &descent, nil))
      guard width > 0 else { continue }
      context.textMatrix = CGAffineTransform(scaleX: frame.width / width, y: 1)
      context.textPosition = CGPoint(x: frame.minX, y: frame.minY + descent)
      CTLineDraw(ctLine, context)
    }
    context.restoreGState()
  }
}
