import Commerce
import Foundation
import Synchronization
import Testing

@testable import PDFAlgoPro

/// Notifications that record what was asked of them.
private final class RecordingNotifications: NotificationScheduling {
  struct State {
    var allows = true
    var asked = 0
    var scheduled: [(identifier: String, title: String, body: String, date: Date)] = []
    var cancelled: [String] = []
  }
  let state = Mutex(State())

  func requestAuthorization() async -> Bool {
    state.withLock {
      $0.asked += 1
      return $0.allows
    }
  }
  func schedule(identifier: String, title: String, body: String, at date: Date) async -> Bool {
    state.withLock { $0.scheduled.append((identifier, title, body, date)) }
    return true
  }
  func cancel(identifier: String) async { state.withLock { $0.cancelled.append(identifier) } }
}

@MainActor
@Suite("The trial reminder's scheduling (FR-STORE-006)")
struct TrialReminderSchedulerTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let day: TimeInterval = 24 * 60 * 60

  private func make() -> (TrialReminderScheduler, RecordingNotifications) {
    let notifications = RecordingNotifications()
    let fixed = now
    return (TrialReminderScheduler(notifications: notifications) { fixed }, notifications)
  }

  @Test("Turned on, one reminder is scheduled a day before the trial ends, replacing any other")
  func on() async {
    let (scheduler, notifications) = make()
    let end = now.addingTimeInterval(3 * day)
    #expect(await scheduler.set(true, trialEndsAt: end))
    let state = notifications.state.withLock { $0 }
    #expect(state.cancelled == [TrialReminderScheduler.identifier], "An earlier reminder goes first")
    #expect(state.asked == 1 && state.scheduled.count == 1)
    #expect(state.scheduled.first?.identifier == TrialReminderScheduler.identifier)
    #expect(state.scheduled.first?.date == end.addingTimeInterval(-day))
    #expect(state.scheduled.first?.title.isEmpty == false && state.scheduled.first?.body.isEmpty == false)
  }

  @Test("Turned off, the reminder is removed and permission is not asked for")
  func off() async {
    let (scheduler, notifications) = make()
    #expect(await !scheduler.set(false, trialEndsAt: now.addingTimeInterval(3 * day)))
    let state = notifications.state.withLock { $0 }
    #expect(state.cancelled.count == 1 && state.asked == 0 && state.scheduled.isEmpty)
  }

  @Test("When notifications are declined, nothing is scheduled and the answer is no")
  func declined() async {
    let (scheduler, notifications) = make()
    notifications.state.withLock { $0.allows = false }
    #expect(await !scheduler.set(true, trialEndsAt: now.addingTimeInterval(3 * day)))
    #expect(notifications.state.withLock { $0.scheduled.isEmpty })
  }

  @Test("With less than a day of the trial left there is nothing to schedule, and nobody is asked")
  func tooLate() async {
    let (scheduler, notifications) = make()
    #expect(await !scheduler.set(true, trialEndsAt: now.addingTimeInterval(day / 2)))
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

  @Test("UI tests schedule nothing and are never asked")
  func silent() async {
    let silent = SilentNotifications()
    #expect(await silent.requestAuthorization())
    #expect(await silent.schedule(identifier: "x", title: "t", body: "b", at: now))
    await silent.cancel(identifier: "x")
  }
}
