import Core
import Foundation

/// The library index as the app opens it at launch: on a background task, so launch never waits for
/// the store to open or for a schema migration to run (#244).
///
/// Every call waits until the store is open, so the library shows its loading state meanwhile. The
/// store opens as `LibraryIndex` opens it, with the same fallback ladder.
public final class OpeningLibraryIndex: LibraryStore, Sendable {
  private let opening: Task<LibraryIndex, Never>

  /// Starts opening the index at a store URL, or in memory when the URL is `nil`, and returns at once.
  public init(storeURL: URL?) {
    opening = Task.detached(priority: .userInitiated) { LibraryIndex(storeURL: storeURL) }
  }

  /// How the index was opened, once it has.
  public var level: LibraryIndex.StoreLevel {
    get async { await opening.value.level }
  }

  /// Every entry, but those whose file is gone.
  public func all() async throws -> [Document] {
    try await opening.value.all()
  }

  /// One entry, or `nil`; also `nil` for an entry whose file is gone.
  public func document(_ id: DocumentID) async throws -> Document? {
    try await opening.value.document(id)
  }

  /// Inserts or replaces an entry.
  public func upsert(_ document: Document) async throws {
    try await opening.value.upsert(document)
  }

  /// Deletes an entry if it exists.
  public func delete(_ id: DocumentID) async throws {
    try await opening.value.delete(id)
  }

  /// The file identity recorded for each entry that has one.
  public func fileIdentities() async throws -> [DocumentID: String] {
    try await opening.value.fileIdentities()
  }

  /// Records the identity of an entry's file, or clears it with `nil`; does nothing without the entry.
  public func setFileIdentity(_ identity: String?, for id: DocumentID) async throws {
    try await opening.value.setFileIdentity(identity, for: id)
  }

  /// The entries whose file is gone, with when it was found gone.
  public func goneEntries() async throws -> [(document: Document, goneAt: Date)] {
    try await opening.value.goneEntries()
  }

  /// Marks an entry's file gone at a date, or back with `nil`; does nothing without the entry.
  public func setGone(_ date: Date?, for id: DocumentID) async throws {
    try await opening.value.setGone(date, for: id)
  }
}
