import PDFKit

/// A form field's value as PDFKit reports it: text and choice fields use the string, buttons the state.
struct FormValue: Equatable {
  let text: String?
  let state: Int

  init(_ widget: PDFAnnotation) {
    text = widget.widgetStringValue
    state = widget.buttonWidgetState.rawValue
  }
}

extension PDFDocumentController {
  /// Whether a form field was filled in or changed since the document was opened or last saved.
  ///
  /// PDFKit edits form fields itself and says nothing when it does, so the values are compared with
  /// those recorded when the document was opened, unlocked or saved (defect D1).
  public var hasChangedFormValues: Bool {
    formValues.contains { FormValue($0.widget) != $0.value }
  }

  /// Whether there is anything to write: annotation changes or form entries.
  public var needsSaving: Bool { hasUnsavedChanges || hasChangedFormValues }

  /// Commits the text of a form field still being edited, so a save includes it.
  public func endEditing() {
    view?.endEditing()
  }

  /// Records the current value of every form field.
  ///
  /// Documents without form fields are not walked with PDFKit, so opening a long document costs
  /// little extra.
  func recordFormValues() {
    guard !document.isLocked, hasFormFields else {
      formValues = []
      return
    }
    formValues = (0..<document.pageCount)
      .flatMap { document.page(at: $0)?.annotations ?? [] }
      .filter { $0.type?.lowercased() == "widget" }
      .map { ($0, FormValue($0)) }
  }

  /// Whether any page has a widget annotation, read from the page dictionaries.
  ///
  /// Not from the AcroForm: PDFKit, like some other producers, writes widgets without one and still
  /// lets people fill them in.
  private var hasFormFields: Bool {
    guard let pdf = document.documentRef, pdf.numberOfPages > 0 else { return false }
    for number in 1...pdf.numberOfPages {
      var annotations: CGPDFArrayRef?
      guard let page = pdf.page(at: number)?.dictionary, CGPDFDictionaryGetArray(page, "Annots", &annotations),
        let annotations
      else { continue }
      for index in 0..<CGPDFArrayGetCount(annotations) {
        var annotation: CGPDFDictionaryRef?
        var subtype: UnsafePointer<CChar>?
        if CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
          CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype, String(cString: subtype) == "Widget"
        {
          return true
        }
      }
    }
    return false
  }
}
