import Core
import Foundation
import Observation

/// The first-run introduction (FR-ONB-001, FR-ONB-002, FR-ONB-006): three pages, one capability
/// each, skippable from every page, and never an account or a permission request.
///
/// The model knows nothing of the store. What follows the introduction (the subscription offer,
/// then Home) is the app's to decide in `onFinish`, and the last page stays up, its buttons at
/// rest, until `onFinish` returns.
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
  /// Whether the person has finished or skipped and the app is deciding what follows; the page
  /// shows that it is working, and a second tap does nothing.
  public private(set) var isFinishing = false

  private let settings: any SettingsStoring
  private let intelligence: any DocumentIntelligence
  private let telemetry: any TelemetryRecording
  private let onFinish: (AppSettings) async -> Void

  /// Creates the model; `onFinish` receives the saved settings when the person finishes or skips,
  /// and may take a moment over what it shows next.
  public init(
    settings: any SettingsStoring, intelligence: any DocumentIntelligence, telemetry: any TelemetryRecording,
    onFinish: @escaping (AppSettings) async -> Void
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
    await telemetry.record("onboarding.page.viewed")
    let availability = await intelligence.availability()
    guard availability.isAvailable, !isLastPage else { return }
    pages[pages.count - 1] = .ask
  }

  /// Goes to the next page, or finishes on the last.
  public func advance() async {
    guard !isFinishing else { return }
    if isLastPage {
      await finish()
    } else {
      index += 1
      await telemetry.record("onboarding.page.viewed")
    }
  }

  /// Goes to the page after this one, as a swipe does; on the last page a swipe does nothing, since
  /// only Continue ends the introduction.
  public func goForward() async {
    guard !isLastPage else { return }
    await advance()
  }

  /// Goes back a page, as a swipe does; nothing on the first.
  public func goBack() async {
    guard !isFinishing, index > 0 else { return }
    index -= 1
    await telemetry.record("onboarding.page.viewed")
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
    guard !isFinishing else { return }
    isFinishing = true
    var current = settings.load()
    current.hasCompletedOnboarding = true
    settings.save(current)
    await telemetry.record(event)
    await onFinish(current)
    isFinishing = false
  }
}
