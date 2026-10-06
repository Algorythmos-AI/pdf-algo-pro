import Core
import Foundation
import Testing

@testable import Telemetry

@Suite("Telemetry")
struct TelemetryTests {
  @Test("Only catalogued, well-formed events are counted (ADR-0017)")
  func onlyCataloguedEvents() async {
    let telemetry = LocalTelemetry(now: { Date(timeIntervalSince1970: 1_800_000_000) })
    await telemetry.record("onboarding.flow.completed")
    await telemetry.record("onboarding.flow.completed")
    await telemetry.record("task.core.completed")
    await telemetry.record("user.email.typed")
    await telemetry.record("Onboarding.Flow.Completed")
    #expect(await telemetry.todaysCounts() == ["onboarding.flow.completed": 2, "task.core.completed": 1])
  }

  @Test("The catalogue itself follows the naming rule", arguments: Array(TelemetryEvent.catalogue))
  func catalogueIsWellFormed(name: String) {
    #expect(TelemetryEvent.isWellFormed(name))
  }

  @Test(arguments: ["a.b", "a.b.c.d", "a..b", "a.B.c", "a.b-c.d", "a.é.c", ""])
  func malformedNames(name: String) {
    #expect(!TelemetryEvent.isWellFormed(name))
  }

  @Test("Counts start again each day")
  func dailyCounts() async {
    let clock = Clock()
    let telemetry = LocalTelemetry(calendar: Calendar(identifier: .gregorian), now: { clock.now })
    await telemetry.record("task.core.completed")
    clock.advance(by: 86_400)
    #expect(await telemetry.todaysCounts().isEmpty)
  }

  @Test("Diagnostics carry no document details and bucket the library size")
  func diagnostics() {
    let summary = DiagnosticsSummary(
      appVersion: "0.1.0", build: "7", system: "iOS 26.5", libraryIndex: "onDisk", documentCount: 42,
      events: ["task.core.completed": 3])
    #expect(
      summary.text
        == "App: PDF Algo Pro 0.1.0 (7)\nSystem: iOS 26.5\nLibrary index: onDisk\nDocuments: 11-100\nEvent task.core.completed: 3"
    )
    #expect([0, 5, 500, 5000].map(DiagnosticsSummary.bucket) == ["0", "1-10", "101-1000", "1000+"])
  }
}

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date { lock.withLock { value } }
  func advance(by seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@Suite("Diagnostics log")
struct DiagnosticsLogTests {
  private static let start = Date(timeIntervalSince1970: 1_800_000_000)

  private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = DiagnosticsLogTests.start
    var now: Date { lock.withLock { current } }
    func advance(days: Double) { lock.withLock { current += days * 86_400 } }
  }

  @Test("System-reported problems are kept on the device for 30 days and summarised (P6)")
  func keepsAndSummarises() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID())/problems.json")
    let clock = Clock()
    let log = DiagnosticsLog(file: file, now: { clock.now })
    #expect(await log.summary() == ["System-reported problems (30 days): none"])

    await log.add([
      DiagnosticRecord(kind: .crash, date: Self.start, build: "41", detail: "exception 1, signal 11"),
      DiagnosticRecord(kind: .hang, date: Self.start, build: "41", detail: "2.5 sec"),
    ])
    clock.advance(days: 20)
    await log.add([DiagnosticRecord(kind: .crash, date: clock.now, build: "42")])

    let reopened = DiagnosticsLog(file: file, now: { clock.now })
    #expect(
      await reopened.summary() == [
        "System-reported crash (30 days): 2, latest in build 42",
        "System-reported hang (30 days): 1, latest in build 41, 2.5 sec",
      ])
    clock.advance(days: 15)
    #expect(await reopened.recent().map(\.build) == ["42"], "Older than 30 days are not reported")
    await reopened.add([])
    #expect(await DiagnosticsLog(file: file, now: { clock.now }).recent().count == 1, "and are removed")
  }

  @Test("The log keeps at most 100 records, newest first to survive")
  func capacity() async {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID())/problems.json")
    let log = DiagnosticsLog(file: file, now: { Self.start })
    let records = (0..<150).map {
      DiagnosticRecord(kind: .cpuException, date: Self.start.addingTimeInterval(Double(-$0)), build: "\($0)")
    }
    await log.add(records)
    let kept = await log.recent()
    #expect(kept.count == DiagnosticsLog.capacity && kept.last?.build == "0")
  }

  @Test("The diagnostics summary ends with the system-reported problems")
  func summaryIncludesProblems() {
    let summary = DiagnosticsSummary(
      appVersion: "1.0", build: "42", system: "iOS 26", libraryIndex: "persistent", documentCount: 3, events: [:],
      problems: ["System-reported problems (30 days): none"])
    #expect(summary.lines.last == "System-reported problems (30 days): none")
  }

  @Test("The diagnostics summary ends with the text-editing counts when there are any")
  func summaryIncludesTextEditing() {
    let summary = DiagnosticsSummary(
      appVersion: "1.0", build: "42", system: "iOS 26", libraryIndex: "persistent", documentCount: 3, events: [:],
      problems: ["System-reported problems (30 days): none"],
      textEditing: TextEditingDiagnostics(pageKind: .text).lines)
    #expect(summary.lines.contains("Text editing page: text"))
    #expect(summary.lines.last == "Text editing session: made 0, covered 0, refused 0")
  }
}
