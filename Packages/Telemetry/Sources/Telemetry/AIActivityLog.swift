import Core
import Foundation

/// The counts behind the privacy report (FR-SET-005): how many AI requests each tier answered each
/// day, kept for 30 days on this device. No question, answer, document or identifier is stored.
///
/// The file is versioned (bar item B11). A file written by a newer build is left untouched and
/// counting starts afresh in memory, so an older TestFlight build never overwrites it (plan item H6).
public actor AIActivityLog: AIActivityRecording {
  /// The file's format version.
  static let version = 1
  /// How long counts are kept.
  static let retention = 30

  private struct File: Codable {
    var version: Int
    /// Day (yyyy-mm-dd) to tier to count.
    var days: [String: [String: Int]]
  }

  private let url: URL?
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private var days: [String: [String: Int]]
  private let canWrite: Bool

  /// Opens the log at `url`, or keeps it in memory when `url` is `nil`.
  public init(url: URL?, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
    self.url = url
    self.calendar = calendar
    self.now = now
    let file = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(File.self, from: $0) }
    if let file, file.version > Self.version {
      days = [:]
      canWrite = false
    } else {
      days = file?.days ?? [:]
      canWrite = true
    }
  }

  /// Counts one request answered by a tier, and forgets days past the retention.
  public func record(_ tier: IntelligenceTier) async {
    days[dayKey(now()), default: [:]][tier.rawValue, default: 0] += 1
    let oldest = dayKey(calendar.date(byAdding: .day, value: -Self.retention, to: now()) ?? now())
    days = days.filter { $0.key > oldest }
    save()
  }

  /// The counts for the last `days` days.
  public func activity(days count: Int) async -> AIActivity {
    let oldest = dayKey(calendar.date(byAdding: .day, value: -count, to: now()) ?? now())
    var requests: [IntelligenceTier: Int] = [:]
    for (day, tiers) in days where day > oldest {
      for (name, value) in tiers {
        guard let tier = IntelligenceTier(rawValue: name) else { continue }
        requests[tier, default: 0] += value
      }
    }
    let cloud = requests.filter { $0.key != .onDevice }.values.reduce(0, +)
    return AIActivity(requests: requests, documentsSentToCloud: cloud, days: count)
  }

  private func save() {
    guard canWrite, let url, let data = try? JSONEncoder().encode(File(version: Self.version, days: days)) else {
      return
    }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  private func dayKey(_ date: Date) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
