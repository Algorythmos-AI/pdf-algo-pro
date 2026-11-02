#if DEBUG
  import Core
  import SwiftUI

  // Previews of the assistant for the design pass (PAP-070): each task with a made-up answer, and
  // the screen when on-device intelligence is unavailable, at the largest accessibility text size,
  // in dark appearance and right to left. The answers are scripted, not generated.

  /// Intelligence with scripted answers, or none when it is unavailable here.
  private struct PreviewIntelligence: DocumentIntelligence {
    let unavailable: IntelligenceUnavailableReason?

    private var answer: Answer {
      Answer(
        text: "The lease runs for twelve months from 1 November. Rent is due on the first of each month, and "
          + "either side can end it with sixty days’ notice.",
        citations: [Citation(pageIndex: 0, quote: "twelve months"), Citation(pageIndex: 2, quote: "sixty days")],
        tier: .onDevice, isGrounded: true)
    }

    func availability() async -> IntelligenceAvailability {
      unavailable.map { .unavailable($0) } ?? .available(.onDevice)
    }

    func summarize(_ pages: [PageText]) async throws -> Answer { answer }
    func answer(_ question: String, from pages: [PageText]) async throws -> Answer { answer }
    func extractFields(from pages: [PageText]) async throws -> Extraction {
      Extraction(
        fields: [
          ExtractedField(key: "startDate", value: "1 November 2026", pageIndex: 0),
          ExtractedField(key: "noticePeriod", value: "60 days", pageIndex: 2),
        ], tier: .onDevice)
    }
    func explainContract(_ pages: [PageText]) async throws -> Answer { answer }
  }

  /// Telemetry that keeps nothing.
  private struct PreviewTelemetry: TelemetryRecording {
    func record(_ event: String) async {}
  }

  /// The assistant on one task; it starts itself when it appears.
  private func assistantPreview(
    _ task: AssistantTask = .summarize, unavailable: IntelligenceUnavailableReason? = nil
  ) -> AssistantView {
    AssistantView(
      model: AssistantModel(
        task: task, intelligence: PreviewIntelligence(unavailable: unavailable),
        pages: { [PageText(pageIndex: 0, text: "A made-up lease for previews.")] }, telemetry: PreviewTelemetry(),
        onReveal: { _ in }))
  }

  #Preview("Summary") { assistantPreview() }
  #Preview("Summary, largest text") { assistantPreview().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Summary, dark") { assistantPreview().preferredColorScheme(.dark) }
  #Preview("Summary, right to left") { assistantPreview().environment(\.layoutDirection, .rightToLeft) }

  #Preview("Ask, before a question") { assistantPreview(.ask) }
  #Preview("Ask, largest text") { assistantPreview(.ask).environment(\.dynamicTypeSize, .accessibility5) }

  #Preview("Extract") { assistantPreview(.extract) }
  #Preview("Extract, largest text") { assistantPreview(.extract).environment(\.dynamicTypeSize, .accessibility5) }

  #Preview("Explain a contract") { assistantPreview(.explainContract) }
  #Preview("Explain a contract, dark") { assistantPreview(.explainContract).preferredColorScheme(.dark) }

  #Preview("Unavailable") { assistantPreview(unavailable: .appleIntelligenceNotEnabled) }
  #Preview("Unavailable, largest text") {
    assistantPreview(unavailable: .appleIntelligenceNotEnabled).environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("Daily allowance used") { assistantPreview(unavailable: .dailyAllowanceUsed) }
#endif
