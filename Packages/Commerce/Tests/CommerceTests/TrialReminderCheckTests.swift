import CommerceTestSupport
import Foundation
import Testing

@testable import Commerce

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 60 * 60
private let day: TimeInterval = 24 * hour

/// A pending reminder and the background check that may come for it, as the app keeps them.
@MainActor
private final class PendingReminder: TrialReminderHolding {
  var isPending = true
  var checks: [Date] = []

  func removeReminder() async { isPending = false }
  func scheduleCheck(at date: Date) { checks.append(date) }
}

@MainActor
@Suite("The trial reminder's background check (#336)")
struct TrialReminderCheckTests {
  private typealias Checked = (outcome: TrialReminderCheck.Outcome, reminder: PendingReminder)

  /// Runs the check at a moment, with the App Store reporting an entitlement then.
  private func check(_ entitlement: Entitlement, at moment: Date = now) async -> Checked {
    let reminder = PendingReminder()
    let store = EntitlementStore(provider: FakeEntitlements(entitlement)) { moment }
    let outcome = await TrialReminderCheck(entitlements: store, reminder: reminder) { moment }.run()
    return (outcome, reminder)
  }

  @Test("Paid, refunded, lapsed or ended without the app being opened, the pending reminder is removed")
  func removed() async {
    let over: [Entitlement] = [
      .subscribed, .revoked, .expired, .inGracePeriod, .inBillingRetry, .none,
      .trial(endsAt: now.addingTimeInterval(-hour)),
    ]
    for entitlement in over {
      let (outcome, reminder) = await check(entitlement)
      #expect(outcome == .removed, "\(entitlement)")
      #expect(!reminder.isPending, "A reminder is still pending for \(entitlement)")
      #expect(reminder.checks.isEmpty, "Nothing is left to check for \(entitlement)")
    }
  }

  @Test("While the trial runs the reminder stays, and the check comes again until the reminder is due")
  func kept() async {
    let end = now.addingTimeInterval(3 * day)
    let reminderDate = TrialReminder.reminderDate(trialEndsAt: end)
    let (early, first) = await check(.trial(endsAt: end))
    #expect(first.isPending)
    #expect(early == .kept(nextCheck: reminderDate.addingTimeInterval(-TrialReminder.checkLead)))
    #expect(first.checks == [reminderDate.addingTimeInterval(-TrialReminder.checkLead)])

    let late = reminderDate.addingTimeInterval(-4 * hour)
    let (again, second) = await check(.trial(endsAt: end), at: late)
    #expect(second.isPending)
    #expect(again == .kept(nextCheck: late.addingTimeInterval(TrialReminder.checkInterval)))

    let (last, third) = await check(.trial(endsAt: end), at: reminderDate.addingTimeInterval(-hour))
    #expect(third.isPending && third.checks.isEmpty, "Nothing to check once the reminder is about to fire")
    #expect(last == .kept(nextCheck: nil))
  }

  @Test("The first check of a new trial is due before its reminder, and none once the reminder is due")
  func checkDate() {
    let end = now.addingTimeInterval(3 * day)
    let reminderDate = TrialReminder.reminderDate(trialEndsAt: end)
    #expect(
      TrialReminder.checkDate(trialEndsAt: end, now: now) == reminderDate.addingTimeInterval(-TrialReminder.checkLead))
    #expect(TrialReminder.checkDate(trialEndsAt: end, now: reminderDate) == nil)
    #expect(TrialReminder.checkDate(trialEndsAt: now.addingTimeInterval(day / 2), now: now) == nil)
  }

  @Test("Only a running trial, or an entitlement not known yet, keeps a reminder")
  func keeps() {
    #expect(TrialReminder.keepsReminder(for: nil, now: now))
    #expect(TrialReminder.keepsReminder(for: .trial(endsAt: now.addingTimeInterval(hour)), now: now))
    #expect(!TrialReminder.keepsReminder(for: .trial(endsAt: now), now: now))
    for entitlement: Entitlement in [.none, .subscribed, .inGracePeriod, .inBillingRetry, .expired, .revoked] {
      #expect(!TrialReminder.keepsReminder(for: entitlement, now: now), "\(entitlement)")
    }
  }
}
