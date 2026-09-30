import Foundation

/// A problem the system reported about an earlier run of the app.
///
/// It is reduced to what "Report a problem" shows: its kind, when, which build, and the system's short
/// reason. Never call stacks, paths or content.
public struct DiagnosticRecord: Codable, Equatable, Sendable {
  /// What went wrong.
  public enum Kind: String, Codable, Sendable, CaseIterable {
    /// The app crashed.
    case crash
    /// The main thread stopped responding.
    case hang
    /// The app used too much processor time.
    case cpuException
    /// The app wrote too much to disk.
    case diskWriteException
    /// The app took too long to launch.
    case launch
  }

  /// What went wrong.
  public let kind: Kind
  /// When the system recorded it.
  public let date: Date
  /// The app build it happened in.
  public let build: String
  /// The system's short reason, for example "EXC_BAD_ACCESS, SIGSEGV", or a duration.
  public let detail: String?

  /// Creates a record.
  public init(kind: Kind, date: Date, build: String, detail: String? = nil) {
    self.kind = kind
    self.date = date
    self.build = build
    self.detail = detail
  }
}

/// Problems the system reported through MetricKit, kept on this device only (P6, ADR-0017).
///
/// Records older than 30 days are dropped, and at most 100 are kept. The file is excluded from backup
/// by the app. Nothing is sent anywhere: "Report a problem" includes the summary only when the person
/// sends the report.
public actor DiagnosticsLog {
  /// How long records are kept.
  public static let retention: TimeInterval = 30 * 86_400
  /// The most records kept.
  public static let capacity = 100

  private let file: URL
  private let now: @Sendable () -> Date
  private var records: [DiagnosticRecord]

  /// Opens the log in a file, which is created on the first write.
  public init(file: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    self.file = file
    self.now = now
    records =
      (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([DiagnosticRecord].self, from: $0) } ?? []
  }

  /// Adds records, drops old ones and writes the log.
  public func add(_ new: [DiagnosticRecord]) {
    let cutoff = now().addingTimeInterval(-Self.retention)
    records = Array((records + new).filter { $0.date >= cutoff }.sorted { $0.date < $1.date }.suffix(Self.capacity))
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(records).write(
      to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  /// The records from the last 30 days, oldest first.
  public func recent() -> [DiagnosticRecord] {
    let cutoff = now().addingTimeInterval(-Self.retention)
    return records.filter { $0.date >= cutoff }
  }

  /// One line per kind of problem in the last 30 days, with the latest build and reason, for the
  /// diagnostics summary.
  public func summary() -> [String] {
    let recent = recent()
    guard !recent.isEmpty else { return ["System-reported problems (30 days): none"] }
    return DiagnosticRecord.Kind.allCases.compactMap { kind in
      let matching = recent.filter { $0.kind == kind }
      guard let latest = matching.last else { return nil }
      let reason = latest.detail.map { ", \($0)" } ?? ""
      return "System-reported \(kind.rawValue) (30 days): \(matching.count), latest in build \(latest.build)\(reason)"
    }
  }
}
