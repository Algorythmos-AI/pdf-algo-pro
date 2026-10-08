import CoreTestSupport
import Foundation
import Testing

@testable import OCR

/// The OCR accuracy gates (W3.3, bar item B5): character and word error rates per language and
/// condition, against the thresholds in docs/testing-strategy.md ("OCR accuracy testing", "Thresholds").
///
/// Every pull request runs a subset; `FULL_SUITE=1` (or `TEST_RUNNER_FULL_SUITE=1` through xcodebuild)
/// runs the full corpus of 200 clean and 100 degraded pages per language.
@Suite("OCR accuracy", .tags(.ocr))
struct OCRAccuracyTests {
  /// The gates: character and word error rates a subset may not exceed.
  static let gates: [OCRCorpus.Condition: (cer: Double, wer: Double?)] = [
    .clean: (0.02, 0.05), .degraded: (0.05, nil),
  ]

  static var isFullSuite: Bool { ProcessInfo.processInfo.environment["FULL_SUITE"] == "1" }

  @Test("Recognition meets the accuracy gates in English and French (FR-SCAN-002)")
  func accuracy() async throws {
    let counts: [OCRCorpus.Condition: Int] =
      Self.isFullSuite ? [.clean: 200, .degraded: 100] : [.clean: 3, .degraded: 2]
    var report = [
      "# OCR accuracy", "", "| Language | Condition | Pages | CER | WER | Gate |", "|---|---|---|---|---|---|",
    ]
    // The same gates for English and French alone and among the wider set of languages: adding
    // languages must not make the first two worse.
    for (name, recognizer) in [("", VisionTextRecognizer()), (" (wider set)", VisionTextRecognizer.wider)] {
      for language in OCRCorpus.Language.allCases {
        for condition in OCRCorpus.Condition.allCases {
          let pages = OCRCorpus.pages(language, condition, count: counts[condition] ?? 0, seed: 2026)
          var score = RecognitionScore()
          for page in pages {
            let lines = try await recognizer.recognizeText(in: page.image)
            score = score + RecognitionScore(recognised: lines.map(\.text).joined(separator: "\n"), truth: page.truth)
          }
          let gate = try #require(Self.gates[condition])
          let passes = score.characterErrorRate <= gate.cer && (gate.wer.map { score.wordErrorRate <= $0 } ?? true)
          report.append(
            "| \(language.rawValue)\(name) | \(condition.rawValue) | \(pages.count) | "
              + String(format: "%.2f%% | %.2f%% | ", score.characterErrorRate * 100, score.wordErrorRate * 100)
              + (passes ? "pass" : "FAIL") + " |")
          #expect(
            score.characterErrorRate <= gate.cer,
            "\(language.rawValue)\(name) \(condition.rawValue): CER \(score.characterErrorRate) above \(gate.cer)")
          if let wer = gate.wer {
            #expect(
              score.wordErrorRate <= wer,
              "\(language.rawValue)\(name) \(condition.rawValue): WER \(score.wordErrorRate) above \(wer)")
          }
        }
      }
    }
    let text = report.joined(separator: "\n") + "\n"
    print(text)
    SuiteReport.write(text, named: "ocr-accuracy.md")
  }
}

@Suite("Recognition scoring")
struct RecognitionScoreTests {
  @Test("Error rates count insertions, deletions and substitutions over the ground truth")
  func rates() {
    let exact = RecognitionScore(recognised: "Facture n° 42", truth: "Facture n° 42")
    #expect(exact.characterErrorRate == 0 && exact.wordErrorRate == 0)
    let accent = RecognitionScore(recognised: "Facture a ete", truth: "Facture à été")
    #expect(accent.characterEdits == 3 && accent.wordEdits == 2, "Accents are significant")
    let spacing = RecognitionScore(recognised: "Où\u{00A0}?\nOui", truth: "Où\u{202F}? Oui")
    #expect(spacing.characterEdits == 0, "No-break spaces and line breaks count as one space")
    let french = RecognitionScore(
      recognised: "l'École dit : «oui»!", truth: "l\u{2019}École dit\u{202F}: «\u{202F}oui\u{202F}»\u{202F}!")
    #expect(french.characterEdits == 0, "Apostrophe forms and French punctuation spacing are typography")
    #expect(RecognitionScore(recognised: "vita!", truth: "vitæ\u{202F}!").characterEdits == 1, "Letters still count")
    let missing = RecognitionScore(recognised: "", truth: "abcd")
    #expect(missing.characterErrorRate == 1 && missing.wordErrorRate == 1)
    let total = exact + missing
    #expect(total.characters == exact.characters + 4 && total.characterEdits == 4)
    #expect(RecognitionScore().characterErrorRate == 0)
    #expect(RecognitionScore.distance(Array("kitten"), Array("sitting")) == 3)
  }
}
