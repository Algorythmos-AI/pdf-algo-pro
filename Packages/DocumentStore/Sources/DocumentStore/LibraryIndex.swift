import Core
import CoreData
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

/// Version 2 of the library index schema: version 1, the identity of each entry's file, and when an
/// entry's file was found gone (#224).
///
/// Like version 1, every attribute is optional or defaulted and nothing is unique. Version 1 shipped
/// in Staging builds and is never changed; a store in it migrates to this one in a lightweight stage,
/// since both new attributes are optional. Its entries have no identity until the library records
/// one for each file still at its name.
public enum LibrarySchemaV2: VersionedSchema {
  /// The schema version.
  public static let versionIdentifier = Schema.Version(2, 0, 0)

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
    /// The file's path inside the library folder, such as `Report.pdf` or `Work/Report.pdf`.
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
    /// The identity of the file, so it is found again when the Files app renames or moves it
    /// (`FileIdentity`); `nil` until the library has recorded it.
    public var fileIdentity: String?
    /// When the library found the file gone, so far that it couldn't follow it; `nil` while it is
    /// there. Such an entry is kept, out of the library, for a while in case the file comes back.
    public var goneAt: Date?

    init(_ document: Document) {
      id = document.id.rawValue
      update(from: document)
    }

    /// Takes every value but the file identity and `goneAt`, which only `setFileIdentity` and
    /// `setGone` change.
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

/// The schema the index is in now.
typealias CurrentLibrarySchema = LibrarySchemaV2

/// The migration plan for the index; later versions add stages here.
public enum LibraryMigrationPlan: SchemaMigrationPlan {
  /// Every schema version, oldest first.
  public static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self] }
  /// Version 2 only adds optional attributes, so a lightweight stage migrates to it.
  public static var stages: [MigrationStage] {
    [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)]
  }
}

/// Where the library keeps its index (ADR-0006).
///
/// The app uses `LibraryIndex`. The library reads and writes the index only through these calls, so
/// a test can stand in a store whose writes fail.
public protocol LibraryStore: Sendable {
  /// Every entry, but those whose file is gone (`setGone`).
  func all() async throws -> [Document]
  /// One entry, or `nil`; also `nil` for an entry whose file is gone.
  func document(_ id: DocumentID) async throws -> Document?
  /// Inserts or replaces an entry.
  func upsert(_ document: Document) async throws
  /// Deletes an entry if it exists.
  func delete(_ id: DocumentID) async throws
  /// The file identity recorded for each entry that has one (#224).
  func fileIdentities() async throws -> [DocumentID: String]
  /// Records the identity of an entry's file, or clears it with `nil`; does nothing without the entry.
  ///
  /// `upsert` never changes it, so an entry keeps its identity through every other change.
  func setFileIdentity(_ identity: String?, for id: DocumentID) async throws
  /// The entries whose file is gone, with when it was found gone (#224).
  func goneEntries() async throws -> [(document: Document, goneAt: Date)]
  /// Marks an entry's file gone at a date, taking the entry out of `all()`, or back with `nil`; does
  /// nothing without the entry. `upsert` never changes it.
  func setGone(_ date: Date?, for id: DocumentID) async throws
}

/// The SwiftData store, isolated to its own model actor.
@ModelActor
actor SwiftDataIndexStore {
  typealias Entry = CurrentLibrarySchema.DocumentEntry

  func all() throws -> [Document] {
    try modelContext.fetch(FetchDescriptor<Entry>()).filter { $0.goneAt == nil }.map(\.value)
  }

  func document(_ id: DocumentID) throws -> Document? {
    guard let entry = try entry(id), entry.goneAt == nil else { return nil }
    return entry.value
  }

  func upsert(_ document: Document) throws {
    if let existing = try entry(document.id) {
      existing.update(from: document)
    } else {
      modelContext.insert(Entry(document))
    }
    try save()
  }

  func delete(_ id: DocumentID) throws {
    guard let existing = try entry(id) else { return }
    modelContext.delete(existing)
    try save()
  }

  func fileIdentities() throws -> [DocumentID: String] {
    var identities: [DocumentID: String] = [:]
    for entry in try modelContext.fetch(FetchDescriptor<Entry>()) {
      if let identity = entry.fileIdentity { identities[DocumentID(rawValue: entry.id)] = identity }
    }
    return identities
  }

  func setFileIdentity(_ identity: String?, for id: DocumentID) throws {
    guard let existing = try entry(id), existing.fileIdentity != identity else { return }
    existing.fileIdentity = identity
    try save()
  }

  func goneEntries() throws -> [(document: Document, goneAt: Date)] {
    try modelContext.fetch(FetchDescriptor<Entry>()).compactMap { entry in
      entry.goneAt.map { (document: entry.value, goneAt: $0) }
    }
  }

  func setGone(_ date: Date?, for id: DocumentID) throws {
    guard let existing = try entry(id), existing.goneAt != date else { return }
    existing.goneAt = date
    try save()
  }

  /// Saves, or puts the context back as it was saved last: a change that failed must not be saved
  /// later by an unrelated one (#225).
  private func save() throws {
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func entry(_ id: DocumentID) throws -> Entry? {
    let raw = id.rawValue
    var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == raw })
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }
}

/// The library index (ADR-0006), opened with a fallback ladder so a damaged store never stops the
/// app: on disk, then recreated, then in memory, then a plain dictionary. The index can always be
/// rebuilt from the files, so no step loses a document.
///
/// The store holds tags, favourites, reading positions and deletion dates that exist nowhere else,
/// so a store that won't open is never replaced while it may still open later (#226). It gets a
/// second try first. A store written by a newer build, as when a tester installs an older TestFlight
/// build (plan item H6), and a store that can't be read at the moment, are left as they are, and the
/// launch uses an index in memory (bar item B11). Only a file that isn't a store at all is moved
/// aside, never deleted, into a `Kept` folder beside the store, and a new store made; the last few
/// are kept, so they can be recovered.
public actor LibraryIndex: LibraryStore {
  /// How the index was opened.
  public enum StoreLevel: Sendable, Equatable {
    /// The store on disk opened normally.
    case onDisk
    /// The file on disk was not a store, so it was kept aside and a new store made.
    case recreated
    /// The store on disk was written by a newer build. It is left untouched, and this launch uses an
    /// index in memory, so nothing done now is kept (B11).
    case newerStore
    /// Nothing could be opened on disk; a SwiftData store in memory is used for this launch. A store
    /// on disk is left as it is, to be tried again at the next launch.
    case inMemory
    /// SwiftData is unavailable; entries are kept in a dictionary for this launch.
    case withoutStore
  }

  /// The rung of the ladder the index is on.
  nonisolated public let level: StoreLevel
  private let store: SwiftDataIndexStore?
  private var memory: [DocumentID: Document] = [:]
  private var memoryIdentities: [DocumentID: String] = [:]
  private var memoryGone: [DocumentID: Date] = [:]

  /// Opens the index at a store URL, or in memory when the URL is `nil`.
  ///
  /// One store opens at a time in the process: Core Data crashes (SIGSEGV in
  /// `_generateTriggerSQL`) when two containers for the same model load at the same moment, which
  /// parallel tests did. The app opens one store, so this costs it nothing.
  public init(storeURL: URL?) {
    (store, level) = Self.opening.withLock { _ in Self.open(storeURL) }
  }

  /// Held while a store opens; tests that make a store of their own hold it too.
  static let opening = Mutex(())

  private static func open(_ storeURL: URL?) -> (SwiftDataIndexStore?, StoreLevel) {
    let schema = Schema(versionedSchema: CurrentLibrarySchema.self)
    var level = StoreLevel.inMemory
    if let storeURL {
      if let opened = openOnDisk(schema: schema, url: storeURL, level: &level) { return opened }
    }
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    if let container = try? ModelContainer(for: schema, configurations: configuration) {
      return (SwiftDataIndexStore(modelContainer: container), level)
    }
    return (nil, .withoutStore)
  }

  /// Opens the store on disk, or returns `nil` with the level the index in memory is on instead.
  private static func openOnDisk(
    schema: Schema, url: URL, level: inout StoreLevel
  ) -> (SwiftDataIndexStore?, StoreLevel)? {
    // A newer build's store is never opened: SwiftData would migrate it down to this build's schema,
    // losing what this build doesn't know, and the newer build would find it changed (B11, H6).
    guard condition(of: url) != .newer else {
      level = .newerStore
      return nil
    }
    // A second try before anything else (ADR-0006): a failure can be momentary.
    for _ in 0..<2 {
      if let container = try? makeContainer(schema: schema, url: url) {
        return (SwiftDataIndexStore(modelContainer: container), .onDisk)
      }
    }
    switch condition(of: url) {
    case .notAStore:
      if keepAside(url), let container = try? makeContainer(schema: schema, url: url) {
        return (SwiftDataIndexStore(modelContainer: container), .recreated)
      }
    case .newer:
      level = .newerStore
    case .missing, .unavailable:
      break
    }
    return nil
  }

  /// What is at a store's URL, looked at without opening or changing it.
  enum Condition: Equatable {
    /// Nothing.
    case missing
    /// A file that isn't a SQLite database; it can never open.
    case notAStore
    /// A store none of this build's schema versions can read: a newer build wrote it.
    case newer
    /// A store this build can read, or a file that can't be read at the moment; it may open next time.
    case unavailable
  }

  /// Looks at a store without opening or changing it.
  static func condition(of storeURL: URL) -> Condition {
    guard FileManager.default.fileExists(atPath: storeURL.path) else { return .missing }
    guard let handle = try? FileHandle(forReadingFrom: storeURL) else { return .unavailable }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 16) else { return .unavailable }
    guard header == Data("SQLite format 3\u{0}".utf8) else { return .notAStore }
    guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
    else { return .unavailable }
    let known = LibraryMigrationPlan.schemas.compactMap { NSManagedObjectModel.makeManagedObjectModel(for: $0.models) }
    // Without a model to compare with, the store is taken to be this build's, and opened as usual.
    guard known.count == LibraryMigrationPlan.schemas.count else { return .unavailable }
    let readable = known.contains { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }
    return readable ? .unavailable : .newer
  }

  /// How many stores that wouldn't open are kept; older ones are removed.
  static let keptLimit = 3

  /// The folder unreadable stores are moved to, beside the store.
  static func keptFolder(for storeURL: URL) -> URL {
    storeURL.deletingLastPathComponent().appendingPathComponent("Kept", isDirectory: true)
  }

  /// Moves a store that won't open, with its `-shm` and `-wal` files, into its own folder under `Kept`.
  ///
  /// Returns `false`, with every file back where it was, when one can't be moved: nothing is deleted,
  /// since the `-wal` holds the latest changes, and no new store is made beside what is left.
  private static func keepAside(_ storeURL: URL) -> Bool {
    let fileManager = FileManager.default
    let kept = keptFolder(for: storeURL)
    // Microseconds since 1970, zero-padded, so the names sort in the order the stores were kept.
    let stamp = String(format: "%017lld", Int64(Date().timeIntervalSince1970 * 1_000_000))
    let folder = kept.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    var moved: [(from: URL, to: URL)] = []
    for suffix in ["", "-shm", "-wal"] {
      let file = URL(fileURLWithPath: storeURL.path + suffix)
      guard fileManager.fileExists(atPath: file.path) else { continue }
      let destination = folder.appendingPathComponent(file.lastPathComponent)
      guard (try? fileManager.moveItem(at: file, to: destination)) != nil else {
        for (from, to) in moved.reversed() { try? fileManager.moveItem(at: to, to: from) }
        if (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
          try? fileManager.removeItem(at: folder)
        }
        return false
      }
      moved.append((file, destination))
    }
    let folders = (try? fileManager.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil)) ?? []
    for old in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropLast(keptLimit) {
      try? fileManager.removeItem(at: old)
    }
    return true
  }

  private static func makeContainer(schema: Schema, url: URL) throws -> ModelContainer {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
  }

  /// Every entry, but those whose file is gone.
  public func all() async throws -> [Document] {
    guard let store else { return memory.values.filter { memoryGone[$0.id] == nil } }
    return try await store.all()
  }

  /// One entry, or `nil`; also `nil` for an entry whose file is gone.
  public func document(_ id: DocumentID) async throws -> Document? {
    guard let store else { return memoryGone[id] == nil ? memory[id] : nil }
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
      memoryIdentities[id] = nil
      memoryGone[id] = nil
      return
    }
    try await store.delete(id)
  }

  /// The file identity recorded for each entry that has one.
  public func fileIdentities() async throws -> [DocumentID: String] {
    guard let store else { return memoryIdentities }
    return try await store.fileIdentities()
  }

  /// Records the identity of an entry's file, or clears it with `nil`; does nothing without the entry.
  public func setFileIdentity(_ identity: String?, for id: DocumentID) async throws {
    guard let store else {
      if memory[id] != nil { memoryIdentities[id] = identity }
      return
    }
    try await store.setFileIdentity(identity, for: id)
  }

  /// The entries whose file is gone, with when it was found gone.
  public func goneEntries() async throws -> [(document: Document, goneAt: Date)] {
    guard let store else {
      return memoryGone.compactMap { id, date in memory[id].map { (document: $0, goneAt: date) } }
    }
    return try await store.goneEntries()
  }

  /// Marks an entry's file gone at a date, or back with `nil`; does nothing without the entry.
  public func setGone(_ date: Date?, for id: DocumentID) async throws {
    guard let store else {
      if memory[id] != nil { memoryGone[id] = date }
      return
    }
    try await store.setGone(date, for: id)
  }
}
