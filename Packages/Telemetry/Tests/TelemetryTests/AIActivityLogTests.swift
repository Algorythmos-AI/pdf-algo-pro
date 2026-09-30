import Core
import Foundation
import Testing

@testable import Telemetry

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date { lock.withLock { value } }
  func advance(days: Double) { lock.withLock { value += days * 86_400 } }
}

@Suite("Privacy report counts (FR-SET-005)")
struct AIActivityLogTests {
  private func url() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID())/ai-activity.json")
  }

  @Test("Requests are counted by tier, cloud tiers count as documents sent, and the file survives relaunch")
  func counts() async {
    let file = url()
    let clock = Clock()
    let log = AIActivityLog(url: file, calendar: Calendar(identifier: .gregorian), now: { clock.now })
    await log.record(.onDevice)
    await log.record(.onDevice)
    await log.record(.privateCloudCompute)
    let activity = await log.activity(days: 30)
    #expect(activity.requests[.onDevice] == 2 && activity.requests[.privateCloudCompute] == 1)
    #expect(activity.documentsSentToCloud == 1)
    let reopened = AIActivityLog(url: file, calendar: Calendar(identifier: .gregorian), now: { clock.now })
    #expect(await reopened.activity(days: 30) == activity)
  }

  @Test("Counts older than 30 days drop out")
  func retention() async {
    let clock = Clock()
    let log = AIActivityLog(url: url(), calendar: Calendar(identifier: .gregorian), now: { clock.now })
    await log.record(.onDevice)
    clock.advance(days: 31)
    await log.record(.onDevice)
    #expect(await log.activity(days: 30).requests[.onDevice] == 1)
  }

  @Test("A file from a newer build is left untouched (H6)")
  func newerFileIsKept() async throws {
    let file = url()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let newer = Data(#"{"version":99,"days":{},"future":true}"#.utf8)
    try newer.write(to: file)
    let log = AIActivityLog(url: file)
    await log.record(.onDevice)
    #expect(await log.activity(days: 30).requests[.onDevice] == 1)
    #expect(try Data(contentsOf: file) == newer)
  }
}
