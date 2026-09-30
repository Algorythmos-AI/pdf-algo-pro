import Foundation
import PDFKit

/// Compression presets (FR-ORG-004).
///
/// PDFKit re-encodes the images and, for email, scales them for screens; text, vector drawing and
/// annotations stay as they are, so the document stays searchable.
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
    let data = try Data(contentsOf: staging, options: .mappedIfSafe)
    return data.count < originalSize ? data : nil
  }
}
