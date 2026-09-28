import Core
import Foundation

/// Retrieval, citation parsing and grounding checks: the logic that keeps answers tied to pages.
/// It is pure and model-independent, so it is tested exhaustively (FR-AI-001, FR-AI-002, FR-AI-010).
enum Grounding {
  /// Words that carry no meaning for matching, in English and French.
  static let stopWords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "by", "can", "do", "does", "for", "from", "how", "in", "is", "it",
    "of", "on", "or", "that", "the", "this", "to", "was", "what", "when", "where", "which", "who", "why", "with",
    "au", "aux", "ce", "ces", "dans", "de", "des", "du", "en", "est", "et", "il", "la", "le", "les", "leur", "ou",
    "par", "pour", "quel", "quelle", "qui", "quoi", "sur", "un", "une",
  ]

  /// Folded content words of a text.
  static func words(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
      .filter { $0.count > 1 && !stopWords.contains($0) }
  }

  /// Pages ranked by BM25 relevance to a query, best first; pages with no matching word are left out.
  static func rank(_ pages: [PageText], for query: String) -> [PageText] {
    let terms = Set(words(query))
    guard !terms.isEmpty else { return [] }
    let documents = pages.map { words($0.text) }
    let averageLength = max(1, Double(documents.map(\.count).reduce(0, +)) / Double(max(1, documents.count)))
    var documentFrequency: [String: Int] = [:]
    for words in documents {
      for term in terms where words.contains(term) { documentFrequency[term, default: 0] += 1 }
    }
    let scored: [(page: PageText, score: Double)] = zip(pages, documents).map { page, words in
      var counts: [String: Int] = [:]
      for word in words where terms.contains(word) { counts[word, default: 0] += 1 }
      let score = counts.reduce(0.0) { total, entry in
        let frequency = Double(entry.value)
        let df = Double(documentFrequency[entry.key] ?? 0)
        let idf = log(1 + (Double(pages.count) - df + 0.5) / (df + 0.5))
        let norm = frequency * 2.2 / (frequency + 1.2 * (0.25 + 0.75 * Double(words.count) / averageLength))
        return total + idf * norm
      }
      return (page, score)
    }
    return scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }.map(\.page)
  }

  /// A response split into its text and the pages it cites. Markers such as `[p3]`, `[p. 3]`,
  /// `[P3, p4]` and `[pp3-5]` are recognised and removed; cited pages outside `validPages` are dropped.
  static func parseCitations(_ response: String, validPages: Set<Int>) -> (text: String, pageIndices: [Int]) {
    let pattern = /\[\s*[pP]{1,2}\.?\s*(\d{1,5})(?:\s*[-–]\s*(\d{1,5}))?((?:\s*[,;]\s*[pP]?\.?\s*\d{1,5})*)\s*\]/
    var pages: [Int] = []
    func add(_ number: Int) {
      let index = number - 1
      if validPages.contains(index), !pages.contains(index) { pages.append(index) }
    }
    for match in response.matches(of: pattern) {
      guard let first = Int(match.output.1) else { continue }
      let last = match.output.2.flatMap { Int($0) } ?? first
      if last >= first, last - first <= 50 {
        for number in first...last { add(number) }
      }
      for extra in match.output.3.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }) { add(extra) }
    }
    let stripped = response.replacing(pattern, with: "")
      .replacingOccurrences(of: " .", with: ".")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (stripped, pages)
  }

  /// Whether a response is the model's "not in the document" answer.
  static func isNotFound(_ response: String) -> Bool {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.uppercased().hasPrefix("NOT_FOUND") || trimmed.uppercased() == "NOT FOUND"
  }

  /// Pages that support a text by word overlap, for sentences the model did not cite. A page must
  /// share at least `minimumShare` of the text's content words.
  static func supportingPages(for text: String, in pages: [PageText], minimumShare: Double = 0.5) -> [Int] {
    let wanted = Set(words(text))
    guard !wanted.isEmpty else { return [] }
    let best = pages.map { page -> (Int, Double) in
      let present = Set(words(page.text))
      return (page.pageIndex, Double(wanted.intersection(present).count) / Double(wanted.count))
    }.max { $0.1 < $1.1 }
    guard let best, best.1 >= minimumShare else { return [] }
    return [best.0]
  }

  /// The sentence on a page that best supports a text, copied verbatim so the reader can find and
  /// highlight it.
  static func quote(supporting text: String, on page: PageText) -> String? {
    let wanted = Set(words(text))
    let sentences = page.text
      .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.count >= 8 }
    let best = sentences.map { ($0, Set(words($0)).intersection(wanted).count) }.max { $0.1 < $1.1 }
    guard let best, best.1 > 0 else { return nil }
    return String(best.0.prefix(160))
  }

  /// Builds a grounded answer from a response: citations parsed, missing ones repaired by overlap,
  /// and a verbatim quote attached to each cited page. With no supported page the answer is
  /// not-found, never an uncited claim.
  static func answer(from response: String, pages: [PageText], tier: IntelligenceTier) -> Answer {
    guard !isNotFound(response) else { return .notFound(tier: tier) }
    let parsed = parseCitations(response, validPages: Set(pages.map(\.pageIndex)))
    var cited = parsed.pageIndices
    if cited.isEmpty {
      cited = supportingPages(for: parsed.text, in: pages)
    }
    guard !cited.isEmpty, !parsed.text.isEmpty else { return .notFound(tier: tier) }
    let byIndex = Dictionary(uniqueKeysWithValues: pages.map { ($0.pageIndex, $0) })
    let citations = cited.map { index in
      Citation(pageIndex: index, quote: byIndex[index].flatMap { quote(supporting: parsed.text, on: $0) })
    }
    return Answer(text: parsed.text, citations: citations, tier: tier, isGrounded: true)
  }

  /// Finds a value verbatim in the pages (ignoring case, accents and spacing) and returns its page.
  static func page(containing value: String, in pages: [PageText]) -> Int? {
    let needle = normalized(value)
    guard needle.count >= 2 else { return nil }
    return pages.first { normalized($0.text).contains(needle) }?.pageIndex
  }

  private static func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
