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
  LocalSearchIndex(
    folder: FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID())"), spotlight: spotlight)
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
    try await index.index(
      lease,
      pages: [
        PageText(pageIndex: 0, text: "Parties"),
        PageText(pageIndex: 1, text: "The monthly rent is due on the first day."),
      ])
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

  @Test("Spotlight can be rebuilt from the stored text; deleted documents leave it (defect D11)")
  func reindexSpotlight() async throws {
    let spotlight = RecordingSpotlight()
    let index = try makeIndex(spotlight: spotlight)
    let kept = document("Kept")
    var binned = document("Binned")
    try await index.index(kept, pages: [PageText(pageIndex: 0, text: "first"), PageText(pageIndex: 1, text: "second")])
    binned.deletedAt = .now

    await index.reindexSpotlight([kept, binned])

    #expect(await spotlight.indexed[kept.id] == "first\nsecond")
    #expect(await spotlight.indexed[binned.id] == "", "Recorded as sent; the real indexer removes deleted documents")
    await LocalSearchIndex(folder: FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID())"))
      .reindexSpotlight([kept])
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

  @Test("Pruning removes the text and Spotlight entries of documents the library no longer has (FR-LIB-006)")
  func prune() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID())")
    let spotlight = RecordingSpotlight()
    let index = LocalSearchIndex(folder: folder, spotlight: spotlight)
    let kept = document("Kept")
    let stale = document("Stale")
    for item in [kept, stale] { try await index.index(item, pages: [PageText(pageIndex: 0, text: item.title)]) }
    try Data("{}".utf8).write(to: folder.appendingPathComponent("not-an-id.json"))

    #expect(await index.prune(keeping: [kept.id]) == [stale.id])

    #expect(try await index.pages(of: stale.id).isEmpty)
    #expect(try await index.pages(of: kept.id).map(\.text) == ["Kept"])
    #expect(await spotlight.removed == [stale.id])
    #expect(await index.prune(keeping: [kept.id]).isEmpty)
    #expect(await LocalSearchIndex(folder: folder.appendingPathComponent("missing")).prune(keeping: []).isEmpty)
  }

  @Test("Spotlight forgets a document even when its stored text cannot be removed")
  func spotlightFirst() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID())")
    let spotlight = RecordingSpotlight()
    let index = LocalSearchIndex(folder: folder, spotlight: spotlight)
    let report = document("Report")
    try await index.index(report, pages: [PageText(pageIndex: 0, text: "text")])
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

    await #expect(throws: (any Error).self) { try await index.remove(report.id) }

    #expect(await spotlight.removed == [report.id])
  }

  @Test func snippetsAreShortAndMarkTruncation() {
    let text = String(repeating: "lorem ", count: 40) + "needle" + String(repeating: " ipsum", count: 40)
    let snippet = SearchText.snippet(text, around: SearchText.terms("needle"))
    #expect(snippet?.hasPrefix("…") == true && snippet?.hasSuffix("…") == true)
    #expect(snippet?.contains("needle") == true)
    #expect((snippet?.count ?? 0) <= 125)
    #expect(SearchText.snippet("abc", around: SearchText.terms("zzz")) == nil)
  }

  @Test func termsSplitOnSpacesAndPunctuation() {
    #expect(SearchText.terms("  Tax, 2026!  e-mail ").map(\.typed) == ["tax", "2026", "e-mail"])
    #expect(SearchText.terms("  Tax, 2026!  e-mail ").allSatisfy { $0.base == nil }, "No base forms unless asked")
  }

  @Test("With base forms on, a searched word also finds its base form; off, search is as it was")
  func baseForms() async throws {
    // Whether the system has base forms differs by device; without them there is nothing to check.
    guard BaseForms.has(.english) else { return }
    #expect(SearchText.terms("Invoices paid", baseForms: true).map(\.base) == ["invoice", "pay"])
    #expect(SearchText.terms("résumé 2026", baseForms: true).map(\.typed) == ["resume", "2026"])
    // A snippet is found around whichever form is in the text.
    #expect(
      SearchText.snippet("We will pay on Friday.", around: SearchText.terms("paid", baseForms: true))?.contains("pay")
        == true)

    func hits(_ query: String, baseForms: Bool) async throws -> Int {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let index = LocalSearchIndex(folder: folder, usesBaseForms: baseForms)
      let document = Document(title: "Letter", fileName: "letter.pdf", addedAt: .now, tags: [])
      try await index.index(document, pages: [PageText(pageIndex: 0, text: "Please pay the child care fee.")])
      return try await index.search(query, in: [document]).count
    }
    #expect(try await hits("paid", baseForms: false) == 0)
    #expect(try await hits("paid", baseForms: true) == 1)
    #expect(try await hits("children fees", baseForms: true) == 1)
    #expect(try await hits("pay fee", baseForms: false) == 1, "What was found before is still found")
    #expect(try await hits("holiday", baseForms: true) == 0)
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
    #expect(SpotlightIndexer.item(for: value, text: nil).attributeSet.textContent == nil, "Titles only")
    #expect(SpotlightIndexer.item(for: value, text: nil).attributeSet.title == "Contract")
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
