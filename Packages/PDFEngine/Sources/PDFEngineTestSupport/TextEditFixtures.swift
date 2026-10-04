import CoreGraphics
import CoreText
import Foundation
import PDFEngine
import PDFKit

/// Synthetic PDFs for the text editing tests: generated in code, never real documents (AGENTS.md
/// rule 6).
///
/// The fonts named here ship with both iOS and macOS, so no font file is committed.
public enum TextEditFixtures {
  /// How a line sits against its anchor point.
  public enum Anchor: Sendable {
    /// The line starts at the point.
    case leading
    /// The line is centred on the point.
    case centre
    /// The line ends at the point.
    case trailing
  }

  /// One line of text to draw.
  public struct Line: Sendable {
    /// The text.
    public var text: String
    /// The PostScript name of the font.
    public var font: String
    /// The font size in points.
    public var size: CGFloat
    /// The anchor point of the baseline, in page space.
    public var point: CGPoint
    /// How the line sits against the point.
    public var anchor: Anchor
    /// The baseline's angle, in radians.
    public var angle: CGFloat
    /// The colour as red, green and blue from 0 to 1.
    public var color: [CGFloat]
    /// When set, the line is stretched to exactly this width, as a justified line is.
    public var justifiedWidth: CGFloat?

    /// Creates a line.
    public init(
      _ text: String, font: String = "Georgia", size: CGFloat = 12, at point: CGPoint, anchor: Anchor = .leading,
      angle: CGFloat = 0, color: [CGFloat] = [0, 0, 0], justifiedWidth: CGFloat? = nil
    ) {
      self.text = text
      self.font = font
      self.size = size
      self.point = point
      self.anchor = anchor
      self.angle = angle
      self.color = color
      self.justifiedWidth = justifiedWidth
    }
  }

  /// Why a fixture could not be made.
  public struct Failure: Error {
    /// Creates the error.
    public init() {}
  }

  /// US Letter.
  public static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

  /// A PDF drawn with Core Graphics and Core Text, one array of lines per page.
  ///
  /// - Parameters:
  ///   - pages: The lines of each page.
  ///   - box: The media box of every page.
  ///   - decorate: Draws anything else a page needs, before its text.
  ///   - finish: Draws anything a page needs over its text.
  /// - Returns: The PDF's data.
  /// - Throws: `Failure` if Core Graphics cannot create the PDF.
  public static func make(
    pages: [[Line]], box: CGRect = letter, decorate: (CGContext, Int) -> Void = { _, _ in },
    finish: (CGContext, Int) -> Void = { _, _ in }
  ) throws -> Data {
    let data = NSMutableData()
    var mediaBox = box
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { throw Failure() }
    for (index, lines) in pages.enumerated() {
      context.beginPDFPage(nil)
      context.saveGState()
      decorate(context, index)
      context.restoreGState()
      for line in lines { draw(line, in: context) }
      context.saveGState()
      finish(context, index)
      context.restoreGState()
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }

  /// Draws one line.
  public static func draw(_ line: Line, in context: CGContext) {
    let font = CTFontCreateWithName(line.font as CFString, line.size, nil)
    let color = CGColor(
      srgbRed: line.color.first ?? 0, green: line.color.dropFirst().first ?? 0,
      blue: line.color.dropFirst(2).first ?? 0, alpha: 1)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    var typeset = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
    if let width = line.justifiedWidth, let justified = CTLineCreateJustifiedLine(typeset, 1, Double(width)) {
      typeset = justified
    }
    let width = CGFloat(CTLineGetTypographicBounds(typeset, nil, nil, nil))
    let offset: CGFloat =
      switch line.anchor {
      case .leading: 0
      case .centre: -width / 2
      case .trailing: -width
      }
    context.saveGState()
    context.translateBy(x: line.point.x, y: line.point.y)
    context.rotate(by: line.angle)
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: offset, y: 0)
    CTLineDraw(typeset, context)
    context.restoreGState()
  }

  /// The one page of a PDF as PDFKit writes it on its own: what the editor is given to work on.
  @MainActor
  public static func singlePage(_ data: Data, pageIndex: Int = 0, password: String? = nil) throws -> Data {
    guard let document = PDFDocument(data: data) else { throw Failure() }
    if let password { document.unlock(withPassword: password) }
    guard let page = document.page(at: pageIndex), let copy = page.copy() as? PDFPage else { throw Failure() }
    for annotation in copy.annotations { copy.removeAnnotation(annotation) }
    let single = PDFDocument()
    single.insert(copy, at: 0)
    guard let result = single.dataRepresentation() else { throw Failure() }
    return result
  }

  // MARK: - The acceptance scenarios

  /// Scenario 1: an invoice with a customer name, a table with amounts aligned on the right, and a
  /// total.
  public static func invoice() throws -> Data {
    try make(pages: [
      [
        Line("Invoice", font: "Helvetica-Bold", size: 22, at: CGPoint(x: 72, y: 720)),
        Line("Customer: John Smith", at: CGPoint(x: 72, y: 680)),
        Line("Invoice number: INV-2026-0042", at: CGPoint(x: 72, y: 662)),
        Line("Fence repair", font: "Helvetica", size: 11, at: CGPoint(x: 72, y: 610)),
        Line("$950.00", font: "Helvetica", size: 11, at: CGPoint(x: 540, y: 610), anchor: .trailing),
        Line("Materials", font: "Helvetica", size: 11, at: CGPoint(x: 72, y: 592)),
        Line("$300.00", font: "Helvetica", size: 11, at: CGPoint(x: 540, y: 592), anchor: .trailing),
        Line("Total", font: "Helvetica-Bold", size: 11, at: CGPoint(x: 72, y: 560)),
        Line("$1,250.00", font: "Helvetica-Bold", size: 11, at: CGPoint(x: 540, y: 560), anchor: .trailing),
      ]
    ]) { context, _ in
      context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
      context.stroke(CGRect(x: 66, y: 580, width: 480, height: 48), width: 0.5)
    }
  }

  /// Scenario 2: a résumé.
  ///
  /// With room, the job title has the line to itself; without, a date sits to its right, as in a
  /// two-column layout.
  public static func resume(hasRoom: Bool) throws -> Data {
    var lines = [
      Line("Alex Morgan", font: "Helvetica-Bold", size: 20, at: CGPoint(x: 72, y: 720)),
      Line("Experience", font: "Helvetica-Bold", size: 13, at: CGPoint(x: 72, y: 676)),
      Line("2024 Data Analyst", font: "Helvetica", size: 11, at: CGPoint(x: 72, y: 652)),
      Line("Built weekly reporting for the sales team.", font: "Helvetica", size: 11, at: CGPoint(x: 72, y: 636)),
    ]
    if !hasRoom {
      lines.append(Line("Sydney, full time", font: "Helvetica", size: 11, at: CGPoint(x: 180, y: 652)))
    }
    return try make(pages: [lines])
  }

  /// Scenario 3: a contract paragraph set margin to margin, with a typo ("recieve") in its second
  /// line, a bookmark and a title.
  public static func contract() throws -> Data {
    let paragraph = [
      "The Supplier shall deliver the goods described in Schedule A to the",
      "Customer, and the Customer shall recieve them at the delivery address",
      "on the date agreed in writing between the parties to this agreement,",
      "unless either party gives notice.",
    ]
    var lines = [Line("Supply agreement", font: "TimesNewRomanPS-BoldMT", size: 16, at: CGPoint(x: 72, y: 720))]
    for (index, text) in paragraph.enumerated() {
      lines.append(
        Line(
          text, font: "TimesNewRomanPSMT", size: 12, at: CGPoint(x: 72, y: 680 - CGFloat(index) * 16),
          justifiedWidth: index < paragraph.count - 1 ? 380 : nil))
    }
    let data = try make(pages: [lines, [Line("Schedule A", font: "TimesNewRomanPSMT", at: CGPoint(x: 72, y: 720))]])
    guard let document = PDFDocument(data: data), let first = document.page(at: 0), let second = document.page(at: 1)
    else { throw Failure() }
    let root = PDFOutline()
    for (label, page) in [("Agreement", first), ("Schedule A", second)] {
      let item = PDFOutline()
      item.label = label
      item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
      root.insertChild(item, at: root.numberOfChildren)
    }
    document.outlineRoot = root
    document.documentAttributes = [
      PDFDocumentAttribute.titleAttribute: "Supply agreement", PDFDocumentAttribute.authorAttribute: "Test author",
    ]
    guard let result = document.dataRepresentation() else { throw Failure() }
    return result
  }

  /// Scenario 4: lecture notes with a typo ("mitocondria").
  public static func lectureNotes() throws -> Data {
    try make(pages: [
      [
        Line("Cell biology, week 3", font: "Helvetica-Bold", size: 16, at: CGPoint(x: 72, y: 720)),
        Line("The mitocondria is where the cell makes most of its energy.", at: CGPoint(x: 72, y: 684)),
        Line("Ribosomes build proteins from amino acids.", at: CGPoint(x: 72, y: 666)),
      ]
    ])
  }

  // MARK: - Hand-assembled content

  /// A one-page PDF with exactly this content stream and two standard fonts: `/F1` Helvetica and
  /// `/F2` Times-Roman, neither embedded.
  ///
  /// PDFKit rewrites the page before the editor sees it, so these test how unusual operators come
  /// through that rewrite and the edit together.
  public static func raw(content: String, extraResources: String = "", mediaBox: String = "0 0 612 792") -> Data {
    assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)] /Contents 4 0 R /Resources << /Font << "
        + "/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> "
        + "/F2 << /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >> >> "
        + "\(extraResources) >> >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ])
  }

  /// A PDF from object bodies, numbered from 1, with a classic cross-reference table.
  ///
  /// The first object is the catalog.
  public static func assemble(_ objects: [String]) -> Data {
    var output = Array("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
      offsets.append(output.count)
      output += Array("\(index + 1) 0 obj\n\(body)\nendobj\n".utf8)
    }
    let start = output.count
    output += Array("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8)
    for offset in offsets {
      let digits = String(offset)
      output += Array((String(repeating: "0", count: 10 - digits.count) + digits + " 00000 n \n").utf8)
    }
    output += Array("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8)
    return Data(output)
  }
}
