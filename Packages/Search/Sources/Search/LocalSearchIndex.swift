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
  private let usesBaseForms: Bool
  private var cache: [DocumentID: [PageText]] = [:]

  /// Creates an index in a folder, optionally mirroring documents into Spotlight (FR-LIB-005).
  ///
  /// If the folder cannot be created, writes fail with an error and search still works from memory.
  ///
  /// - Parameters:
  ///   - folder: Where the page texts are kept.
  ///   - spotlight: The system index to mirror documents into, if any.
  ///   - usesBaseForms: Whether a searched word also finds its base form ("invoices" finds "invoice").
  public init(folder: URL, spotlight: (any SpotlightIndexing)? = nil, usesBaseForms: Bool = false) {
    self.usesBaseForms = usesBaseForms
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
  ///
  /// The Spotlight entry goes first, so a file that cannot be removed never leaves the document
  /// findable in Spotlight.
  public func remove(_ id: DocumentID) async throws {
    cache[id] = nil
    await spotlight?.remove(id)
    let url = file(for: id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// Removes the derived text and Spotlight entries of every document not in `ids`.
  public func prune(keeping ids: Set<DocumentID>) async -> [DocumentID] {
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    var removed: [DocumentID] = []
    for file in files where file.pathExtension == "json" {
      guard let id = DocumentID(string: file.deletingPathExtension().lastPathComponent), !ids.contains(id) else {
        continue
      }
      try? await remove(id)
      removed.append(id)
    }
    return removed
  }

  /// Writes every document to Spotlight again from the stored text (defect D11).
  ///
  /// Used after the Spotlight index or the text setting changed. Documents in Recently Deleted are
  /// removed from Spotlight.
  public func reindexSpotlight(_ documents: [Document]) async {
    guard let spotlight else { return }
    for document in documents {
      let text = ((try? await pages(of: document.id)) ?? []).map(\.text).joined(separator: "\n")
      await spotlight.index(document, text: text)
    }
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
    let interval = Signposts.begin("Search.Query")
    defer { interval.end() }
    let terms = SearchText.terms(query, baseForms: usesBaseForms)
    guard !terms.isEmpty else { return [] }
    var scored: [(hit: SearchHit, score: Int, title: String)] = []
    for document in documents {
      try Task.checkCancellation()
      let title = SearchText.fold(document.title + " " + document.tags.joined(separator: " "))
      let pages = (try? await pages(of: document.id)) ?? []
      let folded = pages.map { SearchText.fold($0.text) }
      let everything = title + " " + folded.joined(separator: " ")
      guard terms.allSatisfy({ $0.isFound(in: everything) }) else { continue }
      let titleMatches = terms.filter { $0.isFound(in: title) }.count
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

  /// One word of a query: as typed, and in its base form when that is asked for and differs.
  struct Term: Equatable {
    /// The word as typed, folded.
    let typed: String
    /// The word's base form, folded ("invoices" gives "invoice"), when it has one that differs.
    let base: String?

    /// The forms to look for, the typed one first.
    var forms: [String] { [typed] + (base.map { [$0] } ?? []) }

    /// Whether either form is in some folded text.
    func isFound(in folded: String) -> Bool { forms.contains(where: folded.contains) }
  }

  /// The query's words, folded; every word must match, in the form typed or, with `baseForms`,
  /// in its base form.
  static func terms(_ query: String, baseForms: Bool = false) -> [Term] {
    // The language is told from the whole query; a single word is too little to tell it from.
    let language = baseForms ? BaseForms.language(of: query) : nil
    return query.split { $0.isWhitespace || $0.isPunctuation && $0 != "-" }.compactMap { piece in
      let typed = fold(String(piece))
      guard !typed.isEmpty else { return nil }
      let base = BaseForms.of(String(piece), in: language).map(fold)
      return Term(typed: typed, base: base == typed ? nil : base)
    }
  }

  /// About 120 characters of text around the first matching term.
  static func snippet(_ text: String, around terms: [Term]) -> String? {
    let folded = fold(text)
    guard let term = terms.flatMap(\.forms).first(where: folded.contains), let range = folded.range(of: term) else {
      return nil
    }
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
  /// How often the query's words are in this text; a word counts in whichever form is there more.
  fileprivate func matchCount(of terms: [SearchText.Term]) -> Int {
    terms.reduce(0) { count, term in count + (term.forms.map { components(separatedBy: $0).count - 1 }.max() ?? 0) }
  }
}
