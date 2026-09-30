import Foundation

/// Where a model runs (ADR-0009).
///
/// Each cloud tier is opt-in.
public enum IntelligenceTier: String, CaseIterable, Codable, Sendable {
  /// Apple's on-device foundation model: private, offline, the default.
  case onDevice
  /// Apple Private Cloud Compute (V1, opt-in).
  case privateCloudCompute
  /// Claude by Anthropic (V2, opt-in).
  case claude
}

/// Why document intelligence cannot run right now (FR-ONB-006).
public enum IntelligenceUnavailableReason: String, Codable, Sendable, CaseIterable {
  /// The device does not support Apple Intelligence.
  case deviceNotEligible
  /// Apple Intelligence is turned off in Settings.
  case appleIntelligenceNotEnabled
  /// The model is still downloading or otherwise not ready.
  case modelNotReady
  /// The user hid AI features in Settings (FR-AI-009).
  case hiddenBySettings
  /// The request does not fit the on-device model and no opt-in tier is available in this build.
  case requestTooLarge
}

/// Whether document intelligence can run, and on which tier.
public enum IntelligenceAvailability: Hashable, Sendable {
  /// Ready on the given tier.
  case available(IntelligenceTier)
  /// Not available, with the reason to show the user.
  case unavailable(IntelligenceUnavailableReason)

  /// Whether a tier is ready.
  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }
}

/// The text of one page, the unit that answers cite.
public struct PageText: Hashable, Codable, Sendable {
  /// The zero-based page index.
  public let pageIndex: Int
  /// The page's text, from the text layer or on-device recognition.
  public let text: String

  /// Creates a page text value.
  public init(pageIndex: Int, text: String) {
    self.pageIndex = pageIndex
    self.text = text
  }
}

/// A page an answer draws on, with the passage that supports it when the model quoted one.
public struct Citation: Hashable, Codable, Sendable, Identifiable {
  /// The zero-based page index.
  public let pageIndex: Int
  /// A short passage from the page that supports the sentence, when available.
  public let quote: String?

  /// Creates a citation.
  public init(pageIndex: Int, quote: String? = nil) {
    self.pageIndex = pageIndex
    self.quote = quote
  }

  /// A stable identity for lists.
  public var id: String { "\(pageIndex)|\(quote ?? "")" }

  /// The one-based page number people see ("p. 12").
  public var pageNumber: Int { pageIndex + 1 }
}

/// Generated text about a document and the pages it draws on (FR-AI-001, FR-AI-002, FR-AI-010).
public struct Answer: Hashable, Sendable {
  /// The generated text, with citation markers removed.
  public let text: String
  /// The pages the text draws on, in order of first use.
  public let citations: [Citation]
  /// The tier that produced the answer; always shown to the user.
  public let tier: IntelligenceTier
  /// Whether the answer is supported by the document.
  ///
  /// An ungrounded answer is shown as "Not found in this document" instead of the text.
  public let isGrounded: Bool
  /// Sentences left out of `text` because the document did not support them (defect D10).
  ///
  /// The assistant says that part of the answer was left out; the AI evaluation counts them.
  public let omittedClaims: Int

  /// Creates an answer.
  public init(text: String, citations: [Citation], tier: IntelligenceTier, isGrounded: Bool, omittedClaims: Int = 0) {
    self.text = text
    self.citations = citations
    self.tier = tier
    self.isGrounded = isGrounded
    self.omittedClaims = omittedClaims
  }

  /// The answer for a question the document does not answer.
  public static func notFound(tier: IntelligenceTier) -> Answer {
    Answer(text: "", citations: [], tier: tier, isGrounded: false)
  }
}

/// One field extracted from a document (FR-AI-003).
public struct ExtractedField: Hashable, Sendable, Identifiable {
  /// The field's stable key, for example `invoiceNumber`.
  public let key: String
  /// The value, editable by the user before export.
  public var value: String
  /// The page the value was found on, when it could be verified in the text.
  public let pageIndex: Int?

  /// Creates an extracted field.
  public init(key: String, value: String, pageIndex: Int?) {
    self.key = key
    self.value = value
    self.pageIndex = pageIndex
  }

  /// The field's identity in lists.
  public var id: String { key }

  /// Whether the value was found verbatim in the document.
  public var isVerified: Bool { pageIndex != nil }
}

/// Fields extracted from a document, exportable as CSV.
public struct Extraction: Hashable, Sendable {
  /// The fields, in a stable order.
  public var fields: [ExtractedField]
  /// The tier that produced them.
  public let tier: IntelligenceTier

  /// Creates an extraction.
  public init(fields: [ExtractedField], tier: IntelligenceTier) {
    self.fields = fields
    self.tier = tier
  }

  /// The fields as CSV (RFC 4180 quoting), with a header row.
  ///
  /// Values come from untrusted documents, so a cell a spreadsheet would run as a formula is made
  /// inert (see `neutralized(_:)`).
  public var csv: String {
    func quoted(_ value: String) -> String {
      "\"" + Self.neutralized(value).replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    let rows = fields.map { "\(quoted($0.key)),\(quoted($0.value)),\($0.pageIndex.map { String($0 + 1) } ?? "")" }
    return (["field,value,page"] + rows).joined(separator: "\r\n") + "\r\n"
  }

  /// A cell value that no spreadsheet runs as a formula (CSV injection, plan item H2).
  ///
  /// Excel, Numbers and Google Sheets treat a cell starting with `=`, `+`, `-`, `@`, a tab or a carriage
  /// return as a formula, so a document could plant `=HYPERLINK(...)` in an extracted value. Such a
  /// cell gets a leading apostrophe, which spreadsheets show as text
  /// ([OWASP CSV injection](https://owasp.org/www-community/attacks/CSV_Injection)). A plain signed
  /// number, such as `-12.50` or `+33 1 23 45 67 89`, is left alone so amounts stay numbers.
  public static func neutralized(_ value: String) -> String {
    guard let first = value.unicodeScalars.first else { return value }
    switch first {
    case "=", "@", "\t", "\r":
      return "'" + value
    case "+", "-":
      let rest = value.unicodeScalars.dropFirst()
      let numeric = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: " .,\u{00A0}\u{202F}"))
      let isNumber =
        !rest.isEmpty && rest.allSatisfy(numeric.contains) && rest.contains { CharacterSet.decimalDigits.contains($0) }
      return isNumber ? value : "'" + value
    default:
      return value
    }
  }
}

/// Document intelligence: summarise, answer, extract and explain, with page citations.
///
/// Implementations route between tiers; features never talk to a model directly.
public protocol DocumentIntelligence: Sendable {
  /// Whether a tier can run now.
  func availability() async -> IntelligenceAvailability
  /// Summarises the pages, citing the pages each point draws on.
  func summarize(_ pages: [PageText]) async throws -> Answer
  /// Answers a question from the pages, or returns a not-found answer.
  func answer(_ question: String, from pages: [PageText]) async throws -> Answer
  /// Extracts structured fields and verifies each value against the text.
  func extractFields(from pages: [PageText]) async throws -> Extraction
  /// Explains a contract's key terms in plain language. The UI adds the not-legal-advice disclosure.
  func explainContract(_ pages: [PageText]) async throws -> Answer
}

/// Errors from document intelligence.
public enum IntelligenceError: Error, Equatable, Sendable {
  /// No tier can run; the reason says why.
  case unavailable(IntelligenceUnavailableReason)
  /// The document has no text to work with (for example a scan that has not been recognised).
  case noText
  /// The model declined, for example because of its safety guardrails.
  case refused
  /// The model failed for another reason.
  case generationFailed
}
