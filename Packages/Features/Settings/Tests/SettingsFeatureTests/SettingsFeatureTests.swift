import Core
import CoreTestSupport
import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Settings model")
struct SettingsModelTests {
  private func makeModel() -> (SettingsModel, InMemorySettingsStore, Changes) {
    let store = InMemorySettingsStore(AppSettings(hasCompletedOnboarding: true, intents: [.read]))
    let changes = Changes()
    let model = SettingsModel(store: store, diagnostics: { "App: PDF Algo Pro 0.1.0" }) { changes.values.append($0) }
    return (model, store, changes)
  }

  @Test("Hiding AI is saved and announced at once (FR-AI-009)")
  func hideAI() {
    let (model, store, changes) = makeModel()
    model.isIntelligenceHidden = true
    #expect(store.load().isIntelligenceHidden && model.isIntelligenceHidden)
    #expect(changes.values.last?.isIntelligenceHidden == true)
  }

  @Test("Home intents can be changed later, keeping their order (FR-ONB-003)")
  func intents() {
    let (model, store, _) = makeModel()
    model.toggle(.scan)
    model.toggle(.read)
    #expect(store.load().intents == [.scan])
    #expect(model.isChosen(.scan) && !model.isChosen(.read))
  }

  @Test func readerLayout() {
    let (model, store, _) = makeModel()
    model.readerDisplayMode = .singlePage
    #expect(store.load().readerDisplayMode == .singlePage && model.readerDisplayMode == .singlePage)
  }

  @Test("Diagnostics are attached only when the user opts in (FR-SET-003)")
  func supportEmail() async throws {
    let (model, _, _) = makeModel()
    let plain = try #require(await model.supportEmailURL())
    #expect(plain.absoluteString.hasPrefix("mailto:info@algorythmos.com.au?subject=PDF%20Algo%20Pro%20support"))
    #expect(!plain.absoluteString.contains("0.1.0"))
    model.includesDiagnostics = true
    let withDiagnostics = try #require(await model.supportEmailURL())
    #expect(withDiagnostics.absoluteString.contains("0.1.0"))
  }

  @Test func screenRenders() {
    let (model, _, _) = makeModel()
    #expect(ImageRenderer(content: SettingsView(model: model, version: "0.1.0").frame(width: 390, height: 844)).uiImage != nil)
    for intent in OnboardingIntent.allCases { _ = SettingsView.intentTitle(intent) }
  }
}

@MainActor
private final class Changes {
  var values: [AppSettings] = []
}
