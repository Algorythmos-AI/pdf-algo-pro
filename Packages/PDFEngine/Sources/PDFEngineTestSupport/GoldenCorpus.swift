import CoreGraphics
import CoreText
import Foundation
import PDFEngine
import PDFKit

/// The synthetic golden corpus (W3.1, docs/testing-strategy.md, "Regression testing: the golden PDF
/// corpus"): documents that differ and fail the way real ones do, generated at run time.
///
/// Every readable case says what a correct reader sees in it; every malformed case must fail cleanly
/// or open, and never crash or hang.
public enum GoldenCorpus {
  /// A readable document and what it contains.
  public struct Case: Sendable, CustomStringConvertible {
    /// A short, stable name for test output.
    public let name: String
    /// The number of pages.
    public let pageCount: Int
    /// A word that text search must find, or `nil` when the pages have no text layer.
    public let searchable: String?
    /// The password that opens it, when it has one.
    public let password: String?
    /// Whether it is encrypted, with or without an open password.
    public let isEncrypted: Bool
    /// Whether its author allows notes and markup.
    public let allowsAnnotating: Bool
    /// Makes the document.
    public let make: @Sendable () throws -> Data

    /// The name, for parameterised test output.
    public var description: String { name }
  }

  /// Every readable case.
  public static let cases: [Case] = [
    text(pages: 20),
    text(pages: 500),
    text(pages: 1_000),
    Case(
      name: "mixed sizes and rotations", pageCount: 4, searchable: "landscape", password: nil, isEncrypted: false,
      allowsAnnotating: true, make: makeMixedSizesAndRotations),
    Case(
      name: "outline", pageCount: 3, searchable: "Chapter", password: nil, isEncrypted: false,
      allowsAnnotating: true, make: makeOutline),
    Case(
      name: "right-to-left and CJK", pageCount: 2, searchable: "世界", password: nil, isEncrypted: false,
      allowsAnnotating: true,
      make: { try SyntheticPDF.make(pages: ["مرحبا بالعالم שלום עולם", "你好世界 こんにちは 안녕하세요"]) }),
    Case(
      name: "form", pageCount: 1, searchable: "Application", password: nil, isEncrypted: false,
      allowsAnnotating: true, make: TestPDFs.makeForm),
    Case(
      name: "every annotation type", pageCount: 1, searchable: "Annotated", password: nil, isEncrypted: false,
      allowsAnnotating: true, make: makeAnnotated),
    Case(
      name: "user password", pageCount: 1, searchable: "Protected", password: "corpus-user", isEncrypted: true,
      allowsAnnotating: true,
      make: {
        try TestPDFs.makeProtected(
          userPassword: "corpus-user", ownerPassword: "corpus-owner", permissions: [.allowsCommenting])
      }),
    Case(
      name: "owner restrictions", pageCount: 1, searchable: "Protected", password: nil, isEncrypted: true,
      allowsAnnotating: false,
      make: {
        try TestPDFs.makeProtected(
          userPassword: nil, ownerPassword: "corpus-owner", permissions: [.allowsLowQualityPrinting])
      }),
    Case(
      name: "image only", pageCount: 2, searchable: nil, password: nil, isEncrypted: false, allowsAnnotating: true,
      make: { try SyntheticPDF.makeImageOnly(pages: ["Scanned page one", "Scanned page two"]) }),
    Case(
      name: "scanned and digital", pageCount: 3, searchable: "Digital", password: nil, isEncrypted: false,
      allowsAnnotating: true, make: makeScannedAndDigital),
    Case(
      name: "active content", pageCount: 1, searchable: "Inert", password: nil, isEncrypted: false,
      allowsAnnotating: true, make: makeActiveContent),
  ]

  /// A malformed file: it must fail cleanly or open, and never crash or hang the engine.
  public struct Malformed: Sendable, CustomStringConvertible {
    /// A short, stable name for test output.
    public let name: String
    /// The file.
    public let data: Data

    /// The name, for parameterised test output.
    public var description: String { name }
  }

  /// Every malformed case, including 40 fuzzed copies of a fixed document made from a fixed seed.
  public static func malformed() -> [Malformed] {
    let sample = fuzzBase()
    var cases: [(String, Data)] = [
      ("empty", Data()),
      ("header only", Data("%PDF-1.7\n".utf8)),
      ("truncated in half", sample.prefix(sample.count / 2)),
      ("truncated before the trailer", sample.prefix(max(0, sample.count - 40))),
      (
        "garbage after the header",
        Data("%PDF-1.7\n".utf8) + Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 31) })
      ),
      ("broken cross-reference table", corruptingXref(of: sample)),
      ("wrong stream length", rawPDF(content: "BT /F1 12 Tf 72 700 Td (Wrong length) Tj ET", declaredLength: 9_999)),
      ("circular page tree", circularPageTree()),
      ("deep nesting", rawPDF(content: String(repeating: "q ", count: 5_000) + String(repeating: "Q ", count: 5_000))),
      ("metadata key that isn't UTF-8", TestPDFs.makeWithUnreadableInfoKey()),
    ]
    cases += fuzzed(sample, count: 40).enumerated().map { ("fuzzed \($0.offset)", $0.element) }
    return cases.map { Malformed(name: $0.0, data: $0.1) }
  }

  // MARK: - Makers

  private static func text(pages: Int) -> Case {
    Case(
      name: "text, \(pages) pages", pageCount: pages, searchable: "Closing\(pages)", password: nil, isEncrypted: false,
      allowsAnnotating: true,
      make: {
        try SyntheticPDF.make(
          pages: (1...pages).map { $0 == pages ? "Closing\(pages) page." : "Page \($0) of the corpus text." })
      })
  }

  private static func makeMixedSizesAndRotations() throws -> Data {
    let sizes = [
      CGSize(width: 612, height: 792), CGSize(width: 595, height: 842), CGSize(width: 842, height: 595),
      CGSize(width: 420, height: 595),
    ]
    let words = ["Letter", "A4", "A4 landscape", "A5"]
    let data = try draw(sizes: sizes) { index, box, context in
      TestPDFs.drawText(words[index], at: CGPoint(x: 40, y: box.height - 80), in: context)
    }
    guard let document = PDFDocument(data: data) else { throw TestPDFs.Failure() }
    for (index, rotation) in [(1, 90), (2, 180), (3, 270)] { document.page(at: index)?.rotation = rotation }
    guard let rotated = document.dataRepresentation() else { throw TestPDFs.Failure() }
    return rotated
  }

  private static func makeOutline() throws -> Data {
    guard
      let document = PDFDocument(data: try SyntheticPDF.make(pages: ["Chapter one", "Chapter two", "Chapter three"]))
    else { throw TestPDFs.Failure() }
    let root = PDFOutline()
    for index in 0..<3 {
      guard let page = document.page(at: index) else { continue }
      let item = PDFOutline()
      item.label = "Chapter \(index + 1)"
      item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
      root.insertChild(item, at: index)
    }
    document.outlineRoot = root
    guard let data = document.dataRepresentation() else { throw TestPDFs.Failure() }
    return data
  }

  private static func makeAnnotated() throws -> Data {
    guard let document = PDFDocument(data: try SyntheticPDF.make(pages: ["Annotated page with text to mark up."])),
      let page = document.page(at: 0)
    else { throw TestPDFs.Failure() }
    let kinds: [PDFAnnotationSubtype] = [
      .highlight, .underline, .strikeOut, .text, .freeText, .square, .circle, .line, .ink, .stamp, .link,
    ]
    for (index, kind) in kinds.enumerated() {
      let bounds = CGRect(x: 60 + CGFloat(index % 4) * 120, y: 560 - CGFloat(index / 4) * 120, width: 100, height: 60)
      let annotation = PDFAnnotation(bounds: bounds, forType: kind, withProperties: nil)
      annotation.color = .systemBlue
      switch kind {
      case .freeText: annotation.contents = "Free text"
      case .text: annotation.contents = "A note"
      case .line:
        annotation.startPoint = CGPoint(x: 0, y: 0)
        annotation.endPoint = CGPoint(x: 100, y: 60)
      case .ink:
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10, y: 10))
        path.addLine(to: CGPoint(x: 90, y: 50))
        annotation.add(PlatformBezierPath(cgPath: path))
      case .link: annotation.url = URL(string: "https://example.com/corpus")
      default: break
      }
      page.addAnnotation(annotation)
    }
    guard let data = document.dataRepresentation() else { throw TestPDFs.Failure() }
    return data
  }

  private static func makeScannedAndDigital() throws -> Data {
    guard let digital = PDFDocument(data: try SyntheticPDF.make(pages: ["Digital page one", "Digital page three"])),
      let scanned = PDFDocument(data: try SyntheticPDF.makeImageOnly(pages: ["Scanned page two"])),
      let page = scanned.page(at: 0)
    else { throw TestPDFs.Failure() }
    digital.insert(page, at: 1)
    guard let data = digital.dataRepresentation() else { throw TestPDFs.Failure() }
    return data
  }

  /// A page with a JavaScript open action and a link to a remote URL: both must stay inert.
  private static func makeActiveContent() throws -> Data {
    let content = "BT /F1 18 Tf 72 700 Td (Inert page) Tj ET"
    let objects = [
      "<< /Type /Catalog /Pages 2 0 R /OpenAction << /S /JavaScript /JS (app.alert('corpus')) >> >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> "
        + "/Annots [6 0 R] >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Type /Annot /Subtype /Link /Rect [72 650 300 680] /A << /S /Launch /F (calc.exe) >> >>",
    ]
    return assemble(objects)
  }

  // MARK: - Malformed

  private static func corruptingXref(of data: Data) -> Data {
    var bytes = [UInt8](data)
    if let range = data.range(of: Data("xref".utf8), options: .backwards) {
      for index in range.lowerBound..<min(bytes.count, range.lowerBound + 200) { bytes[index] = UInt8(ascii: "9") }
    }
    return Data(bytes)
  }

  private static func rawPDF(content: String, declaredLength: Int? = nil) -> Data {
    assemble([
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
      "<< /Length \(declaredLength ?? content.utf8.count) >>\nstream\n\(content)\nendstream",
    ])
  }

  private static func circularPageTree() -> Data {
    assemble([
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 2 >>",
      "<< /Type /Pages /Parent 2 0 R /Kids [2 0 R] /Count 1 >>",
    ])
  }

  /// The document the truncated, corrupted and fuzzed cases start from: two pages of text, a font, a
  /// note, an outline and metadata, written byte for byte.
  ///
  /// A document drawn by Core Graphics embeds the time and the operating system's version, so the same
  /// seed would change different bytes on every run and platform.
  private static func fuzzBase() -> Data {
    func stream(_ content: String) -> String { "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream" }
    let resources = "/Resources << /Font << /F1 7 0 R >> >>"
    return assemble(
      [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 8 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R \(resources) /Annots [10 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Rotate 90 /Contents 6 0 R \(resources) >>",
        stream("BT /F1 18 Tf 72 700 Td (Fuzz base, page one) Tj ET"),
        stream("BT /F1 18 Tf 72 700 Td (Invoice total: 42) Tj 0 -24 Td (Page two) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Outlines /First 9 0 R /Last 9 0 R /Count 1 >>",
        "<< /Title (Page two) /Parent 8 0 R /Dest [4 0 R /Fit] >>",
        "<< /Type /Annot /Subtype /Text /Rect [72 600 96 624] /Contents (A note) >>",
        "<< /Title (Fuzz base) /Author (Golden corpus) /Keywords (fuzz) /CreationDate (D:20260930120000Z) >>",
      ], info: 11)
  }

  /// A PDF file from object bodies, numbered from 1, with a correct cross-reference table.
  private static func assemble(_ objects: [String], info: Int? = nil) -> Data {
    var output = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
      offsets.append(output.utf8.count)
      output += "\(index + 1) 0 obj\n\(body)\nendobj\n"
    }
    let xref = output.utf8.count
    output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets { output += String(format: "%010d 00000 n \n", offset) }
    let infoEntry = info.map { " /Info \($0) 0 R" } ?? ""
    output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R\(infoEntry) >>\nstartxref\n\(xref)\n%%EOF\n"
    return Data(output.utf8)
  }

  /// Copies of a file with a few bytes changed, from a fixed seed so every run tests the same files.
  private static func fuzzed(_ data: Data, count: Int) -> [Data] {
    var generator = SeededGenerator(seed: 0x5EED_2026)
    return (0..<count).map { _ in
      var bytes = [UInt8](data)
      for _ in 0..<Int.random(in: 1...16, using: &generator) {
        bytes[Int.random(in: 0..<bytes.count, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
      }
      return Data(bytes)
    }
  }

  // MARK: - Drawing

  private static func draw(sizes: [CGSize], page: (Int, CGSize, CGContext) -> Void) throws -> Data {
    let data = NSMutableData()
    var first = CGRect(origin: .zero, size: sizes.first ?? CGSize(width: 612, height: 792))
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &first, nil)
    else { throw TestPDFs.Failure() }
    for (index, size) in sizes.enumerated() {
      var box = CGRect(origin: .zero, size: size)
      let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
      context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
      page(index, size, context)
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }
}

/// A small deterministic random number generator (SplitMix64), so fuzzed files are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

#if canImport(UIKit)
  import UIKit

  typealias PlatformBezierPath = UIBezierPath
#else
  import AppKit

  typealias PlatformBezierPath = NSBezierPath
#endif
