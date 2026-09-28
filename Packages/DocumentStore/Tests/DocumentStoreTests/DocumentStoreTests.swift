import Core
import Foundation
import Testing

@testable import DocumentStore

private let pdf = Data("%PDF-1.7\n1 0 obj << >> endobj\n%%EOF\n".utf8)

/// A library in a fresh temporary folder, with a clock the test controls.
private struct Harness {
  let root: URL
  let clock: TestClock
  let library: FileDocumentLibrary

  init(storeURL: URL? = nil) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
    clock = TestClock()
    let clock = self.clock
    library = FileDocumentLibrary(
      documentsFolder: root.appendingPathComponent("Documents"), deletedFolder: root.appendingPathComponent("Deleted"),
      index: LibraryIndex(storeURL: storeURL ?? root.appendingPathComponent("Index/library.store")), now: { clock.now })
  }

  var documentsFolder: URL { root.appendingPathComponent("Documents") }

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

  @Test("Files added in the Files app appear; entries without a file disappear")
  func reconcile() async throws {
    let harness = try Harness()
    let kept = try await harness.library.addDocument(data: pdf, title: "Kept")
    let lost = try await harness.library.addDocument(data: pdf, title: "Lost")
    try FileManager.default.removeItem(at: try await harness.library.fileURL(for: lost.id))
    try pdf.write(to: harness.documentsFolder.appendingPathComponent("From Files.pdf"))
    try Data("notes".utf8).write(to: harness.documentsFolder.appendingPathComponent("notes.txt"))

    let added = try await harness.library.reconcileWithFiles()

    #expect(added.map(\.title) == ["From Files"])
    let titles = try await harness.library.documents(in: .all, sortedBy: .title).map(\.title)
    #expect(titles == ["From Files", "Kept"])
    #expect(try await harness.library.document(withID: kept.id) != nil)
    #expect(try await harness.library.reconcileWithFiles().isEmpty)
  }
}

@Suite("Library index")
struct LibraryIndexTests {
  @Test("The index persists across launches")
  func persists() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID())/library.store")
    let document = Document(title: "Persisted", fileName: "p.pdf", addedAt: .now, tags: ["a"])
    let first = LibraryIndex(storeURL: url)
    #expect(await first.level == .onDisk)
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
    #expect(await index.level == .recreated)
    let document = Document(title: "After", fileName: "a.pdf", addedAt: .now)
    try await index.upsert(document)
    #expect(try await index.all() == [document])
  }

  @Test func withoutAURLTheIndexLivesInMemory() async throws {
    let index = LibraryIndex(storeURL: nil)
    #expect(await index.level == .inMemory)
    let document = Document(title: "Memory", fileName: "m.pdf", addedAt: .now)
    try await index.upsert(document)
    var changed = document
    changed.isFavorite = true
    try await index.upsert(changed)
    #expect(try await index.document(document.id)?.isFavorite == true)
  }
}
