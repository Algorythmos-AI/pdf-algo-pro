import Core
import Foundation
import SwiftData
import Synchronization

/// Version 1 of the library index schema (ADR-0006).
///
/// Every attribute is optional or defaulted and nothing is unique, so the schema can sync through CloudKit later
/// without a migration.
public enum LibrarySchemaV1: VersionedSchema {
  /// The schema version.
  public static let versionIdentifier = Schema.Version(1, 0, 0)

  /// The models in this version.
  public static var models: [any PersistentModel.Type] { [DocumentEntry.self] }

  /// One document's index entry.
  ///
  /// The file is the source of truth; this is derived data.
  @Model
  public final class DocumentEntry {
    /// The document identifier.
    public var id = UUID()
    /// The title shown in the library.
    public var title = ""
    /// The file name inside the library folder.
    public var fileName = ""
    /// When the document was added.
    public var addedAt = Date.distantPast
    /// When the contents last changed.
    public var modifiedAt = Date.distantPast
    /// When the document was last opened.
    public var lastOpenedAt: Date?
    /// The last page shown, zero-based.
    public var lastPageIndex = 0
    /// The page count, zero while unknown.
    public var pageCount = 0
    /// Whether the document is a favourite.
    public var isFavorite = false
    /// The user's tags.
    public var tags: [String] = []
    /// When the document was moved to Recently Deleted.
    public var deletedAt: Date?
    /// Whether the PDF has selectable text.
    public var hasTextLayer = false
    /// Whether the PDF needs a password.
    public var isEncrypted = false

    init(_ document: Document) {
      id = document.id.rawValue
      update(from: document)
    }

    func update(from document: Document) {
      title = document.title
      fileName = document.fileName
      addedAt = document.addedAt
      modifiedAt = document.modifiedAt
      lastOpenedAt = document.lastOpenedAt
      lastPageIndex = document.lastPageIndex
      pageCount = document.pageCount
      isFavorite = document.isFavorite
      tags = document.tags
      deletedAt = document.deletedAt
      hasTextLayer = document.hasTextLayer
      isEncrypted = document.isEncrypted
    }

    var value: Document {
      Document(
        id: DocumentID(rawValue: id), title: title, fileName: fileName, addedAt: addedAt, modifiedAt: modifiedAt,
        lastOpenedAt: lastOpenedAt, lastPageIndex: lastPageIndex, pageCount: pageCount, isFavorite: isFavorite,
        tags: tags, deletedAt: deletedAt, hasTextLayer: hasTextLayer, isEncrypted: isEncrypted)
    }
  }
}

/// The migration plan for the index; later versions add stages here.
public enum LibraryMigrationPlan: SchemaMigrationPlan {
  /// Every schema version, oldest first.
  public static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
  /// No migrations yet.
  public static var stages: [MigrationStage] { [] }
}

/// The SwiftData store, isolated to its own model actor.
@ModelActor
actor SwiftDataIndexStore {
  func all() throws -> [Document] {
    try modelContext.fetch(FetchDescriptor<LibrarySchemaV1.DocumentEntry>()).map(\.value)
  }

  func document(_ id: DocumentID) throws -> Document? {
    try entry(id)?.value
  }

  func upsert(_ document: Document) throws {
    if let existing = try entry(document.id) {
      existing.update(from: document)
    } else {
      modelContext.insert(LibrarySchemaV1.DocumentEntry(document))
    }
    try modelContext.save()
  }

  func delete(_ id: DocumentID) throws {
    guard let existing = try entry(id) else { return }
    modelContext.delete(existing)
    try modelContext.save()
  }

  private func entry(_ id: DocumentID) throws -> LibrarySchemaV1.DocumentEntry? {
    let raw = id.rawValue
    var descriptor = FetchDescriptor<LibrarySchemaV1.DocumentEntry>(predicate: #Predicate { $0.id == raw })
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }
}

/// The library index (ADR-0006), opened with a fallback ladder so a damaged store never stops the
/// app: on disk, then recreated, then in memory, then a plain dictionary. The index can always be
/// rebuilt from the files, so no step loses a document.
///
/// A store that won't open is moved aside, never deleted: it may hold tags, favourites and titles
/// that exist nowhere else, and it may simply be newer than this build, as when a tester installs
/// an older TestFlight build (plan item H6). The last few are kept in a `Kept` folder beside the
/// store, so they can be recovered.
public actor LibraryIndex {
  /// How the index was opened.
  public enum StoreLevel: Sendable, Equatable {
    /// The store on disk opened normally.
    case onDisk
    /// The store on disk could not be opened, so it was deleted and recreated.
    case recreated
    /// Nothing could be opened on disk; a SwiftData store in memory is used for this launch.
    case inMemory
    /// SwiftData is unavailable; entries are kept in a dictionary for this launch.
    case withoutStore
  }

  /// The rung of the ladder the index is on.
  nonisolated public let level: StoreLevel
  private let store: SwiftDataIndexStore?
  private var memory: [DocumentID: Document] = [:]

  /// Opens the index at a store URL, or in memory when the URL is `nil`.
  ///
  /// One store opens at a time in the process: Core Data crashes (SIGSEGV in
  /// `_generateTriggerSQL`) when two containers for the same model load at the same moment, which
  /// parallel tests did. The app opens one store, so this costs it nothing.
  public init(storeURL: URL?) {
    (store, level) = Self.opening.withLock { _ in Self.open(storeURL) }
  }

  private static let opening = Mutex(())

  private static func open(_ storeURL: URL?) -> (SwiftDataIndexStore?, StoreLevel) {
    let schema = Schema(versionedSchema: LibrarySchemaV1.self)
    if let storeURL, let container = try? makeContainer(schema: schema, url: storeURL) {
      return (SwiftDataIndexStore(modelContainer: container), .onDisk)
    }
    if let storeURL {
      keepAside(storeURL)
      if let container = try? makeContainer(schema: schema, url: storeURL) {
        return (SwiftDataIndexStore(modelContainer: container), .recreated)
      }
    }
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    if let container = try? ModelContainer(for: schema, configurations: configuration) {
      return (SwiftDataIndexStore(modelContainer: container), .inMemory)
    }
    return (nil, .withoutStore)
  }

  /// How many stores that wouldn't open are kept; older ones are removed.
  static let keptLimit = 3

  /// The folder unreadable stores are moved to, beside the store.
  static func keptFolder(for storeURL: URL) -> URL {
    storeURL.deletingLastPathComponent().appendingPathComponent("Kept", isDirectory: true)
  }

  /// Moves a store that won't open, with its `-shm` and `-wal` files, into its own folder under `Kept`.
  private static func keepAside(_ storeURL: URL) {
    let fileManager = FileManager.default
    let kept = keptFolder(for: storeURL)
    // Microseconds since 1970, zero-padded, so the names sort in the order the stores were kept.
    let stamp = String(format: "%017lld", Int64(Date().timeIntervalSince1970 * 1_000_000))
    let folder = kept.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    for suffix in ["", "-shm", "-wal"] {
      let file = URL(fileURLWithPath: storeURL.path + suffix)
      guard fileManager.fileExists(atPath: file.path) else { continue }
      if (try? fileManager.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))) == nil {
        // A file that can't be moved still mustn't stop the app from opening a new store.
        try? fileManager.removeItem(at: file)
      }
    }
    let folders = (try? fileManager.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil)) ?? []
    for old in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropLast(keptLimit) {
      try? fileManager.removeItem(at: old)
    }
  }

  private static func makeContainer(schema: Schema, url: URL) throws -> ModelContainer {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
  }

  /// Every entry.
  public func all() async throws -> [Document] {
    guard let store else { return Array(memory.values) }
    return try await store.all()
  }

  /// One entry, or `nil`.
  public func document(_ id: DocumentID) async throws -> Document? {
    guard let store else { return memory[id] }
    return try await store.document(id)
  }

  /// Inserts or replaces an entry.
  public func upsert(_ document: Document) async throws {
    guard let store else {
      memory[document.id] = document
      return
    }
    try await store.upsert(document)
  }

  /// Deletes an entry if it exists.
  public func delete(_ id: DocumentID) async throws {
    guard let store else {
      memory[id] = nil
      return
    }
    try await store.delete(id)
  }
}
