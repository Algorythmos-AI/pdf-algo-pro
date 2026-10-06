import AssistantFeature
import Core
import CoreSpotlight
import Foundation
import LibraryFeature
import OCR
import Observation
import OnboardingFeature
import PDFEngine
import ReaderFeature
import ScanFeature
import SettingsFeature
import SwiftUI

/// App-level state and the one router every entry point goes through (ADR-0004).
///
/// The router only navigates: opening a link never deletes, sends or changes anything.
@MainActor
@Observable
final class AppModel {
  /// A sheet over the library.
  enum Sheet: String, Identifiable {
    case scan
    case settings
    var id: String { rawValue }
  }

  private(set) var settings: AppSettings
  var sheet: Sheet?
  let container: AppContainer
  let library: LibraryModel
  /// App Lock (FR-SET-002).
  let lock: AppLock
  /// How this device confirms its owner, read once at launch; `nil` without a passcode.
  let lockMethod: AppLockMethod?
  /// Asks for a rating after real successes, at a calm moment (plan §6).
  let reviews: ReviewPrompter
  @ObservationIgnored private var reader: (selection: DocumentSelection, model: ReaderModel)?
  @ObservationIgnored private(set) lazy var onboarding = OnboardingModel(
    settings: container.settings, intelligence: container.intelligence, telemetry: container.telemetry
  ) { [weak self] in self?.settings = $0 }

  init(container: AppContainer) {
    self.container = container
    settings = container.settings.load()
    let store = container.settings
    lock = AppLock(authenticator: container.authenticator) { store.load().isAppLockEnabled }
    lockMethod = container.authenticator.method()
    let reviews = ReviewPrompter(
      defaults: container.environment.isUITesting
        ? UserDefaults(suiteName: "ui-testing-reviews") ?? .standard : .standard,
      version: container.version, isEnabled: !container.environment.isUITesting)
    self.reviews = reviews
    Task { [telemetry = container.telemetry] in
      await telemetry.observe { event in Task { @MainActor in reviews.handle(event) } }
    }
    library = LibraryModel(
      library: container.library, intake: container.intake, index: container.index, settings: container.settings,
      telemetry: container.telemetry, thumbnails: container.thumbnails)
    IntentRouter.shared.attach(
      library: container.library, intelligence: container.intelligence, index: container.index
    ) { [weak self] route in self?.navigate(to: route) }
    if container.environment.seedsSample {
      Task { await library.addSample() }
    }
    if container.environment.seedsDamaged {
      Task { [library, container] in
        // The sample, with its file then overwritten by bytes that aren't a PDF, as a damaged file would be.
        guard let data = try? SyntheticPDF.makeSample(),
          let document = try? await container.intake.add(data: data, title: "Damaged sample"),
          let url = try? await container.library.fileURL(for: document.id)
        else { return }
        try? Data("not a PDF any more".utf8).write(to: url)
        await library.reload()
        library.open(document.id)
      }
    }
    if container.environment.seedsLocked {
      Task { [library, container] in
        // A synthetic document; its password is a fixture, known to the UI tests.
        guard let data = try? SyntheticPDF.makeEncrypted(pages: ["Locked page"], password: Self.lockedSamplePassword),
          let document = try? await container.intake.add(data: data, title: "Locked sample")
        else { return }
        await library.reload()
        library.open(document.id)
      }
    }
    Task { await container.migrateSpotlightIfNeeded() }
    // Text recognition the app was stopped in the middle of goes on from where it was (P8).
    Task { await container.recognition.resumePending() }
  }

  /// The password of the `-seed-library locked` document (a test fixture).
  static let lockedSamplePassword = "open-sesame"

  // MARK: - Routing

  /// Navigates to a route from a URL, Spotlight, a widget or an intent.
  func navigate(to route: Route) {
    switch route {
    case .library(let section):
      sheet = nil
      library.section = section
      library.selection = nil
    case .document(let id, let pageIndex):
      sheet = nil
      library.open(id, pageIndex: pageIndex)
    case .scan:
      sheet = .scan
    case .settings:
      sheet = .settings
    }
  }

  /// Handles a `pdfalgopro://` URL; anything else is ignored.
  func handle(_ url: URL) {
    if url.isFileURL {
      Task { await library.importFiles([url]) }
    } else if let route = DeepLink.route(for: url) {
      navigate(to: route)
    }
  }

  /// Opens a Spotlight result (FR-LIB-005).
  func handleSpotlight(_ activity: NSUserActivity) {
    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
      let id = DocumentID(string: identifier)
    else { return }
    navigate(to: .document(id, pageIndex: nil))
  }

  // MARK: - Feature models

  /// The reader for a selection, made once: the library's detail column asks again on every redraw.
  func makeReader(for selection: DocumentSelection) -> ReaderModel {
    if let reader, reader.selection == selection { return reader.model }
    let model = ReaderModel(
      selection: selection.id, pageIndex: selection.pageIndex, task: selection.task, library: container.library,
      intake: container.intake, index: container.index, settings: container.settings, telemetry: container.telemetry,
      recognition: container.recognition, signatures: container.signatures, textEditing: container.textEditing,
      textEditingDiagnostics: container.textEditingDiagnostics, textEditor: container.textEditor)
    reader = (selection, model)
    return model
  }

  /// Lets go of the reader once its document has closed, so opening it again starts afresh.
  func closeReader() {
    reader = nil
  }

  func makeAssistant(for context: ReaderAssistantContext) -> AssistantModel {
    AssistantModel(
      task: context.task, intelligence: container.intelligence, pages: context.pages, telemetry: container.telemetry,
      onReveal: context.reveal)
  }

  func makeScan() -> ScanModel {
    ScanModel(
      intake: container.intake, builder: container.builder, telemetry: container.telemetry,
      recognizer: VisionTextRecognizer()
    ) {
      [weak self] document in
      guard let self else { return }
      sheet = nil
      Task {
        await library.reload()
        library.open(document.id)
      }
    }
  }

  /// The internal tools section in Settings: the live AI evaluation, in Debug and Staging builds only.
  var internalTools: AnyView? {
    #if INTERNAL_TOOLS
      AnyView(EvaluationSection(intelligence: container.intelligence))
    #else
      nil
    #endif
  }

  func makeSettings() -> SettingsModel {
    SettingsModel(
      store: container.settings, diagnostics: { [container] in await container.diagnostics() },
      activity: container.activity,
      onChange: { [weak self] settings in
        guard let self else { return }
        let textSettingChanged = settings.indexesTextInSpotlight != self.settings.indexesTextInSpotlight
        self.settings = settings
        self.lock.settingChanged()
        if textSettingChanged { Task { await self.container.reindexSpotlight() } }
      }, versionsSize: { [container] in await container.library.versionsSize() },
      deleteVersions: { [container] in try await container.library.deleteAllVersions() }, lockMethod: lockMethod,
      authenticate: { [container] reason in await container.authenticator.authenticate(reason: reason) })
  }
}
