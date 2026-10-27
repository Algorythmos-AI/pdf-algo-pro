import Foundation

/// Documents whose search text and Spotlight entry still have to catch up with their file (#236).
///
/// A refresh is written down before it starts and crossed off once it has worked, so one that failed,
/// or that the app was stopped in the middle of, is done again at the next library load. Only
/// document identifiers are kept, in a small file on the device.
public actor PendingRefreshes {
  private let url: URL?
  private var ids: Set<DocumentID>

  /// Opens the list kept at `url`, or one in memory when `url` is `nil`.
  ///
  /// A list that can't be read starts empty; it only costs a refresh that would have been retried.
  public init(url: URL?) {
    self.url = url
    let stored = url.flatMap { try? Data(contentsOf: $0) }.flatMap {
      try? JSONDecoder().decode([DocumentID].self, from: $0)
    }
    ids = Set(stored ?? [])
  }

  /// The documents still to refresh, in a stable order.
  public var all: [DocumentID] {
    ids.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
  }

  /// Writes a document down as still to refresh.
  ///
  /// - Throws: when the list can't be written, so the caller knows a failure would not be retried.
  public func add(_ id: DocumentID) throws {
    guard ids.insert(id).inserted else { return }
    try save()
  }

  /// Crosses a document off.
  public func remove(_ id: DocumentID) throws {
    guard ids.remove(id) != nil else { return }
    try save()
  }

  private func save() throws {
    guard let url else { return }
    let data = try JSONEncoder().encode(all)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
