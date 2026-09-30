import CoreGraphics
import Foundation

/// Whether a PDF carries digital signatures, which saving through PDFKit would break (plan item H9).
///
/// PDFKit writes the whole file again, so the byte ranges a signature covers change and every reader
/// then shows the signature as broken. A signed document is therefore saved as a copy, and the
/// original keeps its valid signature.
public enum DigitalSignatureStatus: Equatable, Sendable {
  /// No signed signature field.
  case none
  /// At least one signature field holds a signature (`/FT /Sig` with a `/V` dictionary).
  case signed
  /// Certified by its author (`/Perms /DocMDP` in the catalog): any change breaks the certification.
  case certified

  /// Whether saving the document in place would break a signature.
  public var isSigned: Bool { self != .none }

  /// The status of the PDF at `url`; `.none` when the file can't be read or is locked.
  public static func of(fileAt url: URL) -> DigitalSignatureStatus {
    guard let pdf = CGPDFDocument(url as CFURL) else { return .none }
    return of(pdf)
  }

  /// The status of PDF data; `.none` when it can't be read or is locked.
  public static func of(data: Data) -> DigitalSignatureStatus {
    guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { return .none }
    return of(pdf)
  }

  /// Fields are walked at most this deep and this many, so a malformed or circular form can't hang
  /// the app (golden corpus: deep nesting, circular trees).
  static let maximumDepth = 32
  static let maximumFields = 10_000

  private static func of(_ pdf: CGPDFDocument) -> DigitalSignatureStatus {
    withExtendedLifetime(pdf) {
      guard !pdf.isEncrypted || pdf.isUnlocked, let catalog = pdf.catalog else { return .none }
      var permissions: CGPDFDictionaryRef?
      var docMDP: CGPDFDictionaryRef?
      if CGPDFDictionaryGetDictionary(catalog, "Perms", &permissions), let permissions,
        CGPDFDictionaryGetDictionary(permissions, "DocMDP", &docMDP), docMDP != nil
      {
        return .certified
      }
      var form: CGPDFDictionaryRef?
      var fields: CGPDFArrayRef?
      guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form,
        CGPDFDictionaryGetArray(form, "Fields", &fields), let fields
      else { return .none }
      var visited = 0
      return containsSignedField(fields, depth: 0, visited: &visited) ? .signed : .none
    }
  }

  private static func containsSignedField(_ fields: CGPDFArrayRef, depth: Int, visited: inout Int) -> Bool {
    guard depth < maximumDepth else { return false }
    for index in 0..<CGPDFArrayGetCount(fields) {
      visited += 1
      guard visited <= maximumFields else { return false }
      var field: CGPDFDictionaryRef?
      guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
      var type: UnsafePointer<CChar>?
      var value: CGPDFDictionaryRef?
      if CGPDFDictionaryGetName(field, "FT", &type), let type, String(cString: type) == "Sig",
        CGPDFDictionaryGetDictionary(field, "V", &value), value != nil
      {
        return true
      }
      var kids: CGPDFArrayRef?
      if CGPDFDictionaryGetArray(field, "Kids", &kids), let kids,
        containsSignedField(kids, depth: depth + 1, visited: &visited)
      {
        return true
      }
    }
    return false
  }
}
