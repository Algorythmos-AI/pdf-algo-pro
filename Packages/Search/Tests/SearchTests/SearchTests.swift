import Core
import Foundation
import Testing

@testable import Search

private actor RecordingSpotlight: SpotlightIndexing {
  var indexed: [DocumentID: String] = [:]
  var removed: [DocumentID] = []
  func index(_ document: Document, text: String) async { indexed[document.id] = text }
  func remove(_ id: DocumentID) async { removed.append(id) }
}

private func makeIndex(spotlight: (any SpotlightIndexing)? = nil) throws -> LocalSearchIndex {
  LocalSearchIndex(folder: FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID())"), spotlight: spotlight)
}

private func document(_ title: String, tags: [String] = []) -> Document {
  Document(title: title, fileName: "\(title).pdf", addedAt: .now, tags: tags)
}

@Suite("Local search")
struct LocalSearchIndexTests {
  @Test("Text matches report the page and a snippet (FR-LIB-003)")
  func textMatch() async throws {
    let index = try makeIndex()
    let lease = document("Lease")
    try await index.index(lease, pages: [PageText(pageIndex: 0, text: "Parties"), PageText(pageIndex: 1, text: "The monthly rent is due on the first day.")])
    let hits = try await index.search("RENT due", in: [lease])
    #expect(hits.count == 1)
    #expect(hits[0].pageIndex == 1)
    #expect(hits[0].snippet?.contains("monthly rent") == true)
  }

  @Test("Accents and case are ignored: \"resume\" finds \"Résumé\"")
  func foldsDiacritics() async throws {
    let index = try makeIndex()
    let cv = document("CV")
    try await index.index(cv, pages: [PageText(pageIndex: 0, text: "Mon Résumé professionnel")])
    #expect(try await index.search("resume", in: [cv]).map(\.documentID) == [cv.id])
  }

  @Test("Title and tag matches rank above text matches; every word must match")
  func ranking() async throws {
    let index = try makeIndex()
    let byTitle = document("Invoice March")
    let byTag = document("Receipt", tags: ["invoice"])
    let byText = document("Letter")
    let unrelated = document("Other")
    try await index.index(byTitle, pages: [])
    try await index.index(byTag, pages: [])
    try await index.index(byText, pages: [PageText(pageIndex: 3, text: "please pay this invoice")])
    try await index.index(unrelated, pages: [PageText(pageIndex: 0, text: "nothing here")])
    let hits = try await index.search("invoice", in: [byText, unrelated, byTag, byTitle])
    #expect(hits.map(\.documentID) == [byTitle.id, byTag.id, byText.id])
    #expect(hits[0].pageIndex == nil && hits[2].pageIndex == 3)
    #expect(try await index.search("invoice march", in: [byText, byTitle]).map(\.documentID) == [byTitle.id])
    #expect(try await index.search("   ", in: [byTitle]).isEmpty)
  }

  @Test("Stored text survives a relaunch and is deleted with the document (FR-LIB-006)")
  func persistenceAndRemoval() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID())")
    let spotlight = RecordingSpotlight()
    let report = document("Report")
    let pages = [PageText(pageIndex: 0, text: "quarterly results")]
    try await LocalSearchIndex(folder: folder, spotlight: spotlight).index(report, pages: pages)
    let reopened = LocalSearchIndex(folder: folder, spotlight: spotlight)
    #expect(try await reopened.pages(of: report.id) == pages)
    #expect(await spotlight.indexed[report.id] == "quarterly results")
    try await reopened.remove(report.id)
    try await reopened.remove(report.id)
    #expect(try await reopened.pages(of: report.id).isEmpty)
    #expect(await spotlight.removed == [report.id, report.id])
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
  }

  @Test func snippetsAreShortAndMarkTruncation() {
    let text = String(repeating: "lorem ", count: 40) + "needle" + String(repeating: " ipsum", count: 40)
    let snippet = SearchText.snippet(text, around: ["needle"])
    #expect(snippet?.hasPrefix("…") == true && snippet?.hasSuffix("…") == true)
    #expect(snippet?.contains("needle") == true)
    #expect((snippet?.count ?? 0) <= 125)
    #expect(SearchText.snippet("abc", around: ["zzz"]) == nil)
  }

  @Test func termsSplitOnSpacesAndPunctuation() {
    #expect(SearchText.terms("  Tax, 2026!  e-mail ") == ["tax", "2026", "e-mail"])
  }
}

@Suite("Spotlight items")
struct SpotlightItemTests {
  @Test("Items carry the document ID, title, tags and bounded text")
  func itemContents() {
    var value = document("Contract", tags: ["legal"])
    value.pageCount = 12
    let item = SpotlightIndexer.item(for: value, text: String(repeating: "x", count: 30_000))
    #expect(item.uniqueIdentifier == value.id.description)
    #expect(item.domainIdentifier == SpotlightIndexer.domain)
    #expect(item.attributeSet.title == "Contract")
    #expect(item.attributeSet.keywords == ["legal"])
    #expect(item.attributeSet.textContent?.count == SpotlightIndexer.textLimit)
  }

  @Test func indexingAndRemovalNeverThrow() async {
    let indexer = SpotlightIndexer(indexName: "tests-\(UUID())")
    var value = document("Temporary")
    await indexer.index(value, text: "text")
    value.deletedAt = .now
    await indexer.index(value, text: "text")
    await indexer.remove(value.id)
  }
}
