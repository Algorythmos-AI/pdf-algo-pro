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
    /// Whether its words were taken out of search while it was protected; until a refresh puts them
    /// back, it isn't given up.
    public var wordsRemoved: Bool?
  }

  private struct Stored: Codable {
    var changes: Int
    var owed: [DocumentID: Owed]
  }

  private let url: URL?
  private var changes = 0
  private var owed: [DocumentID: Owed] = [:]
  /// Changes whose save hasn't ended yet, in this launch only: after a relaunch no save is under way,
  /// and the file is as the last one left it.
  private var saving: [DocumentID: Set<Int>] = [:]

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

  /// Writes a change down: the document needs a refresh that reads the file after it is saved.
  ///
  /// - Parameters:
  ///   - id: The document that changes.
  ///   - protecting: `true` when the change protects it, `false` when it removes the protection (a
  ///     password taken off), `nil` when it leaves that as it was.
  ///   - saved: Whether the file is already written; if not, `saveFinished(_:change:)` says when.
  /// - Returns: the change's number.
  /// - Throws: when the list can't be written, so the caller knows a failure would not be retried.
  @discardableResult
  public func add(_ id: DocumentID, protecting: Bool? = nil, saved: Bool = true) throws -> Int {
    changes += 1
    let protects = protecting ?? (owed[id]?.protects ?? false)
    // Failures carry on: a file found changed again at every launch must not reset its tries.
    owed[id] = Owed(
      change: changes, failures: owed[id]?.failures ?? 0, protects: protects, wordsRemoved: owed[id]?.wordsRemoved)
    if !saved { saving[id, default: []].insert(changes) }
    try save()
    return changes
  }

  /// Notes that the file was read and isn't locked: no change protects it any more, unless a save is
  /// still under way, which may yet lock it.
  public func readUnlocked(_ id: DocumentID) throws {
    guard saving[id] == nil, var entry = owed[id], entry.protects else { return }
    entry.protects = false
    owed[id] = entry
    try save()
  }

  /// Notes that the document's words were taken out of search while it was protected.
  public func wordsRemoved(_ id: DocumentID) throws {
    guard var entry = owed[id], entry.wordsRemoved != true else { return }
    entry.wordsRemoved = true
    owed[id] = entry
    try save()
  }

  /// Notes that the save of a change has ended, whether it worked or not.
  public func saveFinished(_ id: DocumentID, change: Int) {
    saving[id]?.remove(change)
    if saving[id]?.isEmpty == true { saving[id] = nil }
  }

  /// The latest change a refresh that reads the file now would cover, or `nil` when it would cover
  /// none: nothing is owed, or a save is still under way.
  public func coverage(_ id: DocumentID) -> Int? {
    guard saving[id] == nil else { return nil }
    return owed[id]?.change
  }

  /// Crosses a document off once a refresh covering every change up to `change` has worked.
  public func finished(_ id: DocumentID, upTo change: Int) throws {
    guard let entry = owed[id], entry.change <= change, saving[id] == nil else { return }
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
