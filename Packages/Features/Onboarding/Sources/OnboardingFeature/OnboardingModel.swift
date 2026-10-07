import Core
import Foundation
import Observation

/// The first-run introduction (FR-ONB-001, FR-ONB-002, FR-ONB-006): three pages, one capability
/// each, skippable from every page, and never an account or a permission request.
///
/// The model knows nothing of the store. What follows the introduction (the subscription offer,
/// then Home) is the app's to decide, once `onFinish` has run.
@MainActor
@Observable
public final class OnboardingModel {
  /// The pages, in order.
  ///
  /// The third is about on-device intelligence only when it is known to work here. Until that is
  /// known it is the page that needs nothing, and a page that is on screen never changes.
  public private(set) var pages: [OnboardingPage] = [.scan, .sign, .organize]
  /// Which page is showing.
  public private(set) var index = 0

  private let settings: any SettingsStoring
  private let intelligence: any DocumentIntelligence
  private let telemetry: any TelemetryRecording
  private let onFinish: (AppSettings) -> Void

  /// Creates the model; `onFinish` receives the saved settings when the person finishes or skips.
  public init(
    settings: any SettingsStoring, intelligence: any DocumentIntelligence, telemetry: any TelemetryRecording,
    onFinish: @escaping (AppSettings) -> Void
  ) {
    self.settings = settings
    self.intelligence = intelligence
    self.telemetry = telemetry
    self.onFinish = onFinish
  }

  /// The page that is showing.
  public var page: OnboardingPage { pages[index] }

  /// Whether the last page is showing.
  public var isLastPage: Bool { index == pages.count - 1 }

  /// Finds out whether on-device intelligence works here, and shows its page third if so.
  public func load() async {
    await telemetry.record("onboarding.flow.started")
    let availability = await intelligence.availability()
    guard availability.isAvailable, !isLastPage else { return }
    pages[pages.count - 1] = .ask
  }

  /// Goes to the next page, or finishes on the last.
  public func advance() async {
    if isLastPage {
      await finish()
    } else {
      index += 1
    }
  }

  /// Finishes the introduction after its last page.
  public func finish() async {
    await complete(recording: "onboarding.flow.completed")
  }

  /// Leaves the introduction early; it never returns uninvited.
  public func skip() async {
    await complete(recording: "onboarding.flow.skipped")
  }

  /// Marks first run as done before anything else is shown, so that leaving the app at whatever
  /// comes next (the subscription offer) leads to Home the next time.
  private func complete(recording event: String) async {
    var current = settings.load()
    current.hasCompletedOnboarding = true
    settings.save(current)
    await telemetry.record(event)
    onFinish(current)
  }
}
