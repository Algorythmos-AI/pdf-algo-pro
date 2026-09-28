import AssistantFeature
import Core
import CoreSpotlight
import Foundation
import LibraryFeature
import Observation
import OnboardingFeature
import ReaderFeature
import ScanFeature
import SettingsFeature

/// App-level state and the one router every entry point goes through (ADR-0004). The router only
/// navigates: opening a link never deletes, sends or changes anything.
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
  @ObservationIgnored private(set) lazy var onboarding = OnboardingModel(
    settings: container.settings, intelligence: container.intelligence, telemetry: container.telemetry
  ) { [weak self] in self?.settings = $0 }

  init(container: AppContainer) {
    self.container = container
    settings = container.settings.load()
    library = LibraryModel(
      library: container.library, intake: container.intake, index: container.index, settings: container.settings,
      telemetry: container.telemetry, thumbnails: container.thumbnails)
    if container.environment.seedsSample {
      Task { await library.addSample() }
    }
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

  func makeReader(for selection: DocumentSelection) -> ReaderModel {
    ReaderModel(
      selection: selection.id, pageIndex: selection.pageIndex, task: selection.task, library: container.library,
      intake: container.intake, index: container.index, settings: container.settings, telemetry: container.telemetry,
      builder: container.builder)
  }

  func makeAssistant(for context: ReaderAssistantContext) -> AssistantModel {
    AssistantModel(
      task: context.task, intelligence: container.intelligence, pages: context.pages, telemetry: container.telemetry,
      onReveal: context.reveal)
  }

  func makeScan() -> ScanModel {
    ScanModel(intake: container.intake, builder: container.builder, telemetry: container.telemetry) { [weak self] document in
      guard let self else { return }
      sheet = nil
      Task {
        await library.reload()
        library.open(document.id)
      }
    }
  }

  func makeSettings() -> SettingsModel {
    SettingsModel(store: container.settings, diagnostics: { [container] in await container.diagnostics() }) { [weak self] in
      self?.settings = $0
    }
  }
}
