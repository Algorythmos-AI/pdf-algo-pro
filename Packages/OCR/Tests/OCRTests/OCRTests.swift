import Core
import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import OCR

/// Draws large black text on white, the way a clean scan looks.
private func image(of lines: [String], size: CGSize = CGSize(width: 1600, height: 1000)) throws -> CGImage {
  let context = try #require(
    CGContext(
      data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(origin: .zero, size: size))
  let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
  for (index, text) in lines.enumerated() {
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    context.textPosition = CGPoint(x: 100, y: size.height - 200 - CGFloat(index) * 160)
    CTLineDraw(line, context)
  }
  return try #require(context.makeImage())
}

@Suite("Vision text recognition", .tags(.ocr))
struct VisionTextRecognizerTests {
  @Test("English and French text is recognised on device, top to bottom (FR-SCAN-002)")
  func recognisesLinesInReadingOrder() async throws {
    let lines = try await VisionTextRecognizer().recognizeText(
      in: image(of: ["Invoice total 120", "Facture numéro 42"]))
    let text = lines.map(\.text).joined(separator: "\n").lowercased()
    #expect(text.contains("invoice total"))
    #expect(text.contains("facture"))
    #expect(lines.first?.text.lowercased().contains("invoice") == true)
    for line in lines {
      #expect((0...1).contains(line.bounds.minX) && (0...1).contains(line.bounds.maxY))
      #expect(line.confidence > 0)
    }
  }

  @Test("With words asked for, every line comes with its words, each inside the line and in reading order")
  func words() async throws {
    let lines = try await VisionTextRecognizer.wider.recognizeText(
      in: image(of: ["Invoice total is 120 dollars.", "Facture numéro 42"]))
    #expect(lines.count == 2)
    for line in lines {
      let words = try #require(line.words, "The line has its words")
      #expect(words.map(\.text).joined(separator: " ") == line.text, "Together the words are the line")
      #expect(words.count >= 3)
      for (word, next) in zip(words, words.dropFirst()) {
        #expect(word.bounds.maxX <= next.bounds.minX + 0.01, "Left to right, without overlap")
      }
      for word in words {
        #expect(word.bounds.minX >= line.bounds.minX - 0.01 && word.bounds.maxX <= line.bounds.maxX + 0.01)
        #expect(word.bounds.width > 0 && word.bounds.height > 0)
      }
    }
    // Punctuation stays with its word.
    #expect(lines.first?.words?.last?.text.hasSuffix(".") == true)
    // Without asking, lines are as they always were.
    let plain = try await VisionTextRecognizer().recognizeText(in: image(of: ["Invoice total 120"]))
    #expect(plain.first?.words == nil)
  }

  @Test("The wider set recognises other languages in Latin and Cyrillic letters, with their accents")
  func otherLanguages() async throws {
    let samples = [
      "Rechnung über zwölf Stühle", "Factura número catorce del señor", "Fattura numero quindici",
      "Счёт на оплату товара",
    ]
    for sample in samples {
      let lines = try await VisionTextRecognizer.wider.recognizeText(in: image(of: [sample]))
      #expect(lines.map(\.text).joined(separator: " ") == sample, "\(sample)")
    }
    #expect(VisionTextRecognizer.widerLanguages.prefix(2) == VisionTextRecognizer.firstLanguages[...])
  }

  @Test("A line is split at its spaces, however many, and a line of spaces has no words")
  func wordRanges() {
    func words(_ text: String) -> [String] { VisionTextRecognizer.wordRanges(in: text).map { String(text[$0]) } }
    #expect(words("Total due: 120.00") == ["Total", "due:", "120.00"])
    #expect(words("  two  spaces ") == ["two", "spaces"])
    #expect(words("   ").isEmpty && words("").isEmpty)
    #expect(words("l'été à 5 €") == ["l'été", "à", "5", "€"])
  }

  @Test func blankPagesHaveNoLines() async throws {
    #expect(try await VisionTextRecognizer().recognizeText(in: image(of: [])).isEmpty)
  }

  @Test("Lines on the same row read left to right; empty lines are dropped")
  func readingOrder() {
    let left = RecognizedLine(text: "left", bounds: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.05), confidence: 1)
    let right = RecognizedLine(text: "right", bounds: CGRect(x: 0.6, y: 0.51, width: 0.2, height: 0.05), confidence: 1)
    let top = RecognizedLine(text: "top", bounds: CGRect(x: 0.5, y: 0.9, width: 0.2, height: 0.05), confidence: 1)
    let blank = RecognizedLine(text: "  ", bounds: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), confidence: 1)
    #expect(VisionTextRecognizer.lines(from: [right, blank, left, top]).map(\.text) == ["top", "left", "right"])
  }
}

extension Tag {
  @Tag static var ocr: Self
}
