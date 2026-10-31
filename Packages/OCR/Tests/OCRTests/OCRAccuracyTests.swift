import Core
import CoreTestSupport
import Foundation
import Testing

@testable import OCR

/// The OCR accuracy gates (W3.3, bar item B5): character and word error rates per language and
/// condition, against the thresholds in docs/testing-strategy.md ("OCR accuracy testing", "Thresholds").
///
/// Every pull request runs a subset; `FULL_SUITE=1` (or `TEST_RUNNER_FULL_SUITE=1` through xcodebuild)
/// runs the full corpus of 200 clean and 100 degraded pages per language. `OCR_RECOGNIZERS` (a
/// comma-separated list of `line`, `wider`, `document`, `line-uncorrected`, `document-uncorrected`)
/// runs only those recognisers, so CI can split the full corpus across jobs.
@Suite("OCR accuracy", .tags(.ocr))
struct OCRAccuracyTests {
  /// The gates: character and word error rates a subset may not exceed.
  static let gates: [OCRCorpus.Condition: (cer: Double, wer: Double?)] = [
    .clean: (0.02, 0.05), .degraded: (0.05, nil),
  ]

  static var isFullSuite: Bool { ProcessInfo.processInfo.environment["FULL_SUITE"] == "1" }

  /// The recognisers asked for by `OCR_RECOGNIZERS`, or nil for all of them.
  static var chosenRecognizers: Set<String>? {
    guard let value = ProcessInfo.processInfo.environment["OCR_RECOGNIZERS"], !value.isEmpty else { return nil }
    return Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
  }

  /// Whether this system reads French worse than the gate allows, a known issue (#308).
  ///
  /// iOS 27.0's recogniser misreads French ligatures and accents ("vitæ" as "vita", "sœur" as
  /// "sceur", "signé" as "signe") more often than iOS 26.5, with or without language correction,
  /// and no request setting avoids it. On the full corpus it still meets the 5% gate (3.0% of
  /// words against 2.3% on iOS 26.5, run 40469533664); on the three-page subset a few misread
  /// words take it over. The gate stays 5% on every system for consistency (owner's decisions,
  /// 2026-10-26 and 2026-10-27, PAP-069); on iOS 27 or later only the subset's French clean
  /// word-error check is marked as a known issue, and the full corpus is gated without a marker.
  /// When Apple fixes the recogniser the check passes, Swift Testing reports that the known issue
  /// no longer occurs, and this marker is removed.
  static var readsFrenchWorse: Bool {
    #if os(iOS)
      ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    #else
      false
    #endif
  }

  @Test("Recognition meets the accuracy gates in English and French (FR-SCAN-002)")
  func accuracy() async throws {
    let counts: [OCRCorpus.Condition: Int] =
      Self.isFullSuite ? [.clean: 200, .degraded: 100] : [.clean: 3, .degraded: 2]
    var report = [
      "# OCR accuracy", "", "| Language | Condition | Pages | CER | WER | Gate |", "|---|---|---|---|---|---|",
    ]
    var wrongWords: [String] = []
    // The same gates for English and French alone and among the wider set of languages: adding
    // languages must not make the first two worse.
    let recognizers: [(key: String, name: String, recognizer: any TextRecognizing, gated: Bool)] = [
      ("line", "", VisionTextRecognizer(), true), ("wider", " (wider set)", VisionTextRecognizer.wider, true),
      ("document", " (as a document)", VisionDocumentRecognizer(), true),
      // Reported, not gated: the same recognisers without language correction, so a run shows how
      // much the dictionaries help or hurt on that system (issue 308: French on iOS 27).
      ("line-uncorrected", " (no correction)", VisionTextRecognizer(correctsLanguage: false), false),
      (
        "document-uncorrected", " (as a document, no correction)",
        VisionDocumentRecognizer(
          fallback: VisionTextRecognizer(
            languages: VisionTextRecognizer.widerLanguages, detectsLanguage: true, findsWords: true,
            correctsLanguage: false)), false
      ),
    ]
    let chosen = Self.chosenRecognizers
    for (key, name, recognizer, gated) in recognizers where chosen?.contains(key) ?? true {
      for language in OCRCorpus.Language.allCases {
        for condition in OCRCorpus.Condition.allCases {
          let pages = OCRCorpus.pages(language, condition, count: counts[condition] ?? 0, seed: 2026)
          var score = RecognitionScore()
          // Each page's wrong words, so a failure names them and the log alone says what to fix; on
          // the full corpus, how often each misreading happens instead, the most frequent first.
          var misread: [String] = []
          var tally: [String: Int] = [:]
          for (index, page) in pages.enumerated() {
            let lines = try await recognizer.recognizeText(in: page.image)
            let recognised = lines.map(\.text).joined(separator: "\n")
            score = score + RecognitionScore(recognised: recognised, truth: page.truth)
            let edits = RecognitionScore.wordDifferences(recognised: recognised, truth: page.truth)
            for edit in edits { tally[edit, default: 0] += 1 }
            if !edits.isEmpty {
              misread.append("page \(index + 1) (\(page.font)): " + edits.joined(separator: "; "))
            }
          }
          if Self.isFullSuite {
            misread = tally.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(25)
              .map { "\($0.value)x \($0.key)" }
          }
          let label = "\(language.rawValue)\(name) \(condition.rawValue)"
          if !misread.isEmpty { wrongWords.append("- \(label): " + misread.joined(separator: " | ")) }
          let detail = misread.isEmpty ? "" : "; wrong words: " + misread.joined(separator: " | ")
          let gate = try #require(Self.gates[condition])
          guard gated else {
            report.append(
              "| \(language.rawValue)\(name) | \(condition.rawValue) | \(pages.count) | "
                + String(format: "%.2f%% | %.2f%% | ", score.characterErrorRate * 100, score.wordErrorRate * 100)
                + "not gated |")
            continue
          }
          let knownIssue = language == .french && condition == .clean && Self.readsFrenchWorse && !Self.isFullSuite
          let passesCER = score.characterErrorRate <= gate.cer
          let passesWER = gate.wer.map { score.wordErrorRate <= $0 } ?? true
          let verdict =
            passesCER && passesWER ? "pass" : passesCER && knownIssue ? "FAIL, known issue #308" : "FAIL"
          report.append(
            "| \(language.rawValue)\(name) | \(condition.rawValue) | \(pages.count) | "
              + String(format: "%.2f%% | %.2f%% | ", score.characterErrorRate * 100, score.wordErrorRate * 100)
              + verdict + " |")
          #expect(
            score.characterErrorRate <= gate.cer,
            "\(label): CER \(score.characterErrorRate) above \(gate.cer)\(detail)")
          if let wer = gate.wer {
            let check = {
              #expect(
                score.wordErrorRate <= wer,
                "\(label): WER \(score.wordErrorRate) (\(score.wordEdits) of \(score.words) words) above \(wer)\(detail)"
              )
            }
            if knownIssue {
              // Known issue (#308): the 5% gate stands; on iOS 27 the three-page French subset
              // misses it. If this check passes here, Swift Testing reports the known issue as
              // gone: remove this marker.
              withKnownIssue("iOS 27 reads French ligatures and accents worse (#308); gate stays \(wer)") {
                check()
              }
            } else {
              check()
            }
          }
        }
      }
    }
    // Every subset's wrong words, passing or not, so two systems' runs compare word by word.
    report += ["", "## Wrong words", ""] + (wrongWords.isEmpty ? ["None."] : wrongWords)
    let text = report.joined(separator: "\n") + "\n"
    print(text)
    SuiteReport.write(text, named: "ocr-accuracy.md")
  }
}

/// The same gates for pages the size of a camera's, brought down as scanning brings them down.
///
/// `SearchablePDFBuilder` does this before recognition (#371). Only the recognisers the app can use
/// are gated here.
@Suite("OCR accuracy after bringing a camera's pages down", .tags(.ocr))
struct OCRCameraSizeTests {
  /// The longer side of what the document camera gives on a 12-megapixel iPhone camera, in pixels.
  static let cameraSize = 4_032

  @Test("Pages brought down from a camera's size meet the accuracy gates (#371)")
  func accuracy() async throws {
    let counts: [OCRCorpus.Condition: Int] =
      OCRAccuracyTests.isFullSuite ? [.clean: 200, .degraded: 100] : [.clean: 3, .degraded: 2]
    let recognizers: [(key: String, recognizer: any TextRecognizing)] = [
      ("line", VisionTextRecognizer()), ("wider", VisionTextRecognizer.wider),
      ("document", VisionDocumentRecognizer()),
    ]
    var report = [
      "# OCR accuracy, brought down from a camera's size", "", "| Case | Pages | CER | WER |", "|---|---|---|---|",
    ]
    let chosen = OCRAccuracyTests.chosenRecognizers
    for (key, recognizer) in recognizers where chosen?.contains(key) ?? true {
      for language in OCRCorpus.Language.allCases {
        for condition in OCRCorpus.Condition.allCases {
          let pages = OCRCorpus.pages(
            language, condition, count: counts[condition] ?? 0, seed: 2026, camera: Self.cameraSize)
          #expect(pages.allSatisfy { max($0.image.width, $0.image.height) <= 2_200 })
          var score = RecognitionScore()
          for page in pages {
            let lines = try await recognizer.recognizeText(in: page.image)
            score = score + RecognitionScore(recognised: lines.map(\.text).joined(separator: "\n"), truth: page.truth)
          }
          let label = "\(key) \(language.rawValue) \(condition.rawValue)"
          report.append(
            "| \(label) | \(pages.count) | "
              + String(format: "%.2f%% | %.2f%% |", score.characterErrorRate * 100, score.wordErrorRate * 100))
          let gate = try #require(OCRAccuracyTests.gates[condition])
          #expect(score.characterErrorRate <= gate.cer, "\(label): CER \(score.characterErrorRate) above \(gate.cer)")
          guard let wer = gate.wer else { continue }
          let check = {
            #expect(score.wordErrorRate <= wer, "\(label): WER \(score.wordErrorRate) above \(wer)")
          }
          // The known issue of `OCRAccuracyTests`, which on a subset this small may or may not show.
          if language == .french, OCRAccuracyTests.readsFrenchWorse, !OCRAccuracyTests.isFullSuite {
            withKnownIssue("iOS 27 reads French ligatures and accents worse (#308)", isIntermittent: true) { check() }
          } else {
            check()
          }
        }
      }
    }
    let text = report.joined(separator: "\n") + "\n"
    print(text)
    SuiteReport.write(text, named: "ocr-accuracy-camera-size.md")
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
    #expect(RecognitionScore.wordDifferences(recognised: "Facture n° 42", truth: "Facture n° 42").isEmpty)
    #expect(
      RecognitionScore.wordDifferences(recognised: "Facture a ete", truth: "Facture à été")
        == [#""à" read as "a""#, #""été" read as "ete""#])
    #expect(
      RecognitionScore.wordDifferences(recognised: "la facture", truth: "la facture émise") == [#""émise" missed"#])
    #expect(RecognitionScore.wordDifferences(recognised: "la x facture", truth: "la facture") == [#""x" added"#])
  }
}
