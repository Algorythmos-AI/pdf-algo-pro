#if DEBUG
  import Core
  import DesignSystem
  import SwiftUI

  // Previews of the introduction for the design pass (PAP-070): each page, at the largest
  // accessibility text size, in dark appearance and right to left. Pictures are held still, as in
  // the snapshot tests.

  /// Settings held in memory, so a preview never touches the app's own.
  private final class PreviewSettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings = AppSettings()

    func load() -> AppSettings { lock.withLock { settings } }

    func save(_ settings: AppSettings) { lock.withLock { self.settings = settings } }
  }

  /// Telemetry that keeps nothing.
  private struct PreviewTelemetry: TelemetryRecording {
    func record(_ event: String) async {}
  }

  /// Intelligence that is available, or not, and answers nothing: the introduction only asks
  /// whether it works here.
  private struct PreviewIntelligence: DocumentIntelligence {
    let isAvailable: Bool

    func availability() async -> IntelligenceAvailability {
      isAvailable ? .available(.onDevice) : .unavailable(.deviceNotEligible)
    }

    func summarize(_ pages: [PageText]) async throws -> Answer { throw IntelligenceError.noText }
    func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
      throw IntelligenceError.noText
    }
    func extractFields(from pages: [PageText]) async throws -> Extraction { throw IntelligenceError.noText }
    func explainContract(_ pages: [PageText]) async throws -> Answer { throw IntelligenceError.noText }
  }

  /// The introduction on one of its pages, counting from 0.
  private struct OnboardingPreview: View {
    let page: Int
    @State private var model: OnboardingModel

    init(page: Int = 0, intelligenceAvailable: Bool = true) {
      self.page = page
      _model = State(
        initialValue: OnboardingModel(
          settings: PreviewSettingsStore(), intelligence: PreviewIntelligence(isAvailable: intelligenceAvailable),
          telemetry: PreviewTelemetry(), onFinish: { _ in }))
    }

    var body: some View {
      OnboardingView(model: model)
        .environment(\.playsDecorativeMotion, false)
        .task {
          await model.load()
          for _ in 0..<page { await model.advance() }
        }
    }
  }

  #Preview("Scan") { OnboardingPreview() }
  #Preview("Scan, largest text") { OnboardingPreview().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Scan, dark") { OnboardingPreview().preferredColorScheme(.dark) }
  #Preview("Scan, right to left") { OnboardingPreview().environment(\.layoutDirection, .rightToLeft) }

  #Preview("Sign") { OnboardingPreview(page: 1) }
  #Preview("Sign, largest text") { OnboardingPreview(page: 1).environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Sign, dark") { OnboardingPreview(page: 1).preferredColorScheme(.dark) }

  #Preview("Ask") { OnboardingPreview(page: 2) }
  #Preview("Ask, largest text") { OnboardingPreview(page: 2).environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Ask, dark") { OnboardingPreview(page: 2).preferredColorScheme(.dark) }

  #Preview("Organise, without intelligence") { OnboardingPreview(page: 2, intelligenceAvailable: false) }
  #Preview("Organise, largest text") {
    OnboardingPreview(page: 2, intelligenceAvailable: false).environment(\.dynamicTypeSize, .accessibility5)
  }
#endif
