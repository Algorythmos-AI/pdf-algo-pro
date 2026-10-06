import Foundation

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
/// counts start again on a new calendar day. They are about this device: reinstalling the app
/// clears them, which is accepted, since anything stronger needs an account or a server.
public actor UsageAllowance {
  private struct Counts: Codable, Equatable {
    /// The day the counts are for, as year, month and day in the device's calendar.
    var day: [Int]
    var used: [String: Int]
  }

  private let limits: AllowanceLimits
  private let store: any AllowanceStoring
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private let isUnlimited: Bool

  /// Creates the allowance.
  ///
  /// With `isUnlimited` it never refuses and never counts: UI tests that are not about the allowance use it.
  public init(
    limits: AllowanceLimits = .free, store: any AllowanceStoring, calendar: Calendar = .current,
    isUnlimited: Bool = false, now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.limits = limits
    self.store = store
    self.calendar = calendar
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

  /// Whether an action may start.
  public func isAllowed(_ action: MeteredAction, entitlement: Entitlement) -> Bool {
    isUnlimited
      || FeatureGate.isAllowed(
        action, usedToday: usedToday(action), limits: limits, entitlement: entitlement, now: now())
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
  /// Counts stored for an earlier day are dropped. Counts stored for a later day are kept as today's:
  /// setting the clock back does not refill the allowance.
  private func counts() -> Counts {
    let today = day(of: now())
    guard let data = store.load(), let stored = try? JSONDecoder().decode(Counts.self, from: data),
      stored.day.count == 3
    else { return Counts(day: today, used: [:]) }
    if stored.day.lexicographicallyPrecedes(today) { return Counts(day: today, used: [:]) }
    return Counts(day: stored.day, used: stored.used)
  }

  private func day(of date: Date) -> [Int] {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return [parts.year ?? 0, parts.month ?? 0, parts.day ?? 0]
  }
}
