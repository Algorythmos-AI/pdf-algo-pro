import Foundation

/// The document type Extract finds, in the reader's language (#304).
///
/// The on-device model names the type in English whatever language the document is in: the
/// extraction prompt gives English examples. A French invoice came back as "invoice". The types the
/// model names are a short list, so each is given its name in the app's language here; any other
/// value, such as one the model took from the document itself, is shown as it came.
enum DocumentTypeName {
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
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard var resource = names[key] else { return value }
    resource.locale = locale
    let name = String(localized: resource)
    return name.lowercased() == key ? value : name
  }
}
