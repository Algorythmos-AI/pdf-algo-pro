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
    let interval = Signposts.begin("Scan.Searchable")
    defer { interval.end() }
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
  /// Pages already recognised, for example before the app was stopped, are passed in `done` and
  /// not recognised again; each newly recognised page is handed to `onPage` as soon as it is ready,
  /// so it can be kept (P8).
  ///
  /// - Throws: `PDFEngineError.unreadable`, `.passwordRequired`, `.restricted` (encrypted), `.saveFailed`, `CancellationError`, or
  ///   the recogniser's error.
  public func addTextLayer(
    toPDFAt url: URL, resuming done: [Int: [RecognizedLine]] = [:],
    onPage: @Sendable (Int, [RecognizedLine]) async -> Void = { _, _ in },
    progress: @Sendable (Double) -> Void = { _ in }
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
      if let lines = done[index] {
        recognized.append(lines)
      } else {
        guard let page = source.page(at: index + 1) else { throw PDFEngineError.renderFailed }
        let image = try PageRenderer.render(page, maximumPixelSize: renderPixelSize)
        let lines = try await recognizer.recognizeText(in: image)
        recognized.append(lines)
        await onPage(index, lines)
      }
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

  /// Puts the rebuilt pages into the original document, in place of its own, and writes it.
  ///
  /// `drawPDFPage` draws a page's content only. The original document keeps everything else: its
  /// metadata and outline, and each page's annotations and rotation move to the page that replaces
  /// it, as a text edit swaps a page. Links and outline entries are pointed at the new pages.
  ///
  /// The annotations stay in the document they were read from. Moved into another document instead,
  /// PDFKit on iOS 27 wrote none of them: a note and a link were missing from the searchable copy,
  /// while a text edit's swap kept them (#307). The outline and links PDFKit leaves out are put back.
  private static func carryOver(from originalData: Data, onto rebuiltData: Data) throws -> Data {
    guard let original = PDFDocument(data: originalData), let rebuilt = PDFDocument(data: rebuiltData),
      original.pageCount == rebuilt.pageCount
    else { throw PDFEngineError.saveFailed }
    let replaced = (0..<original.pageCount).compactMap { original.page(at: $0) }
    let replacements = (0..<rebuilt.pageCount).compactMap { rebuilt.page(at: $0) }
    guard replaced.count == original.pageCount, replacements.count == replaced.count else {
      throw PDFEngineError.saveFailed
    }
    // Where each link and outline entry goes, read while the original pages are in place: a
    // destination whose page has left the document no longer says which page it was.
    var pointers: [(page: Int, destination: PDFDestination, point: (PDFDestination) -> Void)] = []
    func note(_ destination: PDFDestination?, _ point: @escaping (PDFDestination) -> Void) -> Bool {
      guard let destination, let page = destination.page else { return false }
      let index = original.index(for: page)
      guard index != NSNotFound else { return false }
      pointers.append((index, destination, point))
      return true
    }
    for page in replaced {
      for annotation in page.annotations where !note(annotation.destination, { annotation.destination = $0 }) {
        _ = note((annotation.action as? PDFActionGoTo)?.destination) {
          annotation.action = PDFActionGoTo(destination: $0)
        }
      }
    }
    func walk(_ item: PDFOutline, depth: Int) {
      guard depth < PDFDocumentController.outlineDepthLimit else { return }
      if !note(item.destination, { item.destination = $0 }) {
        _ = note((item.action as? PDFActionGoTo)?.destination) { item.action = PDFActionGoTo(destination: $0) }
      }
      for index in 0..<item.numberOfChildren {
        if let child = item.child(at: index) { walk(child, depth: depth + 1) }
      }
    }
    if let root = original.outlineRoot { walk(root, depth: 0) }
    for (index, (old, new)) in zip(replaced, replacements).enumerated() {
      new.rotation = old.rotation
      // The new page goes into the document before anything is moved onto it: a form field moved to
      // a page that is not in a document yet loses its name when the page is inserted.
      original.removePage(at: index)
      original.insert(new, at: index)
      let fields = old.annotations.map { (widget: $0, name: $0.fieldName) }
      // A pop-up travels with the note it belongs to; moved on its own as well, it would be there twice.
      for annotation in old.annotations where annotation.type != "Popup" {
        old.removeAnnotation(annotation)
        new.addAnnotation(annotation)
      }
      for field in fields where field.widget.fieldName != field.name { field.widget.fieldName = field.name }
    }
    for pointer in pointers {
      let destination = PDFDestination(page: replacements[pointer.page], at: pointer.destination.point)
      destination.zoom = pointer.destination.zoom
      pointer.point(destination)
    }
    // A damaged metadata key would end the app as PDFKit writes it; its readable entries are kept.
    original.repairAttributesIfNeeded()
    // `rebuilt` holds the new pages' content, so it lives until the document is written.
    let data = withExtendedLifetime(rebuilt) { PDFDocumentController.dataRepresentation(of: original) }
    guard let data else { throw PDFEngineError.saveFailed }
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
