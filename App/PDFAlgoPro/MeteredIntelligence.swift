import Commerce
import Core
import Foundation

/// Document intelligence within the free tier's daily allowance (FR-STORE-001, FR-STORE-008).
///
/// Each summary, answer, extraction or explanation is one request. The allowance is asked before a
/// request starts and counted only when it succeeds, so a request that fails, is refused or is
/// cancelled costs nothing. With Pro there is no limit. When the day's requests are used, the
/// intelligence reports itself unavailable for that reason, which the assistant explains, and
/// nothing about a document the person already has is affected.
struct MeteredIntelligence: DocumentIntelligence {
  let base: any DocumentIntelligence
  let allowance: UsageAllowance
  /// The person's entitlement, once known.
  let entitlement: @Sendable () async -> Entitlement

  func availability() async -> IntelligenceAvailability {
    let availability = await base.availability()
    guard availability.isAvailable, await !isAllowed() else { return availability }
    return .unavailable(.dailyAllowanceUsed)
  }

  func summarize(_ pages: [PageText]) async throws -> Answer {
    try await metered { try await base.summarize(pages) }
  }

  func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
    try await metered { try await base.answer(question, from: pages) }
  }

  func answer(_ question: String, from pages: [PageText], after earlier: [Exchange]) async throws -> Answer {
    try await metered { try await base.answer(question, from: pages, after: earlier) }
  }

  func extractFields(from pages: [PageText]) async throws -> Extraction {
    try await metered { try await base.extractFields(from: pages) }
  }

  func explainContract(_ pages: [PageText]) async throws -> Answer {
    try await metered { try await base.explainContract(pages) }
  }

  private func isAllowed() async -> Bool {
    await allowance.isAllowed(.intelligenceRequest, entitlement: await entitlement())
  }

  /// Runs a request on a unit of the allowance held for it.
  ///
  /// Two requests can't both take the last unit (#265). A cancelled request gives its unit back at
  /// once: the request that replaces it may need it.
  private func metered<Result: Sendable>(_ request: () async throws -> Result) async throws -> Result {
    guard let unit = await allowance.reserve(.intelligenceRequest, entitlement: await entitlement()) else {
      throw IntelligenceError.unavailable(.dailyAllowanceUsed)
    }
    do {
      let result = try await withTaskCancellationHandler {
        try await request()
      } onCancel: { [allowance] in
        allowance.release(unit)
      }
      // A model may finish after its request was cancelled or replaced; nobody sees that result, so it
      // costs nothing (#259).
      try Task.checkCancellation()
      await allowance.commit(unit)
      return result
    } catch {
      allowance.release(unit)
      throw error
    }
  }
}
