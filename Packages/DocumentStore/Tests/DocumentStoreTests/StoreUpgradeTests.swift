import Core
import CoreData
import Foundation
import SwiftData
import Testing

@testable import DocumentStore

/// The library index's schema as Staging build 27 shipped it, frozen (bar item B11).
///
/// Build 27 was cut on 2026-10-11 from `integration` at 6ccb255. `LibrarySchemaV1` there is the same,
/// attribute for attribute, as in the first app commit (8dfbb59) and on `integration` when this was
/// written, so this is also the schema of build 1 and of every Staging build since. It must never
/// change: a store a tester's phone holds keeps this shape until a newer build migrates it.
///
/// It is written with Core Data and plain `NSManagedObject`s, as SwiftData writes it (the same
/// entity, attribute types, history tracking, and tags archived by `NSSecureUnarchiveFromData`), not
/// with a second SwiftData model class: SwiftData maps model classes to entities by name across the
/// process, and a second `DocumentEntry` class has crashed every test running beside it (#291).
private enum SchemaV1Staging27 {
  /// The schema's version identifier.
  static let versionIdentifier = "1.0.0"

  /// The entry's attributes: name, type, and whether it is optional.
  static let attributes: [(name: String, type: NSAttributeType, isOptional: Bool)] = [
    ("id", .UUIDAttributeType, false),
    ("title", .stringAttributeType, false),
    ("fileName", .stringAttributeType, false),
    ("addedAt", .dateAttributeType, false),
    ("modifiedAt", .dateAttributeType, false),
    ("lastOpenedAt", .dateAttributeType, true),
    ("lastPageIndex", .integer64AttributeType, false),
    ("pageCount", .integer64AttributeType, false),
    ("isFavorite", .booleanAttributeType, false),
    ("tags", .transformableAttributeType, false),
    ("deletedAt", .dateAttributeType, true),
    ("hasTextLayer", .booleanAttributeType, false),
    ("isEncrypted", .booleanAttributeType, false),
  ]

  /// The model with its one entity, `DocumentEntry`.
  static func model() -> NSManagedObjectModel {
    let entry = NSEntityDescription()
    entry.name = "DocumentEntry"
    entry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
    entry.properties = attributes.map { name, type, isOptional in
      let attribute = NSAttributeDescription()
      attribute.name = name
      attribute.attributeType = type
      attribute.isOptional = isOptional
      attribute.renamingIdentifier = name
      if type == .transformableAttributeType {
        attribute.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
      }
      return attribute
    }
    let model = NSManagedObjectModel()
    model.entities = [entry]
    model.versionIdentifiers = [versionIdentifier]
    return model
  }

  /// Writes a store at `url` holding these entries, as build 27 would have.
  static func write(_ documents: [Document], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try LibraryIndex.opening.withLock { _ in
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model())
      let store = try coordinator.addPersistentStore(
        type: .sqlite, at: url, options: [NSPersistentHistoryTrackingKey: true as NSNumber])
      defer { try? coordinator.remove(store) }
      let context = NSManagedObjectContext(.privateQueue)
      context.persistentStoreCoordinator = coordinator
      try context.performAndWait { try insert(documents, into: context) }
    }
  }

  private static func insert(_ documents: [Document], into context: NSManagedObjectContext) throws {
    for document in documents {
      let entry = NSEntityDescription.insertNewObject(forEntityName: "DocumentEntry", into: context)
      entry.setValue(document.id.rawValue, forKey: "id")
      entry.setValue(document.title, forKey: "title")
      entry.setValue(document.fileName, forKey: "fileName")
      entry.setValue(document.addedAt, forKey: "addedAt")
      entry.setValue(document.modifiedAt, forKey: "modifiedAt")
      entry.setValue(document.lastOpenedAt, forKey: "lastOpenedAt")
      entry.setValue(document.lastPageIndex, forKey: "lastPageIndex")
      entry.setValue(document.pageCount, forKey: "pageCount")
      entry.setValue(document.isFavorite, forKey: "isFavorite")
      entry.setValue(document.tags as NSArray, forKey: "tags")
      entry.setValue(document.deletedAt, forKey: "deletedAt")
      entry.setValue(document.hasTextLayer, forKey: "hasTextLayer")
      entry.setValue(document.isEncrypted, forKey: "isEncrypted")
    }
    try context.save()
  }
}

/// A phone's library as Staging build 27 left it: the files, the earlier versions and the index.
///
/// Every record and file is synthetic (AGENTS.md rule 6).
private struct Staging27Library {
  /// When build 27 last ran; the new build launches a day later.
  static let lastRun = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12 00:00 UTC

  let root: URL
  var documents: URL { root.appendingPathComponent("Documents", isDirectory: true) }
  var recentlyDeleted: URL { root.appendingPathComponent("Support/RecentlyDeleted", isDirectory: true) }
  var previousVersions: URL { root.appendingPathComponent("Support/Derived/PreviousVersions", isDirectory: true) }
  var indexStore: URL { root.appendingPathComponent("Support/Derived/Library.store") }

  /// A favourite, tagged, read part-way, saved twice.
  let taxReturn = Document(
    title: "Tax return 2025", fileName: "Tax return 2025.pdf", addedAt: lastRun - 20 * 86_400,
    modifiedAt: lastRun - 3_600, lastOpenedAt: lastRun - 1_800, lastPageIndex: 7, pageCount: 12, isFavorite: true,
    tags: ["2025", "tax"], hasTextLayer: true)
  /// Needs a password; never opened; one earlier version kept the way build 1 kept it.
  let statement = Document(
    title: "Locked statement", fileName: "Locked statement.pdf", addedAt: lastRun - 10 * 86_400,
    modifiedAt: lastRun - 5 * 86_400, pageCount: 3, isEncrypted: true)
  /// A title and tag outside ASCII, renamed so its file name has a number.
  let receipt = Document(
    title: "Reçu café", fileName: "Reçu café 2.pdf", addedAt: lastRun - 2 * 86_400, modifiedAt: lastRun - 2 * 86_400,
    lastOpenedAt: lastRun - 86_400, lastPageIndex: 0, pageCount: 1, tags: ["été"])
  /// In Recently Deleted for two days.
  let invoice = Document(
    title: "Old invoice", fileName: "Old invoice.pdf", addedAt: lastRun - 40 * 86_400,
    modifiedAt: lastRun - 40 * 86_400, lastOpenedAt: lastRun - 30 * 86_400, lastPageIndex: 1, pageCount: 2,
    tags: ["work"], deletedAt: lastRun - 2 * 86_400)

  var all: [Document] { [taxReturn, statement, receipt, invoice] }

  /// The two saves of the tax return, as build 27 named them: milliseconds since 1970, zero-padded.
  let taxReturnSaves = [lastRun - 86_400, lastRun - 3_600]
  /// The single earlier version build 1 kept of the statement, as `<id>.pdf`, saved at this time.
  let statementSave = lastRun - 5 * 86_400

  static func pdf(_ text: String) -> Data { Data("%PDF-1.7\n% \(text)\n%%EOF\n".utf8) }

  /// Lays the library out in a fresh folder.
  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("staging-27-\(UUID().uuidString)")
    let fileManager = FileManager.default
    for folder in [documents, recentlyDeleted, previousVersions] {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    for document in all {
      let folder = document.isDeleted ? recentlyDeleted : documents
      try Self.pdf(document.title).write(to: folder.appendingPathComponent(document.fileName))
    }
    let history = previousVersions.appendingPathComponent(taxReturn.id.rawValue.uuidString, isDirectory: true)
    try fileManager.createDirectory(at: history, withIntermediateDirectories: true)
    for (number, saved) in taxReturnSaves.enumerated() {
      try Self.pdf("tax return, save \(number + 1)").write(to: history.appendingPathComponent(Self.versionName(saved)))
    }
    let single = previousVersions.appendingPathComponent("\(statement.id.rawValue.uuidString).pdf")
    try Self.pdf("statement, earlier").write(to: single)
    try fileManager.setAttributes([.modificationDate: statementSave], ofItemAtPath: single.path)
    try SchemaV1Staging27.write(all, to: indexStore)
  }

  /// The store's schema hashes and this build's, for a failure message.
  var storeState: String {
    let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: indexStore)
    let stored = (metadata?[NSStoreModelVersionHashesKey] as? [String: Data])?.mapValues { $0.base64EncodedString() }
    func hashes(_ schema: any VersionedSchema.Type) -> [String: String] {
      NSManagedObjectModel.makeManagedObjectModel(for: schema.models)?
        .entityVersionHashesByName.mapValues { $0.base64EncodedString() } ?? [:]
    }
    return "Store hashes \(stored ?? [:]), identifiers \(metadata?[NSStoreModelVersionIdentifiersKey] ?? "none"); "
      + "LibrarySchemaV1 hashes \(hashes(LibrarySchemaV1.self)), LibrarySchemaV2 hashes \(hashes(LibrarySchemaV2.self))"
  }

  static func versionName(_ date: Date) -> String {
    String(format: "%015lld.pdf", Int64(date.timeIntervalSince1970 * 1000))
  }

  /// The library as this build opens it at launch.
  func open(now: Date) -> (LibraryIndex, FileDocumentLibrary) {
    let index = LibraryIndex(storeURL: indexStore)
    let library = FileDocumentLibrary(
      documentsFolder: documents, deletedFolder: recentlyDeleted, previousVersionsFolder: previousVersions,
      index: index, now: { now })
    return (index, library)
  }
}

@Suite("Upgrading from a Staging build (B11)")
struct StoreUpgradeTests {
  @Test("The frozen Staging 27 schema is still LibrarySchemaV1: a shipped schema is never changed in place")
  func shippedSchemaIsUnchanged() throws {
    let shipped = try #require(SchemaV1Staging27.model().entitiesByName["DocumentEntry"])
    let current = try #require(
      NSManagedObjectModel.makeManagedObjectModel(for: LibrarySchemaV1.models)?.entitiesByName["DocumentEntry"])
    func describe(_ entity: NSEntityDescription) -> [String] {
      entity.attributesByName.values.map {
        "\($0.name) type \($0.attributeType.rawValue) optional \($0.isOptional) \($0.valueTransformerName ?? "")"
      }.sorted()
    }
    #expect(
      shipped.versionHash == current.versionHash,
      """
      LibrarySchemaV1 no longer has the shape Staging build 27 shipped, so a tester's store would no longer \
      open as V1. Put V1 back, and add the change as LibrarySchemaV2 with a stage in LibraryMigrationPlan. \
      Shipped: \(describe(shipped)). Now: \(describe(current)).
      """)
    #expect(LibrarySchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(LibraryMigrationPlan.schemas.first == LibrarySchemaV1.self)
  }

  @Test("A library Staging build 27 left opens in this build with every entry, file and earlier version")
  func staging27LibrarySurvives() async throws {
    let old = try Staging27Library()
    // This build can read the store, so it is opened and never taken for a newer build's.
    #expect(LibraryIndex.condition(of: old.indexStore) == .unavailable, "\(old.storeState)")

    let launch = Staging27Library.lastRun + 86_400
    let (index, library) = old.open(now: launch)
    #expect(index.level == .onDisk, "\(old.storeState)")
    #expect(!FileManager.default.fileExists(atPath: LibraryIndex.keptFolder(for: old.indexStore).path))

    // Every entry, every field: title, file name, dates, reading position, page count, favourite,
    // tags, deletion date, text layer and password.
    let entries = try await index.all().sorted { $0.title < $1.title }
    #expect(entries == old.all.sorted { $0.title < $1.title })

    // The files and the index agree, so the launch's reconciliation adds and removes nothing.
    #expect(try await library.reconcileWithFiles() == Reconciliation())
    #expect(try await library.purgeExpired(now: launch).isEmpty)

    #expect(
      try await library.documents(in: .all, sortedBy: .title).map(\.id) == [
        old.statement.id, old.receipt.id, old.taxReturn.id,
      ])
    #expect(try await library.documents(in: .favorites, sortedBy: .title).map(\.id) == [old.taxReturn.id])
    #expect(
      try await library.documents(in: .recents, sortedBy: .recentlyOpened).map(\.id) == [
        old.taxReturn.id, old.receipt.id,
      ])
    #expect(try await library.documents(in: .tag("ÉTÉ"), sortedBy: .title).map(\.id) == [old.receipt.id])
    #expect(try await library.documents(in: .recentlyDeleted, sortedBy: .title).map(\.id) == [old.invoice.id])
    #expect(try await library.allTags() == ["2025", "été", "tax"])
    for document in old.all {
      #expect(
        try Data(contentsOf: try await library.fileURL(for: document.id)) == Staging27Library.pdf(document.title))
    }

    // Earlier versions: build 27's history as it was, and build 1's single version moved into one.
    let saves = await library.versions(of: old.taxReturn.id)
    #expect(saves.map(\.id) == old.taxReturnSaves.reversed().map(Staging27Library.versionName))
    #expect(saves.map(\.savedAt) == old.taxReturnSaves.reversed())
    let statementVersions = await library.versions(of: old.statement.id)
    #expect(statementVersions.map(\.savedAt) == [old.statementSave])
    #expect(await !library.hasPreviousVersion(of: old.receipt.id))

    // Still kept 30 days after the deletion build 27 recorded, then purged.
    let deletedAt = try #require(old.invoice.deletedAt)
    #expect(try await library.purgeExpired(now: deletedAt + FileDocumentLibrary.retention) == [old.invoice.id])
  }

  @Test("A change made in this build to a Staging 27 store is kept at the next launch, beside the old entries")
  func changesToAnUpgradedStoreAreKept() async throws {
    let old = try Staging27Library()
    let launch = Staging27Library.lastRun + 86_400
    let (_, library) = old.open(now: launch)
    try await library.setFavorite(true, for: old.statement.id)
    try await library.setTags(["bank"], for: old.statement.id)
    try await library.recordOpened(old.statement.id, pageIndex: 2)

    let (reopened, _) = old.open(now: launch + 60)
    #expect(reopened.level == .onDisk)
    var statement = old.statement
    statement.isFavorite = true
    statement.tags = ["bank"]
    statement.lastOpenedAt = launch
    statement.lastPageIndex = 2
    let expected = [old.taxReturn, statement, old.receipt, old.invoice].sorted { $0.title < $1.title }
    #expect(try await reopened.all().sorted { $0.title < $1.title } == expected)
  }

  @Test("A Staging 27 store moves to V2, and a file renamed and moved in Files after that keeps its entry (#224)")
  func upgradedLibraryFollowsRenamedFiles() async throws {
    let old = try Staging27Library()
    let launch = Staging27Library.lastRun + 86_400
    let (index, library) = old.open(now: launch)
    #expect(index.level == .onDisk, "\(old.storeState)")
    #expect(try await index.fileIdentities().isEmpty, "Build 27 recorded no file identities")

    // The launch's reconciliation records an identity for each file still at its name.
    #expect(try await library.reconcileWithFiles() == Reconciliation())
    let recorded = try await index.fileIdentities()
    #expect(
      Set(recorded.keys) == Set([old.taxReturn.id, old.statement.id, old.receipt.id]),
      "Recorded \(recorded); \(old.storeState)")
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: old.indexStore)
    let current = try #require(NSManagedObjectModel.makeManagedObjectModel(for: LibrarySchemaV2.models))
    #expect(current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata), "\(old.storeState)")

    // In Files, the tax return is renamed and moved into a folder; then the app launches again.
    let folder = old.documents.appendingPathComponent("2025", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.moveItem(
      at: old.documents.appendingPathComponent(old.taxReturn.fileName),
      to: folder.appendingPathComponent("Tax return 2025 filed.pdf"))
    let (reopened, relaunched) = old.open(now: launch + 60)

    let result = try await relaunched.reconcileWithFiles()

    let identities = try await reopened.fileIdentities()
    let found = FileIdentity(of: folder.appendingPathComponent("Tax return 2025 filed.pdf"))?.stored ?? "none"
    #expect(
      result == Reconciliation(),
      "removed \(result.removed), added \(result.added.map(\.fileName)); recorded \(identities), the file's \(found)")
    var taxReturn = old.taxReturn
    taxReturn.fileName = "2025/Tax return 2025 filed.pdf"
    #expect(try await reopened.document(old.taxReturn.id) == taxReturn, "Same entry, every field, a new path")
    #expect(await relaunched.versions(of: old.taxReturn.id).map(\.savedAt) == old.taxReturnSaves.reversed())
    #expect(
      try Data(contentsOf: try await relaunched.fileURL(for: old.taxReturn.id))
        == Staging27Library.pdf(old.taxReturn.title))
  }
}
