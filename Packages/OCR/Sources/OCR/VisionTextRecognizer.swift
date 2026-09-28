import Core
import CoreGraphics
import Foundation
import Vision

/// On-device text recognition with Vision (ADR-0008). Nothing leaves the device.
public struct VisionTextRecognizer: TextRecognizing {
  /// The languages recognised, English and French first (FR-SCAN-002).
  public let languages: [Locale.Language]

  /// Creates a recogniser for the given languages.
  public init(languages: [Locale.Language] = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "fr-FR")]) {
    self.languages = languages
  }

  /// Recognises lines of text in an image, top to bottom.
  ///
  /// - Throws: Vision's error when recognition fails.
  public func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages
    let observations = try await request.perform(on: image)
    return Self.lines(from: observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return RecognizedLine(
        text: candidate.string, bounds: observation.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1)), confidence: Double(candidate.confidence))
    })
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
