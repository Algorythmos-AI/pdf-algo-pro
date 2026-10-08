import Core
import CoreGraphics
import Foundation
import Vision

/// On-device text recognition with Vision (ADR-0008).
///
/// Nothing leaves the device.
public struct VisionTextRecognizer: TextRecognizing {
  /// The languages recognised, English and French first (FR-SCAN-002).
  public let languages: [Locale.Language]
  /// Whether Vision works out the language of each piece of text itself, among `languages`.
  public let detectsLanguage: Bool
  /// Whether each line comes with its words and where they are.
  public let findsWords: Bool

  /// English and French: the two languages the app has always recognised.
  public static let firstLanguages = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "fr-FR")]

  /// The languages recognised when the wider set is on, in the order Vision should prefer them.
  ///
  /// These are the languages written in Latin and Cyrillic letters that Vision recognises
  /// (measured on macOS 26 and iOS 26 with `supportedRecognitionLanguages`, 2026-10-08). Chinese,
  /// Japanese, Korean, Thai and Arabic are recognised by Vision too and stay off here until saving
  /// such text has been checked by the independent readers (issue 96).
  public static let widerLanguages =
    firstLanguages
    + [
      "de-DE", "es-ES", "it-IT", "pt-BR", "nl-NL", "sv-SE", "da-DK", "nb-NO", "pl-PL", "cs-CZ", "ro-RO", "tr-TR",
      "id-ID", "ms-MY", "vi-VT", "ru-RU", "uk-UA",
    ].map { Locale.Language(identifier: $0) }

  /// Creates a recogniser for the given languages.
  ///
  /// - Parameters:
  ///   - languages: The languages to recognise, most likely first.
  ///   - detectsLanguage: Whether Vision picks the language of each piece of text itself.
  ///   - findsWords: Whether each line carries its words and their boxes.
  public init(
    languages: [Locale.Language] = VisionTextRecognizer.firstLanguages, detectsLanguage: Bool = false,
    findsWords: Bool = false
  ) {
    self.languages = languages
    self.detectsLanguage = detectsLanguage
    self.findsWords = findsWords
  }

  /// A recogniser for the wider set of languages, found automatically, with words.
  public static var wider: VisionTextRecognizer {
    VisionTextRecognizer(languages: widerLanguages, detectsLanguage: true, findsWords: true)
  }

  /// Recognises lines of text in an image, top to bottom.
  ///
  /// - Throws: Vision's error when recognition fails.
  public func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    // Only languages this device's Vision knows: asking for another makes the request fail.
    let known = Set(request.supportedRecognitionLanguages.map(\.maximalIdentifier))
    let usable = languages.filter { known.contains($0.maximalIdentifier) }
    request.recognitionLanguages = usable.isEmpty ? Self.firstLanguages : usable
    request.automaticallyDetectsLanguage = detectsLanguage
    let observations = try await request.perform(on: image)
    return Self.lines(from: observations.compactMap { Self.line(from: $0, findsWords: findsWords) })
  }

  /// One recognised line from Vision's observation, with its words when asked for.
  static func line(from observation: RecognizedTextObservation, findsWords: Bool) -> RecognizedLine? {
    guard let candidate = observation.topCandidates(1).first else { return nil }
    let unit = CGSize(width: 1, height: 1)
    let text = candidate.string
    var words: [RecognizedWord]?
    if findsWords {
      // Every word must have a box, or the line is kept as one piece: a line with some words
      // placed and some not would lose the others from the text layer.
      let found = wordRanges(in: text).map { range in
        candidate.boundingBox(for: range).map {
          RecognizedWord(text: String(text[range]), bounds: $0.boundingBox.toImageCoordinates(unit))
        }
      }
      if !found.isEmpty, found.allSatisfy({ $0 != nil }) { words = found.compactMap { $0 } }
    }
    return RecognizedLine(
      text: text, bounds: observation.boundingBox.toImageCoordinates(unit), confidence: Double(candidate.confidence),
      words: words)
  }

  /// The runs of a line between its spaces: words, each with the punctuation attached to it.
  static func wordRanges(in text: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var start: String.Index?
    for index in text.indices {
      if text[index].isWhitespace {
        if let begun = start { ranges.append(begun..<index) }
        start = nil
      } else if start == nil {
        start = index
      }
    }
    if let begun = start { ranges.append(begun..<text.endIndex) }
    return ranges
  }

  /// Orders lines as people read them: top to bottom, then left to right on the same line.
  static func lines(from lines: [RecognizedLine]) -> [RecognizedLine] {
    lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.sorted { lhs, rhs in
      if abs(lhs.bounds.midY - rhs.bounds.midY) > min(lhs.bounds.height, rhs.bounds.height) / 2 {
        return lhs.bounds.midY > rhs.bounds.midY
      }
      return lhs.bounds.minX < rhs.bounds.minX
    }
  }
}
