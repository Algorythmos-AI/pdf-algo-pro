import Core
import Foundation

/// The document type Extract finds, in the reader's language (#304).
///
/// The on-device model names the type in English whatever language the document is in: the
/// extraction prompt gives English examples. A French invoice came back as "invoice". The types the
/// model names are a short list, so each is given its name in the app's language here; any other
/// value is shown as it came.
///
/// Only what is shown, copied and shared changes. The model's value stays as found, so a value
/// found in the document keeps its citation to the words that are there.
enum DocumentTypeName {
  /// The extracted field that holds the document type.
  static let key = "documentType"

  private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

  /// The kinds of document Extract is for, by the English name the model gives, in lower case.
  private static let names: [String: LocalizedStringResource] = [
    "invoice": LocalizedStringResource("Invoice", bundle: bundle, comment: "A kind of document Extract found"),
    "tax invoice": LocalizedStringResource("Tax invoice", bundle: bundle, comment: "A kind of document Extract found"),
    "bill": LocalizedStringResource("Bill", bundle: bundle, comment: "A kind of document Extract found"),
    "receipt": LocalizedStringResource("Receipt", bundle: bundle, comment: "A kind of document Extract found"),
    "quote": LocalizedStringResource("Quote", bundle: bundle, comment: "A kind of document Extract found"),
    "quotation": LocalizedStringResource("Quote", bundle: bundle, comment: "A kind of document Extract found"),
    "estimate": LocalizedStringResource("Estimate", bundle: bundle, comment: "A kind of document Extract found"),
    "statement": LocalizedStringResource("Statement", bundle: bundle, comment: "A kind of document Extract found"),
    "bank statement": LocalizedStringResource(
      "Bank statement", bundle: bundle, comment: "A kind of document Extract found"),
    "credit note": LocalizedStringResource("Credit note", bundle: bundle, comment: "A kind of document Extract found"),
    "purchase order": LocalizedStringResource(
      "Purchase order", bundle: bundle, comment: "A kind of document Extract found"),
    "delivery note": LocalizedStringResource(
      "Delivery note", bundle: bundle, comment: "A kind of document Extract found"),
    // The same words as the Contract task, so one translation serves both.
    "contract": LocalizedStringResource("Contract", bundle: bundle),
  ]

  /// The document type to show for a value the model gave.
  ///
  /// - Parameters:
  ///   - value: The type as the model gave it.
  ///   - locale: The language to show it in.
  /// - Returns: The type's name in that language; the value as it came when the model gave a type
  ///   not on the list, or when the name differs from it only in capitals, so English keeps the
  ///   model's own words.
  static func presented(_ value: String, locale: Locale = .current) -> String {
    presentedName(value, locale: locale)
  }

  /// An extraction as the reader sees it, copies and shares it.
  ///
  /// The document type is put in the reader's language only while it is the model's own words: a
  /// value found in the document is the document's word, with its citation, and a value the person
  /// changed is theirs.
  ///
  /// - Parameters:
  ///   - extraction: The fields as the model found them, with the person's changes.
  ///   - edited: The keys of the fields the person changed.
  ///   - locale: The language to show the type in.
  /// - Returns: The extraction to show, copy and share; every other field as it came.
  static func presented(_ extraction: Extraction, edited: Set<String>, locale: Locale = .current) -> Extraction {
    var result = extraction
    for index in result.fields.indices {
      let field = result.fields[index]
      guard field.key == key, !edited.contains(key), !field.isVerified else { continue }
      result.fields[index].value = presentedName(field.value, locale: locale)
    }
    return result
  }

  private static func presentedName(_ value: String, locale: Locale) -> String {
    let english = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard var resource = names[english] else { return value }
    resource.locale = locale
    let name = String(localized: resource)
    return name.lowercased() == english ? value : name
  }
}
