import Foundation
import Synchronization

/// Something the free tier lets a person do a limited number of times a day (FR-STORE-001, PAP-044).
///
/// Only actions that make something new are metered. Nothing a person does with a document they
/// already have is here: those are `DocumentOperation`s, which no entitlement gates (FR-STORE-004).
public enum MeteredAction: String, Sendable, CaseIterable, Codable {
  /// Saving a scan as a document.
  case scan
  /// Asking the on-device intelligence for a summary, an answer or an extraction.
  case intelligenceRequest
}

/// How many times a day the free tier allows each metered action.
public struct AllowanceLimits: Sendable, Equatable {
  /// Scans saved per day.
  public var scans: Int
  /// Intelligence requests per day.
  public var intelligenceRequests: Int

  /// Creates limits.
  public init(scans: Int, intelligenceRequests: Int) {
    self.scans = scans
    self.intelligenceRequests = intelligenceRequests
  }

  /// The limit for an action.
  public func limit(for action: MeteredAction) -> Int {
    switch action {
    case .scan: scans
    case .intelligenceRequest: intelligenceRequests
    }
  }

  /// The free tier's limits.
  ///
  /// `Assumption:` three scans and five requests a day leave the free tier useful for an occasional
  /// task; the owner sets the numbers from research (PRD open question OQ-2).
  public static let free = AllowanceLimits(scans: 3, intelligenceRequests: 5)
}

extension FeatureGate {
  /// Whether a metered action may start: always with Pro, otherwise while the day's count is below its limit.
  public static func isAllowed(
    _ action: MeteredAction, usedToday: Int, limits: AllowanceLimits, entitlement: Entitlement, now: Date
  ) -> Bool {
    entitlement.grantsPro(at: now) || usedToday < limits.limit(for: action)
  }
}

/// Where the day's counts are kept.
public protocol AllowanceStoring: Sendable {
  /// The stored counts; `nil` when nothing was stored.
  func load() -> Data?
  /// Replaces the stored counts.
  func save(_ data: Data)
}

/// Counts in `UserDefaults` (declared in the privacy manifest, reason CA92.1).
public final class UserDefaultsAllowanceStore: AllowanceStoring, @unchecked Sendable {
  // `UserDefaults` is thread-safe; it is not marked `Sendable` in the SDK.
  private let defaults: UserDefaults
  private let key: String

  /// Creates a store over a defaults domain.
  public init(defaults: UserDefaults = .standard, key: String = "commerce.allowance.v1") {
    self.defaults = defaults
    self.key = key
  }

  /// The stored counts.
  public func load() -> Data? { defaults.data(forKey: key) }

  /// Stores the counts.
  public func save(_ data: Data) { defaults.set(data, forKey: key) }
}

/// The free tier's daily allowance, counted on this device (ADR-0026).
///
/// A call site asks `isAllowed` before the action starts and calls `recordSuccess` only once it has
/// succeeded, so a failed scan or request costs nothing and work already done is never refused. The
/// counts start again on a new calendar day: a Gregorian day in the device's time zone as it is when
/// the counts are read, whatever calendar the person uses (#245). They are about this device:
/// reinstalling the app clears them, which is accepted, since anything stronger needs an account or a
/// server.
public actor UsageAllowance {
  private struct Counts: Codable, Equatable {
    /// The day the counts are for, as year, month and day in the Gregorian calendar.
    var day: [Int]
    var used: [String: Int]
  }

  private let limits: AllowanceLimits
  private let store: any AllowanceStoring
  private let timeZone: TimeZone?
  private let now: @Sendable () -> Date
  private let isUnlimited: Bool
  /// Units held for actions under way (`reserve`).
  ///
  /// They live in memory only, and outside the actor's isolation, so that a cancelled action gives its
  /// unit back at once, before anything started in its place asks.
  private nonisolated let held = Mutex<Set<Reservation>>([])

  /// Creates the allowance.
  ///
  /// With `isUnlimited` it never refuses and never counts: UI tests that are not about the allowance use it.
  /// Only the time zone of `calendar` is used, and without one the device's current time zone is read
  /// each time; the day is always a Gregorian day, so changing calendars never moves it.
  public init(
    limits: AllowanceLimits = .free, store: any AllowanceStoring, calendar: Calendar? = nil,
    isUnlimited: Bool = false, now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.limits = limits
    self.store = store
    self.timeZone = calendar?.timeZone
    self.isUnlimited = isUnlimited
    self.now = now
  }

  /// How many times an action was done today.
  public func usedToday(_ action: MeteredAction) -> Int {
    counts().used[action.rawValue] ?? 0
  }

  /// How many times an action can still be done today without Pro.
  public func remainingToday(_ action: MeteredAction) -> Int {
    isUnlimited ? .max : max(0, limits.limit(for: action) - usedToday(action))
  }

  /// Whether an action may start; units held for actions under way count as used (#265).
  public func isAllowed(_ action: MeteredAction, entitlement: Entitlement) -> Bool {
    isUnlimited
      || FeatureGate.isAllowed(
        action, usedToday: usedToday(action) + unitsHeld(action), limits: limits, entitlement: entitlement,
        now: now())
  }

  /// Counts an action that succeeded.
  public func recordSuccess(_ action: MeteredAction) {
    guard !isUnlimited else { return }
    var current = counts()
    current.used[action.rawValue, default: 0] += 1
    if let data = try? JSONEncoder().encode(current) { store.save(data) }
  }

  /// Today's counts.
  ///
  /// Counts stored for an earlier day are dropped. Counts stored for the next day are kept as today's,
  /// so setting the clock back a day, or crossing the date line westwards, does not refill the
  /// allowance. Counts stored for a day further ahead are dropped too: they come from a clock that was
  /// wrong, or from an earlier version that counted days in the person's own calendar, and keeping
  /// them would refuse every action until that day came (#245).
  private func counts() -> Counts {
    let calendar = dayCalendar()
    let today = day(of: now(), in: calendar)
    guard let data = store.load(), let stored = try? JSONDecoder().decode(Counts.self, from: data),
      stored.day.count == 3
    else { return Counts(day: today, used: [:]) }
    if stored.day.lexicographicallyPrecedes(today) || days(from: today, to: stored.day, in: calendar) > 1 {
      return Counts(day: today, used: [:])
    }
    return Counts(day: stored.day, used: stored.used)
  }

  /// The calendar days are counted in: Gregorian, in the given time zone or the device's current one.
  private func dayCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone ?? .autoupdatingCurrent
    return calendar
  }

  private func day(of date: Date, in calendar: Calendar) -> [Int] {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return [parts.year ?? 0, parts.month ?? 0, parts.day ?? 0]
  }

  /// How many days one stored day is after another; `Int.max` when either is not a date.
  private func days(from start: [Int], to end: [Int], in calendar: Calendar) -> Int {
    guard let from = calendar.date(from: DateComponents(year: start[0], month: start[1], day: start[2])),
      let to = calendar.date(from: DateComponents(year: end[0], month: end[1], day: end[2]))
    else { return .max }
    return calendar.dateComponents([.day], from: from, to: to).day ?? .max
  }
}

/// Holding a unit of the allowance while an action runs (#265).
///
/// `isAllowed` and `recordSuccess` are separate calls, so two actions started together can both pass
/// the check for the last unit. An action that can be started twice at once holds a unit with
/// `reserve` instead, and ends it with `commit` once it has succeeded, or with `release`.
extension UsageAllowance {
  /// One unit of an action's allowance, held while the action runs.
  public struct Reservation: Sendable, Hashable {
    private let id = UUID()
    /// The action the unit is held for.
    public let action: MeteredAction
  }

  /// Holds one unit of an action's allowance before the action starts; `nil` when none is left.
  ///
  /// Units held count against the limit at once, in `isAllowed` too: while one holds the last unit,
  /// nothing else is offered. A cancelled action gives its unit back at once with `release`.
  public func reserve(_ action: MeteredAction, entitlement: Entitlement) -> Reservation? {
    guard isAllowed(action, entitlement: entitlement) else { return nil }
    let reservation = Reservation(action: action)
    held.withLock { _ = $0.insert(reservation) }
    return reservation
  }

  /// Counts the action a unit was held for, which has succeeded; nothing once the unit was given back.
  public func commit(_ reservation: Reservation) {
    guard held.withLock({ $0.remove(reservation) }) != nil else { return }
    recordSuccess(reservation.action)
  }

  /// How many units are held for an action now.
  nonisolated func unitsHeld(_ action: MeteredAction) -> Int {
    held.withLock { units in units.count { $0.action == action } }
  }

  /// Gives back a unit held for an action that failed or was cancelled.
  ///
  /// It may be called from any thread, at once, and more than once.
  public nonisolated func release(_ reservation: Reservation) {
    held.withLock { _ = $0.remove(reservation) }
  }
}
