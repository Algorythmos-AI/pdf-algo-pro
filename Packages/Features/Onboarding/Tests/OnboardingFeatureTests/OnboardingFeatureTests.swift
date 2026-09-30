import Core
import CoreTestSupport
import SwiftUI
import Testing

@testable import OnboardingFeature

@MainActor
@Suite("Onboarding")
struct OnboardingModelTests {
  private func makeModel(
    availability: IntelligenceAvailability = .available(.onDevice)
  ) -> (OnboardingModel, InMemorySettingsStore, RecordingTelemetry, Box) {
    let settings = InMemorySettingsStore()
    let telemetry = RecordingTelemetry()
    let finished = Box()
    let model = OnboardingModel(
      settings: settings, intelligence: FakeIntelligence(availability: availability), telemetry: telemetry
    ) { finished.value = $0 }
    return (model, settings, telemetry, finished)
  }

  @Test("AI-first options lead; every option is offered once")
  func groups() {
    let (model, _, _, _) = makeModel()
    #expect(model.askAndUnderstand == [.chatWithPDF, .summarizeDocument, .extractData, .analyzeContract])
    #expect(model.askAndUnderstand + model.workWithPDFs == OnboardingIntent.offered)
  }

  @Test("Only options this build can do are offered, none marked as coming later (FR-ONB-007)")
  func onlyShippedOptions() {
    let (model, _, _, _) = makeModel()
    #expect(!model.intents.contains(.editText) && !model.intents.contains(.convert))
    #expect(model.intents == OnboardingIntent.allCases.filter(\.isOffered))
  }

  @Test("Choices keep their order and can be undone; the first leads the home screen")
  func selection() async {
    let (model, settings, telemetry, finished) = makeModel()
    model.toggle(.scan)
    model.toggle(.chatWithPDF)
    model.toggle(.read)
    model.toggle(.read)
    #expect(model.selected == [.scan, .chatWithPDF] && model.isSelected(.scan) && !model.isSelected(.read))
    await model.finish()
    #expect(settings.load().intents == [.scan, .chatWithPDF] && settings.load().hasCompletedOnboarding)
    #expect(finished.value?.intents == [.scan, .chatWithPDF])
    #expect(HomeAction.primary(for: settings.load().intents) == .scanDocument)
    #expect(
      await telemetry.events == [
        "onboarding.intent.selected", "onboarding.intent.selected", "onboarding.flow.completed",
      ])
  }

  @Test("Skipping finishes onboarding without choosing anything (FR-ONB-002)")
  func skip() async {
    let (model, settings, telemetry, finished) = makeModel()
    await model.skip()
    #expect(settings.load().hasCompletedOnboarding && settings.load().intents.isEmpty)
    #expect(finished.value != nil)
    #expect(await telemetry.events == ["onboarding.flow.skipped"])
  }

  @Test("AI options explain themselves when Apple Intelligence is unavailable (FR-ONB-006)")
  func unavailableIntelligence() async {
    let (available, _, _, _) = makeModel()
    await available.load()
    #expect(!available.intelligenceNeedsNote)
    let (unavailable, _, telemetry, _) = makeModel(availability: .unavailable(.appleIntelligenceNotEnabled))
    #expect(!unavailable.intelligenceNeedsNote)
    await unavailable.load()
    #expect(unavailable.intelligenceNeedsNote)
    #expect(await telemetry.events == ["onboarding.flow.started"])
  }

  @Test("Every intent has a title, a description and a symbol", arguments: OnboardingIntent.allCases)
  func copy(intent: OnboardingIntent) {
    #expect(!IntentCopy.symbol(intent).isEmpty)
    _ = IntentCopy.title(intent)
    _ = IntentCopy.detail(intent)
  }

  @Test func screenRenders() {
    let (model, _, _, _) = makeModel()
    #expect(ImageRenderer(content: OnboardingView(model: model).frame(width: 390, height: 844)).uiImage != nil)
  }
}

@MainActor
final class Box {
  var value: AppSettings?
}
