import Core
import Foundation
import Testing

@testable import DocumentStore

/// Library defects from the R1 review, apart from file identity (#224).
@Suite("Renaming and reading again (R1 review)")
struct LibraryReviewFixesTests {
  private let pdf = Data("%PDF-1.7\n1 0 obj << >> endobj\n%%EOF\n".utf8)

  private func library() -> (FileDocumentLibrary, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString)")
    let documents = root.appendingPathComponent("Documents")
    let library = FileDocumentLibrary(
      documentsFolder: documents, deletedFolder: root.appendingPathComponent("Deleted"),
      index: LibraryIndex(storeURL: nil))
    return (library, documents)
  }

  @Test("Changing only a title's capitals keeps the file name, with no number added (#263)")
  func caseOnlyRenameKeepsTheName() async throws {
    let (library, documents) = library()
    let document = try await library.addDocument(data: pdf, title: "report")
    let renamed = try await library.rename(document.id, to: "Report")
    #expect(renamed.title == "Report" && renamed.fileName == "Report.pdf")
    #expect(try FileManager.default.contentsOfDirectory(atPath: documents.path) == ["Report.pdf"])
    let other = try await library.addDocument(data: pdf, title: "Other")
    #expect(try await library.rename(other.id, to: "Report").fileName == "Report 2.pdf", "Another file still clashes")
    let slashed = try await library.addDocument(data: pdf, title: "A/B")
    #expect(try await library.rename(slashed.id, to: "A:B").fileName == "A-B.pdf", "The same file name")
  }

  @Test("A document read again with fewer pages keeps its reading position on a page it has (#242)")
  func positionStaysWithinThePages() async throws {
    let (library, _) = library()
    let document = try await library.addDocument(data: pdf, title: "Invoice")
    try await library.recordOpened(document.id, pageIndex: 40)
    try await library.updateInspection(PDFInspection(pageCount: 2, isEncrypted: false, pages: []), for: document.id)
    #expect(try await library.document(withID: document.id)?.lastPageIndex == 1)
    try await library.updateInspection(PDFInspection(pageCount: 0, isEncrypted: true, pages: []), for: document.id)
    #expect(
      try await library.document(withID: document.id)?.lastPageIndex == 1,
      "A locked document's page count is unknown, so its position stays")
  }

  @Test("A file replaced under its name by an older PDF is reported for reading again, once (#242)")
  func replacedFileIsReported() async throws {
    let (library, documents) = library()
    let document = try await library.addDocument(data: pdf, title: "Invoice")
    #expect(try await library.reconcileWithFiles() == Reconciliation(), "Nothing changed yet")
    // Another PDF, last changed long before, put in its place, as the Files app's Replace does.
    let url = documents.appendingPathComponent(document.fileName)
    let other = documents.deletingLastPathComponent().appendingPathComponent("Other.pdf")
    try Data("%PDF-1.7\n% another invoice\n%%EOF\n".utf8).write(to: other)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: other.path)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: other, to: url)
    #expect(try await library.changedSinceRecorded().isEmpty, "Its date alone doesn't tell")
    let result = try await library.reconcileWithFiles()
    #expect(result.changed == [document.id], "\(result)")
    #expect(result.added.isEmpty && result.removed.isEmpty)
    #expect(try await library.reconcileWithFiles() == Reconciliation(), "Reported once")
  }

  // MARK: - Opening at launch (#244)

  /// Opens the app's index while another store holds the opening lock for up to two seconds, as a
  /// slow open or a migration would, and returns how long the caller waited.
  private static func openWhileAnotherStoreOpens(at storeURL: URL) -> (OpeningLibraryIndex, Duration) {
    let held = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    Thread {
      LibraryIndex.opening.withLock { _ in
        held.signal()
        _ = release.wait(timeout: .now() + 2)
      }
    }.start()
    held.wait()
    let clock = ContinuousClock()
    let started = clock.now
    let index = OpeningLibraryIndex(storeURL: storeURL)
    let waited = clock.now - started
    release.signal()
    return (index, waited)
  }

  @Test("Launch doesn't wait for the library index to open or migrate; its calls do (#244)")
  func indexOpensOffTheCaller() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("opening-\(UUID().uuidString)")
    let (index, waited) = Self.openWhileAnotherStoreOpens(at: root.appendingPathComponent("Index/Library.store"))
    #expect(waited < .seconds(1), "The caller waited \(waited) for the store to open")
    let document = Document(title: "Lease", fileName: "Lease.pdf", addedAt: .now)
    try await index.upsert(document)
    #expect(try await index.all().map(\.id) == [document.id], "A call waits until the store is open")
    #expect(await index.level == .onDisk)
  }

  @Test("Creating the library moves no file; earlier versions are moved before any is read (#244)")
  func versionsMoveOffTheCaller() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("versions-\(UUID().uuidString)")
    let previous = root.appendingPathComponent("Previous")
    try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
    let id = DocumentID()
    let single = previous.appendingPathComponent("\(id.rawValue.uuidString).pdf")
    try pdf.write(to: single)
    let library = FileDocumentLibrary(
      documentsFolder: root.appendingPathComponent("Documents"), deletedFolder: root.appendingPathComponent("Deleted"),
      previousVersionsFolder: previous, index: LibraryIndex(storeURL: nil))
    #expect(FileManager.default.fileExists(atPath: single.path), "Launch doesn't wait for the move")
    #expect(await library.versions(of: id).count == 1, "Moved before the history is read")
    #expect(!FileManager.default.fileExists(atPath: single.path))
  }
}
