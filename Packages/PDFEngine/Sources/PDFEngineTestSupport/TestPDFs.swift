import CoreText
import Foundation
import PDFEngine
import PDFKit

/// Synthetic PDFs for tests: generated in code, never real documents (AGENTS.md rule 6).
public enum TestPDFs {
  /// Why a test PDF could not be made.
  public struct Failure: Error {}

  /// A one-page form with an empty text field "name" and an unticked check box "agree" whose on
  /// state is "Yes".
  public static func makeForm() throws -> Data {
    guard let document = PDFDocument(data: try SyntheticPDF.make(pages: ["Application form"])),
      let page = document.page(at: 0)
    else { throw Failure() }
    let name = PDFAnnotation(
      bounds: CGRect(x: 72, y: 600, width: 240, height: 24), forType: .widget, withProperties: nil)
    name.widgetFieldType = .text
    name.fieldName = "name"
    page.addAnnotation(name)
    let agree = PDFAnnotation(
      bounds: CGRect(x: 72, y: 560, width: 18, height: 18), forType: .widget, withProperties: nil)
    agree.widgetFieldType = .button
    agree.widgetControlType = .checkBoxControl
    agree.fieldName = "agree"
    agree.buttonWidgetStateString = "Yes"
    agree.buttonWidgetState = .offState
    page.addAnnotation(agree)
    guard let data = document.dataRepresentation() else { throw Failure() }
    return data
  }

  /// A one-page encrypted PDF with the text "Protected page".
  ///
  /// - Parameters:
  ///   - userPassword: The password that opens it, or `nil` to open without one.
  ///   - ownerPassword: The password that lifts the restrictions.
  ///   - permissions: What someone with the user password may do.
  /// - Returns: The PDF's data.
  /// - Throws: `Failure` if Core Graphics cannot create the PDF.
  public static func makeProtected(
    userPassword: String?, ownerPassword: String, permissions: CGPDFAccessPermissions
  ) throws -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    var info: [CFString: Any] = [
      kCGPDFContextOwnerPassword: ownerPassword, kCGPDFContextAccessPermissions: permissions.rawValue,
    ]
    if let userPassword { info[kCGPDFContextUserPassword] = userPassword }
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
    else { throw Failure() }
    context.beginPDFPage(nil)
    let text = NSAttributedString(
      string: "Protected page", attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 18, nil)])
    context.textPosition = CGPoint(x: 72, y: 700)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    context.endPDFPage()
    context.closePDF()
    return data as Data
  }

  /// The `/V` entry of a field on the first page, read with Core Graphics rather than PDFKit, so a
  /// test sees what another PDF reader would.
  public static func storedValue(of field: String, in url: URL) -> String? {
    // The dictionaries belong to the document, so it must outlive every read.
    guard let pdf = CGPDFDocument(url as CFURL) else { return nil }
    return withExtendedLifetime(pdf) {
      var annotations: CGPDFArrayRef?
      guard let page = pdf.page(at: 1)?.dictionary, CGPDFDictionaryGetArray(page, "Annots", &annotations),
        let annotations
      else { return nil }
      for index in 0..<CGPDFArrayGetCount(annotations) {
        var annotation: CGPDFDictionaryRef?
        var title: CGPDFStringRef?
        guard CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
          CGPDFDictionaryGetString(annotation, "T", &title), let title,
          CGPDFStringCopyTextString(title) as String? == field
        else { continue }
        var text: CGPDFStringRef?
        if CGPDFDictionaryGetString(annotation, "V", &text), let text {
          return CGPDFStringCopyTextString(text) as String?
        }
        var name: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(annotation, "V", &name), let name { return String(cString: name) }
        return nil
      }
      return nil
    }
  }
}
