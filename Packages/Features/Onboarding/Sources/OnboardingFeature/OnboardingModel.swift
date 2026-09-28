import Core
import Foundation
import Observation

/// The onboarding intent picker (FR-ONB-001 to FR-ONB-004): one optional question, AI-first options
/// on top, skippable, and never a paywall, account or permission request.
@MainActor
@Observable
public final class OnboardingModel {
  /// The options, in the fixed order.
  public let intents = OnboardingIntent.allCases
  /// The chosen intents, in the order they were chosen; the first leads the home screen.
  public private(set) var selected: [OnboardingIntent] = []
  /// Whether document intelligence can run on this device, once known.
  public private(set) var availability: IntelligenceAvailability?

  private let settings: any SettingsStoring
  private let intelligence: any DocumentIntelligence
  private let telemetry: any TelemetryRecording
  private let onFinish: (AppSettings) -> Void

  /// Creates the model; `onFinish` receives the saved settings when the user continues or skips.
  public init(
    settings: any SettingsStoring, intelligence: any DocumentIntelligence, telemetry: any TelemetryRecording,
    onFinish: @escaping (AppSettings) -> Void
  ) {
    self.settings = settings
    self.intelligence = intelligence
    self.telemetry = telemetry
    self.onFinish = onFinish
    selected = settings.load().intents
  }

  /// Checks intelligence availability, so AI options can explain themselves (FR-ONB-006).
  public func load() async {
    await telemetry.record("onboarding.flow.started")
    availability = await intelligence.availability()
  }

  /// The AI-first options.
  public var askAndUnderstand: [OnboardingIntent] { intents.filter(\.usesIntelligence) }
  /// The other options.
  public var workWithPDFs: [OnboardingIntent] { intents.filter { !$0.usesIntelligence } }

  /// Whether an intent is chosen.
  public func isSelected(_ intent: OnboardingIntent) -> Bool {
    selected.contains(intent)
  }

  /// Chooses or un-chooses an intent.
  public func toggle(_ intent: OnboardingIntent) {
    if let index = selected.firstIndex(of: intent) {
      selected.remove(at: index)
    } else {
      selected.append(intent)
    }
  }

  /// Whether AI options should carry the "needs Apple Intelligence" note.
  public var intelligenceNeedsNote: Bool {
    guard let availability else { return false }
    return !availability.isAvailable
  }

  /// Saves the choice and finishes onboarding.
  public func finish() async {
    var current = settings.load()
    current.intents = selected
    current.hasCompletedOnboarding = true
    settings.save(current)
    for _ in selected { await telemetry.record("onboarding.intent.selected") }
    await telemetry.record("onboarding.flow.completed")
    onFinish(current)
  }

  /// Skips the question; it never returns uninvited and stays in Settings.
  public func skip() async {
    var current = settings.load()
    current.hasCompletedOnboarding = true
    settings.save(current)
    await telemetry.record("onboarding.flow.skipped")
    onFinish(current)
  }
}
