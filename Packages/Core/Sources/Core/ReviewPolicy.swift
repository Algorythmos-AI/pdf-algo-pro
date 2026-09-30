import Foundation

/// When the app may ask for a rating (plan revision 3, §6): after real successes, never early and never
/// after something went wrong.
///
/// The rules: not in the first session; at least three successes, on at least two different days; at
/// most once per app version; and never in a session that had an error. The system shows the request
/// at most three times in 365 days, whatever the app asks.
public struct ReviewPolicy: Codable, Equatable, Sendable {
  /// Sessions started, counting the current one.
  public private(set) var sessions = 0
  /// Successes so far.
  public private(set) var successes = 0
  /// The days with a success, as `yyyy-MM-dd`, most recent last; a few are enough.
  public private(set) var successDays: [String] = []
  /// The app version a rating was last asked for in.
  public private(set) var askedInVersion: String?

  /// Events that count as a success: a document saved, a scan made, an answer kept.
  public static let successEvents: Set<String> = ["task.core.completed", "intelligence.answer.kept"]
  /// Events that mean something went wrong in this session.
  public static let errorEvents: Set<String> = ["quality.operation.failed"]

  /// A policy with no history.
  public init() {}

  /// Counts a new session.
  public mutating func startSession() {
    sessions += 1
  }

  /// Counts a success on a day.
  public mutating func recordSuccess(on day: String) {
    successes += 1
    if successDays.last != day {
      successDays.append(day)
      successDays = Array(successDays.suffix(7))
    }
  }

  /// Whether a rating may be asked for now.
  public func isDue(version: String, sessionHadError: Bool) -> Bool {
    sessions >= 2 && successes >= 3 && Set(successDays).count >= 2 && askedInVersion != version && !sessionHadError
  }

  /// Records that a rating was asked for in a version.
  public mutating func asked(in version: String) {
    askedInVersion = version
  }

  /// A day key for `recordSuccess(on:)`.
  public static func day(of date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
