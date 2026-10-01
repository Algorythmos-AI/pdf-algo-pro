import Core
import Foundation

/// One entry in the consent history: what was decided for a tier, and when.
public struct ConsentRecord: Hashable, Codable, Sendable {
  /// The cloud tier the decision is about.
  public let tier: IntelligenceTier
  /// The decision.
  public let state: ConsentState
  /// The app version that recorded it, when known.
  public let appVersion: String?

  /// Creates a record.
  public init(tier: IntelligenceTier, state: ConsentState, appVersion: String?) {
    self.tier = tier
    self.state = state
    self.appVersion = appVersion
  }
}

/// The consent records for the cloud tiers, on this device only (AI governance, consent model).
///
/// The file is versioned JSON. It is excluded from backups, so a restored or migrated device asks
/// again (plan item H7), and a file written by a newer build is left untouched and read as "no
/// consent" (plan item H6): the store fails closed and never wipes what it cannot read. Decisions made
/// while such a file is present last for the session only.
public actor ConsentStore: ConsentProviding {
  /// The file's format version.
  static let version = 1

  private struct Header: Codable {
    var version: Int
  }

  private struct File: Codable {
    var version: Int
    /// Tier raw value to the current state.
    var states: [String: ConsentState]
    /// Every decision, oldest first; never rewritten.
    var history: [ConsentRecord]
  }

  private let url: URL?
  private let currentTextVersion: Int
  private let appVersion: String?
  private let now: @Sendable () -> Date
  private var states: [String: ConsentState]
  private var records: [ConsentRecord]
  private let canWrite: Bool

  /// Opens the store at `url`, or keeps it in memory when `url` is `nil`.
  ///
  /// - Parameters:
  ///   - url: The file; its folder is created on the first write.
  ///   - currentTextVersion: The consent-text version this build shows.
  ///   - appVersion: The app version to note in the history.
  ///   - now: The clock.
  public init(
    url: URL?, currentTextVersion: Int = ConsentState.currentTextVersion, appVersion: String? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.url = url
    self.currentTextVersion = currentTextVersion
    self.appVersion = appVersion
    self.now = now
    let data = url.flatMap { try? Data(contentsOf: $0) }
    let header = data.flatMap { try? JSONDecoder().decode(Header.self, from: $0) }
    if let header, header.version > Self.version {
      states = [:]
      records = []
      canWrite = false
    } else {
      let file = data.flatMap { try? JSONDecoder().decode(File.self, from: $0) }
      states = file?.states ?? [:]
      records = file?.history ?? []
      canWrite = true
    }
  }

  /// The consent on record for a tier; `notAsked` for the on-device tier, which needs none.
  public func consent(for tier: IntelligenceTier) -> ConsentState {
    guard tier.isCloud else { return .notAsked }
    return states[tier.rawValue] ?? .notAsked
  }

  /// Whether content may be sent to the tier now.
  ///
  /// True when consent was given, on this build's consent text, and has not been revoked. Always
  /// `false` for the on-device tier, which sends nothing.
  public func hasCurrentConsent(for tier: IntelligenceTier) -> Bool {
    consent(for: tier).permitsSending(currentTextVersion: currentTextVersion)
  }

  /// Records the user's opt-in to a cloud tier on this build's consent text.
  ///
  /// - Parameters:
  ///   - tier: The cloud tier; the on-device tier is ignored.
  ///   - askBeforeSending: Whether each request still needs a confirmation.
  public func grant(_ tier: IntelligenceTier, askBeforeSending: Bool) {
    set(tier, status: askBeforeSending ? .askBeforeSending : .granted)
  }

  /// Takes the consent for a cloud tier back; it applies to the very next read.
  public func revoke(_ tier: IntelligenceTier) {
    set(tier, status: .revoked)
  }

  /// Every decision recorded, oldest first, for the user to see.
  public func history() -> [ConsentRecord] { records }

  private func set(_ tier: IntelligenceTier, status: ConsentState.Status) {
    guard tier.isCloud else { return }
    let state = ConsentState(status: status, textVersion: currentTextVersion, decidedAt: now())
    states[tier.rawValue] = state
    records.append(ConsentRecord(tier: tier, state: state, appVersion: appVersion))
    save()
  }

  private func save() {
    let file = File(version: Self.version, states: states, history: records)
    guard canWrite, var url, let data = try? JSONEncoder().encode(file) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    // An atomic write replaces the file, so the flag is set again after every write.
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }
}
