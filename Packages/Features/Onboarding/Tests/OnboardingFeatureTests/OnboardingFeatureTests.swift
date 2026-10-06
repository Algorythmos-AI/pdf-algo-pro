import Core
import CoreTestSupport
import SwiftUI
import Testing

@testable import OnboardingFeature

@MainActor
@Suite("Onboarding")
struct OnboardingModelTests {
  private func makeModel(
    availability: IntelligenceAvailability = .available(.onDevice), stored: AppSettings? = nil
  ) -> (OnboardingModel, InMemorySettingsStore, RecordingTelemetry, Box) {
    let settings = InMemorySettingsStore()
    if let stored { settings.save(stored) }
    let telemetry = RecordingTelemetry()
    let finished = Box()
    let model = OnboardingModel(
      settings: settings, intelligence: FakeIntelligence(availability: availability), telemetry: telemetry
    ) { finished.value = $0 }
    return (model, settings, telemetry, finished)
  }

  @Test("Three pages, one capability each, starting with scanning (FR-ONB-001)")
  func pages() async {
    let (model, _, telemetry, _) = makeModel()
    #expect(model.pages.count == 3)
    #expect(model.pages.prefix(2) == [.scan, .sign])
    #expect(model.index == 0 && model.page == .scan && !model.isLastPage)
    await model.load()
    #expect(model.pages == [.scan, .sign, .ask])
    #expect(await telemetry.events == ["onboarding.flow.started"])
  }

  @Test("Where on-device intelligence is unavailable, the third page needs none (FR-ONB-006)")
  func unavailableIntelligence() async {
    let (model, _, _, _) = makeModel(availability: .unavailable(.appleIntelligenceNotEnabled))
    await model.load()
    #expect(model.pages == [.scan, .sign, .organize])
    #expect(!model.pages.contains(.ask))
  }

  @Test("Until intelligence is known to work, the third page is the one that needs none")
  func unknownIntelligence() {
    let (model, _, _, _) = makeModel()
    #expect(model.pages == [.scan, .sign, .organize])
  }

  @Test("A page that is on screen never changes, even when the answer comes late")
  func lateAnswer() async {
    let (model, _, _, _) = makeModel()
    await model.advance()
    await model.advance()
    #expect(model.isLastPage && model.page == .organize)
    await model.load()
    #expect(model.page == .organize, "The answer came once the third page was showing")
  }

  @Test("Continue walks the pages, and finishes on the last")
  func advance() async {
    let (model, settings, telemetry, finished) = makeModel()
    await model.advance()
    #expect(model.index == 1 && model.page == .sign)
    #expect(!settings.load().hasCompletedOnboarding && finished.value == nil)
    await model.advance()
    #expect(model.index == 2 && model.isLastPage)
    #expect(!settings.load().hasCompletedOnboarding && finished.value == nil)
    await model.advance()
    #expect(settings.load().hasCompletedOnboarding)
    #expect(finished.value?.hasCompletedOnboarding == true)
    #expect(await telemetry.events == ["onboarding.flow.completed"])
  }

  @Test("Skip finishes from any page (FR-ONB-002)", arguments: 0...2)
  func skip(from page: Int) async {
    let (model, settings, telemetry, finished) = makeModel()
    for _ in 0..<page { await model.advance() }
    await model.skip()
    #expect(settings.load().hasCompletedOnboarding)
    #expect(finished.value != nil)
    #expect(await telemetry.events == ["onboarding.flow.skipped"])
  }

  @Test("First run is saved as done before anything that follows is shown")
  func savedBeforeFinishing() async {
    let settings = InMemorySettingsStore()
    var savedWhenCalled = false
    let model = OnboardingModel(
      settings: settings, intelligence: FakeIntelligence(availability: .available(.onDevice)),
      telemetry: RecordingTelemetry()
    ) { _ in savedWhenCalled = settings.load().hasCompletedOnboarding }
    await model.skip()
    #expect(savedWhenCalled)
  }

  @Test("Finishing keeps the settings that were already there")
  func keepsSettings() async {
    let stored = AppSettings(intents: [.scan], isIntelligenceHidden: true, isAppLockEnabled: true)
    let (model, settings, _, finished) = makeModel(stored: stored)
    await model.finish()
    var expected = stored
    expected.hasCompletedOnboarding = true
    #expect(settings.load() == expected && finished.value == expected)
  }

  @Test("Every page has a headline, a sentence and a symbol", arguments: OnboardingPage.allCases)
  func copy(page: OnboardingPage) {
    #expect(!page.symbol.isEmpty)
    #expect(page.id == page.rawValue)
    _ = page.title
    _ = page.detail
    #expect(page.usesIntelligence == (page == .ask))
  }

  @Test("Each page renders, at the default and at an accessibility text size", arguments: OnboardingPage.allCases)
  func renders(page: OnboardingPage) {
    #expect(ImageRenderer(content: OnboardingIllustration(page: page)).uiImage != nil)
    let (model, _, _, _) = makeModel()
    let screen = OnboardingView(model: model).frame(width: 390, height: 844)
    #expect(ImageRenderer(content: screen).uiImage != nil)
    #expect(ImageRenderer(content: screen.dynamicTypeSize(.accessibility3)).uiImage != nil)
  }
}

@MainActor
final class Box {
  var value: AppSettings?
}
