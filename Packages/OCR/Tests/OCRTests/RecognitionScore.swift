import Foundation

/// Character and word error rates, as the testing strategy defines them ("OCR accuracy testing",
/// "Metrics"): Levenshtein edits over the ground truth's length, after normalisation.
struct RecognitionScore: Equatable {
  /// Character edits and ground-truth characters.
  var characterEdits = 0
  var characters = 0
  /// Word edits and ground-truth words.
  var wordEdits = 0
  var words = 0

  /// The character error rate, from 0.
  var characterErrorRate: Double { characters == 0 ? 0 : Double(characterEdits) / Double(characters) }
  /// The word error rate, from 0.
  var wordErrorRate: Double { words == 0 ? 0 : Double(wordEdits) / Double(words) }

  /// Scores one page.
  init(recognised: String, truth: String) {
    let recognised = Self.normalised(recognised)
    let truth = Self.normalised(truth)
    characterEdits = Self.distance(Array(recognised), Array(truth))
    characters = truth.count
    let recognisedWords = recognised.split(separator: " ").map(String.init)
    let truthWords = truth.split(separator: " ").map(String.init)
    wordEdits = Self.distance(recognisedWords, truthWords)
    words = truthWords.count
  }

  init() {}

  /// Adds another page's counts, so a subset's rate is over all its characters, not an average of pages.
  static func + (lhs: Self, rhs: Self) -> Self {
    var total = lhs
    total.characterEdits += rhs.characterEdits
    total.characters += rhs.characters
    total.wordEdits += rhs.wordEdits
    total.words += rhs.words
    return total
  }

  /// The text as scored.
  ///
  /// - Unicode NFKC, and every run of whitespace, including no-break spaces and line breaks, as one space.
  /// - Typographic apostrophes and quotation marks compare equal to their ASCII forms (Vision returns
  ///   `'` for `’`).
  /// - The space before `;`, `:`, `!`, `?` and `»`, and after `«`, is ignored: French typography puts a
  ///   narrow no-break space there, which recognition reports inconsistently. The marks still count.
  ///
  /// Case and accents stay significant: "é" read as "e" is an error.
  static func normalised(_ text: String) -> String {
    let folded = text.precomposedStringWithCompatibilityMapping
      .map { character -> Character in
        switch character {
        case "\u{2019}", "\u{2018}", "\u{02BC}", "\u{2032}": "'"
        case "\u{201C}", "\u{201D}", "\u{201E}": "\""
        default: character
        }
      }
    let spaced = String(folded).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return
      spaced
      .replacing(#/ ([;:!?»])/#) { String($0.output.1) }
      .replacing(#/« /#, with: "«")
  }

  /// The word edits between the recognised text and the ground truth, in reading order.
  ///
  /// Each reads `"été" read as "ete"`, `"à" missed` or `"x" added`, after normalisation; none when
  /// every word is right. A failing gate reports these, so the log alone names the wrong words.
  static func wordDifferences(recognised: String, truth: String) -> [String] {
    let found = normalised(recognised).split(separator: " ").map(String.init)
    let wanted = normalised(truth).split(separator: " ").map(String.init)
    // The full table of distances between prefixes, walked back from the end to find the edits.
    var table = Array(repeating: Array(repeating: 0, count: wanted.count + 1), count: found.count + 1)
    for i in 0...found.count { table[i][0] = i }
    for j in 0...wanted.count { table[0][j] = j }
    for i in stride(from: 1, through: found.count, by: 1) {
      for j in stride(from: 1, through: wanted.count, by: 1) {
        let same = found[i - 1] == wanted[j - 1] ? 0 : 1
        table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + same)
      }
    }
    var edits: [String] = []
    var i = found.count
    var j = wanted.count
    while i > 0 || j > 0 {
      if i > 0, j > 0, table[i][j] == table[i - 1][j - 1] + (found[i - 1] == wanted[j - 1] ? 0 : 1) {
        if found[i - 1] != wanted[j - 1] { edits.append("\"\(wanted[j - 1])\" read as \"\(found[i - 1])\"") }
        i -= 1
        j -= 1
      } else if j > 0, table[i][j] == table[i][j - 1] + 1 {
        edits.append("\"\(wanted[j - 1])\" missed")
        j -= 1
      } else {
        edits.append("\"\(found[i - 1])\" added")
        i -= 1
      }
    }
    return edits.reversed()
  }

  /// The minimum number of insertions, deletions and substitutions turning one sequence into another.
  static func distance<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> Int {
    guard !lhs.isEmpty else { return rhs.count }
    guard !rhs.isEmpty else { return lhs.count }
    var previous = Array(0...rhs.count)
    var current = Array(repeating: 0, count: rhs.count + 1)
    for (i, left) in lhs.enumerated() {
      current[0] = i + 1
      for (j, right) in rhs.enumerated() {
        current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1))
      }
      swap(&previous, &current)
    }
    return previous[rhs.count]
  }
}
