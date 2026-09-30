import Core
import Foundation
import Observation

/// Asks for a rating at a calm moment after real successes (plan revision 3, §6).
///
/// Successes and errors come from the on-device telemetry events. When `ReviewPolicy` says a rating is
/// due, the request waits until the person closes a document or a sheet, so it never interrupts work.
/// UI tests never see it.
@MainActor
@Observable
final class ReviewPrompter {
  @ObservationIgnored private var policy: ReviewPolicy
  @ObservationIgnored private var sessionHadError = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let version: String
  @ObservationIgnored private let isEnabled: Bool
  @ObservationIgnored private let now: () -> Date
  private static let key = "review.policy.v1"

  init(
    defaults: UserDefaults = .standard, version: String, isEnabled: Bool, now: @escaping () -> Date = { Date() }
  ) {
    self.defaults = defaults
    self.version = version
    self.isEnabled = isEnabled
    self.now = now
    policy =
      defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ReviewPolicy.self, from: $0) }
      ?? ReviewPolicy()
    policy.startSession()
    save()
  }

  /// Takes in one telemetry event.
  func handle(_ event: String) {
    if ReviewPolicy.errorEvents.contains(event) {
      sessionHadError = true
    } else if ReviewPolicy.successEvents.contains(event) {
      policy.recordSuccess(on: ReviewPolicy.day(of: now()))
      save()
    }
  }

  /// Whether to ask now, at a calm moment; asking is recorded, so it happens once per version.
  func shouldAskNow() -> Bool {
    guard isEnabled, policy.isDue(version: version, sessionHadError: sessionHadError) else { return false }
    policy.asked(in: version)
    save()
    return true
  }

  private func save() {
    if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: Self.key) }
  }
}
