import Core
import Foundation

/// The in-app search index: each document's page text stored on device, searched case- and
/// diacritic-insensitively across titles, tags and text, including recognised text (FR-LIB-003).
///
/// Page text is derived data kept in Application Support, one file per document, and removed with
/// the document (FR-LIB-006). `Assumption:` a linear scan is fast enough for libraries up to a few
/// thousand documents; the 10,000-document performance test decides whether a token index is needed
/// (architecture review, open questions).
public actor LocalSearchIndex: DocumentIndexing {
  private let folder: URL
  private let spotlight: (any SpotlightIndexing)?
  private var cache: [DocumentID: [PageText]] = [:]

  /// Creates an index in a folder, optionally mirroring documents into Spotlight (FR-LIB-005).
  ///
  /// If the folder cannot be created, writes fail with an error and search still works from memory.
  public init(folder: URL, spotlight: (any SpotlightIndexing)? = nil) {
    self.folder = folder
    self.spotlight = spotlight
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  /// Adds or replaces a document in the index (and in Spotlight, FR-LIB-005).
  public func index(_ document: Document, pages: [PageText]) async throws {
    cache[document.id] = pages
    let data = try JSONEncoder().encode(pages)
    try data.write(to: file(for: document.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    await spotlight?.index(document, text: pages.map(\.text).joined(separator: "\n"))
  }

  /// Removes a document and its derived text (FR-LIB-006).
  public func remove(_ id: DocumentID) async throws {
    cache[id] = nil
    let url = file(for: id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    await spotlight?.remove(id)
  }

  /// The stored page texts of a document, for intelligence and reading aloud.
  public func pages(of id: DocumentID) async throws -> [PageText] {
    if let cached = cache[id] { return cached }
    let url = file(for: id)
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let pages = try JSONDecoder().decode([PageText].self, from: Data(contentsOf: url))
    cache[id] = pages
    return pages
  }

  /// Documents matching a query, best first.
  public func search(_ query: String, in documents: [Document]) async throws -> [SearchHit] {
    let terms = SearchText.terms(query)
    guard !terms.isEmpty else { return [] }
    var scored: [(hit: SearchHit, score: Int, title: String)] = []
    for document in documents {
      try Task.checkCancellation()
      let title = SearchText.fold(document.title + " " + document.tags.joined(separator: " "))
      let pages = (try? await pages(of: document.id)) ?? []
      let folded = pages.map { SearchText.fold($0.text) }
      let everything = title + " " + folded.joined(separator: " ")
      guard terms.allSatisfy(everything.contains) else { continue }
      let titleMatches = terms.filter(title.contains).count
      if titleMatches == terms.count {
        scored.append(
          (SearchHit(documentID: document.id, pageIndex: nil, snippet: nil), 1000 + titleMatches, document.title))
        continue
      }
      let best = folded.indices.max { folded[$0].matchCount(of: terms) < folded[$1].matchCount(of: terms) }
      let pageIndex = best.map { pages[$0].pageIndex }
      let snippet = best.flatMap { SearchText.snippet(pages[$0].text, around: terms) }
      let score = titleMatches * 100 + (best.map { folded[$0].matchCount(of: terms) } ?? 0)
      scored.append((SearchHit(documentID: document.id, pageIndex: pageIndex, snippet: snippet), score, document.title))
    }
    return scored.sorted { lhs, rhs in
      lhs.score != rhs.score
        ? lhs.score > rhs.score : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }.map(\.hit)
  }

  private func file(for id: DocumentID) -> URL {
    folder.appendingPathComponent("\(id).json")
  }
}

/// Text normalisation shared by indexing and queries.
enum SearchText {
  /// Lower-cased, diacritics removed, so "Resume" finds "Résumé".
  static func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
  }

  /// The query's words, folded; every word must match.
  static func terms(_ query: String) -> [String] {
    fold(query).split { $0.isWhitespace || $0.isPunctuation && $0 != "-" }.map(String.init).filter { !$0.isEmpty }
  }

  /// About 120 characters of text around the first matching term.
  static func snippet(_ text: String, around terms: [String]) -> String? {
    let folded = fold(text)
    guard let term = terms.first(where: folded.contains), let range = folded.range(of: term) else { return nil }
    let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
    let characters = Array(text)
    guard offset < characters.count else { return nil }
    let start = max(0, offset - 50)
    let end = min(characters.count, offset + 70)
    let body = String(characters[start..<end]).replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespaces)
    return (start > 0 ? "…" : "") + body + (end < characters.count ? "…" : "")
  }
}

extension String {
  fileprivate func matchCount(of terms: [String]) -> Int {
    terms.reduce(0) { count, term in count + components(separatedBy: term).count - 1 }
  }
}
