import Foundation

/// Documents whose search text and Spotlight entry still have to catch up with their file (#236).
///
/// A change is written down before it is saved, and crossed off once a refresh that began after it
/// has worked, so one that failed, or that the app was stopped in the middle of, is done again at the
/// next library load. Changes are numbered, so a refresh that began before a later change never
/// crosses that change off. Only document identifiers and counts are kept, in a small file on the
/// device.
public actor PendingRefreshes {
  /// One document's owed refresh.
  public struct Owed: Codable, Equatable, Sendable {
    /// The number of the latest change it is owed for.
    public var change: Int
    /// How many refreshes for it have failed since that change.
    public var failures: Int
    /// Whether a change protected the document, so its words must leave search whatever else fails.
    public var protects: Bool
  }

  private struct Stored: Codable {
    var changes: Int
    var owed: [DocumentID: Owed]
  }

  private let url: URL?
  private var changes = 0
  private var owed: [DocumentID: Owed] = [:]

  /// Opens the list kept at `url`, or one in memory when `url` is `nil`.
  ///
  /// A list that can't be read starts empty; it only costs a refresh that would have been retried.
  public init(url: URL?) {
    self.url = url
    guard let data = url.flatMap({ try? Data(contentsOf: $0) }) else { return }
    if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
      changes = stored.changes
      owed = stored.owed
    } else if let ids = try? JSONDecoder().decode([DocumentID].self, from: data) {
      // The first form of the list: identifiers only.
      owed = Dictionary(uniqueKeysWithValues: ids.map { ($0, Owed(change: 0, failures: 0, protects: false)) })
    }
  }

  /// The documents still to refresh, in a stable order.
  public var all: [DocumentID] {
    owed.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
  }

  /// What a document is owed, or `nil` when nothing is.
  public func owed(_ id: DocumentID) -> Owed? {
    owed[id]
  }

  /// Writes a change down: the document needs a refresh that begins after now.
  ///
  /// - Parameters:
  ///   - id: The document that changes.
  ///   - protecting: Whether the change protects it; that stays until the refresh is crossed off.
  /// - Throws: when the list can't be written, so the caller knows a failure would not be retried.
  public func add(_ id: DocumentID, protecting: Bool = false) throws {
    changes += 1
    let protects = protecting || (owed[id]?.protects ?? false)
    owed[id] = Owed(change: changes, failures: 0, protects: protects)
    try save()
  }

  /// Crosses a document off once a refresh covering every change up to `change` has worked.
  public func finished(_ id: DocumentID, upTo change: Int) throws {
    guard let entry = owed[id], entry.change <= change else { return }
    owed[id] = nil
    try save()
  }

  /// Counts a failed refresh; returns how many have failed since the latest change.
  @discardableResult
  public func failed(_ id: DocumentID) throws -> Int {
    guard var entry = owed[id] else { return 0 }
    entry.failures += 1
    owed[id] = entry
    try save()
    return entry.failures
  }

  /// Crosses a document off whatever it is owed.
  public func remove(_ id: DocumentID) throws {
    guard owed.removeValue(forKey: id) != nil else { return }
    try save()
  }

  private func save() throws {
    guard let url else { return }
    let data = try JSONEncoder().encode(Stored(changes: changes, owed: owed))
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
