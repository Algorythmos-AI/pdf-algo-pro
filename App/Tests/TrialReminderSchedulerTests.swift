import Commerce
import Foundation
import Synchronization
import Testing
import UserNotifications

@testable import PDFAlgoPro

/// Notifications that record what was asked of them.
private final class RecordingNotifications: NotificationScheduling {
  struct State {
    var allows = true
    var asked = 0
    var scheduled: [(identifier: String, title: String, body: String, interval: TimeInterval)] = []
    var cancelled: [String] = []
  }
  let state = Mutex(State())

  func requestAuthorization() async -> Bool {
    state.withLock {
      $0.asked += 1
      return $0.allows
    }
  }
  func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) async -> Bool {
    state.withLock { $0.scheduled.append((identifier, title, body, interval)) }
    return true
  }
  func cancel(identifier: String) async { state.withLock { $0.cancelled.append(identifier) } }
}

/// Background checks that record what was asked of them.
private final class RecordingChecks: BackgroundChecking {
  struct State {
    var scheduled: [(identifier: String, date: Date)] = []
    var cancelled: [String] = []
  }
  let state = Mutex(State())

  func schedule(identifier: String, at date: Date) { state.withLock { $0.scheduled.append((identifier, date)) } }
  func cancel(identifier: String) { state.withLock { $0.cancelled.append(identifier) } }
}

@MainActor
@Suite("The trial reminder's scheduling (FR-STORE-006)")
struct TrialReminderSchedulerTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let day: TimeInterval = 24 * 60 * 60

  private func make() -> (TrialReminderScheduler, RecordingNotifications) {
    let (scheduler, notifications, _) = makeWithChecks()
    return (scheduler, notifications)
  }

  private func makeWithChecks() -> (TrialReminderScheduler, RecordingNotifications, RecordingChecks) {
    let notifications = RecordingNotifications()
    let checks = RecordingChecks()
    let fixed = now
    let defaults = UserDefaults(suiteName: "reminder-tests-\(UUID().uuidString)") ?? .standard
    let scheduler = TrialReminderScheduler(notifications: notifications, checks: checks, defaults: defaults) { fixed }
    return (scheduler, notifications, checks)
  }

  @Test("Without a notification, the app says once that the trial ends within a day (FR-STORE-006)")
  func notice() {
    let (scheduler, _) = make()
    let soon = now.addingTimeInterval(day / 2)
    #expect(scheduler.noticeDue(for: .trial(endsAt: now.addingTimeInterval(3 * day))) == nil, "Not yet")
    #expect(scheduler.noticeDue(for: .trial(endsAt: soon)) == soon)
    #expect(scheduler.noticeDue(for: .trial(endsAt: soon)) == nil, "Once per trial")
    #expect(scheduler.noticeDue(for: .trial(endsAt: now.addingTimeInterval(day / 4))) != nil, "A later trial is new")
    for entitlement in [Entitlement?.none, Entitlement.none, .subscribed, .expired] {
      #expect(scheduler.noticeDue(for: entitlement) == nil)
    }
  }

  @Test("A trial with a notification scheduled gets no in-app notice as well; turning it off brings the notice back")
  func noticeOrNotification() async {
    let (scheduler, _) = make()
    let end = now.addingTimeInterval(day + 60)
    #expect(await scheduler.set(true, trialEndsAt: end) == .scheduled)
    #expect(scheduler.noticeDue(for: .trial(endsAt: end)) == nil)
    #expect(await scheduler.set(false, trialEndsAt: end) == .off)
    // Still more than a day away, so not due yet; the trial is no longer marked as reminded.
    #expect(scheduler.noticeDue(for: .trial(endsAt: end)) == nil)
  }

  @Test("Turned on, one reminder is scheduled a day before the trial ends, replacing any other")
  func on() async {
    let (scheduler, notifications) = make()
    let end = now.addingTimeInterval(3 * day)
    #expect(await scheduler.set(true, trialEndsAt: end) == .scheduled)
    let state = notifications.state.withLock { $0 }
    #expect(state.cancelled == [TrialReminderScheduler.identifier], "An earlier reminder goes first")
    #expect(state.asked == 1 && state.scheduled.count == 1)
    #expect(state.scheduled.first?.identifier == TrialReminderScheduler.identifier)
    #expect(state.scheduled.first?.interval == 2 * day, "Due a day before the end, which is three days away")
    #expect(state.scheduled.first?.title.isEmpty == false && state.scheduled.first?.body.isEmpty == false)
  }

  @Test("The reminder's words stay true for someone who paid, changed plans or was refunded before it arrived (#264)")
  func wordsStayTrue() async throws {
    let (scheduler, notifications) = make()
    let end = now.addingTimeInterval(3 * day)
    #expect(await scheduler.set(true, trialEndsAt: end) == .scheduled)
    let scheduled = try #require(notifications.state.withLock { $0.scheduled.first })
    let words = "\(scheduled.title) / \(scheduled.body)"
    #expect(
      !words.contains("trial ends") && scheduled.body.contains("still running"),
      "The reminder states the trial's end as a fact, which is false once it was paid or refunded: \(words)")
    let expected = TrialReminderScheduler.words()
    #expect(scheduled.title == expected.title && scheduled.body == expected.body)
  }

  @Test("A change of time zone after scheduling moves neither when the reminder fires nor what it says (#246, #264)")
  func timeZoneChange() async throws {
    let (scheduler, notifications) = make()
    // 00:30 UTC: 01:30 on 19 January in Paris and Auckland's afternoon, 19:30 on 18 January in New York.
    let end = now.addingTimeInterval(3 * day + 16.5 * 60 * 60)
    #expect(await scheduler.set(true, trialEndsAt: end) == .scheduled)
    let scheduled = try #require(notifications.state.withLock { $0.scheduled.first })
    let zones = ["Europe/Paris", "America/New_York", "Pacific/Auckland"].compactMap(TimeZone.init(identifier:))
    #expect(zones.count == 3)
    for zone in zones {
      var style = Date.FormatStyle.dateTime.day().month(.wide)
      style.timeZone = zone
      let day = end.formatted(style)
      #expect(
        !scheduled.body.contains(day),
        "The words name the end as \(day), which is the wrong day in another time zone: \(scheduled.body)")
    }
    let trigger = try #require(
      SystemNotifications.trigger(after: scheduled.interval),
      "The reminder must fire after an elapsed interval, not at calendar components that float with the zone")
    #expect(trigger.timeInterval == end.addingTimeInterval(-day).timeIntervalSince(now) && !trigger.repeats)
    #expect(SystemNotifications.trigger(after: 0) == nil && SystemNotifications.trigger(after: -day) == nil)
  }

  @Test("Turned off, the reminder is removed and permission is not asked for")
  func off() async {
    let (scheduler, notifications) = make()
    #expect(await scheduler.set(false, trialEndsAt: now.addingTimeInterval(3 * day)) == .off)
    let state = notifications.state.withLock { $0 }
    #expect(state.cancelled.count == 1 && state.asked == 0 && state.scheduled.isEmpty)
  }

  @Test("When notifications are declined, nothing is scheduled and the answer says so")
  func declined() async {
    let (scheduler, notifications) = make()
    notifications.state.withLock { $0.allows = false }
    #expect(await scheduler.set(true, trialEndsAt: now.addingTimeInterval(3 * day)) == .notificationsDeclined)
    #expect(notifications.state.withLock { $0.scheduled.isEmpty })
  }

  @Test("With less than a day of the trial left there is nothing to schedule, nobody is asked, and the answer says so")
  func tooLate() async {
    let (scheduler, notifications) = make()
    #expect(await scheduler.set(true, trialEndsAt: now.addingTimeInterval(day / 2)) == .tooLate)
    let state = notifications.state.withLock { $0 }
    #expect(state.asked == 0 && state.scheduled.isEmpty)
  }

  @Test("A reminder is kept while the trial runs or nothing is known, and removed otherwise")
  func entitlementChanges() async {
    let (scheduler, notifications) = make()
    await scheduler.entitlementChanged(.trial(endsAt: now.addingTimeInterval(day)))
    await scheduler.entitlementChanged(nil)
    #expect(notifications.state.withLock { $0.cancelled.isEmpty })
    let over: [Entitlement] = [
      .subscribed, .expired, .revoked, Entitlement.none, .inGracePeriod, .inBillingRetry,
      .trial(endsAt: now.addingTimeInterval(-day)),
    ]
    for entitlement in over { await scheduler.entitlementChanged(entitlement) }
    #expect(notifications.state.withLock { $0.cancelled.count } == over.count)
  }

  @Test("A scheduled reminder asks for a background check before it is due, and removing it withdraws the check (#336)")
  func backgroundCheck() async throws {
    let (scheduler, notifications, checks) = makeWithChecks()
    let end = now.addingTimeInterval(3 * day)
    #expect(await scheduler.set(true, trialEndsAt: end) == .scheduled)
    let check = try #require(checks.state.withLock { $0.scheduled.first })
    #expect(check.identifier == TrialReminderScheduler.checkIdentifier)
    #expect(check.identifier.hasSuffix(".trial-reminder-check"), "Info.plist permits this identifier only")
    #expect(check.date == TrialReminder.checkDate(trialEndsAt: end, now: now))
    #expect(check.date < end.addingTimeInterval(-day), "The check may come before the reminder")

    await scheduler.entitlementChanged(.subscribed)
    #expect(notifications.state.withLock { $0.cancelled.last } == TrialReminderScheduler.identifier)
    #expect(checks.state.withLock { $0.cancelled.last } == TrialReminderScheduler.checkIdentifier)
  }

  @Test("The background check removes the reminder of a trial paid or refunded meanwhile (#336)")
  func backgroundCheckRemoves() async {
    for entitlement: Entitlement in [.subscribed, .revoked] {
      let (scheduler, notifications, checks) = makeWithChecks()
      #expect(await scheduler.set(true, trialEndsAt: now.addingTimeInterval(3 * day)) == .scheduled)
      let store = EntitlementStore(provider: FixedEntitlements(entitlement)) { [now] in now }
      let outcome = await TrialReminderCheck(entitlements: store, reminder: scheduler) { [now] in now }.run()
      #expect(outcome == .removed)
      // Once on turning the reminder on, once by the check.
      #expect(notifications.state.withLock { $0.cancelled.count } == 2, "\(entitlement)")
      #expect(checks.state.withLock { $0.cancelled.count } == 2, "\(entitlement)")
    }
  }

  @Test("UI tests schedule nothing and are never asked")
  func silent() async {
    let silent = SilentNotifications()
    #expect(await silent.requestAuthorization())
    #expect(await silent.schedule(identifier: "x", title: "t", body: "b", after: day))
    await silent.cancel(identifier: "x")
    NoBackgroundChecks().schedule(identifier: "x", at: now)
    NoBackgroundChecks().cancel(identifier: "x")
  }
}
