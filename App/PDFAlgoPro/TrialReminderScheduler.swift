import Commerce
import Foundation
import UserNotifications

/// What the trial reminder needs from the system's notifications.
protocol NotificationScheduling: Sendable {
  /// Asks the person to allow notifications; `true` when they are, or already were, allowed.
  func requestAuthorization() async -> Bool
  /// Schedules one notification, replacing any with the same identifier; `false` when it failed.
  func schedule(identifier: String, title: String, body: String, at date: Date) async -> Bool
  /// Removes a notification that has not been delivered yet.
  func cancel(identifier: String) async
}

/// The system's notifications.
///
/// The adapter alone: asking for permission shows a system prompt, so unit and UI tests use a
/// stand-in and the device smoke test covers this.
struct SystemNotifications: NotificationScheduling {
  func requestAuthorization() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
  }

  func schedule(identifier: String, title: String, body: String, at date: Date) async -> Bool {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    return (try? await UNUserNotificationCenter.current().add(request)) != nil
  }

  func cancel(identifier: String) async {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
  }
}

/// Notifications that are always allowed and never shown, for UI tests.
struct SilentNotifications: NotificationScheduling {
  func requestAuthorization() async -> Bool { true }
  func schedule(identifier: String, title: String, body: String, at date: Date) async -> Bool { true }
  func cancel(identifier: String) async {}
}

/// Schedules the reminder that a trial is about to end (FR-STORE-006, ADR-0026).
///
/// There is at most one, a day before the trial ends. It is asked for on the purchase confirmation,
/// the only place the app asks to send notifications, and it is removed as soon as the entitlement
/// is no longer a trial: after a cancellation that has run out, a refund or the first paid period.
/// Its words are true whether or not the person has already cancelled.
@MainActor
final class TrialReminderScheduler {
  static let identifier = "commerce.trial.reminder"

  /// Where the scheduler remembers which trial it has reminded of, or will.
  static let key = "commerce.trial.reminded"

  private let notifications: any NotificationScheduling
  private let defaults: UserDefaults
  private let now: @Sendable () -> Date

  init(
    notifications: any NotificationScheduling, defaults: UserDefaults = .standard,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.notifications = notifications
    self.defaults = defaults
    self.now = now
  }

  /// The end of the trial that a notification is scheduled for, or that the in-app notice was shown for.
  private var remindedTrialEnd: Date? {
    get { defaults.object(forKey: Self.key) as? Date }
    set { defaults.set(newValue, forKey: Self.key) }
  }

  /// Turns the reminder on or off for a trial that ends at a date.
  ///
  /// - Returns: Whether a reminder is now scheduled. It is not when the person declines
  ///   notifications, or when less than a day of the trial is left.
  func set(_ isOn: Bool, trialEndsAt: Date) async -> Bool {
    await notifications.cancel(identifier: Self.identifier)
    if remindedTrialEnd == trialEndsAt { remindedTrialEnd = nil }
    guard isOn, let date = TrialReminder.notificationDate(for: .trial(endsAt: trialEndsAt), now: now()),
      await notifications.requestAuthorization()
    else { return false }
    let day = trialEndsAt.formatted(.dateTime.day().month(.wide))
    let scheduled = await notifications.schedule(
      identifier: Self.identifier, title: String(localized: "Your trial ends tomorrow"),
      body: String(localized: "Your PDF Algo Pro trial ends on \(day). Manage it in Settings, under Subscription."),
      at: date)
    // The notification is the reminder for this trial; the in-app notice then stays away.
    if scheduled { remindedTrialEnd = trialEndsAt }
    return scheduled
  }

  /// The in-app notice for someone with no notification: the trial's end, when it is a day away or less.
  ///
  /// It is given once per trial, and never for a trial a notification was scheduled for
  /// (FR-STORE-006: "a local notification if the user allows it, otherwise an in-app notice").
  ///
  /// - Returns: The date to show, or `nil` when there is nothing to say now.
  func noticeDue(for entitlement: Entitlement?) -> Date? {
    guard let entitlement, case .trial(let endsAt) = entitlement,
      TrialReminder.isDueAtLaunch(entitlement: entitlement, now: now(), lastRemindedTrialEnd: remindedTrialEnd)
    else { return nil }
    remindedTrialEnd = endsAt
    return endsAt
  }

  /// The entitlement changed: a reminder for a trial that is over, refunded or paid is removed.
  func entitlementChanged(_ entitlement: Entitlement?) async {
    // Nothing known yet, or a trial still running: the reminder stays.
    guard let entitlement else { return }
    if case .trial(let endsAt) = entitlement, endsAt > now() { return }
    await notifications.cancel(identifier: Self.identifier)
  }
}
