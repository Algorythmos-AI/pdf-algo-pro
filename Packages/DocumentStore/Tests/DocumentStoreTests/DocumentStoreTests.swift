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
  let index: any LibraryStore
  let library: FileDocumentLibrary

  init(storeURL: URL? = nil, index: (any LibraryStore)? = nil) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
    clock = TestClock()
    let clock = self.clock
    self.index = index ?? LibraryIndex(storeURL: storeURL ?? root.appendingPathComponent("Index/library.store"))
    library = FileDocumentLibrary(
      documentsFolder: root.appendingPathComponent("Documents"), deletedFolder: root.appendingPathComponent("Deleted"),
      previousVersionsFolder: root.appendingPathComponent("Previous"), index: self.index, now: { clock.now })
  }

  var documentsFolder: URL { root.appendingPathComponent("Documents") }

  /// Every file under the library's folder with its identity now, and the identities the index
  /// holds, for a failure message.
  func state() async throws -> String {
    let files = (FileManager.default.subpaths(atPath: documentsFolder.path) ?? []).sorted().map { path in
      "\(path) (\(FileIdentity(of: documentsFolder.appendingPathComponent(path))?.stored ?? "no identity"))"
    }
    let identities = try await index.fileIdentities().map { "\($0.key): \($0.value)" }.sorted()
    return "files \(files); recorded identities \(identities)"
  }

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
    let recorded = try await harness.index.fileIdentities()
    #expect(deleted.allSatisfy { recorded[$0.id] != nil }, "Its identity is recorded at once: \(recorded)")
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

  @Test("A file renamed in the Files app keeps its entry: tags, favourite, position, earlier versions (#224)")
  func renamedInFilesKeepsItsEntry() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Report")
    try await harness.library.setTags(["tax"], for: document.id)
    try await harness.library.setFavorite(true, for: document.id)
    try await harness.library.recordOpened(document.id, pageIndex: 40)
    let kept = try #require(try await harness.library.previousVersionURL(for: document.id))
    try pdf.write(to: kept)
    let old = try await harness.library.fileURL(for: document.id)
    try FileManager.default.moveItem(at: old, to: harness.documentsFolder.appendingPathComponent("Report 2026.pdf"))

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result == Reconciliation(), "removed \(result.removed), added \(result.added.map(\.fileName)); \(state)")
    let after = try #require(try await harness.library.document(withID: document.id), "Entry removed; \(state)")
    #expect(
      after.fileName == "Report 2026.pdf" && after.tags == ["tax"] && after.isFavorite && after.lastPageIndex == 40,
      "\(after); \(state)")
    #expect(after.title == "Report", "The title is the library's, like its tags")
    #expect(await harness.library.hasPreviousVersion(of: document.id))
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).map(\.id) == [document.id])
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation(), "Nothing left to pick up")
  }

  @Test("A file moved into a folder in the Files app keeps its entry and stays listed (#224)")
  func movedIntoAFolderKeepsItsEntry() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Lease")
    try await harness.library.setTags(["home"], for: document.id)
    try await harness.library.recordOpened(document.id, pageIndex: 12)
    let folder = harness.documentsFolder.appendingPathComponent("Contracts", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let moved = folder.appendingPathComponent("Lease.pdf")
    try FileManager.default.moveItem(at: try await harness.library.fileURL(for: document.id), to: moved)

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result == Reconciliation(), "removed \(result.removed), added \(result.added.map(\.fileName)); \(state)")
    let after = try #require(try await harness.library.document(withID: document.id), "Entry removed; \(state)")
    #expect(
      after.fileName == "Contracts/Lease.pdf" && after.tags == ["home"] && after.lastPageIndex == 12,
      "\(after); \(state)")
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).map(\.id) == [document.id])
    #expect(try await harness.library.fileURL(for: document.id).path == moved.path)
    #expect(try await harness.library.document(at: moved)?.id == document.id, "Opened from Files, it is found")
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation(), "Nothing left to pick up")

    // Renaming in the app keeps a file in its folder.
    let renamed = try await harness.library.rename(document.id, to: "Lease 2026")
    #expect(renamed.fileName == "Contracts/Lease 2026.pdf")
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Lease 2026.pdf").path))
  }

  @Test("A PDF the library doesn't track, put in a folder, is neither added nor touched (PAP-030 item 7)")
  func untrackedFileInAFolderIsLeftAlone() async throws {
    let harness = try Harness()
    let folder = harness.documentsFolder.appendingPathComponent("Contracts", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let deed = folder.appendingPathComponent("Deed.pdf")
    try pdf.write(to: deed)

    for round in 1...2 {
      let result = try await harness.library.reconcileWithFiles()
      let state = try await harness.state()
      #expect(result == Reconciliation(), "round \(round): added \(result.added.map(\.fileName)); \(state)")
      #expect(try await harness.library.documents(in: .all, sortedBy: .title).isEmpty, "round \(round); \(state)")
      #expect(try await harness.library.documents(in: .recentlyDeleted, sortedBy: .title).isEmpty, "round \(round)")
    }
    #expect(try Data(contentsOf: deed) == pdf, "The file is left where it is, as it was")
    #expect(try await harness.library.document(at: deed) == nil, "Opened from Files, it is imported as a copy")
  }

  @Test("A tracked file in a folder, deleted and restored, comes back in that folder with its entry (#224)")
  func restoredIntoItsFolder() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Lease")
    try await harness.library.setTags(["home"], for: document.id)
    try await harness.library.setFavorite(true, for: document.id)
    let folder = harness.documentsFolder.appendingPathComponent("Contracts", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.moveItem(
      at: try await harness.library.fileURL(for: document.id), to: folder.appendingPathComponent("Lease.pdf"))
    let followed = try await harness.library.reconcileWithFiles()
    let moved = try await harness.state()
    #expect(followed == Reconciliation(), "\(followed); \(moved)")
    let before = try #require(try await harness.library.document(withID: document.id))
    try #require(before.fileName == "Contracts/Lease.pdf", "\(before); \(moved)")

    try await harness.library.moveToRecentlyDeleted(document.id)
    let identity = try await harness.index.fileIdentities()[document.id]
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation(), "Still in Recently Deleted")
    #expect(try await harness.library.documents(in: .recentlyDeleted, sortedBy: .title).map(\.id) == [document.id])
    // The folder goes in the meantime, so restoring makes it again.
    try FileManager.default.removeItem(at: folder)
    try await harness.library.restore(document.id)

    let after = try #require(try await harness.library.document(withID: document.id))
    let state = try await harness.state()
    #expect(after.fileName == "Contracts/Lease.pdf" && !after.isDeleted, "\(after); \(state)")
    #expect(after.tags == ["home"] && after.isFavorite, "\(after)")
    let restoredIdentity = try await harness.index.fileIdentities()[document.id]
    #expect(restoredIdentity != nil && restoredIdentity == identity, "Recorded at once, the same file: \(state)")
    #expect(try Data(contentsOf: folder.appendingPathComponent("Lease.pdf")) == pdf, "\(state)")
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation(), "\(state)")
  }

  @Test("Saved by another app, then renamed, all while the app is closed: the entry follows (#224)")
  func savedElsewhereThenRenamed() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Notes")
    try await harness.library.setFavorite(true, for: document.id)
    let url = try await harness.library.fileURL(for: document.id)
    let before = try await harness.state()
    // An atomic save writes a new file and swaps it in, so the file number changes; the document
    // identifier of a tracked file stays. No reconciliation runs in between: the app is closed.
    try Data("%PDF-1.7\n% saved elsewhere\n%%EOF\n".utf8).write(to: url, options: .atomic)
    try FileManager.default.moveItem(at: url, to: harness.documentsFolder.appendingPathComponent("Notes 2.pdf"))

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result == Reconciliation(), "removed \(result.removed), added \(result.added.map(\.fileName)); \(state)")
    let after = try #require(try await harness.library.document(withID: document.id), "Entry removed; \(state)")
    #expect(after.fileName == "Notes 2.pdf" && after.isFavorite, "\(after); before the save \(before); now \(state)")
  }

  @Test("Renamed while open, its old name then taken by another PDF: the moved file is the document's (#224)")
  func oldNameTakenWhileOpen() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Report")
    let url = try await harness.library.fileURL(for: document.id)
    let renamed = harness.documentsFolder.appendingPathComponent("Report 2026.pdf")
    try FileManager.default.moveItem(at: url, to: renamed)
    // A new save, or "Keep Both" in Files, puts another document at the old name. It is written
    // atomically, as apps save. A plain write on the same thread straight after the rename is left
    // out: APFS takes that for a safe save of the renamed file and moves its document identifier to
    // the new one, which no app saving a different document does (an atomic write, a clone, a write
    // from another thread, or a file made before the rename, all keep it where it was).
    let other = Data("%PDF-1.7\n% another document\n%%EOF\n".utf8)
    try other.write(to: url, options: .atomic)

    let resolved = try await harness.library.fileURL(for: document.id)

    let state = try await harness.state()
    #expect(resolved.path == renamed.path, "Resolved \(resolved.lastPathComponent); \(state)")
    #expect(try await harness.library.document(withID: document.id)?.fileName == "Report 2026.pdf", "\(state)")
    #expect(try Data(contentsOf: url) == other, "The other document is untouched")
    #expect(try Data(contentsOf: renamed) == pdf)
    let result = try await harness.library.reconcileWithFiles()
    #expect(result.removed.isEmpty && result.added.map(\.fileName) == ["Report.pdf"], "\(result); \(state)")
    #expect(result.added.first?.id != document.id)
  }

  @Test("Two files that swap names keep their own details: the identity wins over the name (#224)")
  func swappedNamesKeepTheirDetails() async throws {
    let harness = try Harness()
    let first = try await harness.library.addDocument(data: pdf, title: "A")
    let second = try await harness.library.addDocument(data: pdf, title: "B")
    try await harness.library.setTags(["first"], for: first.id)
    try await harness.library.setTags(["second"], for: second.id)
    let a = harness.documentsFolder.appendingPathComponent("A.pdf")
    let b = harness.documentsFolder.appendingPathComponent("B.pdf")
    let swap = harness.documentsFolder.appendingPathComponent("swap.tmp")
    try FileManager.default.moveItem(at: a, to: swap)
    try FileManager.default.moveItem(at: b, to: a)
    try FileManager.default.moveItem(at: swap, to: b)

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result == Reconciliation(), "\(result); \(state)")
    let firstAfter = try #require(try await harness.library.document(withID: first.id), "\(state)")
    let secondAfter = try #require(try await harness.library.document(withID: second.id), "\(state)")
    #expect(firstAfter.fileName == "B.pdf" && firstAfter.tags == ["first"], "\(firstAfter); \(state)")
    #expect(secondAfter.fileName == "A.pdf" && secondAfter.tags == ["second"], "\(secondAfter); \(state)")
  }

  @Test("A copy made in Files is a new document; the original, moved after, keeps its entry (#224)")
  func duplicateThenMove() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Report")
    try await harness.library.setTags(["tax"], for: document.id)
    let url = try await harness.library.fileURL(for: document.id)
    try FileManager.default.copyItem(at: url, to: harness.documentsFolder.appendingPathComponent("Report copy.pdf"))
    try FileManager.default.moveItem(at: url, to: harness.documentsFolder.appendingPathComponent("Report final.pdf"))

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result.removed.isEmpty && result.added.map(\.fileName) == ["Report copy.pdf"], "\(result); \(state)")
    let after = try #require(try await harness.library.document(withID: document.id), "\(state)")
    #expect(after.fileName == "Report final.pdf" && after.tags == ["tax"], "\(after); \(state)")
    let copy = try #require(result.added.first)
    #expect(copy.id != document.id && copy.tags.isEmpty)
  }

  @Test("A file moved out of the library and back, with a launch in between, keeps its details (#224)")
  func outAndBack() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Lease")
    try await harness.library.setTags(["home"], for: document.id)
    try await harness.library.recordOpened(document.id, pageIndex: 5)
    let url = try await harness.library.fileURL(for: document.id)
    // Out to another folder on the same volume, so the file keeps its identity.
    let outside = harness.root.appendingPathComponent("Elsewhere/Lease.pdf")
    try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: url, to: outside)

    let out = try await harness.library.reconcileWithFiles()
    #expect(out.removed == [document.id] && out.added.isEmpty, "\(out)")
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).isEmpty, "Out of the library meanwhile")
    harness.clock.advance(days: 29)
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation())

    try FileManager.default.moveItem(at: outside, to: harness.documentsFolder.appendingPathComponent("Lease back.pdf"))
    let back = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(
      back.removed.isEmpty && back.added.map(\.id) == [document.id], "Back, to be indexed again: \(back); \(state)")
    let after = try #require(try await harness.library.document(withID: document.id), "\(state)")
    #expect(after.fileName == "Lease back.pdf" && after.tags == ["home"] && after.lastPageIndex == 5, "\(after)")
    #expect(try await harness.library.documents(in: .all, sortedBy: .title).map(\.id) == [document.id])
  }

  @Test("An entry whose file stays gone is deleted after the 30 days Recently Deleted keeps documents")
  func goneEntriesExpire() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Lost")
    let url = try await harness.library.fileURL(for: document.id)
    let outside = harness.root.appendingPathComponent("Lost.pdf")
    try FileManager.default.moveItem(at: url, to: outside)
    #expect(try await harness.library.reconcileWithFiles().removed == [document.id])
    #expect(try await harness.index.goneEntries().map { $0.document.id } == [document.id])

    harness.clock.advance(days: FileDocumentLibrary.goneRetention / 86_400)
    _ = try await harness.library.reconcileWithFiles()
    #expect(try await harness.index.goneEntries().isEmpty, "Deleted for good")
    try FileManager.default.moveItem(at: outside, to: harness.documentsFolder.appendingPathComponent("Lost.pdf"))
    let back = try await harness.library.reconcileWithFiles()
    #expect(back.added.count == 1 && back.added.first?.id != document.id, "Too late: a new document")
  }

  @Test("An identity recorded on another volume is never taken for a file here (#224)")
  func identityFromAnotherVolumeIsIgnored() async throws {
    let harness = try Harness()
    let first = try await harness.library.addDocument(data: pdf, title: "A")
    let second = try await harness.library.addDocument(data: pdf, title: "B")
    try await harness.library.setTags(["first"], for: first.id)
    // As if restored from a backup of another device: A's identity there has B's numbers here.
    var foreign = try #require(FileIdentity(of: harness.documentsFolder.appendingPathComponent("B.pdf")))
    foreign.volume = "00000000-0000-0000-0000-000000000000"
    try await harness.index.setFileIdentity(foreign.stored, for: first.id)

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result == Reconciliation(), "\(result); \(state)")
    #expect(try await harness.library.document(withID: first.id)?.fileName == "A.pdf", "\(state)")
    #expect(try await harness.library.document(withID: second.id)?.fileName == "B.pdf", "\(state)")
    let recorded = try await harness.index.fileIdentities()[first.id]
    #expect(recorded != foreign.stored, "A's own identity is recorded again: \(state)")
  }

  @Test("A file renamed in Files while the app runs is found by the next save, never written anew (#224)")
  func renamedWhileOpen() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Open")
    let url = try await harness.library.fileURL(for: document.id)
    let renamed = harness.documentsFolder.appendingPathComponent("Open renamed.pdf")
    try FileManager.default.moveItem(at: url, to: renamed)

    let state = try await harness.state()
    #expect(try await harness.library.fileURL(for: document.id).path == renamed.path, "\(state)")
    #expect(try await harness.library.document(withID: document.id)?.fileName == "Open renamed.pdf")
    #expect(try await harness.library.reconcileWithFiles() == Reconciliation())

    // Gone altogether: the library says so rather than give a name a save would write a new file at.
    try FileManager.default.removeItem(at: renamed)
    await #expect(throws: LibraryError.notFound) { try await harness.library.fileURL(for: document.id) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("When two files could be the renamed one, neither is guessed (#224)")
  func ambiguousCandidatesAreNotGuessed() async throws {
    let harness = try Harness()
    let document = try await harness.library.addDocument(data: pdf, title: "Report")
    try await harness.library.setTags(["tax"], for: document.id)
    let url = try await harness.library.fileURL(for: document.id)
    // Hard links are one file under two names, so both have its identity.
    for name in ["Report A.pdf", "Report B.pdf"] {
      try FileManager.default.linkItem(at: url, to: harness.documentsFolder.appendingPathComponent(name))
    }
    try FileManager.default.removeItem(at: url)

    let result = try await harness.library.reconcileWithFiles()

    let state = try await harness.state()
    #expect(result.removed == [document.id], "\(state)")
    #expect(result.added.map(\.fileName) == ["Report A.pdf", "Report B.pdf"], "\(state)")
    #expect(try await harness.library.allTags().isEmpty)
  }
}

/// A library index whose writes start failing when told to, as they do on a full disk.
private actor FailingStore: LibraryStore {
  private var entries: [DocumentID: Document] = [:]
  private var identities: [DocumentID: String] = [:]
  private var gone: [DocumentID: Date] = [:]
  private var failsWrites = false

  func failWrites() { failsWrites = true }

  func all() async throws -> [Document] { entries.values.filter { gone[$0.id] == nil } }

  func document(_ id: DocumentID) async throws -> Document? { gone[id] == nil ? entries[id] : nil }

  func upsert(_ document: Document) async throws {
    guard !failsWrites else { throw CocoaError(.fileWriteOutOfSpace) }
    entries[document.id] = document
  }

  func delete(_ id: DocumentID) async throws {
    guard !failsWrites else { throw CocoaError(.fileWriteOutOfSpace) }
    entries[id] = nil
    identities[id] = nil
    gone[id] = nil
  }

  func fileIdentities() async throws -> [DocumentID: String] { identities }

  func setFileIdentity(_ identity: String?, for id: DocumentID) async throws {
    guard !failsWrites else { throw CocoaError(.fileWriteOutOfSpace) }
    if entries[id] != nil { identities[id] = identity }
  }

  func goneEntries() async throws -> [(document: Document, goneAt: Date)] {
    gone.compactMap { id, date in entries[id].map { (document: $0, goneAt: date) } }
  }

  func setGone(_ date: Date?, for id: DocumentID) async throws {
    guard !failsWrites else { throw CocoaError(.fileWriteOutOfSpace) }
    if entries[id] != nil { gone[id] = date }
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
  static func withContext<T: Sendable>(
    at url: URL, _ body: @Sendable (NSManagedObjectContext) throws -> T
  ) throws -> T {
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
