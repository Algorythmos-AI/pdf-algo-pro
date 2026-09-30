import Foundation
import Testing

@testable import RemoteConfig

@Suite("Remote configuration only switches things off")
struct RemoteConfigurationTests {
  private func configuration(
    _ records: [RemoteRecord], version: String = "1.2.0", channel: String = "production"
  )
    -> RemoteConfiguration
  {
    RemoteConfiguration(records: records, appVersion: version, channel: channel)
  }

  @Test("With no records, the compiled behaviour applies")
  func compiled() {
    let config = RemoteConfiguration(appVersion: "1.0", channel: "production")
    #expect(config.isEnabled("feature.redaction") && config.state(of: "ai.provider.pcc") == .enabled)
    #expect(config.limit("claude-pages-per-request", compiled: 50) == 50)
    #expect(config.disabledTargets.isEmpty)
  }

  @Test("A record disables a feature, a provider or a prompt, with its notice")
  func disables() {
    let config = configuration([
      RemoteRecord(target: "feature.save-in-place", state: "disabled", reasonCode: "save.incident"),
      RemoteRecord(target: "ai.provider.pcc", state: "disabled"),
      RemoteRecord(target: "ai.prompt.summarise.v3", state: "fallback", reasonCode: "prompt.quality"),
    ])
    #expect(config.state(of: "feature.save-in-place") == .disabled(reasonCode: "save.incident"))
    #expect(!config.isEnabled("ai.provider.pcc"))
    #expect(config.state(of: "ai.prompt.summarise.v3") == .fallback(reasonCode: "prompt.quality"))
    #expect(config.isEnabled("ai.prompt.summarise.v3"), "A prompt on its fallback is still on")
    #expect(config.disabledTargets == ["ai.provider.pcc", "feature.save-in-place"])
  }

  @Test("Nothing can be turned on, and unknown or malformed records are ignored")
  func oneWay() {
    let config = configuration([
      RemoteRecord(target: "feature.redaction", state: "disabled"),
      RemoteRecord(target: "feature.redaction", state: "enabled"),
      RemoteRecord(target: "feature.claude-beta", state: "on"),
      RemoteRecord(target: "feature.x", state: "fallback"),
      RemoteRecord(target: "consent.skip", state: "disabled"),
      RemoteRecord(target: "", state: "disabled"),
    ])
    #expect(!config.isEnabled("feature.redaction"), "An enabled record never overrides a disabled one")
    #expect(config.isEnabled("feature.claude-beta") && config.state(of: "feature.x") == .enabled)
    #expect(config.disabledTargets == ["feature.redaction"])
  }

  @Test("A limit can be lowered, never raised, and bad values are ignored")
  func limits() {
    let config = configuration([
      RemoteRecord(target: "limit.pages", value: 20),
      RemoteRecord(target: "limit.pages", value: 30),
      RemoteRecord(target: "limit.tokens", value: 9_000),
      RemoteRecord(target: "limit.bad", value: -1),
      RemoteRecord(target: "limit.nan", value: .nan),
      RemoteRecord(target: "limit.none"),
    ])
    #expect(config.limit("pages", compiled: 50) == 20, "The lowest record wins")
    #expect(config.limit("tokens", compiled: 4_000) == 4_000, "A remote value can't raise a compiled limit")
    #expect(config.limit("bad", compiled: 5) == 5 && config.limit("nan", compiled: 5) == 5)
    #expect(config.limit("none", compiled: 5) == 5)
  }

  @Test("Records apply only to their versions and channel")
  func scope() {
    let records = [
      RemoteRecord(target: "feature.a", state: "disabled", minVersion: "1.2", maxVersion: "1.2.9"),
      RemoteRecord(target: "feature.b", state: "disabled", maxVersion: "1.1.9"),
      RemoteRecord(target: "feature.c", state: "disabled", minVersion: "1.10"),
      RemoteRecord(target: "feature.d", state: "disabled", channel: "staging"),
    ]
    #expect(configuration(records).disabledTargets == ["feature.a"])
    #expect(configuration(records, version: "1.10.0").disabledTargets == ["feature.c"])
    #expect(configuration(records, channel: "staging").disabledTargets == ["feature.a", "feature.d"])
  }

  @Test(
    "Versions compare by number",
    arguments: [
      ("1.9", "1.10", ComparisonResult.orderedAscending), ("1.2", "1.2.0", .orderedSame),
      ("2", "1.9.9", .orderedDescending),
    ])
  func versions(lhs: String, rhs: String, expected: ComparisonResult) {
    #expect(RemoteConfiguration.compare(lhs, rhs) == expected)
  }
}

private actor FakeSource: RemoteRecordSource {
  var records: [RemoteRecord] = []
  var fails = false
  private(set) var fetches = 0

  func set(_ records: [RemoteRecord]) { self.records = records }
  func fail(_ fails: Bool) { self.fails = fails }

  func fetchRecords() async throws -> [RemoteRecord] {
    fetches += 1
    if fails { throw URLError(.notConnectedToInternet) }
    return records
  }
}

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date { lock.withLock { value } }
  func advance(minutes: Double) { lock.withLock { value += minutes * 60 } }
}

@Suite("Remote configuration store")
struct RemoteConfigStoreTests {
  private func cacheURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("remote-\(UUID())/config.json")
  }

  @Test("A fetch applies, is cached, and survives a relaunch that can't reach the network")
  func cachesAndFallsBack() async {
    let source = FakeSource()
    await source.set([RemoteRecord(target: "feature.redaction", state: "disabled")])
    let url = cacheURL()
    let store = RemoteConfigStore(source: source, cacheURL: url, appVersion: "1.0", channel: "production")
    #expect(await store.current.isEnabled("feature.redaction"), "Compiled behaviour before any fetch")
    #expect(await store.refresh())
    #expect(await !store.current.isEnabled("feature.redaction"))

    await source.fail(true)
    let relaunched = RemoteConfigStore(source: source, cacheURL: url, appVersion: "1.0", channel: "production")
    #expect(await !relaunched.refresh())
    #expect(await !relaunched.current.isEnabled("feature.redaction"), "The last known records apply")
  }

  @Test("With nothing cached and no network, the compiled behaviour applies")
  func noCache() async {
    let source = FakeSource()
    await source.fail(true)
    let store = RemoteConfigStore(source: source, cacheURL: cacheURL(), appVersion: "1.0", channel: "production")
    #expect(await !store.refresh())
    #expect(await store.current.disabledTargets.isEmpty)
  }

  @Test("Returning to the foreground fetches only when the last fetch is over the interval old")
  func interval() async {
    let source = FakeSource()
    let clock = Clock()
    let store = RemoteConfigStore(
      source: source, cacheURL: cacheURL(), appVersion: "1.0", channel: "production", now: { clock.now })
    #expect(await store.refreshIfStale(), "No fetch yet, so it fetches")
    clock.advance(minutes: 10)
    #expect(await !store.refreshIfStale())
    clock.advance(minutes: 6)
    #expect(await store.refreshIfStale())
    #expect(await source.fetches == 2)
  }

  @Test("A damaged cache is ignored")
  func damagedCache() async throws {
    let url = cacheURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    let store = RemoteConfigStore(source: FakeSource(), cacheURL: url, appVersion: "1.0", channel: "production")
    #expect(await store.current.disabledTargets.isEmpty)
    #expect(await store.fetchedAt == nil)
  }
}
