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
    #expect(summary.text == "App: PDF Algo Pro 0.1.0 (7)\nSystem: iOS 26.5\nLibrary index: onDisk\nDocuments: 11-100\nEvent task.core.completed: 3")
    #expect([0, 5, 500, 5000].map(DiagnosticsSummary.bucket) == ["0", "1-10", "101-1000", "1000+"])
  }
}

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date { lock.withLock { value } }
  func advance(by seconds: TimeInterval) { lock.withLock { value += seconds } }
}
