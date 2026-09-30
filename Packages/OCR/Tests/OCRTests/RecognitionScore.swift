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
