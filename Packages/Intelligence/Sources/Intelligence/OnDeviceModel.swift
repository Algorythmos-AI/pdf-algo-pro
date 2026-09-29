import Core
import Foundation
import FoundationModels

/// Apple's on-device foundation model: private, offline and free, the default tier (ADR-0009).
public struct OnDeviceModel: LanguageModelDriving {
  /// Tokens kept free for the model's response.
  static let responseReserve = 700
  /// Tokens kept free for instructions and formatting.
  static let instructionReserve = 400

  private let model: SystemLanguageModel

  /// Creates the on-device tier over the system model.
  public init(model: SystemLanguageModel = .default) {
    self.model = model
  }

  /// Always on device.
  public var tier: IntelligenceTier { .onDevice }

  /// Maps the framework's availability to the reasons the app explains (FR-ONB-006).
  public func availability() async -> IntelligenceAvailability {
    Self.map(model.availability)
  }

  static func map(_ availability: SystemLanguageModel.Availability) -> IntelligenceAvailability {
    switch availability {
    case .available: .available(.onDevice)
    case .unavailable(.deviceNotEligible): .unavailable(.deviceNotEligible)
    case .unavailable(.appleIntelligenceNotEnabled): .unavailable(.appleIntelligenceNotEnabled)
    case .unavailable: .unavailable(.modelNotReady)
    }
  }

  /// The context window read at run time, less the reserves.
  public func promptBudget() async -> Int {
    max(500, model.contextSize - Self.responseReserve - Self.instructionReserve)
  }

  /// Counts tokens with the framework where available (iOS 26.4 and later), else estimates.
  public func tokenCount(_ text: String) async -> Int {
    if #available(iOS 26.4, macOS 26.4, *), let count = try? await model.tokenCount(for: text) {
      return count
    }
    return Self.estimatedTokens(text)
  }

  /// Generates text in a fresh session, so no document leaks between requests.
  public func respond(instructions: String, prompt: String) async throws -> String {
    let session = LanguageModelSession(model: model, instructions: instructions)
    do {
      let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: Self.responseReserve)
      return try await session.respond(to: prompt, options: options).content
    } catch let error as LanguageModelSession.GenerationError {
      throw Self.map(error)
    } catch {
      throw ModelError.failed
    }
  }

  /// Extracts fields with guided generation, so the result is always well-formed.
  public func extract(instructions: String, prompt: String) async throws -> ExtractionDraft {
    let session = LanguageModelSession(model: model, instructions: instructions)
    do {
      let fields = try await session.respond(
        to: prompt, generating: GeneratedFields.self, options: GenerationOptions(temperature: 0)
      ).content
      return fields.draft
    } catch let error as LanguageModelSession.GenerationError {
      throw Self.map(error)
    } catch {
      throw ModelError.failed
    }
  }

  static func map(_ error: LanguageModelSession.GenerationError) -> ModelError {
    switch error {
    case .exceededContextWindowSize: .contextTooLarge
    case .guardrailViolation, .refusal: .refused
    case .assetsUnavailable: .unavailable(.modelNotReady)
    default: .failed
    }
  }
}

/// The guided-generation schema for extraction.
@Generable
struct GeneratedFields {
  @Guide(description: "The kind of document, such as invoice, receipt, quote or statement. Empty if unclear.")
  var documentType: String
  @Guide(description: "The invoice, receipt or reference number, copied exactly. Empty if absent.")
  var reference: String
  @Guide(description: "The issue date exactly as written. Empty if absent.")
  var issueDate: String
  @Guide(description: "The due date exactly as written. Empty if absent.")
  var dueDate: String
  @Guide(description: "The total amount due exactly as written, with its currency if shown. Empty if absent.")
  var total: String
  @Guide(description: "The seller or issuer name exactly as written. Empty if absent.")
  var seller: String
  @Guide(description: "The buyer or recipient name exactly as written. Empty if absent.")
  var buyer: String

  var draft: ExtractionDraft {
    func value(_ text: String) -> String? {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return ExtractionDraft(
      documentType: value(documentType), reference: value(reference), issueDate: value(issueDate),
      dueDate: value(dueDate), total: value(total), seller: value(seller), buyer: value(buyer))
  }
}
