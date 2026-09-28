import Core
import CoreGraphics
import Foundation

/// A searchable PDF and the text that recognition found on each page.
public struct RecognizedDocument: Sendable {
  /// The PDF, with an invisible text layer over each page.
  public let data: Data
  /// The recognised text of each page.
  public let pages: [PageText]
}

/// Turns scans into searchable PDFs, on device (FR-SCAN-002, FR-SCAN-003).
///
/// Recognition runs page by page, checks for cancellation between pages and reports progress from
/// 0 to 1, so long scans can be cancelled and resumed.
public actor SearchablePDFBuilder {
  private let recognizer: any TextRecognizing
  private let renderPixelSize: Int

  /// Creates a builder over a text recogniser.
  ///
  /// - Parameters:
  ///   - recognizer: The on-device text recogniser.
  ///   - renderPixelSize: The longest side, in pixels, of page images sent to recognition.
  public init(recognizer: any TextRecognizing, renderPixelSize: Int = 2200) {
    self.recognizer = recognizer
    self.renderPixelSize = renderPixelSize
  }

  /// Builds a PDF from scanned page images.
  ///
  /// - Throws: `CancellationError`, `PDFEngineError.saveFailed`, or the recogniser's error.
  public func makeSearchablePDF(
    from images: [CGImage], progress: @Sendable (Double) -> Void = { _ in }
  ) async throws
    -> RecognizedDocument
  {
    var recognized: [[RecognizedLine]] = []
    for (index, image) in images.enumerated() {
      try Task.checkCancellation()
      recognized.append(try await recognizer.recognizeText(in: image))
      progress(Double(index + 1) / Double(images.count))
    }
    let boxes = images.map { Self.pageBox(for: $0) }
    let data = try PDFWriter.makePDF(mediaBoxes: boxes) { context, index, box in
      context.draw(images[index], in: box)
      PDFWriter.drawInvisibleText(recognized[index], in: box, context: context)
    }
    return RecognizedDocument(data: data, pages: Self.pageTexts(recognized))
  }

  /// Adds a text layer to an existing image-only PDF, keeping each page as it looks.
  ///
  /// - Throws: `PDFEngineError.unreadable`, `.passwordRequired`, `CancellationError`, or the
  ///   recogniser's error.
  public func addTextLayer(
    toPDFAt url: URL, progress: @Sendable (Double) -> Void = { _ in }
  ) async throws
    -> RecognizedDocument
  {
    guard let source = CGPDFDocument(url as CFURL) else { throw PDFEngineError.unreadable }
    guard !source.isEncrypted || source.isUnlocked else { throw PDFEngineError.passwordRequired }
    let pageCount = source.numberOfPages
    var recognized: [[RecognizedLine]] = []
    for index in 0..<pageCount {
      try Task.checkCancellation()
      guard let page = source.page(at: index + 1) else { throw PDFEngineError.renderFailed }
      let image = try PageRenderer.render(page, maximumPixelSize: renderPixelSize)
      recognized.append(try await recognizer.recognizeText(in: image))
      progress(Double(index + 1) / Double(max(pageCount, 1)))
    }
    let boxes = (0..<pageCount).map { source.page(at: $0 + 1)?.getBoxRect(.cropBox) ?? PDFWriter.letter }
    let data = try PDFWriter.makePDF(mediaBoxes: boxes) { context, index, box in
      guard let page = source.page(at: index + 1) else { return }
      context.drawPDFPage(page)
      PDFWriter.drawInvisibleText(recognized[index], in: box, context: context)
    }
    return RecognizedDocument(data: data, pages: Self.pageTexts(recognized))
  }

  private static func pageTexts(_ recognized: [[RecognizedLine]]) -> [PageText] {
    recognized.enumerated().map { index, lines in
      PageText(pageIndex: index, text: lines.map(\.text).joined(separator: "\n"))
    }
  }

  /// A page the width of US Letter with the image's aspect ratio.
  private static func pageBox(for image: CGImage) -> CGRect {
    guard image.width > 0 else { return PDFWriter.letter }
    let height = PDFWriter.letter.width * CGFloat(image.height) / CGFloat(image.width)
    return CGRect(x: 0, y: 0, width: PDFWriter.letter.width, height: height)
  }
}
