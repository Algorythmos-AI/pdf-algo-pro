import Core
import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import PDFEngine

@Suite("The text layer of a scan (FR-SCAN-002)")
struct TextLayerTests {
  /// A page with only an invisible text layer made from these lines.
  private func page(_ lines: [RecognizedLine]) throws -> PDFPage {
    let data = try PDFWriter.makePDF(mediaBoxes: [PDFWriter.letter]) { context, _, box in
      context.setFillColor(CGColor(gray: 0.95, alpha: 1))
      context.fill(box)
      PDFWriter.drawInvisibleText(lines, in: box, context: context)
    }
    return try #require(PDFDocument(data: data)?.page(at: 0))
  }

  /// A line with its words spread evenly along it.
  private func line(_ text: String, y: CGFloat, withWords: Bool) -> RecognizedLine {
    let bounds = CGRect(x: 0.1, y: y, width: 0.8, height: 0.03)
    let parts = text.split(separator: " ").map(String.init)
    let letters = CGFloat(parts.reduce(0) { $0 + $1.count } + parts.count - 1)
    var x = bounds.minX
    let words = parts.map { part in
      let width = bounds.width * CGFloat(part.count) / letters
      defer { x += width + bounds.width / letters }
      return RecognizedWord(text: part, bounds: CGRect(x: x, y: y, width: width, height: 0.03))
    }
    return RecognizedLine(text: text, bounds: bounds, confidence: 0.9, words: withWords ? words : nil)
  }

  private func squeezed(_ text: String?) -> String {
    (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  @Test("Placed word by word, a page reads the same words in the same order as placed line by line")
  func sameText() throws {
    let texts = ["Invoice number INV-2026-0042", "Total due: 120.00", "Thank you for your business."]
    func lines(_ withWords: Bool) -> [RecognizedLine] {
      texts.enumerated().map { line($1, y: 0.8 - CGFloat($0) * 0.06, withWords: withWords) }
    }
    let byLine = squeezed(try page(lines(false)).string)
    let byWord = squeezed(try page(lines(true)).string)
    #expect(byLine == texts.joined(separator: " "))
    #expect(byWord == byLine)
  }

  @Test("With words placed, a point on a word selects that word, where its box says it is")
  func oneWord() throws {
    let recognised = line("Total due: 120.00", y: 0.7, withWords: true)
    let page = try page([recognised])
    let box = page.bounds(for: .mediaBox)
    for word in try #require(recognised.words) {
      // The middle half of the word's box, as a finger would drag over it.
      let area = CGRect(
        x: box.width * (word.bounds.minX + word.bounds.width * 0.25), y: box.height * word.bounds.minY,
        width: box.width * word.bounds.width * 0.5, height: box.height * word.bounds.height)
      let picked = squeezed(page.selection(for: area)?.string)
      #expect(!picked.isEmpty && word.text.contains(picked), "\(word.text) gave [\(picked)]")
    }
    // The whole of a word's box gives the whole word and nothing of its neighbours.
    let first = try #require(recognised.words?.first)
    let whole = CGRect(
      x: box.width * first.bounds.minX, y: box.height * first.bounds.minY, width: box.width * first.bounds.width,
      height: box.height * first.bounds.height)
    #expect(squeezed(page.selection(for: whole)?.string) == first.text)
  }

  @Test("A line is as wide as its box says, whether its own width is more or less, and reads back whole")
  func stretched() throws {
    for (text, width) in [("Total due: 120.00", 0.8), ("Total due: 120.00", 0.12), ("Zażółć gęślą jaźń", 0.7)] {
      let recognised = RecognizedLine(
        text: text, bounds: CGRect(x: 0.1, y: 0.6, width: width, height: 0.03), confidence: 0.9)
      let page = try page([recognised])
      let box = page.bounds(for: .mediaBox)
      #expect(squeezed(page.string) == text, "\(text) at \(width)")
      let drawn = try #require(page.selection(for: box)).bounds(for: page)
      #expect(abs(drawn.width - box.width * width) < box.width * width * 0.06, "\(drawn.width) for \(width)")
      #expect(abs(drawn.minX - box.width * 0.1) < 3)
    }
  }

  @Test("Words that are not the whole line are not used, so no text is lost")
  func wordsMustBeTheLine() throws {
    let whole = line("Seller: Example Stationery", y: 0.7, withWords: true)
    let partial = RecognizedLine(
      text: whole.text, bounds: whole.bounds, confidence: 0.9, words: Array(try #require(whole.words).dropLast()))
    #expect(squeezed(try page([partial]).string) == whole.text)
    let empty = RecognizedLine(text: whole.text, bounds: whole.bounds, confidence: 0.9, words: [])
    #expect(squeezed(try page([empty]).string) == whole.text)
  }

  @Test(
    "Text in each script the recogniser reads comes back from the layer as it went in",
    arguments: [
      "Größe über Straße", "¿Cuánto señor niño?", "Zażółć gęślą jaźń", "Příliš žluťoučký kůň", "Tiếng Việt đẹp quá",
      "Счёт на оплату", "Рахунок їжак ґанок", "Invoice total 120", "Facture numéro 42 à régler",
    ])
  func scripts(_ text: String) throws {
    for withWords in [false, true] {
      let back = squeezed(try page([line(text, y: 0.6, withWords: withWords)]).string)
      #expect(back == text, "\(withWords ? "by word" : "by line") gave [\(back)]")
    }
  }

  @Test("The layer reads back in the order its lines are given, so two columns stay two columns")
  func order() throws {
    // Left column first, then the right, as document recognition gives them; side by side on the page.
    let left = ["The tenant agrees", "to pay the rent"]
    let right = ["The landlord agrees", "to maintain the roof"]
    func column(_ texts: [String], x: CGFloat) -> [RecognizedLine] {
      texts.enumerated().map {
        RecognizedLine(
          text: $1, bounds: CGRect(x: x, y: 0.8 - CGFloat($0) * 0.05, width: 0.35, height: 0.03), confidence: 0.9)
      }
    }
    let read = squeezed(try page(column(left, x: 0.08) + column(right, x: 0.55)).string)
    #expect(read == (left + right).joined(separator: " "))
  }

  @Test("Lines kept by an earlier version, without words, still decode")
  func olderLines() throws {
    let older = #"[{"text":"Old line","bounds":[[0.1,0.5],[0.5,0.04]],"confidence":0.9}]"#
    let lines = try JSONDecoder().decode([RecognizedLine].self, from: Data(older.utf8))
    #expect(lines.first?.text == "Old line" && lines.first?.words == nil)
    let newer = try JSONDecoder().decode(
      [RecognizedLine].self, from: JSONEncoder().encode([line("Two words", y: 0.5, withWords: true)]))
    #expect(newer.first?.words?.map(\.text) == ["Two", "words"])
  }
}
