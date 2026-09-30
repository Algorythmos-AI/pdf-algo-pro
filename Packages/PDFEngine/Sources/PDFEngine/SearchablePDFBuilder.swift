import Core
import CoreGraphics
import Foundation
import PDFKit

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

  /// Adds a text layer to an existing image-only PDF, keeping each page as it looks and everything
  /// added to it: annotations (notes, markup, links, form fields), page rotation, the outline and the
  /// document's metadata.
  ///
  /// - Throws: `PDFEngineError.unreadable`, `.passwordRequired`, `.restricted` (encrypted), `.saveFailed`, `CancellationError`, or
  ///   the recogniser's error.
  public func addTextLayer(
    toPDFAt url: URL, progress: @Sendable (Double) -> Void = { _ in }
  ) async throws
    -> RecognizedDocument
  {
    // One snapshot of the file serves both the page drawing and the carry-over.
    guard let original = try? Data(contentsOf: url, options: .mappedIfSafe),
      let provider = CGDataProvider(data: original as CFData), let source = CGPDFDocument(provider)
    else { throw PDFEngineError.unreadable }
    guard !source.isEncrypted || source.isUnlocked else { throw PDFEngineError.passwordRequired }
    // The searchable copy is drawn afresh and would carry no encryption or restrictions (defect D9).
    guard !source.isEncrypted else { throw PDFEngineError.restricted }
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
    return RecognizedDocument(
      data: try Self.carryOver(from: original, onto: data), pages: Self.pageTexts(recognized))
  }

  /// Moves what drawing a page leaves out from the original onto the rebuilt pages.
  ///
  /// `drawPDFPage` draws the page's content only, so annotations, rotation, the outline and the
  /// metadata are carried over with PDFKit, and links and outline entries are pointed at the new pages.
  private static func carryOver(from originalData: Data, onto rebuiltData: Data) throws -> Data {
    guard let original = PDFDocument(data: originalData), let rebuilt = PDFDocument(data: rebuiltData),
      original.pageCount == rebuilt.pageCount
    else { throw PDFEngineError.saveFailed }
    func retarget(_ destination: PDFDestination?) -> PDFDestination? {
      guard let destination, let page = destination.page else { return destination }
      guard let target = rebuilt.page(at: original.index(for: page)) else { return nil }
      let moved = PDFDestination(page: target, at: destination.point)
      moved.zoom = destination.zoom
      return moved
    }
    func retarget(_ action: PDFAction?) -> PDFAction? {
      guard let goTo = action as? PDFActionGoTo else { return action }
      return retarget(goTo.destination).map { PDFActionGoTo(destination: $0) }
    }
    func copy(_ item: PDFOutline) -> PDFOutline {
      let result = PDFOutline()
      result.label = item.label
      if let destination = retarget(item.destination) {
        result.destination = destination
      } else {
        result.action = retarget(item.action)
      }
      for index in 0..<item.numberOfChildren {
        if let child = item.child(at: index) { result.insertChild(copy(child), at: result.numberOfChildren) }
      }
      result.isOpen = item.isOpen
      return result
    }
    for index in 0..<original.pageCount {
      guard let source = original.page(at: index), let target = rebuilt.page(at: index) else { continue }
      target.rotation = source.rotation
      for annotation in source.annotations {
        source.removeAnnotation(annotation)
        if annotation.destination != nil { annotation.destination = retarget(annotation.destination) }
        if annotation.action != nil { annotation.action = retarget(annotation.action) }
        target.addAnnotation(annotation)
      }
    }
    if let root = original.outlineRoot { rebuilt.outlineRoot = copy(root) }
    rebuilt.documentAttributes = original.readableAttributes
    guard let data = rebuilt.dataRepresentation() else { throw PDFEngineError.saveFailed }
    return data
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
