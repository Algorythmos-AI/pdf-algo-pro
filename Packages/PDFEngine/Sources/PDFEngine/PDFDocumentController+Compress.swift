import Foundation
import PDFKit

/// Compression presets (FR-ORG-004).
///
/// The images are re-encoded as JPEG and, for email, scaled for screens; text, vector drawing and
/// annotations stay as they are, so the document stays searchable. PDFKit does the re-encoding on
/// iOS 26 and macOS; on iOS 27 it writes the images as they were, so `PDFImageRecompression` does it
/// (#308).
extension PDFDocumentController {
  /// How hard to compress.
  public enum CompressionPreset: Sendable, CaseIterable {
    /// The smallest file: images as JPEG at screen resolution, for attachments.
    case email
    /// Images as JPEG at their own resolution, for printing.
    case balanced

    var options: [PDFDocumentWriteOption: Any] {
      switch self {
      case .email: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
      case .balanced: [.saveImagesAsJPEGOption: true]
      }
    }

    /// The same, for the images PDFKit leaves as they were.
    ///
    /// Email keeps 1,600 pixels on an image's longest side, an A4 page at about 140 dots per inch, which
    /// keeps a scanned page's text easy to read.
    var recompression: PDFImageRecompression.Settings {
      switch self {
      case .email: PDFImageRecompression.Settings(maximumSide: 1_600, quality: 0.5)
      case .balanced: PDFImageRecompression.Settings(maximumSide: nil, quality: 0.75)
      }
    }
  }

  /// The document compressed with a preset, or `nil` when that wouldn't make it smaller than
  /// `originalSize` bytes: a file of text and line art is often already as small as it gets, and a
  /// compressed copy must never be bigger than what it replaces.
  ///
  /// An encrypted document stays encrypted, with the same protection as a save.
  ///
  /// - Throws: `PDFEngineError.restricted` when the author's restrictions forbid the change;
  ///   `PDFEngineError.saveFailed` when no file could be written.
  public func compressed(_ preset: CompressionPreset, comparedTo originalSize: Int) throws -> Data? {
    guard !isLocked else { throw PDFEngineError.restricted }
    endEditing()
    let options = try protectionOptions().merging(preset.options) { current, _ in current }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("compress-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staging) }
    guard document.write(to: staging, withOptions: options), let check = PDFDocument(url: staging),
      check.isLocked || check.pageCount == document.pageCount
    else { throw PDFEngineError.saveFailed }
    // A compressed copy keeps the bookmarks and links that PDFKit on iOS 27 leaves out (#307). First, so
    // the pictures are re-encoded in the mended file: that rewrite follows the update's cross-reference
    // chain and copies the outline and the links as they are.
    _ = try mendStructure(in: check, at: staging, options: options)
    var data = try Data(contentsOf: staging, options: .mappedIfSafe)
    // PDFKit on iOS 27 ignores the image options and writes each image as it was (#308), so the images it
    // left are re-encoded here. The result is used only if it opens with every page.
    if let recompressed = PDFImageRecompression.recompressed(data, settings: preset.recompression),
      let reread = PDFDocument(data: recompressed), reread.pageCount == document.pageCount
    {
      data = recompressed
    }
    return data.count < originalSize ? data : nil
  }
}
