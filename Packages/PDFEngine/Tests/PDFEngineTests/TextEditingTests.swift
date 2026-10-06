import Core
import CoreGraphics
import CoreTestSupport
import CoreText
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

private typealias Line = TextEditFixtures.Line

/// The text of a page of a PDF, with all whitespace removed, as PDFKit reads it.
@MainActor
private func squeezedText(_ data: Data, page: Int = 0) -> String {
  EditProof.squeezed(PDFDocument(data: data)?.page(at: page)?.string ?? "")
}

/// A page ready for the editor, and the regions it finds.
@MainActor
private func prepared(_ data: Data) async throws -> (page: Data, regions: [EditableTextRegion]) {
  let page = try TextEditFixtures.singlePage(data)
  return (page, await ContentStreamTextEditor().text(ofPage: page).regions)
}

private func region(_ regions: [EditableTextRegion], containing text: String) throws -> EditableTextRegion {
  try #require(regions.first { $0.text.contains(text) }, "no region contains \(text)")
}

// MARK: - Syntax

@Suite("Text editing: reading PDF syntax")
struct TextEditingSyntaxTests {
  @Test("Numbers, names and strings are read as PDF defines them")
  func tokens() throws {
    var lexer = PDFLexer(
      Array("12 -3.5 .25 +7 /Name /A#20B (a\\(b\\)\\n\\101) <48 656C6C6F7> true % note\n[1 [2]] << /K 1 >>".utf8))
    #expect(try lexer.next().token == .integer(12))
    #expect(try lexer.next().token == .real(-3.5))
    #expect(try lexer.next().token == .real(0.25))
    #expect(try lexer.next().token == .integer(7))
    #expect(try lexer.next().token == .name("Name"))
    #expect(try lexer.next().token == .name("A B"))
    #expect(try lexer.next().token == .string(Array("a(b)\nA".utf8)))
    #expect(try lexer.next().token == .string(Array("Hello".utf8) + [0x70]))
    #expect(try lexer.object(references: false) == .boolean(true))
    #expect(try lexer.object(references: false) == .array([.integer(1), .array([.integer(2)])]))
    #expect(try lexer.object(references: false) == .dictionary(["K": .integer(1)]))
    #expect(try lexer.next().token == .end)
  }

  @Test("A reference is three tokens in a file and three operands in content")
  func references() throws {
    var file = PDFLexer(Array("12 0 R 7".utf8))
    #expect(try file.object(references: true) == .reference(12))
    #expect(try file.object(references: true) == .integer(7))
    var content = PDFLexer(Array("12 0 R".utf8))
    #expect(try content.object(references: false) == .integer(12))
  }

  @Test(
    "Malformed syntax is an error, never a crash",
    arguments: ["(unclosed", "<4G>", ">", "<< /K", "[1 2", "<< 1 2 >>", ")", String(repeating: "[", count: 200)])
  func malformed(source: String) {
    var lexer = PDFLexer(Array(source.utf8))
    #expect(throws: PDFSyntaxError.self) {
      while try lexer.object(references: true) != .null {}
    }
  }

  @Test("Content is split into operators with their operands and where they are")
  func operations() throws {
    let source = "q 1 0 0 1 72 700 cm BT /F1 12 Tf (Hi) Tj [(a) -120 (b)] TJ ET Q"
    let operations = try ContentStream.parse(Array(source.utf8))
    #expect(operations.map(\.name) == ["q", "cm", "BT", "Tf", "Tj", "TJ", "ET", "Q"])
    let show = try #require(operations.first { $0.name == "Tj" })
    #expect(String(decoding: Array(source.utf8)[show.range], as: UTF8.self) == "(Hi) Tj")
    #expect(operations[5].operands == [.array([.string([0x61]), .integer(-120), .string([0x62])])])
  }

  @Test("An inline image is one operation, whatever bytes it holds")
  func inlineImage() throws {
    let source = Array("q BI /W 2 /H 1 /BPC 8 /CS /G ID ".utf8) + [0x00, 0x45, 0x49, 0xFF] + Array(" EI Q (x) Tj".utf8)
    #expect(try ContentStream.parse(source).map(\.name) == ["q", "BI", "Q", "Tj"])
    #expect(throws: PDFSyntaxError.self) { try ContentStream.parse(Array("BI /W 1 ID abc".utf8)) }
    #expect(throws: PDFSyntaxError.self) { try ContentStream.parse(Array("1 2 3".utf8)) }
  }

  @Test("A character map gives single codes and ranges their text")
  func characterMap() throws {
    let map = try CharacterMap.parse(
      Array(
        """
        1 beginbfchar <21> <0141> endbfchar
        2 beginbfrange <22> <24> <0061> <30> <31> [<0058> <00590059>] endbfrange
        """.utf8))
    #expect(map[0x21] == "Ł")
    #expect(map[0x22] == "a" && map[0x23] == "b" && map[0x24] == "c")
    #expect(map[0x30] == "X" && map[0x31] == "YY")
    #expect(throws: PDFSyntaxError.self) {
      try CharacterMap.parse(Array("1 beginbfrange <30> <10> <0041> endbfrange".utf8))
    }
  }

  @Test("Glyph names read as the characters they stand for; unknown names read as nothing")
  func glyphNames() {
    #expect(GlyphNames.text(for: "A") == "A")
    #expect(GlyphNames.text(for: "space") == " ")
    #expect(GlyphNames.text(for: "eacute") == "é")
    #expect(GlyphNames.text(for: "uni20AC") == "€")
    #expect(GlyphNames.text(for: "u1F600") == "😀")
    #expect(GlyphNames.text(for: "Euro") == "€")
    #expect(GlyphNames.text(for: "g1234") == nil)
    #expect(TextFont.withoutSubsetTag("AAAAAB+Georgia-Bold") == "Georgia-Bold")
    #expect(TextFont.withoutSubsetTag("My+Font") == "My+Font")
  }

  /// A one-page file read as it is, without PDFKit rewriting it first.
  private func analysis(content: String, fonts: String, objects: [String] = []) throws -> PageAnalysis {
    try PageAnalysis(
      TextEditFixtures.assemble(
        [
          "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << \(fonts) >> >> >>",
          "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        ] + objects))
  }

  @Test("Two-byte codes with their own character map, as browsers write them, are read glyph by glyph")
  func compositeFont() throws {
    let map = "2 beginbfchar <0001> <0048> <0002> <0069> endbfchar"
    let page = try analysis(
      content: "BT /C1 12 Tf 72 700 Td <00010002> Tj 300 0 Td <0001> Tj <0002> Tj ET",
      fonts: "/C1 << /Type /Font /Subtype /Type0 /BaseFont /AAAAAB+Roboto-Regular /Encoding /Identity-H "
        + "/DescendantFonts [5 0 R] /ToUnicode 6 0 R >>",
      objects: [
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /AAAAAB+Roboto-Regular /DW 500 /W [1 [700 250]] >>",
        "<< /Length \(map.utf8.count) >>\nstream\n\(map)\nendstream",
      ])
    #expect(page.regions.map(\.text) == ["Hi", "Hi"])
    let first = try #require(page.regions.first)
    #expect(first.font.postScriptName == "Roboto-Regular" && first.font.isComposite)
    // 700 and 250 thousandths at 12 points.
    #expect(abs(first.widthDrawn - 11.4) < 0.01)
    // A composite font without its own map cannot be read, so it offers nothing to edit.
    let unmapped = try analysis(
      content: "BT /C1 12 Tf 72 700 Td <00010002> Tj ET",
      fonts: "/C1 << /Type /Font /Subtype /Type0 /BaseFont /Mincho /Encoding /Identity-H /DescendantFonts [5 0 R] >>",
      objects: ["<< /Type /Font /Subtype /CIDFontType0 /BaseFont /Mincho /DW 1000 >>"])
    #expect(unmapped.regions.isEmpty && unmapped.content.runs.first?.text == nil)
  }

  @Test("A font with no space glyph, as TeX writes, reads its gaps as spaces")
  func gapsAsSpaces() throws {
    let widths = Array(repeating: "500", count: 91).joined(separator: " ")
    let page = try analysis(
      content: "BT /F9 10 Tf 72 700 Td [(The) -333 (quick) -333 (fox) -20 (es)] TJ ET",
      fonts: "/F9 << /Type /Font /Subtype /Type1 /BaseFont /CMR10 /FirstChar 32 /LastChar 122 /Widths [\(widths)] "
        + "/Encoding << /Type /Encoding /Differences [84 /T 101 /e /f 104 /h /i 107 /k 111 /o 113 /q 115 /s 117 /u 120 /x 99 /c] >> >>"
    )
    // Wide gaps are spaces; a kerning nudge is not.
    #expect(page.regions.map(\.text) == ["The quick foxes"])
    #expect(page.regions.first?.editable.capability == .limited(.fontSubstituted))
  }

  @Test("A Type 3 font, whose glyphs are drawings, offers nothing to edit in place")
  func type3Font() throws {
    let page = try analysis(
      content: "BT /T3 12 Tf 72 700 Td (AB) Tj ET",
      fonts: "/T3 << /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] "
        + "/CharProcs << >> /Encoding << /Type /Encoding /Differences [65 /A /B] >> /FirstChar 65 /LastChar 66 "
        + "/Widths [600 600] >>")
    #expect(page.regions.isEmpty)
  }

  @Test("Numbers are written as plain decimals")
  func numbers() {
    #expect(TextEraser.number(12) == "12")
    #expect(TextEraser.number(-0.5) == "-0.5")
    #expect(TextEraser.number(0.00001) == "0")
    #expect(TextEraser.number(1234.56789) == "1234.5679")
  }

  @Test("A file that is not what Core Graphics writes is refused, not guessed at")
  func files() throws {
    #expect(throws: PDFSyntaxError.self) { try PDFFile(Data("not a pdf".utf8)) }
    #expect(throws: PDFSyntaxError.self) { try PDFFile(Data("%PDF-1.7\nstartxref\n999999\n%%EOF".utf8)) }
    // A cross-reference stream instead of a table.
    let stream = "%PDF-1.7\n1 0 obj\n<< /Type /XRef >>\nendobj\nstartxref\n9\n%%EOF\n"
    #expect(throws: PDFSyntaxError.unsupported) { try PDFFile(Data(stream.utf8)) }
    // A page tree that never reaches a page.
    let loop = TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [2 0 R] /Count 1 >>",
    ])
    #expect(throws: PDFSyntaxError.self) { try PDFFile(loop).firstPage() }
    let good = try PDFFile(TextEditFixtures.raw(content: "BT /F1 12 Tf 72 700 Td (Hi) Tj ET"))
    let page = try good.firstPage()
    #expect(page.mediaBox == CGRect(x: 0, y: 0, width: 612, height: 792) && page.contents == [4])
    #expect(try good.stream(4).data == Array("BT /F1 12 Tf 72 700 Td (Hi) Tj ET".utf8))
  }

  @Test("Replacing a page's content appends an update and keeps the original bytes")
  func incrementalUpdate() throws {
    let original = TextEditFixtures.raw(content: "BT /F1 12 Tf 72 700 Td (Hi) Tj ET")
    let file = try PDFFile(original)
    let updated = try file.replacingContent(of: try file.firstPage(), with: Array("BT ET".utf8))
    #expect(updated.prefix(original.count) == original)
    let reread = try PDFFile(updated)
    #expect(try reread.stream(4).data == Array("BT ET".utf8))
    #expect(CGPDFDocument(CGDataProvider(data: updated as CFData)!)?.numberOfPages == 1)
  }

  @Test("Erasing a run that later text depends on keeps the pen where it was")
  func eraseKeepsAdvance() throws {
    let font =
      "/F9 << /Type /Font /Subtype /TrueType /BaseFont /Helvetica /Encoding /WinAnsiEncoding /FirstChar 32 "
      + "/LastChar 122 /Widths [\(Array(repeating: "500", count: 91).joined(separator: " "))] >>"
    let content =
      "BT /F9 10 Tf 72 700 Td (Hel) Tj (lo ) Tj /F2 10 Tf (World) Tj ET BT /F9 10 Tf 72 680 Td (Alone) ' ET"
    let data = TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << \(font) "
        + "/F2 << /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >> >> >> >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ])
    let analysis = try PageAnalysis(data)
    #expect(analysis.regions.map(\.text) == ["Hello", "Alone"])
    #expect(analysis.content.runs[0].hasDependents && analysis.content.runs[1].continuesFromPen)
    let erased = try TextEraser.erasing(analysis.regions, in: analysis.content, bytes: analysis.bytes)
    let text = String(decoding: erased, as: UTF8.self)
    // Both erased runs keep their advance, because the text after them starts where they end:
    // three glyphs of 500 at size 10 are 15 units each, an adjustment of -1500 thousandths.
    #expect(text.contains("[-1500] TJ [-1500] TJ /F2 10 Tf (World) Tj"))
    #expect(text.contains("T* ET") && !text.contains("Alone") && !text.contains("Hello"))
  }
}

// MARK: - The engine

@MainActor
@Suite("Text editing: the engine")
struct TextEditorTests {
  let editor = ContentStreamTextEditor()

  @Test("Existing text is found as regions with its place, font, size and colour")
  func detect() async throws {
    let (_, regions) = try await prepared(TextEditFixtures.invoice())
    #expect(
      regions.map(\.text) == [
        "Invoice", "Customer: John Smith", "Invoice number: INV-2026-0042", "Fence repair", "$950.00", "Materials",
        "$300.00", "Total", "$1,250.00",
      ])
    let name = try region(regions, containing: "John Smith")
    #expect(name.style.fontName == "Georgia" && abs(name.style.pointSize - 12) < 0.01 && name.isUpright)
    #expect(abs(name.bounds.minX - 72) < 0.5 && name.bounds.minY < 680 && name.bounds.maxY > 680)
    #expect(name.capability == .direct && name.style.color == .black)
    #expect(try region(regions, containing: "Total").style.isBold)
  }

  @Test("Scenario 1: a name is replaced in the page's own content, in the same font")
  func replace() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let name = try region(regions, containing: "John Smith")
    let result = await editor.applying([TextEdit(region: name, replacement: "Customer: David Smith")], toPage: page)
    #expect(result.outcomes == [.edited(.contentStream)])
    let edited = try #require(result.page)
    #expect(squeezedText(edited).contains("Customer:DavidSmith") && !squeezedText(edited).contains("John"))
    // The new text is text in the content, in the same font, where the old text was.
    let after = await editor.text(ofPage: edited).regions
    let renamed = try region(after, containing: "David Smith")
    #expect(renamed.style.fontName == "Georgia" && abs(renamed.style.pointSize - 12) < 0.01)
    #expect(abs(renamed.bounds.minX - name.bounds.minX) < 0.5 && abs(renamed.bounds.minY - name.bounds.minY) < 0.5)
    #expect(after.count == regions.count)
    // No annotation was added: nothing covers anything.
    #expect(PDFDocument(data: edited)?.page(at: 0)?.annotations.isEmpty == true)
  }

  @Test("Shorter and longer replacements keep the start of a left-aligned line")
  func shorterAndLonger() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let name = try region(regions, containing: "John Smith")
    for replacement in ["Customer: Jo", "Customer: Johnathan Smithers-Wójcik & Sons"] {
      let result = await editor.applying([TextEdit(region: name, replacement: replacement)], toPage: page)
      let edited = try #require(result.page, "\(replacement): \(result.outcomes)")
      let changed = try region(await editor.text(ofPage: edited).regions, containing: String(replacement.suffix(4)))
      #expect(abs(changed.bounds.minX - name.bounds.minX) < 0.5)
    }
  }

  @Test("Scenario 2: a much longer job title fits when the line has room, and is refused calmly when it does not")
  func resume() async throws {
    let (roomy, regions) = try await prepared(TextEditFixtures.resume(hasRoom: true))
    let title = try region(regions, containing: "2024 Data Analyst")
    let edit = TextEdit(region: title, replacement: "2025 Senior Data Scientist")
    let fits = await editor.applying([edit], toPage: roomy)
    #expect(fits.outcomes == [.edited(.contentStream)])
    #expect(squeezedText(try #require(fits.page)).contains("2025SeniorDataScientist"))

    let (tight, tightRegions) = try await prepared(TextEditFixtures.resume(hasRoom: false))
    let crowded = try region(tightRegions, containing: "2024 Data Analyst")
    let refused = await editor.applying(
      [TextEdit(region: crowded, replacement: "2025 Senior Data Scientist")], toPage: tight)
    #expect(refused.outcomes == [.tooLong] && refused.page == nil)
  }

  @Test("An amount aligned on the right keeps its right edge")
  func rightAligned() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let total = try region(regions, containing: "$1,250.00")
    let result = await editor.applying([TextEdit(region: total, replacement: "$12,500.00")], toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    let changed = try region(await editor.text(ofPage: edited).regions, containing: "$12,500.00")
    #expect(abs(changed.bounds.maxX - total.bounds.maxX) < 1 && changed.bounds.minX < total.bounds.minX)
  }

  @Test("Scenario 3: fixing a typo in a justified paragraph keeps the line's edges")
  func justified() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.contract())
    let line = try region(regions, containing: "recieve")
    let fixed = line.text.replacingOccurrences(of: "recieve", with: "receive")
    let result = await editor.applying([TextEdit(region: line, replacement: fixed)], toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    let changed = try region(await editor.text(ofPage: edited).regions, containing: "receive")
    #expect(abs(changed.bounds.minX - line.bounds.minX) < 0.5 && abs(changed.bounds.maxX - line.bounds.maxX) < 1)
    #expect(!squeezedText(edited).contains("recieve"))
  }

  @Test("Rotated text is edited along its own baseline")
  func rotatedText() async throws {
    let data = try TextEditFixtures.make(pages: [
      [
        Line("Upright line", at: CGPoint(x: 72, y: 700)),
        Line("Sideways label", font: "Helvetica", at: CGPoint(x: 500, y: 300), angle: .pi / 2),
      ]
    ])
    let (page, regions) = try await prepared(data)
    let label = try region(regions, containing: "Sideways")
    #expect(abs(label.angle - .pi / 2) < 0.01 && !label.isUpright && label.bounds.height > label.bounds.width)
    let result = await editor.applying([TextEdit(region: label, replacement: "Sideways lapel")], toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    let changed = try region(await editor.text(ofPage: edited).regions, containing: "lapel")
    #expect(abs(changed.angle - .pi / 2) < 0.01 && abs(changed.bounds.minY - label.bounds.minY) < 1)
  }

  @Test("A page whose box does not start at the origin is edited in place", arguments: [0, 90, 180, 270])
  func offsetBoxAndPageRotation(rotation: Int) async throws {
    let box = CGRect(x: 40, y: 60, width: 500, height: 700)
    let data = try TextEditFixtures.make(pages: [[Line("Offset origin text", at: CGPoint(x: 100, y: 600))]], box: box)
    let document = try #require(PDFDocument(data: data))
    document.page(at: 0)?.rotation = rotation
    let (page, regions) = try await prepared(try #require(document.dataRepresentation()))
    // PDFKit writes a page with its box moved to the origin, and the content moved with it.
    let line = try region(regions, containing: "Offset origin")
    #expect(abs(line.bounds.minX - 60) < 0.5 && line.bounds.minY < 540 && line.bounds.maxY > 540)
    let result = await editor.applying([TextEdit(region: line, replacement: "Offset origin words")], toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    let changed = try region(await editor.text(ofPage: edited).regions, containing: "words")
    #expect(abs(changed.bounds.minX - 60) < 0.5 && abs(changed.bounds.minY - line.bounds.minY) < 0.5)
  }

  @Test("The colour of the text is kept")
  func colour() async throws {
    let data = try TextEditFixtures.make(pages: [
      [Line("Overdue notice", at: CGPoint(x: 72, y: 700), color: [0.8, 0, 0])]
    ])
    let (page, regions) = try await prepared(data)
    let notice = try region(regions, containing: "Overdue")
    #expect(notice.style.color.red > 0.7 && notice.style.color.green < 0.1)
    let result = await editor.applying([TextEdit(region: notice, replacement: "Overdue reminder")], toPage: page)
    let changed = try region(await editor.text(ofPage: try #require(result.page)).regions, containing: "reminder")
    #expect(changed.style.color == notice.style.color)
  }

  @Test("Accents, typographic quotes and a ligature are drawn and read back as typed")
  func characters() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.lectureNotes())
    let line = try region(regions, containing: "Ribosomes")
    let replacement = "L’élève a fini son café : œuvre finale"
    let result = await editor.applying([TextEdit(region: line, replacement: replacement)], toPage: page)
    #expect(result.outcomes.first?.isEdited == true, "\(result.outcomes)")
    #expect(squeezedText(try #require(result.page)).contains(EditProof.squeezed("L’élève a fini son café")))
  }

  @Test(
    "A replacement that cannot be drawn is refused and nothing changes",
    arguments: ["", "   ", "Thumbs up 👍", "שלום", "line\u{0}break"])
  func unsupportedCharacters(replacement: String) async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let name = try region(regions, containing: "John Smith")
    let result = await editor.applying([TextEdit(region: name, replacement: replacement)], toPage: page)
    #expect(result.outcomes == [.refused(.unsupportedCharacters)] && result.page == nil)
  }

  /// One line in a typeface the device does not have, whose font stands taller above the line
  /// than the standard fonts do, as the fonts reporting tools embed often do.
  ///
  /// One line only: the font is not embedded, so Core Graphics would redraw any other line in a
  /// font of its own choosing, which is a different matter from the one tested here.
  private static func tallFontPage(_ line: String) -> Data {
    let content = "BT /F1 24 Tf 72 700 Td (\(line)) Tj ET"
    let font =
      "/F1 << /Type /Font /Subtype /TrueType /BaseFont /AAAAAB+NoSuchTypeface /Encoding /WinAnsiEncoding "
      + "/FirstChar 32 /LastChar 122 /Widths [\(Array(repeating: "520", count: 91).joined(separator: " "))] "
      + "/FontDescriptor 5 0 R >>"
    return TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << \(font) >> >> >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
      "<< /Type /FontDescriptor /FontName /AAAAAB+NoSuchTypeface /Flags 32 /Ascent 1079 /Descent -210 "
        + "/CapHeight 700 /ItalicAngle 0 /StemV 80 /FontBBox [-500 -250 1500 1100] >>",
    ])
  }

  @Test("New words in a matched font are proven by where they sit on the line, not by the font's height")
  func matchedFontIsProvenOnTheBaseline() async throws {
    // The matched font is shorter above the line than the original, so the box of the new words is
    // centred lower than the box of the old ones, on the same baseline. The proof compared the
    // boxes and refused every edit to documents like this (a letter from a reporting tool, found
    // on the owner's phone on 2026-10-06).
    let editor = ContentStreamTextEditor()
    for line in ["Sam Example", "12 Sample Street", "Sampletown 2000"] {
      let page = Self.tallFontPage(line)
      let region = try #require(await editor.text(ofPage: page).regions.first)
      #expect(region.capability == .limited(.fontSubstituted))
      // The fixture does what it is for: the substitute's box is centred more than the proof's
      // tolerance away from the original's, on the same baseline.
      let found = try #require(try PageAnalysis(page).regions.first)
      let substitute = FontMatcher.match(found.font, size: CGFloat(found.pointSize), text: "Jordan Quick")
      let originalCentre = (found.font.ascent + found.font.descent) / 2000 * found.pointSize
      let substituteCentre = Double(CTFontGetAscent(substitute.font) - CTFontGetDescent(substitute.font)) / 2
      #expect(!substitute.isExact && abs(originalCentre - substituteCentre) > EditProof.positionTolerance)

      let result = await editor.applying([TextEdit(region: region, replacement: "Jordan Quick")], toPage: page)
      #expect(
        result.outcomes == [.edited(.contentStreamWithFallbackFont)], "\(String(describing: result.proofFailure))")
      let read = PDFDocument(data: try #require(result.page))?.page(at: 0)?.string ?? ""
      #expect(EditProof.squeezed(read).contains("JordanQuick"))
      #expect(await editor.rehearsing(region, onPage: page).outcomes.first?.isEdited == true)
    }
  }

  @Test("New words that really are in the wrong place are still refused, and the proof says how far off")
  func misplacedTextIsRefused() throws {
    let page = Self.tallFontPage("Sam Example")
    let analysis = try PageAnalysis(page)
    let region = try #require(analysis.regions.first)
    guard case .planned(let plan) = TextRedrawer.plan(region, replacement: "Jordan Quick") else {
      Issue.record("not planned")
      return
    }
    let content = try TextEraser.erasing([region], in: analysis.content, bytes: analysis.bytes)
    let erased = try analysis.file.replacingContent(of: analysis.page, with: content)
    // The same words, drawn three points below their line.
    let lower = TextRegion.shifted(region, by: CGVector(dx: 0, dy: -3))
    guard case .planned(let wrong) = TextRedrawer.plan(lower, replacement: "Jordan Quick") else {
      Issue.record("not planned")
      return
    }
    let after = try TextRedrawer.draw([wrong], over: erased)
    let failure = try #require(
      EditProof.failure(before: page, erased: erased, after: after, plans: [plan], regions: analysis.regions))
    #expect(failure.refusal == .notVerified && failure.check.check == .newTextMissing)
    #expect(failure.check.measured == 0 && failure.check.expected == -30, "Tenths of a point, along and off the line")
  }

  @Test("A substitute font is the one of its kind that sets the old words closest to their width")
  func substituteFontIsChosenByWidth() throws {
    let analysis = try PageAnalysis(Self.tallFontPage("Quarterly report for the board"))
    let font = try #require(analysis.regions.first).font
    let words = "Quarterly report for the board"
    func width(_ name: String) -> Double {
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(
          string: words,
          attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(name as CFString, 11, nil)
          ]))
      return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
    // With nothing to measure against, the standard choice.
    #expect(CTFontCopyPostScriptName(FontMatcher.fallback(for: font, size: 11)) as String == "Helvetica")
    // Told how wide the old words were, the family that comes closest.
    for name in ["Verdana", "ArialMT", "Helvetica"] where FontMatcher.deviceFont(named: name, size: 11) != nil {
      let chosen = FontMatcher.fallback(for: font, size: 11, original: (words, width(name)))
      #expect(abs(width(CTFontCopyPostScriptName(chosen) as String) - width(name)) < 0.01 * width(name), "\(name)")
    }
    // The same answer every time.
    let once = FontMatcher.fallback(for: font, size: 11, original: (words, width("Verdana")))
    let again = FontMatcher.fallback(for: font, size: 11, original: (words, width("Verdana")))
    #expect(CTFontCopyPostScriptName(once) == CTFontCopyPostScriptName(again))
  }

  @Test("A font the device does not have is replaced by the closest standard font, and the edit says so")
  func fallbackFont() async throws {
    let content = "BT /F1 12 Tf 72 700 Td (Quarterly report) Tj ET"
    let font =
      "/F1 << /Type /Font /Subtype /TrueType /BaseFont /NoSuchTypeface-Bold /Encoding /WinAnsiEncoding "
      + "/FirstChar 32 /LastChar 122 /Widths [\(Array(repeating: "500", count: 91).joined(separator: " "))] >>"
    let data = TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << \(font) >> >> >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ])
    // Read directly: PDFKit would replace the missing font when it rewrote the page.
    let analysis = try PageAnalysis(data)
    let region = try #require(analysis.regions.first)
    #expect(region.editable.capability == .limited(.fontSubstituted) && region.font.isBold)
    guard case .planned(let plan) = TextRedrawer.plan(region, replacement: "Quarterly review") else {
      Issue.record("not planned")
      return
    }
    #expect(plan.mode == .contentStreamWithFallbackFont)
    #expect(FontMatcher.deviceFont(named: "NoSuchTypeface-Bold", size: 12) == nil)
    #expect(FontMatcher.deviceFont(named: ".SFUI-Regular", size: 12) == nil)
  }

  @Test("The fallback font follows the original's traits")
  func fallbackTraits() throws {
    func name(_ base: String, flags: Int = 32) throws -> String {
      let data = TextEditFixtures.assemble([
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> >>",
        "<< /Type /Font /Subtype /TrueType /BaseFont /\(base) /FontDescriptor 5 0 R >>",
        "<< /Type /FontDescriptor /FontName /\(base) /Flags \(flags) /Ascent 900 /Descent -210 >>",
      ])
      let file = try PDFFile(data)
      let font = try TextFont(dictionary: try #require(try file.dictionary(.reference(4))), in: file)
      return CTFontCopyPostScriptName(FontMatcher.fallback(for: font, size: 12)) as String
    }
    #expect(try name("Calibri") == "Helvetica")
    #expect(try name("Calibri-BoldItalic") == "Helvetica-BoldOblique")
    #expect(try name("Cambria") == "TimesNewRomanPSMT")
    #expect(try name("Garamond-Bold") == "TimesNewRomanPS-BoldMT")
    #expect(try name("Consolas", flags: 33) == "Courier")
    #expect(try name("JetBrainsMono-Italic") == "Courier-Oblique")
    #expect(try name("OpenSans") == "Helvetica")
  }

  @Test("An edit made against text that has since changed is refused as stale")
  func stale() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let name = try region(regions, containing: "John Smith")
    let other = try region(regions, containing: "Total")
    let wrong = EditableTextRegion(
      id: name.id, text: "Customer: Someone Else", bounds: name.bounds, angle: 0, style: name.style,
      capability: .direct)
    let missing = EditableTextRegion(
      id: 999_999, text: "x", bounds: name.bounds, angle: 0, style: name.style, capability: .direct)
    for edit in [TextEdit(region: wrong, replacement: "A"), TextEdit(region: missing, replacement: "A")] {
      let result = await editor.applying([edit], toPage: page)
      #expect(result.outcomes == [.refused(.stale)] && result.page == nil)
    }
    // The same region twice in one batch.
    let twice = await editor.applying(
      [TextEdit(region: other, replacement: "Sum"), TextEdit(region: other, replacement: "All")], toPage: page)
    #expect(twice.outcomes == [.edited(.contentStream), .refused(.stale)] && twice.page == nil)
    #expect(await editor.applying([], toPage: page).outcomes.isEmpty)
  }

  @Test("Several edits to one page are made together, or not at all")
  func batch() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let edits = [
      TextEdit(region: try region(regions, containing: "John Smith"), replacement: "Customer: David Smith"),
      TextEdit(region: try region(regions, containing: "Materials"), replacement: "Timber"),
    ]
    let result = await editor.applying(edits, toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    #expect(squeezedText(edited).contains("DavidSmith") && squeezedText(edited).contains("Timber"))
    let partial = await editor.applying(
      [edits[0], TextEdit(region: try region(regions, containing: "Materials"), replacement: "")], toPage: page)
    #expect(partial.page == nil && partial.outcomes == [.edited(.contentStream), .refused(.unsupportedCharacters)])
  }

  @Test("Scenario 5: an image-only page has no text to edit, with or without a recognised text layer")
  func scanned() async throws {
    let image = try TextEditFixtures.singlePage(SyntheticPDF.makeImageOnly(pages: ["A scanned letter"]))
    #expect(await editor.text(ofPage: image) == EditablePageText(regions: [], kind: .image))
    let lines = [
      RecognizedLine(
        text: "A scanned letter", bounds: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.05), confidence: 0.9)
    ]
    let recognised = try PDFWriter.makePDF(mediaBoxes: [PDFWriter.letter]) { context, _, box in
      context.setFillColor(CGColor(gray: 0.9, alpha: 1))
      context.fill(box)
      PDFWriter.drawInvisibleText(lines, in: box, context: context)
    }
    #expect(squeezedText(recognised).contains("Ascannedletter"))
    let text = await editor.text(ofPage: try TextEditFixtures.singlePage(recognised))
    #expect(text.regions.isEmpty && text.kind == .image)
  }

  @Test("Text drawn with transparency, or under something drawn later, is not edited in place")
  func unsupportedDrawing() async throws {
    let faded = try TextEditFixtures.make(pages: [[]]) { context, _ in
      context.setAlpha(0.4)
      TextEditFixtures.draw(Line("Watermark text", size: 30, at: CGPoint(x: 72, y: 500)), in: context)
    }
    let watermark = try region(try await prepared(faded).regions, containing: "Watermark")
    #expect(watermark.capability == .visualReplacementOnly(.unsupportedDrawing) && !watermark.capability.editsContent)

    let covered = try TextEditFixtures.make(
      pages: [[Line("Under the stamp", at: CGPoint(x: 72, y: 700)), Line("In the clear", at: CGPoint(x: 72, y: 600))]],
      finish: { context, _ in
        context.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.2, alpha: 0.5))
        context.fill(CGRect(x: 60, y: 690, width: 200, height: 30))
      })
    let (page, regions) = try await prepared(covered)
    let under = try region(regions, containing: "Under the stamp")
    #expect(under.capability == .visualReplacementOnly(.overlapsOtherContent))
    #expect(try region(regions, containing: "In the clear").capability == .direct)
    let result = await editor.applying([TextEdit(region: under, replacement: "Under the seal")], toPage: page)
    #expect(result.outcomes == [.refused(.overlapsOtherContent)] && result.page == nil)
  }

  @Test("Text inside a table's grid, stroked after the text, is still edited in place")
  func strokedGrid() async throws {
    let data = try TextEditFixtures.make(
      pages: [[Line("Cell one", at: CGPoint(x: 80, y: 700)), Line("Cell two", at: CGPoint(x: 300, y: 700))]],
      finish: { context, _ in
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.stroke(CGRect(x: 70, y: 690, width: 200, height: 30), width: 1)
        context.stroke(CGRect(x: 270, y: 690, width: 200, height: 30), width: 1)
        // And a frame round the whole page.
        context.stroke(CGRect(x: 20, y: 20, width: 572, height: 752), width: 2)
      })
    let (page, regions) = try await prepared(data)
    #expect(regions.map(\.capability) == [.direct, .direct])
    let result = await editor.applying(
      [TextEdit(region: try region(regions, containing: "Cell one"), replacement: "Cell 1")], toPage: page)
    #expect(result.outcomes == [.edited(.contentStream)])
  }

  @Test("Amounts of the same width in a right-aligned column keep their right edge")
  func equalWidthColumn() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let amount = try region(regions, containing: "$950.00")
    let result = await editor.applying([TextEdit(region: amount, replacement: "$1,950.00")], toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    let changed = try region(await editor.text(ofPage: edited).regions, containing: "$1,950.00")
    #expect(abs(changed.bounds.maxX - amount.bounds.maxX) < 1 && changed.bounds.minX < amount.bounds.minX)
  }

  @Test("A reusable object that declares the whole page but paints a footer blocks only the footer")
  func formObject() throws {
    let content = "BT /F9 12 Tf 72 700 Td (Body text) Tj ET /Fm1 Do"
    let form = "0 0 0 rg 72 40 200 10 re f"
    let font =
      "/F9 << /Type /Font /Subtype /TrueType /BaseFont /Helvetica /Encoding /WinAnsiEncoding /FirstChar 32 "
      + "/LastChar 122 /Widths [\(Array(repeating: "500", count: 91).joined(separator: " "))] >>"
    let data = TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << \(font) >> "
        + "/XObject << /Fm1 5 0 R >> >> >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
      "<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Length \(form.utf8.count) >>\nstream\n\(form)\nendstream",
    ])
    let analysis = try PageAnalysis(data)
    #expect(analysis.regions.first?.text == "Body text" && analysis.regions.first?.refusal == nil)
    #expect(analysis.content.painted.count == 1 && (analysis.content.painted.first?.box.maxY ?? 999) < 60)
  }

  @Test("Text in a right-to-left script is left alone")
  func script() async throws {
    let data = try TextEditFixtures.make(pages: [[Line("שלום עולם", font: "ArialHebrew", at: CGPoint(x: 72, y: 700))]])
    let regions = try await prepared(data).regions
    #expect(regions.allSatisfy { !$0.capability.editsContent })
  }

  @Test(
    "Unusual operators survive PDFKit's rewrite and the edit together",
    arguments: [
      "BT /F1 12 Tf 72 700 Td (First line) Tj 0 -18 Td (Second line) Tj ET",
      "BT /F1 12 Tf 14 TL 72 700 Td (First line) Tj (Second line) ' ET",
      "BT /F1 12 Tf 14 TL 72 700 Td (First line) Tj 2 0.5 (Second line) \" ET",
      "BT /F1 12 Tf 72 700 Td [(Fir) -30 (st li) 20 (ne)] TJ 0 -18 TD (Second line) Tj ET",
      "q q BT /F1 12 Tf 1 0 0 1 72 700 Tm (First line) Tj ET Q BT /F2 12 Tf 72 682 Td (Second line) Tj ET",
      "BT /F1 12 Tf 72 700 Td (First ) Tj /F2 12 Tf (line) Tj ET BT /F1 12 Tf 72 682 Td (Second line) Tj ET",
    ])
  func operators(content: String) async throws {
    let (page, regions) = try await prepared(TextEditFixtures.raw(content: content))
    let second = try region(regions, containing: "Second line")
    let result = await editor.applying([TextEdit(region: second, replacement: "Other line")], toPage: page)
    let edited = try #require(result.page, "\(result.outcomes)")
    let text = squeezedText(edited)
    #expect(text.contains("Firstline") && text.contains("Otherline") && !text.contains("Second"))
  }

  @Test("Only the page asked for is read: the work does not grow with the document", .timeLimit(.minutes(5)))
  func perPage() async throws {
    let short = try TextEditFixtures.make(pages: [[Line("Customer: John Smith", at: CGPoint(x: 72, y: 700))]])
    let long = try TextEditFixtures.make(
      pages: (0..<80).map { [Line("Customer: John Smith on page \($0)", at: CGPoint(x: 72, y: 700))] })
    // The page handed to the editor is about the same size whichever document it came from.
    let small = try TextEditFixtures.singlePage(short)
    let fromLong = try TextEditFixtures.singlePage(long, pageIndex: 60)
    #expect(fromLong.count < small.count * 3)
    #expect(await editor.text(ofPage: fromLong).regions.first?.text == "Customer: John Smith on page 60")
  }
}

// MARK: - The proof

@MainActor
@Suite("Text editing: the proof refuses wrong results")
struct EditProofTests {
  /// A plan for replacing a region, with as much room as the test wants to pretend it has.
  private func plan(
    _ data: Data, containing text: String, replacement: String, room: Double? = nil
  ) throws
    -> (analysis: PageAnalysis, plan: PlannedText, erased: Data)
  {
    let analysis = try PageAnalysis(data)
    var region = try #require(analysis.regions.first { $0.text.contains(text) })
    if let room { region.roomAfter = room }
    guard case .planned(let plan) = TextRedrawer.plan(region, replacement: replacement) else {
      throw TextEditFixtures.Failure()
    }
    let content = try TextEraser.erasing([region], in: analysis.content, bytes: analysis.bytes)
    return (analysis, plan, try analysis.file.replacingContent(of: analysis.page, with: content))
  }

  @Test("A correct edit is proven")
  func correct() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let (analysis, plan, erased) = try plan(page, containing: "John Smith", replacement: "Customer: David Smith")
    let after = try TextRedrawer.draw([plan], over: erased)
    #expect(
      EditProof.refusal(before: page, erased: erased, after: after, plans: [plan], regions: analysis.regions) == nil)
  }

  @Test("Each check of the proof says which one it is")
  func checksAreNamed() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let (analysis, plan, erased) = try plan(page, containing: "John Smith", replacement: "Customer: David Smith")
    func check(_ after: Data, regions: [TextRegion]? = nil) -> TextEditProofFailure.Check? {
      EditProof.failure(
        before: page, erased: erased, after: after, plans: [plan], regions: regions ?? analysis.regions)?.check.check
    }
    #expect(check(try TextRedrawer.draw([plan], over: erased)) == nil)
    #expect(check(Data("not a PDF".utf8)) == .reread)
    #expect(check(erased) == .newTextMissing, "The new words are nowhere")
    // One of the page's other lines is missing from what the proof is told to expect.
    let after = try TextRedrawer.draw([plan], over: erased)
    #expect(check(after, regions: Array(analysis.regions.dropLast())) == .regionCount)
    #expect(Set(TextEditProofFailure.Check.allCases.map(\.rawValue)).count == 10)
  }

  @Test("A result without the new text is refused")
  func missingText() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let (analysis, plan, erased) = try plan(page, containing: "John Smith", replacement: "Customer: David Smith")
    for wrong in [page, erased] {
      #expect(
        EditProof.refusal(before: page, erased: erased, after: wrong, plans: [plan], regions: analysis.regions)
          == .notVerified)
    }
  }

  @Test("A result that also changed other text is refused")
  func collateral() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let (analysis, plan, erased) = try plan(page, containing: "John Smith", replacement: "Customer: David Smith")
    // Erase a second region as well, then draw only the planned one.
    let extra = try #require(analysis.regions.first { $0.text == "Materials" })
    let both = try TextEraser.erasing([plan.region, extra], in: analysis.content, bytes: analysis.bytes)
    let after = try TextRedrawer.draw(
      [plan], over: try analysis.file.replacingContent(of: analysis.page, with: both))
    #expect(
      EditProof.refusal(before: page, erased: erased, after: after, plans: [plan], regions: analysis.regions)
        == .notVerified)
  }

  @Test("New text that would print over its neighbour is refused")
  func overprint() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.resume(hasRoom: false))
    // Pretend the line has room it does not have.
    let (analysis, plan, erased) = try plan(
      page, containing: "2024 Data Analyst", replacement: "2025 Senior Data Scientist", room: 1000)
    let after = try TextRedrawer.draw([plan], over: erased)
    #expect(
      EditProof.refusal(before: page, erased: erased, after: after, plans: [plan], regions: analysis.regions) != nil)
  }

  @Test("New text that cannot be seen is refused")
  func invisible() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let (analysis, plan, erased) = try plan(page, containing: "John Smith", replacement: "Customer: David Smith")
    // Draw the right words in white: they read correctly and show nothing.
    var white = plan.region
    white = TextRegion(
      id: white.id, runs: white.runs, text: white.text, font: white.font, pointSize: white.pointSize,
      drawing: white.drawing, horizontalScale: white.horizontalScale, widthDrawn: white.widthDrawn,
      bounds: white.bounds, fill: [1], characterSpacingDrawn: white.characterSpacingDrawn)
    guard case .planned(let hidden) = TextRedrawer.plan(white, replacement: "Customer: David Smith") else {
      Issue.record("not planned")
      return
    }
    let after = try TextRedrawer.draw([hidden], over: erased)
    #expect(
      EditProof.refusal(before: page, erased: erased, after: after, plans: [plan], regions: analysis.regions)
        == .notVerified)
  }

  @Test("A result drawn in the wrong place is refused")
  func misplaced() throws {
    let page = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    let (analysis, plan, erased) = try plan(page, containing: "John Smith", replacement: "Customer: David Smith")
    var moved = plan.region
    moved = TextRegion(
      id: moved.id, runs: moved.runs, text: moved.text, font: moved.font, pointSize: moved.pointSize,
      drawing: moved.drawing.concatenating(CGAffineTransform(translationX: 0, y: -200)),
      horizontalScale: moved.horizontalScale, widthDrawn: moved.widthDrawn, bounds: moved.bounds, fill: moved.fill,
      characterSpacingDrawn: moved.characterSpacingDrawn)
    guard case .planned(let elsewhere) = TextRedrawer.plan(moved, replacement: "Customer: David Smith") else {
      Issue.record("not planned")
      return
    }
    let after = try TextRedrawer.draw([elsewhere], over: erased)
    #expect(
      EditProof.refusal(before: page, erased: erased, after: after, plans: [plan], regions: analysis.regions)
        == .notVerified)
  }
}

// MARK: - Hostile input

@MainActor
@Suite("Text editing: untrusted input")
struct TextEditingHostileInputTests {
  @Test("Malformed PDFs are refused without a crash", arguments: GoldenCorpus.malformed())
  func malformed(file: GoldenCorpus.Malformed) async {
    let editor = ContentStreamTextEditor()
    let text = await editor.text(ofPage: file.data)
    let region = EditableTextRegion(
      id: 0, text: "x", bounds: .zero, angle: 0,
      style: TextStyle(
        fontName: "Helvetica", pointSize: 12, isBold: false, isItalic: false, isMonospaced: false, color: .black),
      capability: .direct)
    let result = await editor.applying(
      [TextEdit(region: text.regions.first ?? region, replacement: "y")], toPage: file.data)
    #expect(result.page == nil || PDFDocument(data: result.page ?? Data()) != nil)
  }

  // A CI simulator runs this several times slower than a Mac, so the edit, with its three renders,
  // is made for a few of the damaged pages and the reading for all of them.
  @Test("Damaged page content and fonts never crash, hang or produce an unreadable page", .timeLimit(.minutes(5)))
  func fuzzed() async throws {
    let editor = ContentStreamTextEditor()
    let base = try TextEditFixtures.singlePage(TextEditFixtures.invoice())
    var generator = SplitMix(seed: 0x5EED)
    var edited = 0
    for _ in 0..<80 {
      var bytes = [UInt8](base)
      for _ in 0..<Int.random(in: 1...6, using: &generator) {
        let index = Int.random(in: 0..<bytes.count, using: &generator)
        bytes[index] = UInt8.random(in: 0...255, using: &generator)
      }
      let damaged = Data(bytes)
      let text = await editor.text(ofPage: damaged)
      guard edited < 8, let region = text.regions.first else { continue }
      edited += 1
      let result = await editor.applying([TextEdit(region: region, replacement: "Fuzzed")], toPage: damaged)
      if let page = result.page { #expect(PDFDocument(data: page)?.pageCount == 1) }
    }
  }

  @Test("Page content built to exhaust the reader is stopped by its limits")
  func limits() throws {
    #expect(throws: PDFSyntaxError.tooLarge) {
      try ContentStream.parse(Array(String(repeating: "q ", count: TextEditingLimits.operators + 1).utf8))
    }
    #expect(throws: PDFSyntaxError.self) {
      try ContentStream.parse(
        Array((String(repeating: "[", count: 500) + String(repeating: "]", count: 500) + " TJ").utf8))
    }
    // A deeply nested save and restore is interpreted without recursion.
    let nested =
      String(repeating: "q ", count: 5000) + "BT /F1 12 Tf 72 700 Td (Deep) Tj ET "
      + String(repeating: "Q ", count: 5000)
    #expect(throws: Never.self) { _ = try? PageAnalysis(TextEditFixtures.raw(content: nested)) }
    // A page that places a reusable object thousands of times is read without reading it each time.
    let placed = String(repeating: "/Fm1 Do ", count: 20_000)
    let form = String(repeating: "0 0 10 10 re f ", count: 2_000)
    let repeated = TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        + "/Resources << /XObject << /Fm1 5 0 R >> >> >>",
      "<< /Length \(placed.utf8.count) >>\nstream\n\(placed)\nendstream",
      "<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Length \(form.utf8.count) >>\nstream\n\(form)\nendstream",
    ])
    let clock = ContinuousClock()
    let elapsed = try clock.measure { _ = try PageAnalysis(repeated) }
    #expect(elapsed < .seconds(20))
    // A stream that claims more bytes than the file has.
    let lying = TextEditFixtures.assemble([
      "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
      "<< /Length 999999999 >>\nstream\nBT ET\nendstream",
    ])
    #expect(throws: PDFSyntaxError.self) { try PageAnalysis(lying) }
    #expect(throws: PDFSyntaxError.self) { try PDFFile.inflate([0x78, 0x9C, 0xFF, 0xFF, 0xFF]) }
  }
}

/// A small seeded generator, so a failing fuzz case can be run again.
private struct SplitMix: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

extension TextRegion {
  /// The same text, moved on the page; for drawing words where they should not be.
  fileprivate static func shifted(_ region: TextRegion, by move: CGVector) -> TextRegion {
    let drawing = region.drawing.concatenating(CGAffineTransform(translationX: move.dx, y: move.dy))
    return TextRegion(
      id: region.id, runs: region.runs, text: region.text, font: region.font, pointSize: region.pointSize,
      drawing: drawing, horizontalScale: region.horizontalScale, widthDrawn: region.widthDrawn,
      bounds: region.bounds.offsetBy(dx: move.dx, dy: move.dy), fill: region.fill,
      characterSpacingDrawn: region.characterSpacingDrawn)
  }
}
