import Foundation

/// One remote configuration record, as the kill-switch runbook defines it
/// (docs/process/runbooks/kill-switch.md, which owns the schema).
///
/// A record can only take shipped behaviour away or lower a compiled limit; it can never turn anything
/// on (PAP-024, ADR-0024).
public struct RemoteRecord: Codable, Equatable, Sendable {
  /// What the record switches: `feature.<name>`, `ai.provider.<name>`, `ai.prompt.<id>` or
  /// `limit.<name>`.
  public var target: String
  /// `enabled`, `disabled` or `fallback`; ignored for `limit.` records.
  public var state: String?
  /// For a `limit.` record, the value in the limit's unit.
  public var value: Double?
  /// Chooses the notice users see; a key into the app's String Catalog, never free text.
  public var reasonCode: String?
  /// The first app version the record applies to; every version when absent.
  public var minVersion: String?
  /// The last app version the record applies to; every version when absent.
  public var maxVersion: String?
  /// The channel the record applies to, `staging` or `production`; both when absent.
  ///
  /// TestFlight and App Store builds both read CloudKit's production environment, so this keeps a
  /// change for testers away from customers (ADR-0024).
  public var channel: String?
  /// When the record last changed.
  public var updatedAt: Date?

  /// Creates a record.
  public init(
    target: String, state: String? = nil, value: Double? = nil, reasonCode: String? = nil,
    minVersion: String? = nil, maxVersion: String? = nil, channel: String? = nil, updatedAt: Date? = nil
  ) {
    self.target = target
    self.state = state
    self.value = value
    self.reasonCode = reasonCode
    self.minVersion = minVersion
    self.maxVersion = maxVersion
    self.channel = channel
    self.updatedAt = updatedAt
  }
}

/// Where records come from: CloudKit in the app, a fake in tests.
public protocol RemoteRecordSource: Sendable {
  /// Every configuration record.
  func fetchRecords() async throws -> [RemoteRecord]
}
