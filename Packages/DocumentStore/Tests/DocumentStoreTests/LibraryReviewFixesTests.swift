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
}
