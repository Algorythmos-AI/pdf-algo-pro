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
    let model = SettingsModel(
      store: store, diagnostics: { "App: PDF Algo Pro 0.1.0" }, onChange: { changes.values.append($0) })
    return (model, store, changes)
  }

  @Test("Hiding AI is saved and announced at once (FR-AI-009)")
  func hideAI() {
    let (model, store, changes) = makeModel()
    model.isIntelligenceHidden = true
    #expect(store.load().isIntelligenceHidden && model.isIntelligenceHidden)
    #expect(changes.values.last?.isIntelligenceHidden == true)
  }

  @Test("Storage shows the version history and deletes it on request (FR-EDIT-008)")
  func versionHistory() async {
    let sizes = Sizes(value: 4_096)
    let model = SettingsModel(
      store: InMemorySettingsStore(), diagnostics: { "" }, onChange: { _ in },
      versionsSize: { sizes.value }, deleteVersions: { sizes.value = 0 })
    #expect(model.versionsSize == nil)
    await model.loadStorage()
    #expect(model.versionsSize == 4_096)
    await model.deleteVersions()
    #expect(model.versionsSize == 0)
    #expect(model.storageMessage == nil)
  }

  @Test("A failed delete says the documents are unchanged (FR-EDIT-008)")
  func versionHistoryDeleteFails() async {
    struct Failure: Error {}
    let model = SettingsModel(
      store: InMemorySettingsStore(), diagnostics: { "" }, onChange: { _ in }, versionsSize: { 10 },
      deleteVersions: { throw Failure() })
    await model.deleteVersions()
    #expect(model.storageMessage != nil)
    #expect(model.versionsSize == 10)
  }

  @Test("App Lock turns on and off only when the owner confirms (FR-SET-002)")
  func appLock() async {
    let store = InMemorySettingsStore()
    let answers = Answers()
    let model = SettingsModel(
      store: store, diagnostics: { "" }, onChange: { _ in }, lockMethod: .faceID,
      authenticate: { _ in answers.next() })
    answers.values = [false]
    await model.setAppLock(true)
    #expect(!model.isAppLockEnabled, "Not confirmed")
    answers.values = [true]
    await model.setAppLock(true)
    #expect(model.isAppLockEnabled && store.load().isAppLockEnabled)
    #expect(!store.load().indexesTextInSpotlight, "Document text leaves Spotlight while locked (H3)")
    answers.values = [true]
    await model.setAppLock(false)
    #expect(!model.isAppLockEnabled)

    let noPasscode = SettingsModel(
      store: InMemorySettingsStore(), diagnostics: { "" }, onChange: { _ in }, lockMethod: nil,
      authenticate: { _ in true })
    await noPasscode.setAppLock(true)
    #expect(!noPasscode.isAppLockEnabled, "A device without a passcode can't be locked")
  }

  @Test("Home intents can be changed later, keeping their order (FR-ONB-003)")
  func intents() {
    let (model, store, _) = makeModel()
    model.toggle(.scan)
    model.toggle(.read)
    #expect(store.load().intents == [.scan])
    #expect(model.isChosen(.scan) && !model.isChosen(.read))
  }

  @Test("Document text can be kept out of Spotlight (FR-LIB-005, T-11)")
  func spotlightText() {
    let (model, store, changes) = makeModel()
    #expect(model.isSpotlightTextIncluded)
    model.isSpotlightTextIncluded = false
    #expect(!store.load().isSpotlightTextIncluded && !model.isSpotlightTextIncluded)
    #expect(changes.values.last?.isSpotlightTextIncluded == false)
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

  @Test("Without an email account, the report can be copied and names the address")
  func reportWithoutMail() async {
    let (model, _, _) = makeModel()
    #expect(!(await model.supportReport()).contains("0.1.0"))
    model.includesDiagnostics = true
    #expect(await model.supportReport().contains("0.1.0"))
    #expect(SettingsModel.supportAddress == "info@algorythmos.com.au")
  }

  @Test func screenRenders() {
    let (model, _, _) = makeModel()
    #expect(
      ImageRenderer(content: SettingsView(model: model, version: "0.1.0").frame(width: 390, height: 844)).uiImage != nil
    )
    for intent in OnboardingIntent.allCases { _ = SettingsView.intentTitle(intent) }
  }
}

@MainActor
private final class Changes {
  var values: [AppSettings] = []
}

private final class Sizes {
  var value: Int64
  init(value: Int64) { self.value = value }
}

private final class Answers {
  var values: [Bool] = []

  func next() -> Bool {
    values.isEmpty ? false : values.removeFirst()
  }
}
