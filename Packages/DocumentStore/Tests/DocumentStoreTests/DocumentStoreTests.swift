import Core
import CoreData
import Foundation
import SwiftData
import Testing

@testable import DocumentStore

private let pdf = Data("%PDF-1.7\n1 0 obj << >> endobj\n%%EOF\n".utf8)

/// A library in a fresh temporary folder, with a clock the test controls.
private struct Harness {
  let root: URL
  let clock: TestClock
  let library: FileDocumentLibrary

  init(storeURL: URL? = nil, index: (any LibraryStore)? = nil) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
    clock = TestClock()
    let clock = self.clock
    library = FileDocumentLibrary(
      documentsFolder: root.appendingPathComponent("Documents"), deletedFolder: root.appendingPathComponent("Deleted"),
      previousVersionsFolder: root.appendingPathComponent("Previous"),
      index: index ?? LibraryIndex(storeURL: storeURL ?? root.appendingPathComponent("Index/library.store")),
      now: { clock.now })
  }

  var documentsFolder: URL { root.appendingPathComponent("Documents") }

  /// Every file in the library's folder and in Recently Deleted, as "Folder/name".
  func files() throws -> [String] {
    try ["Documents", "Deleted"].flatMap { folder in
      try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
        .map { "\(folder)/\($0)" }
    }.sorted()
  }

  /// The files of a document's earlier versions.
  func versionFiles(of id: DocumentID) -> [String] {
    let folder = root.appendingPathComponent("Previous/\(id.rawValue.uuidString)")
    return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
  }

  func source(named name: String, data: Data = pdf) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/\(name)")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
  }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date { lock.withLock { current } }
  func advance(days: Double) { lock.withLock { current += days * 86_400 } }
}

@Suite("File library")
struct FileDocumentLibraryTests {
  @Test("Imported PDFs become real files named after their title (FR-LIB-001)")
  func importCopiesTheFile() async throws {
    let harness = try Harness()
    let document = try await harness.library.importDocument(from: harness.source(named: "Lease agreement.pdf"))
    #expect(document.title == "Lease agreement")
    let url = try await harness.library.fileURL(for: document.id)
    #expect(url.lastPathComponent == "Lease agreement.pdf")
    #expect(try Data(contentsOf: url) == pdf)
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).map(\.id) == [document.id])
  }

  @Test("Name clashes get a number instead of overwriting")
  func clashingNamesAreNumbered() async throws {
    let harness = try Harness()
    let first = try await harness.library.addDocument(data: pdf, title: "Report")
    let second = try await harness.library.addDocument(data: pdf, title: "Report")
    #expect(first.fileName == "Report.pdf" && second.fileName == "Report 2.pdf")
  }

  @Test("Anything that is not a PDF is refused", arguments: [Data(), Data("hello".utf8), Data("<html>".utf8)])
  func nonPDFsAreRefused(data: Data) async throws {
    let harness = try Harness()
    await #expect(throws: LibraryError.notAPDF) { try await harness.library.addDocument(data: data, title: "x") }
    await #expect(throws: LibraryError.notAPDF) {
      try await harness.library.importDocument(from: harness.source(named: "fake.pdf", data: data))
    }
  }

  @Test func missingSourcesFailWithoutChangingTheLibrary() async throws {
    let harness = try Harness()
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).pdf")
    await #expect(throws: LibraryError.fileAccessFailed) { try await harness.library.importDocument(from: missing) }
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).isEmpty)
  }

  @Test("File names are made safe; titles keep what the user typed")
  func unsafeTitles() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "  ../Q3: plan/v2  ")
    #expect(document.title == "../Q3: plan/v2")
    #expect(document.fileName == "-Q3- plan-v2.pdf")
    let untitled = try await harness.library.addDocument(data: pdf, title: "   ")
    #expect(untitled.title == "Untitled")
    #expect(FileDocumentLibrary.safeFileName("...") == "Document")
  }

  @Test("Renaming renames the file too, and empty titles are refused")
  func rename() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Draft")
    let renamed = try await harness.library.rename(document.id, to: " Final ")
    #expect(renamed.title == "Final" && renamed.fileName == "Final.pdf")
    #expect(FileManager.default.fileExists(atPath: harness.documentsFolder.appendingPathComponent("Final.pdf").path))
    #expect(!FileManager.default.fileExists(atPath: harness.documentsFolder.appendingPathComponent("Draft.pdf").path))
    await #expect(throws: LibraryError.emptyTitle) { try await harness.library.rename(document.id, to: "  ") }
    await #expect(throws: LibraryError.notFound) { try await harness.library.rename(DocumentID(), to: "x") }
  }

  @Test func favouritesTagsAndReadingPosition() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Book")
    try await harness.library.setFavorite(true, for: document.id)
    try await harness.library.setTags(["Tax", " tax ", "Home"], for: document.id)
    try await harness.library.recordOpened(document.id, pageIndex: 41)
    let stored = try #require(try await harness.library.document(withID: document.id))
    #expect(stored.isFavorite && stored.tags == ["Home", "Tax"] && stored.lastPageIndex == 41)
    #expect(stored.lastOpenedAt == harness.clock.now)
    #expect(try await harness.library.allTags() == ["Home", "Tax"])
    #expect(try await harness.library.documents(in: .favorites, sortedBy: .title).count == 1)
    #expect(try await harness.library.documents(in: .tag("home"), sortedBy: .title).count == 1)
    #expect(try await harness.library.documents(in: .recents, sortedBy: .recentlyOpened).count == 1)
  }

  @Test func inspectionAndModificationAreRecorded() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Scan")
    try await harness.library.updateInspection(
      PDFInspection(pageCount: 4, isEncrypted: true, pages: [PageText(pageIndex: 0, text: "text")]), for: document.id)
    harness.clock.advance(days: 1)
    try await harness.library.recordModified(document.id)
    let stored = try #require(try await harness.library.document(withID: document.id))
    #expect(stored.pageCount == 4 && stored.isEncrypted && stored.hasTextLayer)
    #expect(stored.modifiedAt > stored.addedAt)
  }

  @Test("Deleted documents wait 30 days in Recently Deleted, then are purged")
  func recentlyDeleted() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Old")
    try await harness.library.moveToRecentlyDeleted(document.id)
    try await harness.library.moveToRecentlyDeleted(document.id)
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).isEmpty)
    #expect(try await harness.library.documents(in: .recentlyDeleted, sortedBy: .title).count == 1)
    #expect(!FileManager.default.fileExists(atPath: harness.documentsFolder.appendingPathComponent("Old.pdf").path))
    #expect(FileManager.default.fileExists(atPath: try await harness.library.fileURL(for: document.id).path))

    harness.clock.advance(days: 29)
    #expect(try await harness.library.purgeExpired(now: harness.clock.now).isEmpty)
    harness.clock.advance(days: 1)
    #expect(try await harness.library.purgeExpired(now: harness.clock.now) == [document.id])
    #expect(try await harness.library.document(withID: document.id) == nil)
  }

  @Test func restoreBringsTheFileBack() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Keep")
    try await harness.library.moveToRecentlyDeleted(document.id)
    try await harness.library.restore(document.id)
    try await harness.library.restore(document.id)
    let stored = try #require(try await harness.library.document(withID: document.id))
    #expect(!stored.isDeleted)
    #expect(
      FileManager.default.fileExists(atPath: harness.documentsFolder.appendingPathComponent(stored.fileName).path))
  }

  @Test("Permanent deletion removes the file and the entry (FR-LIB-006)")
  func deletePermanently() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Gone")
    let url = try await harness.library.fileURL(for: document.id)
    try await harness.library.deletePermanently(document.id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    await #expect(throws: LibraryError.notFound) { try await harness.library.fileURL(for: document.id) }
  }

  @Test("Nothing to restore until a save has kept an earlier version (FR-EDIT-008)")
  func noPreviousVersionAtFirst() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Fresh")
    #expect(await !harness.library.hasPreviousVersion(of: document.id))
    await #expect(throws: LibraryError.notFound) { try await harness.library.restorePreviousVersion(of: document.id) }
  }

  @Test("Each save keeps a version; restoring one keeps the current file too, so it can be undone (FR-EDIT-008)")
  func versionHistory() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Lease")
    let url = try await harness.library.fileURL(for: document.id)
    let edits = (1...3).map { Data("%PDF-1.7\n% edit \($0)\n%%EOF\n".utf8) }
    for edit in edits {
      let kept = try #require(try await harness.library.previousVersionURL(for: document.id))
      try FileManager.default.copyItem(at: url, to: kept)
      try edit.write(to: url)
      harness.clock.advance(days: 1)
    }
    let versions = await harness.library.versions(of: document.id)
    #expect(versions.count == 3 && versions.map(\.savedAt) == versions.map(\.savedAt).sorted(by: >))
    #expect(await harness.library.versionsSize() > 0)

    let oldest = try #require(versions.last)
    try await harness.library.restore(oldest, of: document.id)
    #expect(try Data(contentsOf: url) == pdf, "The first version is back")
    let after = await harness.library.versions(of: document.id)
    #expect(after.count == 3 && !after.contains(oldest), "The current file was kept; the restored one moved in")

    try await harness.library.restorePreviousVersion(of: document.id)
    #expect(try Data(contentsOf: url) == edits[2], "Restoring the newest undoes the restore")
    try await harness.library.deleteAllVersions()
    #expect(await !harness.library.hasPreviousVersion(of: document.id))
    await #expect(throws: LibraryError.notFound) { try await harness.library.restorePreviousVersion(of: document.id) }
  }

  @Test("Versions past 30 days go, and the quota is the lesser of 2 GB and 5% of free space")
  func versionRetention() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Old")
    let url = try await harness.library.fileURL(for: document.id)
    let first = try #require(try await harness.library.previousVersionURL(for: document.id))
    try FileManager.default.copyItem(at: url, to: first)
    harness.clock.advance(days: 31)
    _ = try await harness.library.previousVersionURL(for: document.id)
    #expect(await harness.library.versions(of: document.id).isEmpty)
    #expect(FileDocumentLibrary.versionQuota(available: 100_000_000_000) == 2_000_000_000)
    #expect(FileDocumentLibrary.versionQuota(available: 10_000_000_000) == 500_000_000)
    #expect(FileDocumentLibrary.versionQuota(available: nil) == 2_000_000_000)
  }

  @Test("The single earlier version the first release kept moves into the history (B11)")
  func migratesSingleVersions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("migrate-\(UUID())")
    let previous = root.appendingPathComponent("Previous")
    try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
    let clock = TestClock()
    let library = FileDocumentLibrary(
      documentsFolder: root.appendingPathComponent("Documents"), deletedFolder: root.appendingPathComponent("Deleted"),
      previousVersionsFolder: previous, index: LibraryIndex(storeURL: root.appendingPathComponent("i/store")),
      now: { clock.now })
    let document = try await library.addDocument(data: pdf, title: "Kept")
    try pdf.write(to: previous.appendingPathComponent("\(document.id.rawValue.uuidString).pdf"))
    let reopened = FileDocumentLibrary(
      documentsFolder: root.appendingPathComponent("Documents"), deletedFolder: root.appendingPathComponent("Deleted"),
      previousVersionsFolder: previous, index: LibraryIndex(storeURL: root.appendingPathComponent("i/store")),
      now: { clock.now })
    #expect(await reopened.versions(of: document.id).count == 1)
  }

  @Test("Deleting a document removes its earlier versions (FR-LIB-006)")
  func earlierVersionsGoWithTheDocument() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Gone")
    let url = try await harness.library.fileURL(for: document.id)
    let previous = try #require(try await harness.library.previousVersionURL(for: document.id))
    try FileManager.default.copyItem(at: url, to: previous)
    try await harness.library.deletePermanently(document.id)
    #expect(!FileManager.default.fileExists(atPath: previous.path))
  }

  @Test("Changes to one document at the same time never undo each other")
  func concurrentChangesAllLand() async throws {
    let library = try Harness().library
    for round in 0..<20 {
      let document = try await library.addDocument(data: pdf, title: "Round \(round)")
      async let opened: Void = library.recordOpened(document.id, pageIndex: 3)
      async let tagged: Void = library.setTags(["Tax"], for: document.id)
      async let deleted: Void = library.moveToRecentlyDeleted(document.id)
      _ = try await (opened, tagged, deleted)
      let stored = try #require(try await library.document(withID: document.id))
      #expect(stored.isDeleted && stored.lastPageIndex == 3 && stored.tags == ["Tax"], "round \(round)")
      #expect(FileManager.default.fileExists(atPath: try await library.fileURL(for: document.id).path))
    }
  }

  @Test("Files added in the Files app appear; entries without a file disappear")
  func reconcile() async throws {
    let harness = try Harness()
    let kept = try await harness.library.addDocument(data: pdf, title: "Kept")
    let lost = try await harness.library.addDocument(data: pdf, title: "Lost")
    try FileManager.default.removeItem(at: try await harness.library.fileURL(for: lost.id))
    try pdf.write(to: harness.documentsFolder.appendingPathComponent("From Files.pdf"))
    try Data("notes".utf8).write(to: harness.documentsFolder.appendingPathComponent("notes.txt"))

    let result = try await harness.library.reconcileWithFiles()

    #expect(result.added.map(\.title) == ["From Files"])
    #expect(result.removed == [lost.id])
    let titles = try await harness.library.documents(in: .all, sortedBy: .title).map(\.title)
    #expect(titles == ["From Files", "Kept"])
    #expect(try await harness.library.document(withID: kept.id) != nil)
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation())
  }

  @Test("A file in the library's folder is found in place and never copied")
  func documentAtURL() async throws {
    let harness = try Harness()
    let known = try await harness.library.importDocument(from: harness.source(named: "Lease.pdf"))
    let binned = try await harness.library.importDocument(from: harness.source(named: "Old.pdf"))
    try await harness.library.moveToRecentlyDeleted(binned.id)
    try pdf.write(to: harness.documentsFolder.appendingPathComponent("From Files.pdf"))
    try Data("notes".utf8).write(to: harness.documentsFolder.appendingPathComponent("notes.txt"))

    #expect(
      try await harness.library.document(at: harness.documentsFolder.appendingPathComponent("Lease.pdf")) == known)
    let adopted = try #require(
      try await harness.library.document(at: harness.documentsFolder.appendingPathComponent("From Files.pdf")))
    #expect(adopted.title == "From Files" && adopted.fileName == "From Files.pdf")
    #expect(
      try await harness.library.document(at: harness.documentsFolder.appendingPathComponent("From Files.pdf"))
        == adopted)
    #expect(try await harness.library.document(at: harness.documentsFolder.appendingPathComponent("notes.txt")) == nil)
    #expect(try await harness.library.document(at: harness.documentsFolder.appendingPathComponent("Old.pdf")) == nil)
    #expect(try await harness.library.document(at: harness.documentsFolder.appendingPathComponent("Gone.pdf")) == nil)
    #expect(try await harness.library.document(at: harness.source(named: "Lease.pdf")) == nil, "Elsewhere is imported")
    #expect(try await harness.library.document(at: URL(string: "https://example.com/Lease.pdf")!) == nil)
    let files = try FileManager.default.contentsOfDirectory(atPath: harness.documentsFolder.path).sorted()
    #expect(files == ["From Files.pdf", "Lease.pdf", "notes.txt"])
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation(), "Nothing left to pick up")
  }

  @Test("Files left in Recently Deleted after an index rebuild come back as deleted and are purged on time")
  func orphanedDeletedFiles() async throws {
    let harness = try Harness()
    let deletedFolder = harness.root.appendingPathComponent("Deleted")
    try FileManager.default.createDirectory(at: deletedFolder, withIntermediateDirectories: true)
    try pdf.write(to: deletedFolder.appendingPathComponent("Old invoice.pdf"))

    let result = try await harness.library.reconcileWithFiles()

    #expect(result == Reconciliation())
    let deleted = try await harness.library.documents(in: .recentlyDeleted, sortedBy: .title)
    #expect(deleted.map(\.title) == ["Old invoice"])
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation())
    #expect(try await harness.library.documents(in: .recentlyDeleted, sortedBy: .title).count == 1)
    harness.clock.advance(days: 30)
    #expect(try await harness.library.purgeExpired(now: harness.clock.now) == deleted.map(\.id))
  }
}

@Suite("Library index")
struct LibraryIndexTests {
  @Test("The index persists across launches")
  func persists() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID())/library.store")
    let document = Document(title: "Persisted", fileName: "p.pdf", addedAt: .now, tags: ["a"])
    let first = LibraryIndex(storeURL: url)
    #expect(first.level == .onDisk)
    try await first.upsert(document)
    let reopened = LibraryIndex(storeURL: url)
    #expect(try await reopened.document(document.id) == document)
    try await reopened.delete(document.id)
    try await reopened.delete(document.id)
    #expect(try await reopened.all().isEmpty)
  }

  @Test("A damaged store is recreated instead of stopping the app")
  func damagedStoreIsRecreated() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("library.store")
    try Data("this is not a database".utf8).write(to: url)
    let index = LibraryIndex(storeURL: url)
    #expect(index.level == .recreated)
    let document = Document(title: "After", fileName: "a.pdf", addedAt: .now)
    try await index.upsert(document)
    #expect(try await index.all() == [document])
  }

  @Test("A store that won't open is kept aside, never deleted, and only the last few are kept (H6)")
  func unreadableStoresAreKept() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("library.store")
    let kept = LibraryIndex.keptFolder(for: url)
    for round in 0..<(LibraryIndex.keptLimit + 2) {
      let bytes = Data("newer or damaged store \(round)".utf8)
      try bytes.write(to: url)
      try bytes.write(to: URL(fileURLWithPath: url.path + "-wal"))
      #expect(LibraryIndex(storeURL: url).level == .recreated)
      let folders = try FileManager.default.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
      let newest = try #require(folders.last)
      #expect(try Data(contentsOf: newest.appendingPathComponent("library.store")) == bytes)
      #expect(FileManager.default.fileExists(atPath: newest.appendingPathComponent("library.store-wal").path))
      #expect(folders.count == min(round + 1, LibraryIndex.keptLimit))
      // Opening the new store removes it, so the next round starts from a damaged file again.
      for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
  }

  @Test("A store this build wrote is one it can read")
  func ownStoreIsReadable() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID())/library.store")
    try await LibraryIndex(storeURL: url).upsert(Document(title: "Mine", fileName: "m.pdf", addedAt: .now))
    #expect(LibraryIndex.condition(of: url) == .unavailable)
  }

  @Test func withoutAURLTheIndexLivesInMemory() async throws {
    let index = LibraryIndex(storeURL: nil)
    #expect(index.level == .inMemory)
    let document = Document(title: "Memory", fileName: "m.pdf", addedAt: .now)
    try await index.upsert(document)
    var changed = document
    changed.isFavorite = true
    try await index.upsert(changed)
    #expect(try await index.document(document.id)?.isFavorite == true)
  }
}

// MARK: - R1 review findings

@Suite("Files renamed or moved in the Files app")
struct RenamedInFilesTests {
  @Test("A file renamed in the Files app keeps its earlier versions (#224)")
  func renamedInFilesKeepsItsVersions() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Report")
    let url = try await harness.library.fileURL(for: document.id)
    for _ in 0..<2 {
      let kept = try #require(try await harness.library.previousVersionURL(for: document.id))
      try FileManager.default.copyItem(at: url, to: kept)
      harness.clock.advance(days: 1)
    }
    let versions = harness.versionFiles(of: document.id)
    try #require(versions.count == 2)

    try FileManager.default.moveItem(at: url, to: harness.documentsFolder.appendingPathComponent("Report 2026.pdf"))
    _ = try await harness.library.reconcileWithFiles()

    #expect(harness.versionFiles(of: document.id) == versions, "Earlier versions are kept, not deleted")
  }

  @Test("Earlier versions of a file gone from the folder still go after 30 days (FR-EDIT-008)")
  func versionsOfAGoneFileExpire() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Gone")
    let url = try await harness.library.fileURL(for: document.id)
    let kept = try #require(try await harness.library.previousVersionURL(for: document.id))
    try FileManager.default.copyItem(at: url, to: kept)
    try FileManager.default.removeItem(at: url)
    _ = try await harness.library.reconcileWithFiles()
    #expect(harness.versionFiles(of: document.id).count == 1)
    harness.clock.advance(days: 31)
    _ = try await harness.library.reconcileWithFiles()
    #expect(harness.versionFiles(of: document.id).isEmpty)
  }

  @Test("A file renamed in the Files app keeps its tags and favourite (stays for spike M4, #6)")
  func renamedInFilesKeepsItsEntry() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Report")
    try await harness.library.setTags(["tax"], for: document.id)
    try await harness.library.setFavorite(true, for: document.id)
    let url = try await harness.library.fileURL(for: document.id)
    try FileManager.default.moveItem(at: url, to: harness.documentsFolder.appendingPathComponent("Report 2026.pdf"))
    let result = try await harness.library.reconcileWithFiles()
    await withKnownIssue("Finding a renamed file needs a stored file identity: spike M4 (#6)") {
      #expect(result.removed.isEmpty)
      let after = try #require(try await harness.library.document(withID: document.id))
      #expect(after.fileName == "Report 2026.pdf" && after.tags == ["tax"] && after.isFavorite)
    }
  }
}

/// A library index whose writes start failing when told to, as they do on a full disk.
private actor FailingStore: LibraryStore {
  private var entries: [DocumentID: Document] = [:]
  private var failsWrites = false

  func failWrites() { failsWrites = true }

  func all() async throws -> [Document] { Array(entries.values) }

  func document(_ id: DocumentID) async throws -> Document? { entries[id] }

  func upsert(_ document: Document) async throws {
    guard !failsWrites else { throw CocoaError(.fileWriteOutOfSpace) }
    entries[document.id] = document
  }

  func delete(_ id: DocumentID) async throws {
    guard !failsWrites else { throw CocoaError(.fileWriteOutOfSpace) }
    entries[id] = nil
  }
}

@Suite("A change whose index write fails")
struct FailedIndexWriteTests {
  enum Change: String, CaseIterable, Sendable {
    case rename, moveToRecentlyDeleted, restore
  }

  @Test("The file goes back where it was, so nothing changed (#225)", arguments: Change.allCases)
  func fileGoesBack(change: Change) async throws {
    let store = FailingStore()
    let harness = try Harness(index: store)
    let document = try await harness.library.addDocument(data: pdf, title: "A")
    if change == .restore { try await harness.library.moveToRecentlyDeleted(document.id) }
    let before = try #require(try await harness.library.document(withID: document.id))
    let files = try harness.files()

    await store.failWrites()
    await #expect(throws: (any Error).self) {
      switch change {
      case .rename: _ = try await harness.library.rename(document.id, to: "B")
      case .moveToRecentlyDeleted: try await harness.library.moveToRecentlyDeleted(document.id)
      case .restore: try await harness.library.restore(document.id)
      }
    }

    #expect(try harness.files() == files, "The file is where the index says it is")
    #expect(try await harness.library.document(withID: document.id) == before)
    #expect(FileManager.default.fileExists(atPath: try await harness.library.fileURL(for: document.id).path))
  }

  @Test("A document whose index write fails is not added, and leaves no file behind (#225)")
  func addLeavesNoFile() async throws {
    let store = FailingStore()
    let harness = try Harness(index: store)
    await store.failWrites()
    await #expect(throws: (any Error).self) { try await harness.library.addDocument(data: pdf, title: "A") }
    #expect(try harness.files().isEmpty)
  }
}

/// The index's store as a later build might write it: its entry has an attribute this build doesn't
/// know.
///
/// Written and read with Core Data and plain `NSManagedObject`s, not with a second SwiftData model
/// class. SwiftData maps model classes to entities by name across the process, so a second
/// `DocumentEntry` class could be given the real entry's entity while another test's index was open;
/// inserting into it then threw `setValue:forUndefinedKey:` for "colour" and crashed every test
/// running in the process.
private enum StoreFromANewerBuild {
  static let colour = "red"

  /// The newer build's model: the entry's name and three of its attributes, and one more.
  static func model() -> NSManagedObjectModel {
    func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
      let attribute = NSAttributeDescription()
      attribute.name = name
      attribute.attributeType = type
      attribute.isOptional = true
      return attribute
    }
    let entry = NSEntityDescription()
    entry.name = "DocumentEntry"
    entry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
    entry.properties = [
      attribute("id", .UUIDAttributeType), attribute("title", .stringAttributeType),
      attribute("fileName", .stringAttributeType), attribute("colour", .stringAttributeType),
    ]
    let model = NSManagedObjectModel()
    model.entities = [entry]
    return model
  }

  /// Runs `body` on a context over the store at `url`, opened with the newer build's model.
  ///
  /// Opening fails if the store no longer has the newer build's shape, for example after an older
  /// build migrated it down to its own schema.
  static func withContext<T>(at url: URL, _ body: (NSManagedObjectContext) throws -> T) throws -> T {
    try LibraryIndex.opening.withLock { _ in
      let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model())
      let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
      defer { try? coordinator.remove(store) }
      let context = NSManagedObjectContext(.privateQueue)
      context.persistentStoreCoordinator = coordinator
      return try context.performAndWait { try body(context) }
    }
  }

  /// Writes one entry with the newer build's attribute set.
  static func write(title: String, to url: URL) throws {
    try withContext(at: url) { context in
      let entry = NSEntityDescription.insertNewObject(forEntityName: "DocumentEntry", into: context)
      entry.setValue(UUID(), forKey: "id")
      entry.setValue(title, forKey: "title")
      entry.setValue("", forKey: "fileName")
      entry.setValue(colour, forKey: "colour")
      try context.save()
    }
  }

  /// The title and colour of every entry, as the newer build reads them.
  static func entries(at url: URL) throws -> [String] {
    try withContext(at: url) { context in
      try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "DocumentEntry")).map {
        "\($0.value(forKey: "title") as? String ?? "nil"), \($0.value(forKey: "colour") as? String ?? "nil")"
      }
    }
  }
}

@Suite("Opening the library index")
struct OpeningTheIndexTests {
  private func storeURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("library.store")
  }

  @Test("A store written by a newer build is left where it is, untouched (#226, B11)")
  func newerStoreIsLeftUntouched() async throws {
    let url = try storeURL()
    try StoreFromANewerBuild.write(title: "Tagged in a newer build", to: url)

    #expect(LibraryIndex.condition(of: url) == .newer)
    let index = LibraryIndex(storeURL: url)
    #expect(index.level == .newerStore)
    try await index.upsert(Document(title: "Added in an older build", fileName: "a.pdf", addedAt: .now))

    #expect(!FileManager.default.fileExists(atPath: LibraryIndex.keptFolder(for: url).path))
    // The newer build still reads its entry, its own attribute included: nothing migrated it down.
    #expect(try StoreFromANewerBuild.entries(at: url) == ["Tagged in a newer build, \(StoreFromANewerBuild.colour)"])
  }

  @Test("A store that can't be read at launch is left in place, and opens again next time (#226)")
  func unreadableStoreIsLeftInPlace() async throws {
    let url = try storeURL()
    let document = Document(title: "Tagged", fileName: "t.pdf", addedAt: .now, isFavorite: true, tags: ["tax"])
    try await LibraryIndex(storeURL: url).upsert(document)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    let unreadable = LibraryIndex(storeURL: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

    #expect(unreadable.level == .inMemory)
    #expect(!FileManager.default.fileExists(atPath: LibraryIndex.keptFolder(for: url).path))
    #expect(try await LibraryIndex(storeURL: url).document(document.id) == document)
  }
}
