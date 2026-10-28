import Commerce
import Foundation
import UserNotifications

/// What the trial reminder needs from the system's notifications.
protocol NotificationScheduling: Sendable {
  /// Asks the person to allow notifications; `true` when they are, or already were, allowed.
  func requestAuthorization() async -> Bool
  /// Schedules one notification to arrive after an interval, replacing any with the same identifier.
  ///
  /// - Returns: `false` when it failed or the interval is not ahead.
  func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) async -> Bool
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

  func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) async -> Bool {
    guard let trigger = Self.trigger(after: interval) else { return false }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    return (try? await UNUserNotificationCenter.current().add(request)) != nil
  }

  func cancel(identifier: String) async {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
  }

  /// A trigger that fires once after an interval, measured in elapsed time; `nil` when it is not ahead.
  ///
  /// Not a calendar trigger: one built from date components floats with the time zone, so after a
  /// flight it would fire hours early or late, possibly after the trial has been charged (#246).
  static func trigger(after interval: TimeInterval) -> UNTimeIntervalNotificationTrigger? {
    interval > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false) : nil
  }
}

/// Notifications that are always allowed and never shown, for UI tests.
struct SilentNotifications: NotificationScheduling {
  func requestAuthorization() async -> Bool { true }
  func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) async -> Bool {
    true
  }
  func cancel(identifier: String) async {}
}

/// Schedules the reminder that a trial is about to end (FR-STORE-006, ADR-0026).
///
/// There is at most one, a day before the trial ends. It is asked for on the purchase confirmation,
/// the only place the app asks to send notifications, and it is removed as soon as the entitlement
/// is no longer a trial: after a cancellation that has run out, a refund or the first paid period.
/// The app learns of those only while it runs, so a reminder can still arrive for someone who has
/// paid, changed plans or been refunded since without opening it; its words stay true then too (#264).
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
  /// - Returns: Whether a reminder is now scheduled, and why not when it isn't: the person turned it
  ///   off, declined notifications, or less than a day of the trial is left.
  func set(_ isOn: Bool, trialEndsAt: Date) async -> TrialReminderOutcome {
    await notifications.cancel(identifier: Self.identifier)
    if remindedTrialEnd == trialEndsAt { remindedTrialEnd = nil }
    guard isOn else { return .off }
    guard let date = TrialReminder.notificationDate(for: .trial(endsAt: trialEndsAt), now: now()) else {
      return .tooLate
    }
    guard await notifications.requestAuthorization() else { return .notificationsDeclined }
    let words = Self.words()
    let scheduled = await notifications.schedule(
      identifier: Self.identifier, title: words.title, body: words.body, after: date.timeIntervalSince(now()))
    // The notification is the reminder for this trial; the in-app notice then stays away.
    if scheduled { remindedTrialEnd = trialEndsAt }
    return scheduled ? .scheduled : .failed
  }

  /// The reminder's title and body.
  ///
  /// They say what is true when the reminder arrives whatever happened to the trial meanwhile: the
  /// trial ends within a day if it is still running. They name no date, which would be written in
  /// the time zone of the moment it was scheduled and could be the wrong day where it is read.
  static func words() -> (title: String, body: String) {
    let body = String(
      localized:
        "If your PDF Algo Pro trial is still running, it ends within a day. To manage or cancel it, open the Settings app, tap your name (Apple Account), then Subscriptions.")
    return (String(localized: "Trial reminder"), body)
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
