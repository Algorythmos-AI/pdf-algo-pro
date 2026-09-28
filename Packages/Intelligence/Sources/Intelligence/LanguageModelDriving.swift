import Core
import Foundation

/// Fields the extraction prompt asks for. Every value is optional: an empty field means the
/// document does not state it.
public struct ExtractionDraft: Hashable, Sendable {
  /// The kind of document, for example "invoice" or "receipt".
  public var documentType: String?
  /// The invoice or reference number.
  public var reference: String?
  /// The issue date as written.
  public var issueDate: String?
  /// The due date as written.
  public var dueDate: String?
  /// The total amount as written.
  public var total: String?
  /// The seller or issuer.
  public var seller: String?
  /// The buyer or recipient.
  public var buyer: String?

  /// Creates a draft.
  public init(
    documentType: String? = nil, reference: String? = nil, issueDate: String? = nil, dueDate: String? = nil,
    total: String? = nil, seller: String? = nil, buyer: String? = nil
  ) {
    self.documentType = documentType
    self.reference = reference
    self.issueDate = issueDate
    self.dueDate = dueDate
    self.total = total
    self.seller = seller
    self.buyer = buyer
  }

  /// The fields in display order, with stable keys.
  var fields: [(key: String, value: String?)] {
    [
      ("documentType", documentType), ("reference", reference), ("issueDate", issueDate), ("dueDate", dueDate),
      ("total", total), ("seller", seller), ("buyer", buyer),
    ]
  }
}

/// Errors a model driver reports, mapped from the framework's errors.
public enum ModelError: Error, Equatable, Sendable {
  /// The prompt did not fit the model's context window.
  case contextTooLarge
  /// The model declined (guardrails or refusal).
  case refused
  /// The model is not available right now.
  case unavailable(IntelligenceUnavailableReason)
  /// Any other failure.
  case failed
}

/// One language model tier. The router drives tiers through this seam, so the grounding logic is
/// tested with scripted models and the live tier is a thin adapter (ADR-0021).
public protocol LanguageModelDriving: Sendable {
  /// The tier this model runs on.
  var tier: IntelligenceTier { get }
  /// Whether the model can run now.
  func availability() async -> IntelligenceAvailability
  /// Tokens available for the prompt, after instructions and the response are reserved.
  func promptBudget() async -> Int
  /// The number of tokens a text uses, exactly when the framework can count, else estimated.
  func tokenCount(_ text: String) async -> Int
  /// Generates text.
  ///
  /// - Throws: `ModelError`.
  func respond(instructions: String, prompt: String) async throws -> String
  /// Generates the extraction fields with guided generation.
  ///
  /// - Throws: `ModelError`.
  func extract(instructions: String, prompt: String) async throws -> ExtractionDraft
}

extension LanguageModelDriving {
  /// An estimate for when the framework cannot count: `Assumption:` about 3 characters per token for
  /// English and French prose, deliberately conservative; checked against `tokenCount` in the AI
  /// evaluation suite.
  static func estimatedTokens(_ text: String) -> Int {
    max(1, text.count / 3)
  }
}
