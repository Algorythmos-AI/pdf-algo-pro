import Foundation

/// What the background check of a trial reminder works on: the pending notification and the next
/// check (#336).
@MainActor
public protocol TrialReminderHolding: AnyObject {
  /// Removes the pending reminder notification, and any background check asked for it.
  func removeReminder() async
  /// Asks the system to run the check again, not before a date.
  func scheduleCheck(at date: Date)
}

/// The check the app makes in the background shortly before a trial reminder is due (#336).
///
/// A reminder is a local notification scheduled when the trial starts; on its own it cannot see a
/// payment, a refund or a lapse that happens later, and the app removes it only when it runs and
/// sees the entitlement change. This check asks the App Store again from the device, with no request
/// of the app's own, and removes the reminder when the trial is no longer running. The system
/// decides whether and when the check runs, so the reminder's words stay true without it.
@MainActor
public struct TrialReminderCheck {
  /// What became of the reminder.
  public enum Outcome: Sendable, Equatable {
    /// The trial is no longer running: the reminder is removed.
    case removed
    /// The trial still runs: the reminder stays, and the check runs again from a date, if any.
    case kept(nextCheck: Date?)
  }

  private let entitlements: EntitlementStore
  private let reminder: any TrialReminderHolding
  private let now: @Sendable () -> Date

  /// Creates a check over the app's entitlement store and its reminder.
  public init(
    entitlements: EntitlementStore, reminder: any TrialReminderHolding,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.entitlements = entitlements
    self.reminder = reminder
    self.now = now
  }

  /// Reads the entitlement now and removes the reminder when the trial is no longer running.
  public func run() async -> Outcome {
    await entitlements.refresh()
    let entitlement = entitlements.entitlement
    let now = now()
    guard TrialReminder.keepsReminder(for: entitlement, now: now) else {
      await reminder.removeReminder()
      return .removed
    }
    guard case .trial(let endsAt) = entitlement, let next = TrialReminder.checkDate(trialEndsAt: endsAt, now: now)
    else { return .kept(nextCheck: nil) }
    reminder.scheduleCheck(at: next)
    return .kept(nextCheck: next)
  }
}
