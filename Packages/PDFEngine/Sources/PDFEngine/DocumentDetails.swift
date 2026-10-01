import CoreGraphics
import Foundation

/// What a PDF says about itself, for the document info sheet (FR-LIB-008).
///
/// Read with Core Graphics, which reads the Info dictionary key by key: PDFKit's own attribute
/// dictionary raises an exception the app can't catch on a damaged key (see `readableAttributes`).
public struct DocumentDetails: Equatable, Sendable {
  /// The file's size in bytes.
  public var fileSize: Int?
  /// The number of pages; zero while the document is locked.
  public var pageCount: Int
  /// The PDF version, such as `1.7`.
  public var version: String
  /// The document's author, as its metadata gives it.
  public var author: String?
  /// The app the document was made in.
  public var creator: String?
  /// The software that wrote the PDF.
  public var producer: String?
  /// When the document was created, as its metadata gives it.
  public var created: Date?
  /// When the document was last changed, as its metadata gives it.
  public var modified: Date?
  /// Whether a password protects the document.
  public var isEncrypted: Bool
  /// Whether its author allows printing.
  public var allowsPrinting: Bool
  /// Whether its author allows copying text.
  public var allowsCopying: Bool

  /// The details of the PDF at `url`, or `nil` when it isn't a readable PDF.
  public static func of(fileAt url: URL) -> DocumentDetails? {
    guard let pdf = CGPDFDocument(url as CFURL) else { return nil }
    return withExtendedLifetime(pdf) {
      var major: Int32 = 0
      var minor: Int32 = 0
      pdf.getVersion(majorVersion: &major, minorVersion: &minor)
      let info = pdf.info
      return DocumentDetails(
        fileSize: try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        pageCount: pdf.isUnlocked ? pdf.numberOfPages : 0,
        version: "\(major).\(minor)",
        author: text(info, "Author"), creator: text(info, "Creator"), producer: text(info, "Producer"),
        created: date(info, "CreationDate"), modified: date(info, "ModDate"),
        isEncrypted: pdf.isEncrypted, allowsPrinting: pdf.allowsPrinting, allowsCopying: pdf.allowsCopying)
    }
  }

  private static func text(_ info: CGPDFDictionaryRef?, _ key: String) -> String? {
    var value: CGPDFStringRef?
    guard let info, CGPDFDictionaryGetString(info, key, &value), let value,
      let string = CGPDFStringCopyTextString(value) as String?
    else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func date(_ info: CGPDFDictionaryRef?, _ key: String) -> Date? {
    var value: CGPDFStringRef?
    guard let info, CGPDFDictionaryGetString(info, key, &value), let value else { return nil }
    return CGPDFStringCopyDate(value) as Date?
  }
}
