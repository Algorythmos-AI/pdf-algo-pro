import Core
import CoreGraphics
import Foundation
import Vision

/// On-device recognition that reads a page as a document: paragraph by paragraph, in the order a
/// person reads them (ADR-0008).
///
/// `VisionTextRecognizer` gives lines and orders them top to bottom, which interleaves the columns
/// of a page set in two columns: the first line of the left column, then the first of the right.
/// Vision's document recognition groups lines into paragraphs and orders those, so each column is
/// read to its end before the next (measured on a two-column page, 2026-10-08). The lines of a
/// table come row by row.
///
/// Nothing leaves the device. When document recognition fails or finds no document, the line
/// recogniser's answer is used, so a page is never left without text because of this.
public struct VisionDocumentRecognizer: TextRecognizing {
  /// What recognises the page when document recognition cannot.
  public let fallback: VisionTextRecognizer

  /// Creates a recogniser.
  ///
  /// - Parameter fallback: The line recogniser used when document recognition gives nothing.
  public init(fallback: VisionTextRecognizer = .wider) {
    self.fallback = fallback
  }

  /// Recognises the lines of text in an image, in reading order.
  ///
  /// - Throws: Vision's error when the fallback fails too.
  public func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
    if let lines = try? await documentLines(in: image), !lines.isEmpty { return lines }
    return try await fallback.recognizeText(in: image)
  }

  /// The page's lines as document recognition orders them, or none when it finds no document.
  func documentLines(in image: CGImage) async throws -> [RecognizedLine] {
    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.automaticallyDetectLanguage = fallback.detectsLanguage
    request.textRecognitionOptions.useLanguageCorrection = true
    let known = Set(request.supportedRecognitionLanguages.map(\.maximalIdentifier))
    let usable = fallback.languages.filter { known.contains($0.maximalIdentifier) }
    if !usable.isEmpty { request.textRecognitionOptions.recognitionLanguages = usable }
    let observations = try await request.perform(on: image)
    var lines: [RecognizedLine] = []
    var seen: Set<CGRect> = []
    func add(_ observation: RecognizedTextObservation) {
      guard let line = VisionTextRecognizer.line(from: observation, findsWords: fallback.findsWords),
        !line.text.trimmingCharacters(in: .whitespaces).isEmpty, seen.insert(line.bounds).inserted
      else { return }
      lines.append(line)
    }
    for observation in observations {
      let document = observation.document
      for paragraph in document.paragraphs { paragraph.lines.forEach(add) }
      // Anything recognised that is in no paragraph still goes in, after them: no text is dropped.
      document.text.lines.forEach(add)
    }
    return lines
  }
}
