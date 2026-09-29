#if DEBUG
  import Core
  import Foundation

  /// Deterministic document intelligence for UI tests (Debug builds only): answers about the
  /// synthetic sample, with the same citations and grounding a real tier returns.
  struct ScriptedIntelligence: DocumentIntelligence {
    let unavailable: Bool
    let isHidden: @Sendable () -> Bool

    func availability() async -> IntelligenceAvailability {
      if isHidden() { return .unavailable(.hiddenBySettings) }
      return unavailable ? .unavailable(.deviceNotEligible) : .available(.onDevice)
    }

    func summarize(_ pages: [PageText]) async throws -> Answer {
      try await check(pages)
      return Answer(
        text: "A short guide to the app, followed by an invoice with a total due of 120.00.",
        citations: [
          Citation(pageIndex: 0, quote: "Welcome to PDF Algo Pro"), Citation(pageIndex: 1, quote: "Total due: 120.00"),
        ],
        tier: .onDevice, isGrounded: true)
    }

    func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
      try await check(pages)
      guard question.localizedCaseInsensitiveContains("total") else { return .notFound(tier: .onDevice) }
      return Answer(
        text: "The total due is 120.00.", citations: [Citation(pageIndex: 1, quote: "Total due: 120.00")],
        tier: .onDevice,
        isGrounded: true)
    }

    func extractFields(from pages: [PageText]) async throws -> Extraction {
      try await check(pages)
      return Extraction(
        fields: [
          ExtractedField(key: "reference", value: "INV-2026-0042", pageIndex: 1),
          ExtractedField(key: "total", value: "120.00", pageIndex: 1),
        ], tier: .onDevice)
    }

    func explainContract(_ pages: [PageText]) async throws -> Answer {
      try await summarize(pages)
    }

    private func check(_ pages: [PageText]) async throws {
      if case .unavailable(let reason) = await availability() { throw IntelligenceError.unavailable(reason) }
      if pages.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        throw IntelligenceError.noText
      }
    }
  }
#endif
