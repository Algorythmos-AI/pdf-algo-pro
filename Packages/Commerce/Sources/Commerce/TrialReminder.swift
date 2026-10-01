import Foundation

/// When to remind the user that a trial is about to convert to a paid period (FR-STORE-006).
///
/// It only computes dates; scheduling a notification or showing a notice is the caller's work.
public enum TrialReminder {
  /// How long before the conversion the reminder is due: two days.
  public static let leadTime: TimeInterval = 2 * 24 * 60 * 60

  /// The moment to remind for a trial that ends at a date.
  public static func reminderDate(trialEndsAt: Date) -> Date {
    trialEndsAt.addingTimeInterval(-leadTime)
  }

  /// The moment to remind for an entitlement; `nil` unless it is a trial.
  public static func reminderDate(for entitlement: Entitlement) -> Date? {
    guard case .trial(let endsAt) = entitlement else { return nil }
    return reminderDate(trialEndsAt: endsAt)
  }

  /// Whether a reminder should be shown at launch.
  ///
  /// It is due when the entitlement is a trial, the reminder date has come, the trial has not ended,
  /// and no reminder was shown yet for a trial ending at that date (`lastRemindedTrialEnd`).
  public static func isDueAtLaunch(entitlement: Entitlement, now: Date, lastRemindedTrialEnd: Date?) -> Bool {
    guard case .trial(let endsAt) = entitlement, lastRemindedTrialEnd != endsAt else { return false }
    return now >= reminderDate(trialEndsAt: endsAt) && now < endsAt
  }
}
