import Foundation

/// Fetches remote configuration and keeps the last known records on the device (kill-switch runbook,
/// "Behaviour in the app").
///
/// - It fetches at launch, and on returning to the foreground when the last fetch is older than
///   `interval` (`Assumption:` 15 minutes).
/// - When a fetch fails, the last known records apply; with none cached, the compiled behaviour does.
/// - A failed or slow fetch never blocks the app: `current` is always available at once.
public actor RemoteConfigStore {
  private let source: any RemoteRecordSource
  private let cacheURL: URL
  private let appVersion: String
  private let channel: String
  private let interval: TimeInterval
  private let now: @Sendable () -> Date
  private var records: [RemoteRecord]
  private var lastFetch: Date?

  /// Creates the store, reading the cached records.
  ///
  /// - Parameters:
  ///   - source: Where records come from.
  ///   - cacheURL: The file that keeps the last known records, in the app's container.
  ///   - appVersion: The build's version.
  ///   - channel: `staging` or `production`.
  ///   - interval: How old the last fetch must be before returning to the foreground fetches again.
  ///   - now: The clock, injected so tests never wait.
  public init(
    source: any RemoteRecordSource, cacheURL: URL, appVersion: String, channel: String,
    interval: TimeInterval = 15 * 60, now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.source = source
    self.cacheURL = cacheURL
    self.appVersion = appVersion
    self.channel = channel
    self.interval = interval
    self.now = now
    let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    records = cached?.records ?? []
    lastFetch = cached?.fetchedAt
  }

  private struct Cache: Codable {
    var records: [RemoteRecord]
    var fetchedAt: Date
  }

  /// The configuration now: the last known records applied to the compiled behaviour.
  public var current: RemoteConfiguration {
    RemoteConfiguration(records: records, appVersion: appVersion, channel: channel)
  }

  /// When records were last fetched, if ever.
  public var fetchedAt: Date? { lastFetch }

  /// Fetches records now; on failure keeps the last known ones.
  ///
  /// - Returns: Whether the fetch succeeded.
  @discardableResult
  public func refresh() async -> Bool {
    do {
      let fetched = try await source.fetchRecords()
      records = fetched
      lastFetch = now()
      let cache = Cache(records: fetched, fetchedAt: now())
      if let data = try? JSONEncoder().encode(cache) {
        try? FileManager.default.createDirectory(
          at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
      return true
    } catch {
      return false
    }
  }

  /// Fetches when the last fetch is older than the interval, or there has been none (for returning to
  /// the foreground).
  ///
  /// - Returns: Whether a fetch was made and succeeded.
  @discardableResult
  public func refreshIfStale() async -> Bool {
    if let lastFetch, now().timeIntervalSince(lastFetch) < interval { return false }
    return await refresh()
  }
}
