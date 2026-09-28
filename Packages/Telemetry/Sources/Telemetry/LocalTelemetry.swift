import Core
import Foundation
import OSLog

/// The event catalogue from the analytics strategy (docs/analytics-strategy.md, event catalogue).
/// Names follow `domain.object.action`; anything else is dropped, so a typo can never create a new
/// event (ADR-0017).
public enum TelemetryEvent {
  /// Every event the app may record.
  public static let catalogue: Set<String> = [
    "onboarding.flow.started", "onboarding.intent.selected", "onboarding.flow.skipped", "onboarding.flow.completed",
    "activation.first_document.opened", "activation.first_value.reached", "task.core.completed",
    "intelligence.request.completed", "intelligence.answer.kept", "intelligence.consent.changed",
    "commerce.paywall.viewed", "commerce.trial.started", "commerce.purchase.completed", "share.document.exported",
    "engagement.week.recorded", "quality.operation.failed",
  ]

  /// Whether a name is well formed: three lower-case segments of letters, digits and underscores.
  public static func isWellFormed(_ name: String) -> Bool {
    let segments = name.split(separator: ".", omittingEmptySubsequences: false)
    return segments.count == 3
      && segments.allSatisfy { segment in
        !segment.isEmpty && segment.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
      }
  }
}

/// On-device telemetry for V1 and V1.1: events are counted per day in memory and written to the
/// unified log with private redaction. Nothing is sent anywhere, so the privacy label stays "Data Not
/// Collected" (PAP-017). The opt-in aggregated upload arrives with the relay in V2.
public actor LocalTelemetry: TelemetryRecording {
  private let logger = Logger(subsystem: "com.algorythmos.pdfalgopro", category: "telemetry")
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private var counts: [String: [String: Int]] = [:]

  /// Creates a recorder.
  public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
    self.calendar = calendar
    self.now = now
  }

  /// Counts a catalogued event for today; unknown or malformed names are dropped.
  public func record(_ event: String) async {
    guard TelemetryEvent.isWellFormed(event), TelemetryEvent.catalogue.contains(event) else {
      logger.debug("Dropped an uncatalogued event")
      return
    }
    let day = Self.dayKey(now(), calendar: calendar)
    counts[day, default: [:]][event, default: 0] += 1
    logger.debug("Recorded \(event, privacy: .public)")
  }

  /// Today's counts, for the diagnostics summary the user can choose to attach (FR-SET-003).
  public func todaysCounts() -> [String: Int] {
    counts[Self.dayKey(now(), calendar: calendar)] ?? [:]
  }

  private static func dayKey(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
  }
}

/// The diagnostics summary for "Report a problem" (FR-SET-003). It holds app, system and health
/// facts only: never document names, content, paths or identifiers.
public struct DiagnosticsSummary: Sendable, Equatable {
  /// Lines of `key: value` text.
  public let lines: [String]

  /// Builds the summary.
  public init(appVersion: String, build: String, system: String, libraryIndex: String, documentCount: Int, events: [String: Int]) {
    var lines = [
      "App: PDF Algo Pro \(appVersion) (\(build))",
      "System: \(system)",
      "Library index: \(libraryIndex)",
      "Documents: \(Self.bucket(documentCount))",
    ]
    lines += events.keys.sorted().map { "Event \($0): \(events[$0] ?? 0)" }
    self.lines = lines
  }

  /// The summary as plain text.
  public var text: String { lines.joined(separator: "\n") }

  /// Counts are bucketed so the summary never reveals an exact library size.
  static func bucket(_ count: Int) -> String {
    switch count {
    case 0: "0"
    case 1...10: "1-10"
    case 11...100: "11-100"
    case 101...1000: "101-1000"
    default: "1000+"
    }
  }
}
