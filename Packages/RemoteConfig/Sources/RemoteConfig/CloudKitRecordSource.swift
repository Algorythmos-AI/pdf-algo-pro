import CloudKit
import Foundation

/// Reads configuration records from the app's CloudKit public database, which every user of the app
/// can read with or without an iCloud account and only the developer role can write
/// (kill-switch runbook; [publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)).
///
/// It needs the iCloud entitlement for the container, so the app wires it in only once the container
/// exists (owner action O4); until then the store runs on the compiled behaviour.
public struct CloudKitRecordSource: RemoteRecordSource {
  /// The record type the runbook's schema describes.
  public static let recordType = "RemoteSwitch"

  private let containerIdentifier: String

  /// Creates a source for a container, such as `iCloud.com.algorythmos.pdfalgopro`.
  public init(containerIdentifier: String) {
    self.containerIdentifier = containerIdentifier
  }

  /// Every configuration record in the public database.
  public func fetchRecords() async throws -> [RemoteRecord] {
    let database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
    let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
    var records: [RemoteRecord] = []
    var cursor: CKQueryOperation.Cursor?
    let (first, next) = try await database.records(matching: query, resultsLimit: 200)
    records += first.compactMap { try? $0.1.get() }.compactMap(Self.record)
    cursor = next
    while let current = cursor {
      let (more, following) = try await database.records(continuingMatchFrom: current, resultsLimit: 200)
      records += more.compactMap { try? $0.1.get() }.compactMap(Self.record)
      cursor = following
    }
    return records
  }

  /// A record from its CloudKit fields; `nil` without a target.
  static func record(_ record: CKRecord) -> RemoteRecord? {
    guard let target = record["target"] as? String, !target.isEmpty else { return nil }
    return RemoteRecord(
      target: target, state: record["state"] as? String, value: (record["value"] as? NSNumber)?.doubleValue,
      reasonCode: record["reasonCode"] as? String, minVersion: record["minVersion"] as? String,
      maxVersion: record["maxVersion"] as? String, channel: record["channel"] as? String,
      updatedAt: record["updatedAt"] as? Date)
  }
}
