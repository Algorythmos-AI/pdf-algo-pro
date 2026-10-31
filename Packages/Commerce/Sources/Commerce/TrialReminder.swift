import Foundation

/// What became of turning the trial reminder on or off.
public enum TrialReminderOutcome: Sendable, Equatable {
  /// A notification is scheduled for the day before the trial ends.
  case scheduled
  /// No reminder, as asked.
  case off
  /// No reminder: the person has not allowed notifications.
  case notificationsDeclined
  /// No reminder: less than a day of the trial is left, so its day before has passed.
  case tooLate
  /// No reminder: the system did not schedule it.
  case failed
}

/// When to remind the user that a trial is about to convert to a paid period (FR-STORE-006).
///
/// It only computes dates; scheduling a notification or showing a notice is the caller's work.
public enum TrialReminder {
  /// How long before the trial ends the reminder is due: one day of the annual plan's three-day trial
  /// (ADR-0026, PAP-049; it was two days for the earlier seven-day trial).
  public static let leadTime: TimeInterval = 24 * 60 * 60

  /// The moment to remind for a trial that ends at a date.
  public static func reminderDate(trialEndsAt: Date) -> Date {
    trialEndsAt.addingTimeInterval(-leadTime)
  }

  /// The moment to remind for an entitlement; `nil` unless it is a trial.
  public static func reminderDate(for entitlement: Entitlement) -> Date? {
    guard case .trial(let endsAt) = entitlement else { return nil }
    return reminderDate(trialEndsAt: endsAt)
  }

  /// The moment to schedule a notification for.
  ///
  /// It is `nil` unless the entitlement is a trial whose reminder date is still ahead; a trial with
  /// less than the lead time left gets the in-app notice instead.
  public static func notificationDate(for entitlement: Entitlement, now: Date) -> Date? {
    guard let date = reminderDate(for: entitlement), date > now else { return nil }
    return date
  }

  /// Whether a reminder can still be set for a trial that ends at a date: its day before is ahead.
  public static func canRemind(trialEndsAt: Date, now: Date) -> Bool {
    notificationDate(for: .trial(endsAt: trialEndsAt), now: now) != nil
  }

  /// Whether a pending reminder still has something to say: the trial is running, or the entitlement
  /// is not known yet.
  ///
  /// A paid period, a grace period or a billing retry, an expiry, a refund, no purchase at all, or a
  /// trial whose end has passed leave it nothing (#264, #336).
  public static func keepsReminder(for entitlement: Entitlement?, now: Date) -> Bool {
    guard let entitlement else { return true }
    guard case .trial(let endsAt) = entitlement else { return false }
    return endsAt > now
  }

  /// How long before the reminder is due the background check may first run (#336).
  ///
  /// The system runs it when it sees fit after that, often hours later, so it starts early enough to
  /// have a chance of coming before the reminder.
  public static let checkLead: TimeInterval = 12 * 60 * 60

  /// How long after one background check the next may run, while the trial still runs (#336).
  public static let checkInterval: TimeInterval = 3 * 60 * 60

  /// The earliest moment for the next background check of a trial's reminder.
  ///
  /// It is `checkLead` before the reminder is due, or `checkInterval` from now when that has passed;
  /// `nil` when that would not come before the reminder, which then fires as it is.
  public static func checkDate(trialEndsAt: Date, now: Date) -> Date? {
    let due = reminderDate(trialEndsAt: trialEndsAt)
    let date = max(due.addingTimeInterval(-checkLead), now.addingTimeInterval(checkInterval))
    return date < due ? date : nil
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
