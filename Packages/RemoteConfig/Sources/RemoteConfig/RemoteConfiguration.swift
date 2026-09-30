import Foundation

/// The configuration a build runs with: its compiled behaviour, less whatever remote records switch off
/// or lower (the kill-switch runbook, PAP-024, ADR-0024).
///
/// The rules are deliberately one-way. A record can disable a target or lower a limit; it can't enable
/// anything the build ships off, raise a compiled limit, turn on a cloud tier or bypass consent. A record
/// that is malformed, for another version or another channel, or names something unknown is ignored.
public struct RemoteConfiguration: Equatable, Sendable {
  /// What a record can do to one target.
  public enum Switch: Equatable, Sendable {
    /// The compiled behaviour applies.
    case enabled
    /// Turned off; the notice for `reasonCode` explains why.
    case disabled(reasonCode: String?)
    /// For a prompt: use the previous version bundled in the app.
    case fallback(reasonCode: String?)
  }

  /// The build's own version, such as `1.2.0`.
  public let appVersion: String
  /// `staging` or `production`.
  public let channel: String
  private var switches: [String: Switch] = [:]
  private var limits: [String: (value: Double, reasonCode: String?)] = [:]

  /// The configuration with nothing switched off: the compiled behaviour.
  public init(appVersion: String, channel: String) {
    self.appVersion = appVersion
    self.channel = channel
  }

  /// The configuration after applying records to the compiled behaviour.
  public init(records: [RemoteRecord], appVersion: String, channel: String) {
    self.init(appVersion: appVersion, channel: channel)
    for record in records where applies(record) {
      if record.target.hasPrefix("limit.") {
        guard let value = record.value, value.isFinite, value >= 0 else { continue }
        let current = limits[record.target]?.value ?? .infinity
        if value < current { limits[record.target] = (value, record.reasonCode) }
        continue
      }
      guard Self.switchPrefixes.contains(where: record.target.hasPrefix) else { continue }
      switch record.state {
      case "disabled":
        switches[record.target] = .disabled(reasonCode: record.reasonCode)
      case "fallback" where record.target.hasPrefix("ai.prompt."):
        if case .disabled = switches[record.target] { continue }
        switches[record.target] = .fallback(reasonCode: record.reasonCode)
      default:
        continue
      }
    }
  }

  static let switchPrefixes = ["feature.", "ai.provider.", "ai.prompt."]

  /// The state of a target: a feature, an AI provider or a prompt.
  public func state(of target: String) -> Switch { switches[target] ?? .enabled }

  /// Whether a target is on (a prompt on its fallback counts as on).
  public func isEnabled(_ target: String) -> Bool {
    if case .disabled = state(of: target) { return false }
    return true
  }

  /// A compiled limit, lowered by a remote record when there is one; never raised.
  public func limit(_ name: String, compiled: Double) -> Double {
    guard let remote = limits["limit.\(name)"]?.value else { return compiled }
    return min(remote, compiled)
  }

  /// Every target switched off, for the diagnostics bundle and `docs/working-memory.md`.
  public var disabledTargets: [String] {
    switches.compactMap { target, state in
      if case .disabled = state { return target }
      return nil
    }.sorted()
  }

  /// Two configurations are equal when they switch and limit the same targets for the same build.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.appVersion == rhs.appVersion && lhs.channel == rhs.channel && lhs.switches == rhs.switches
      && lhs.limits.mapValues(\.value) == rhs.limits.mapValues(\.value)
  }

  private func applies(_ record: RemoteRecord) -> Bool {
    if let channel = record.channel, channel != self.channel { return false }
    if let minimum = record.minVersion, Self.compare(appVersion, minimum) == .orderedAscending { return false }
    if let maximum = record.maxVersion, Self.compare(appVersion, maximum) == .orderedDescending { return false }
    return true
  }

  /// Compares dotted versions numerically (`1.10` is after `1.9`); missing parts count as zero.
  static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
      let a = index < left.count ? left[index] : 0
      let b = index < right.count ? right[index] : 0
      if a != b { return a < b ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }
}
