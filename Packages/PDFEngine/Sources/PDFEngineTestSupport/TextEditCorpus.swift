import CoreGraphics
import Foundation

/// Synthetic documents in the shapes real tools write, for checking that text editing ends well on
/// every line of every kind of page.
///
/// Each is drawn by code. None is, or is derived from, a real document (AGENTS.md, rule 6).
public enum TextEditCorpus {
  private typealias Line = TextEditFixtures.Line

  /// One document of the corpus.
  public struct Document: Sendable {
    /// What kind of page it stands for.
    public let name: String
    /// The PDF.
    public let data: Data
  }

  /// How many documents the corpus has.
  public static let count = 15

  /// Every document of the corpus.
  public static func documents() throws -> [Document] {
    [
      Document(name: "invoice", data: try TextEditFixtures.invoice()),
      Document(name: "résumé with room", data: try TextEditFixtures.resume(hasRoom: true)),
      Document(name: "résumé without room", data: try TextEditFixtures.resume(hasRoom: false)),
      Document(name: "contract, justified", data: try TextEditFixtures.contract()),
      Document(name: "lecture notes", data: try TextEditFixtures.lectureNotes()),
      Document(name: "statement from a reporting tool", data: try statement()),
      Document(name: "letter with bold and italic runs", data: try letter()),
      Document(name: "web page saved as PDF", data: try webPage()),
      Document(name: "paper set like TeX", data: try paper()),
      Document(name: "two columns", data: try twoColumns()),
      Document(name: "rotated and slanted text", data: try rotated()),
      Document(name: "text on colour", data: try onColour()),
      Document(name: "very small and very large text", data: try sizes()),
      Document(name: "hand-written operators", data: operators()),
      Document(name: "page whose box does not start at the origin", data: offsetBox()),
    ]
  }

  /// A statement: a table of rows on alternate shaded bands, amounts aligned on the right, centred
  /// section titles, in a screen typeface at a small size.
  static func statement() throws -> Data {
    var lines = [
      Line("PAY ADVICE", font: "Verdana", size: 16, at: CGPoint(x: 540, y: 730), anchor: .trailing),
      Line("Sample Trading Pty Ltd", font: "Verdana", size: 8, at: CGPoint(x: 540, y: 712), anchor: .trailing),
      Line("Alex Example", font: "Verdana", size: 11, at: CGPoint(x: 72, y: 690)),
      Line("12 Sample Street Sampletown 2000", font: "Verdana", size: 8, at: CGPoint(x: 72, y: 676)),
      Line("Hours", font: "Verdana", size: 11, at: CGPoint(x: 306, y: 640), anchor: .centre),
    ]
    let rows = [
      ("Ordinary hours", "15.2800", "$31.4500", "$480.56"), ("Night shift", "9.2500", "$32.7500", "$302.94"),
      ("Saturday", "7.9700", "$43.4500", "$346.30"), ("Sunday", "5.5000", "$50.3600", "$276.98"),
    ]
    for (index, row) in rows.enumerated() {
      let y = 616 - CGFloat(index) * 18
      lines += [
        Line(row.0, font: "Verdana", size: 8, at: CGPoint(x: 78, y: y)),
        Line(row.1, font: "Verdana", size: 8, at: CGPoint(x: 360, y: y), anchor: .trailing),
        Line(row.2, font: "Verdana", size: 8, at: CGPoint(x: 440, y: y), anchor: .trailing),
        Line(row.3, font: "Verdana", size: 8, at: CGPoint(x: 534, y: y), anchor: .trailing),
      ]
    }
    lines += [
      Line("Gross pay:", font: "Verdana-Bold", size: 8, at: CGPoint(x: 440, y: 520), anchor: .trailing),
      Line("$1,406.78", font: "Verdana", size: 8, at: CGPoint(x: 534, y: 520), anchor: .trailing),
      Line("Page 1 / 1", font: "Verdana", size: 6, at: CGPoint(x: 534, y: 60), anchor: .trailing),
    ]
    return try TextEditFixtures.make(pages: [lines]) { context, _ in
      context.setFillColor(CGColor(gray: 0.94, alpha: 1))
      for band in [0, 2] { context.fill(CGRect(x: 72, y: 610 - CGFloat(band) * 18, width: 468, height: 18)) }
      context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
      context.stroke(CGRect(x: 380, y: 510, width: 160, height: 24), width: 0.5)
    }
  }

  /// A letter: body text with a bold label and an italic phrase sharing lines with regular text.
  static func letter() throws -> Data {
    try TextEditFixtures.make(pages: [
      [
        Line("29 April 2026", font: "Georgia", size: 11, at: CGPoint(x: 72, y: 700)),
        Line("Dear Customer,", font: "Georgia", size: 11, at: CGPoint(x: 72, y: 670)),
        Line("Thank you for choosing us. Your final payment has been received", at: CGPoint(x: 72, y: 646)),
        Line("and your account is now closed.", at: CGPoint(x: 72, y: 630)),
        Line("Phone:", font: "Georgia-Bold", size: 11, at: CGPoint(x: 100, y: 596)),
        Line("1300 000 000, Monday to Friday", font: "Georgia", size: 11, at: CGPoint(x: 142, y: 596)),
        Line("Email:", font: "Georgia-Bold", size: 11, at: CGPoint(x: 100, y: 580)),
        Line("care@example.com", font: "Georgia", size: 11, at: CGPoint(x: 140, y: 580)),
        Line("We will update our", font: "Georgia", size: 11, at: CGPoint(x: 72, y: 548)),
        Line("register", font: "Georgia-Italic", size: 11, at: CGPoint(x: 172, y: 548)),
        Line("within five days.", font: "Georgia", size: 11, at: CGPoint(x: 216, y: 548)),
        Line("Yours sincerely,", font: "Georgia", size: 11, at: CGPoint(x: 72, y: 510)),
        Line("Sample Finance", font: "Georgia-Bold", size: 11, at: CGPoint(x: 72, y: 494)),
      ]
    ])
  }

  /// A web page saved as a PDF: a heading, link-coloured text, lines that run to the edge of the
  /// page, and a small footer.
  static func webPage() throws -> Data {
    try TextEditFixtures.make(pages: [
      [
        Line("Getting started", font: "HelveticaNeue-Bold", size: 24, at: CGPoint(x: 36, y: 730)),
        Line("Home", font: "ArialMT", size: 10, at: CGPoint(x: 36, y: 760), color: [0, 0.4, 0.8]),
        Line("Documentation", font: "ArialMT", size: 10, at: CGPoint(x: 80, y: 760), color: [0, 0.4, 0.8]),
        Line(
          "This guide walks through installing the tools, creating a first project and publishing it to the web.",
          font: "ArialMT", size: 11, at: CGPoint(x: 36, y: 696)),
        Line("Install", font: "HelveticaNeue-Bold", size: 16, at: CGPoint(x: 36, y: 660)),
        Line("Download the installer and follow the steps.", font: "ArialMT", size: 11, at: CGPoint(x: 36, y: 638)),
        Line("https://example.com/guide", font: "ArialMT", size: 7, at: CGPoint(x: 36, y: 24), color: [0.4, 0.4, 0.4]),
        Line("1/3", font: "ArialMT", size: 7, at: CGPoint(x: 576, y: 24), anchor: .trailing, color: [0.4, 0.4, 0.4]),
      ]
    ])
  }

  /// A paper: a centred title, a justified paragraph in a serif face, a line in a fixed-pitch face
  /// and a figure caption.
  static func paper() throws -> Data {
    let paragraph = [
      "We study the problem of changing the words of a page without changing",
      "anything else on it, and show that a proof over the rendered page is",
      "enough to refuse every wrong result we could construct.",
    ]
    var lines = [
      Line("On editing pages", font: "TimesNewRomanPS-BoldMT", size: 17, at: CGPoint(x: 306, y: 720), anchor: .centre),
      Line(
        "A. Author and B. Author", font: "TimesNewRomanPS-ItalicMT", size: 11, at: CGPoint(x: 306, y: 700),
        anchor: .centre),
      Line("Abstract", font: "TimesNewRomanPS-BoldMT", size: 10, at: CGPoint(x: 306, y: 670), anchor: .centre),
    ]
    for (index, text) in paragraph.enumerated() {
      lines.append(
        Line(
          text, font: "TimesNewRomanPSMT", size: 10, at: CGPoint(x: 126, y: 652 - CGFloat(index) * 13),
          justifiedWidth: index < paragraph.count - 1 ? 360 : nil))
    }
    lines += [
      Line("let page = try edit(page)", font: "Courier", size: 9, at: CGPoint(x: 126, y: 590)),
      Line(
        "Figure 1: the page before and after.", font: "TimesNewRomanPSMT", size: 9, at: CGPoint(x: 306, y: 560),
        anchor: .centre),
    ]
    return try TextEditFixtures.make(pages: [lines])
  }

  /// Two columns of short lines with a narrow gap between them.
  static func twoColumns() throws -> Data {
    let left = ["The first column holds", "short lines of body", "text set close to the", "second column."]
    let right = ["The second column", "starts a little to the", "right of where the", "first one ends."]
    var lines: [Line] = []
    for (index, text) in left.enumerated() {
      lines.append(Line(text, font: "Helvetica", size: 11, at: CGPoint(x: 72, y: 700 - CGFloat(index) * 15)))
    }
    for (index, text) in right.enumerated() {
      lines.append(Line(text, font: "Helvetica", size: 11, at: CGPoint(x: 200, y: 700 - CGFloat(index) * 15)))
    }
    return try TextEditFixtures.make(pages: [lines])
  }

  /// A label turned on its side, as on a form's margin, and a stamp at a slant.
  static func rotated() throws -> Data {
    try TextEditFixtures.make(pages: [
      [
        Line("Reference 0042", font: "Helvetica", size: 10, at: CGPoint(x: 40, y: 300), angle: .pi / 2),
        Line("Received", font: "Helvetica-Bold", size: 28, at: CGPoint(x: 200, y: 400), angle: 0.18),
        Line("An upright line beside them.", font: "Helvetica", size: 11, at: CGPoint(x: 120, y: 640)),
      ]
    ])
  }

  /// White text on a dark band, and grey text on white.
  static func onColour() throws -> Data {
    try TextEditFixtures.make(pages: [
      [
        Line("Quarterly summary", font: "Helvetica-Bold", size: 18, at: CGPoint(x: 84, y: 716), color: [1, 1, 1]),
        Line(
          "Prepared for the board", font: "Helvetica", size: 11, at: CGPoint(x: 84, y: 660), color: [0.45, 0.45, 0.45]),
        Line("Confidential", font: "Helvetica", size: 9, at: CGPoint(x: 84, y: 640), color: [0.75, 0.1, 0.1]),
      ]
    ]) { context, _ in
      context.setFillColor(CGColor(srgbRed: 0.1, green: 0.15, blue: 0.35, alpha: 1))
      context.fill(CGRect(x: 72, y: 700, width: 468, height: 44))
    }
  }

  /// Text at the smallest and largest sizes people meet.
  static func sizes() throws -> Data {
    try TextEditFixtures.make(pages: [
      [
        Line("SALE", font: "Helvetica-Bold", size: 72, at: CGPoint(x: 72, y: 620)),
        Line("Terms apply. See in store for details.", font: "Helvetica", size: 5, at: CGPoint(x: 72, y: 590)),
        Line("Ends Sunday", font: "Helvetica", size: 30, at: CGPoint(x: 72, y: 540)),
      ]
    ])
  }

  /// Operators written by hand: lines placed one from another, kerned strings, letter spacing and
  /// horizontal scaling.
  static func operators() -> Data {
    TextEditFixtures.raw(
      content: """
        BT /F1 12 Tf 72 720 Td (First line of a block) Tj 0 -16 Td (Second line of the block) Tj
        0 -16 Td [(Kerned) -120 ( words) 40 ( here)] TJ ET
        BT /F2 11 Tf 1.5 Tc 72 640 Td (Spaced letters) Tj ET
        BT /F1 11 Tf 80 Tz 72 610 Td (Narrowed text) Tj ET
        BT /F2 14 Tf 1 0 0 1 72 570 Tm (Placed by a matrix) Tj ET
        """)
  }

  /// A page whose media box does not start at the origin.
  static func offsetBox() -> Data {
    TextEditFixtures.raw(
      content: "BT /F1 12 Tf 172 920 Td (A line on an offset page) Tj 0 -18 Td (And a second one) Tj ET",
      mediaBox: "100 200 712 992")
  }
}
