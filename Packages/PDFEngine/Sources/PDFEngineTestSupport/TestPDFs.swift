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

  /// A one-page PDF with the text "Damaged metadata" whose Info dictionary has a key that is not
  /// valid UTF-8, as in a damaged file, beside a title, an author, keywords and a creation date.
  ///
  /// PDFKit raises an Objective-C exception, which ends the app, when it reads that dictionary.
  public static func makeWithUnreadableInfoKey() -> Data {
    let content = "BT /F1 18 Tf 72 700 Td (Damaged metadata) Tj ET"
    let objects: [[UInt8]] = [
      Array("<< /Type /Catalog /Pages 2 0 R >>".utf8),
      Array("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Array(
        ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
          + "/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>").utf8),
      Array("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream".utf8),
      Array("<< /Title (Damaged metadata) /Author (Test author) /Keywords (corpus metadata) ".utf8)
        + Array("/CreationDate (D:20260930120000Z) /Br".utf8) + [0xFF] + Array("ken (x) >>".utf8),
    ]
    var output = Array("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
      offsets.append(output.count)
      output += Array("\(index + 1) 0 obj\n".utf8) + body + Array("\nendobj\n".utf8)
    }
    let xref = output.count
    output += Array("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8)
    for offset in offsets { output += Array(String(format: "%010d 00000 n \n", offset).utf8) }
    output += Array(
      "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info 5 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8)
    return Data(output)
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
