import AssistantFeature
import Core
import CoreSpotlight
import Foundation
import LibraryFeature
import OCR
import Observation
import OnboardingFeature
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
    library = LibraryModel(
      library: container.library, intake: container.intake, index: container.index, settings: container.settings,
      telemetry: container.telemetry, thumbnails: container.thumbnails)
    IntentRouter.shared.attach(
      library: container.library, intelligence: container.intelligence, index: container.index
    ) { [weak self] route in self?.navigate(to: route) }
    if container.environment.seedsSample {
      Task { await library.addSample() }
    }
    Task { await container.migrateSpotlightIfNeeded() }
    // Text recognition the app was stopped in the middle of goes on from where it was (P8).
    Task { await container.recognition.resumePending() }
  }

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
      recognition: container.recognition, signatures: container.signatures)
    reader = (selection, model)
    return model
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
