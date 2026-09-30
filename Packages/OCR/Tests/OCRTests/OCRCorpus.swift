import CoreGraphics
import CoreText
import Foundation

/// The synthetic OCR corpus (W3.3, docs/testing-strategy.md, "OCR accuracy testing"): pages drawn from
/// known text, so the ground truth is exact and no real document is involved.
///
/// French pages cover accented capitals, "œ" and "æ", guillemets and the narrow no-break spaces of
/// French punctuation. Degraded pages are skewed, blurred, low in contrast and speckled.
enum OCRCorpus {
  enum Language: String, CaseIterable {
    case english = "EN"
    case french = "FR"
  }

  enum Condition: String, CaseIterable {
    case clean
    case degraded
  }

  struct Page {
    let truth: String
    let image: CGImage
  }

  /// Pages for a language and condition, the same on every run for a given seed.
  static func pages(_ language: Language, _ condition: Condition, count: Int, seed: UInt64) -> [Page] {
    var generator = SplitMix(seed: seed &+ (language == .english ? 0 : 1_000) &+ (condition == .clean ? 0 : 7))
    return (0..<count).compactMap { index in
      let lines = (0..<8).map { _ in sentence(language, using: &generator) }
      let font = index.isMultiple(of: 2) ? "Helvetica" : "Times New Roman"
      guard let clean = render(lines, font: font) else { return nil }
      let image = condition == .clean ? clean : degrade(clean, using: &generator)
      return image.map { Page(truth: lines.joined(separator: "\n"), image: $0) }
    }
  }

  // MARK: - Text

  private static let nnbsp = "\u{202F}"

  private static func sentence(_ language: Language, using generator: inout SplitMix) -> String {
    func pick(_ words: [String]) -> String { words[Int(generator.next() % UInt64(words.count))] }
    let number = String(100 + Int(generator.next() % 9_000))
    let day = String(1 + Int(generator.next() % 28))
    let amount = "\(10 + Int(generator.next() % 990)).\(String(format: "%02d", Int(generator.next() % 100)))"
    let days = String(5 + Int(generator.next() % 55))
    switch language {
    case .english:
      let names = ["Olivia Hart", "Samuel Price", "Grace Moreno", "Daniel Webb", "Chloe Turner"]
      let months = ["January", "March", "May", "August", "October", "December"]
      let documents = ["contract", "invoice", "report", "lease", "statement"]
      let weekdays = ["Monday", "Wednesday", "Friday"]
      switch generator.next() % 5 {
      case 0: return "Invoice \(number) was issued on \(day) \(pick(months)) 2026 for \(amount) dollars."
      case 1: return "Please send the signed \(pick(documents)) to \(pick(names)) before \(pick(weekdays))."
      case 2: return "Payment of \(amount) is due within \(days) days of delivery."
      case 3: return "\(pick(names)) will review the \(pick(documents)) with the finance team."
      default: return "Section \(number) covers insurance, warranties and late fees."
      }
    case .french:
      let names = ["Élodie Martin", "Hélène Garnier", "Loïc Dubois", "Maëlle Roux", "François Lefèvre"]
      let months = ["janvier", "février", "août", "décembre", "juillet"]
      let documents = ["contrat", "bail", "relevé", "dossier"]
      let nouns = ["cœur", "œuvre", "sœur", "vœu", "nœud"]
      switch generator.next() % 6 {
      case 0: return "La facture n° \(number) a été émise le \(day) \(pick(months)) 2026 pour \(amount) €."
      case 1: return "Veuillez envoyer le \(pick(documents)) signé à \(pick(names)) avant vendredi."
      case 2: return "L’article \(number) précise\(nnbsp): «\(nnbsp)le paiement est dû sous \(days) jours\(nnbsp)»."
      case 3: return "À l’École, \(pick(names)) étudie l’\(pick(nouns)) du curriculum vitæ\(nnbsp)!"
      case 4: return "Événement ex æquo\(nnbsp); Ça reste à vérifier avec \(pick(names))."
      default: return "Où se trouve le \(pick(documents)) de \(pick(names))\(nnbsp)?"
      }
    }
  }

  // MARK: - Pages

  /// A page at about 200 dots per inch: black text on white, as a clean scan looks.
  private static func render(_ lines: [String], font name: String) -> CGImage? {
    let size = CGSize(width: 1_700, height: 2_200)
    guard
      let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let font = CTFontCreateWithName(name as CFString, 34, nil)
    for (index, text) in lines.enumerated() {
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
      context.textPosition = CGPoint(x: 110, y: size.height - 180 - CGFloat(index) * 90)
      CTLineDraw(line, context)
    }
    return context.makeImage()
  }

  /// Skews by up to 1.5 degrees, blurs by scaling down and up, lowers the contrast and adds speckles.
  private static func degrade(_ image: CGImage, using generator: inout SplitMix) -> CGImage? {
    let width = image.width
    let height = image.height
    guard
      let small = CGContext(
        data: nil, width: width * 11 / 20, height: height * 11 / 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let output = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    small.interpolationQuality = .medium
    small.draw(image, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
    guard let blurred = small.makeImage() else { return nil }
    output.setFillColor(CGColor(gray: 0.86, alpha: 1))
    output.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let angle = (Double(generator.next() % 300) / 100 - 1.5) * .pi / 180
    output.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    output.rotate(by: angle)
    output.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    output.setAlpha(0.72)
    output.setBlendMode(.multiply)
    output.interpolationQuality = .medium
    output.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
    output.setAlpha(1)
    output.setBlendMode(.normal)
    for _ in 0..<2_500 {
      let gray = Double(generator.next() % 60) / 100
      output.setFillColor(CGColor(gray: gray, alpha: 0.5))
      output.fill(
        CGRect(x: Int(generator.next() % UInt64(width)), y: Int(generator.next() % UInt64(height)), width: 2, height: 2)
      )
    }
    return output.makeImage()
  }
}

/// SplitMix64: a small deterministic generator, so the corpus is the same on every run.
struct SplitMix {
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
