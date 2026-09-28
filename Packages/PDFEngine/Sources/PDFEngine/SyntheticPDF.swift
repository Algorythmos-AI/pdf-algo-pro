import CoreGraphics
import Foundation

/// Synthetic PDFs: the bundled sample and the test corpus.
///
/// No real document ever enters the repository or the app bundle (AGENTS.md rule 6); these are generated from text at
/// run time.
public enum SyntheticPDF {
  /// A PDF whose pages carry the given text as a real text layer.
  ///
  /// - Throws: `PDFEngineError.saveFailed` if Core Graphics cannot create the PDF.
  public static func make(pages: [String], title: String = "Synthetic document") throws -> Data {
    try PDFWriter.makePDF(
      mediaBoxes: Array(repeating: PDFWriter.letter, count: pages.count),
      auxiliaryInfo: [kCGPDFContextTitle: title, kCGPDFContextCreator: "PDF Algo Pro"]
    ) { context, index, box in
      PDFWriter.drawText(pages[index], in: box.insetBy(dx: 56, dy: 56), fontSize: 14, context: context)
    }
  }

  /// A password-protected PDF; the same password opens it and grants every permission.
  ///
  /// - Throws: `PDFEngineError.saveFailed` if Core Graphics cannot create the PDF.
  public static func makeEncrypted(pages: [String], password: String) throws -> Data {
    try PDFWriter.makePDF(
      mediaBoxes: Array(repeating: PDFWriter.letter, count: pages.count),
      auxiliaryInfo: [kCGPDFContextUserPassword: password, kCGPDFContextOwnerPassword: password]
    ) { context, index, box in
      PDFWriter.drawText(pages[index], in: box.insetBy(dx: 56, dy: 56), fontSize: 14, context: context)
    }
  }

  /// An image of text, as a camera or scanner would produce: black text on white, no text layer.
  public static func makeTextImage(_ text: String, size: CGSize = CGSize(width: 1224, height: 1584)) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    PDFWriter.drawText(
      text, in: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.height * 0.08),
      fontSize: size.width / 30, context: context)
    return context.makeImage()
  }

  /// A PDF made only of page images, like an unrecognised scan (FR-SCAN-003).
  ///
  /// - Throws: `PDFEngineError.saveFailed` if Core Graphics cannot create the PDF.
  public static func makeImageOnly(pages: [String]) throws -> Data {
    let images = pages.compactMap { makeTextImage($0) }
    return try PDFWriter.makePDF(mediaBoxes: Array(repeating: PDFWriter.letter, count: images.count)) {
      context, index, box in
      context.draw(images[index], in: box)
    }
  }

  /// The "Try a sample" document shown in an empty library: a short guide and an invoice, so every
  /// MVP feature (reading, search, summary, questions, extraction) can be tried without a real file.
  ///
  /// - Throws: `PDFEngineError.saveFailed` if Core Graphics cannot create the PDF.
  public static func makeSample() throws -> Data {
    try make(pages: SampleContent.pages, title: SampleContent.title)
  }
}

/// The text of the sample document.
///
/// It is written for this app and contains no real person, company or account.
public enum SampleContent {
  /// The sample's title.
  public static let title = "Welcome to PDF Algo Pro"

  /// The sample's pages.
  public static let pages = [
    """
    Welcome to PDF Algo Pro

    This sample shows what the app does with your documents. Everything you see runs on this device: \
    reading, search, text recognition and document intelligence need no account and no network.

    Try these:
    - Search the library for the word "invoice" to find page 2 of this document.
    - Select a sentence and highlight it.
    - Ask "What is the total due?" and tap the page citation in the answer.
    """,
    """
    Invoice

    Invoice number: INV-2026-0042
    Invoice date: 14 September 2026
    Due date: 14 October 2026
    Seller: Example Stationery Pty Ltd
    Buyer: Sample Customer

    Item: Recycled paper, 10 reams
    Total due: 120.00

    Payment terms: 30 days. This invoice is synthetic sample content.
    """,
    """
    Privacy

    Your documents stay on your device. Answers are generated on device and cite the pages they come \
    from; when an answer is not in the document, the app says so instead of guessing.
    """,
  ]
}
