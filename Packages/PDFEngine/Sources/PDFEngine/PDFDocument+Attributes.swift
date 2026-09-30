import CoreGraphics
import Foundation
import PDFKit

extension PDFDocument {
  /// The Info dictionary (title, author, dates and so on), read without ending the app.
  ///
  /// PDFKit's `documentAttributes` raises an Objective-C exception, which Swift cannot catch, when a
  /// key in the Info dictionary is not valid UTF-8, as in a damaged file. Writing the document reads
  /// it too. For such a file, the entries with readable keys are rebuilt here; any other file gets
  /// PDFKit's own answer.
  var readableAttributes: [AnyHashable: Any] {
    guard let info = documentRef?.info, Self.hasUnreadableKey(info) else { return documentAttributes ?? [:] }
    return Self.rebuiltAttributes(info)
  }

  /// Replaces an Info dictionary that PDFKit cannot read with its readable entries.
  ///
  /// The document can then be written. Any other document is left unchanged.
  func repairAttributesIfNeeded() {
    guard let info = documentRef?.info, Self.hasUnreadableKey(info) else { return }
    documentAttributes = Self.rebuiltAttributes(info)
  }

  private static func hasUnreadableKey(_ info: CGPDFDictionaryRef) -> Bool {
    var unreadable = false
    CGPDFDictionaryApplyBlock(
      info,
      { key, _, _ in
        unreadable = String(validatingCString: key) == nil
        return !unreadable
      }, nil)
    return unreadable
  }

  /// The Info entries with readable keys, in the types `PDFDocumentAttribute` documents.
  ///
  /// Text becomes strings, the two dates become dates, and keywords a one-item list. Entries that are
  /// not text, and keys that are not UTF-8, are dropped.
  private static func rebuiltAttributes(_ info: CGPDFDictionaryRef) -> [AnyHashable: Any] {
    var attributes: [AnyHashable: Any] = [:]
    CGPDFDictionaryApplyBlock(
      info,
      { key, object, _ in
        var string: CGPDFStringRef?
        guard let name = String(validatingCString: key), CGPDFObjectGetValue(object, .string, &string),
          let string
        else { return true }
        switch PDFDocumentAttribute(rawValue: name) {
        case .creationDateAttribute, .modificationDateAttribute:
          if let date = CGPDFStringCopyDate(string) { attributes[name] = date as Date }
        case .keywordsAttribute:
          if let text = CGPDFStringCopyTextString(string) { attributes[name] = [text as String] }
        default:
          if let text = CGPDFStringCopyTextString(string) { attributes[name] = text as String }
        }
        return true
      }, nil)
    return attributes
  }
}
