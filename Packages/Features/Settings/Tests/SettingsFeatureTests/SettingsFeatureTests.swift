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

  @Test("The privacy report loads the last 30 days' counts and draws (FR-SET-005)")
  func privacyReport() async {
    let model = SettingsModel(
      store: InMemorySettingsStore(), diagnostics: { "" }, activity: FixedActivity(), onChange: { _ in })
    await model.loadActivity()
    #expect(model.activity?.requests[.onDevice] == 4 && model.activity?.documentsSentToCloud == 0)
    let view = NavigationStack { PrivacyReportView(model: model) }.frame(width: 390, height: 800)
      .environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: view).uiImage != nil)
    let empty = SettingsModel(store: InMemorySettingsStore(), diagnostics: { "" }, onChange: { _ in })
    await empty.loadActivity()
    #expect(empty.activity == AIActivity())
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

  @Test("Diagnostics are in the draft unless the person turns them off, and that choice is kept (FR-SET-003)")
  func supportEmail() async throws {
    let (model, store, _) = makeModel()
    #expect(model.includesDiagnostics, "On for a new install (PAP-041)")
    let withDiagnostics = try #require(await model.supportEmailURL())
    #expect(
      withDiagnostics.absoluteString.hasPrefix("mailto:pdfalgopro@algorythmos.com?subject=PDF%20Algo%20Pro%20support"))
    #expect(withDiagnostics.absoluteString.contains("0.1.0"))
    model.includesDiagnostics = false
    let plain = try #require(await model.supportEmailURL())
    #expect(!plain.absoluteString.contains("0.1.0"), "Turned off, nothing but the person's own words is sent")
    // Settings is built afresh each time it opens: the choice comes back from the store, not from memory.
    #expect(!store.load().includesDiagnostics)
    #expect(!SettingsModel(store: store, diagnostics: { "0.1.0" }, onChange: { _ in }).includesDiagnostics)
  }

  @Test("Without an email account, the report can be copied and names the address")
  func reportWithoutMail() async {
    let (model, _, _) = makeModel()
    #expect(await model.supportReport().contains("0.1.0"))
    model.includesDiagnostics = false
    #expect(!(await model.supportReport()).contains("0.1.0"))
    #expect(SettingsModel.supportAddress == "pdfalgopro@algorythmos.com")
  }

  @Test("The privacy, terms and support links open the website's pages, in French for French readers")
  func publicLinks() {
    #expect(AppLinks.allCases.count == 3)
    for page in AppLinks.allCases {
      let english = page.url(languageCode: "en")
      #expect(english.scheme == "https" && english.host() == "algorythmos.com")
      #expect(english.path() == page.rawValue && page.rawValue.hasPrefix("/pdf-algo-pro/"))
      #expect(page.url(languageCode: "fr").path() == "/fr-fr" + page.rawValue)
      // Any other language, or none, gets the short address the website redirects.
      #expect(page.url(languageCode: "de") == english && page.url(languageCode: nil) == english)
    }
    let privacy = AppLinks.privacyPolicy.url(languageCode: "en").absoluteString
    #expect(privacy == "https://algorythmos.com/pdf-algo-pro/privacy")
  }

  @Test("About shares the product page, in French for French readers, and links to the company's website")
  func aboutLinks() {
    #expect(AppLinks.product(languageCode: "en").absoluteString == "https://algorythmos.com/pdf-algo-pro")
    #expect(AppLinks.product(languageCode: "fr").absoluteString == "https://algorythmos.com/fr-fr/pdf-algo-pro")
    #expect(AppLinks.product(languageCode: nil) == AppLinks.product(languageCode: "de"))
    #expect(AppLinks.company.absoluteString == "https://algorythmos.com")
    // The release check derives the product page from the first page's path; they must agree.
    for page in AppLinks.allCases {
      #expect(page.rawValue.hasPrefix(AppLinks.productPath + "/"))
    }
  }

  @Test("About draws in English and French, at the default and the largest text size")
  func aboutRenders() {
    for language in ["en", "fr"] {
      for size in [DynamicTypeSize.large, .accessibility5] {
        let about = NavigationStack { AboutView(version: "0.1.0 (12)") }
          .environment(\.locale, Locale(identifier: language))
          .environment(\.dynamicTypeSize, size)
          .frame(width: 390, height: 844)
        #expect(ImageRenderer(content: about).uiImage != nil)
      }
    }
  }

  @Test("App Lock's row shows the symbol of the way the device unlocks")
  func lockSymbols() {
    #expect(SettingsView.lockSymbol(.faceID) == "faceid")
    #expect(SettingsView.lockSymbol(.touchID) == "touchid")
    #expect(SettingsView.lockSymbol(.opticID) == "opticid")
    #expect(SettingsView.lockSymbol(.passcode) == "lock" && SettingsView.lockSymbol(nil) == "lock")
  }

  @Test func screenRenders() {
    let (model, _, _) = makeModel()
    #expect(
      ImageRenderer(content: SettingsView(model: model, version: "0.1.0").frame(width: 390, height: 844)).uiImage != nil
    )
    for intent in OnboardingIntent.allCases { _ = SettingsView.intentTitle(intent) }
    // At an accessibility text size the header is left out, so the AI switch stays on the first screen.
    let large = SettingsView(model: model, version: "0.1.0").environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: large.frame(width: 390, height: 844)).uiImage != nil)
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

private struct FixedActivity: AIActivityRecording {
  func record(_ tier: IntelligenceTier) async {}
  func activity(days: Int) async -> AIActivity {
    AIActivity(requests: [.onDevice: 4], documentsSentToCloud: 0, days: days)
  }
}
