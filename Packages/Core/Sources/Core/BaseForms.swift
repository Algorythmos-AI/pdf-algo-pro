import Foundation
import NaturalLanguage

/// The base form of a word, from the system's language data: "paid" gives "pay", "factures"
/// gives "facture".
///
/// Used so that a question or a search finds a word in another of its forms. A base form is
/// looked up in one language, the language of the text the word is in, and each word is looked
/// up once and remembered.
///
/// What the system knows differs by device. Measured on 2026-10-08: macOS 26 gives base forms in
/// English and French; the iOS 26 simulator gives them in English only. Where the system has
/// none for a language or a word (a name, a number), there is none, and the caller keeps the
/// word as it is, so matching is then exactly what it was without this.
public enum BaseForms {
  private static let cache = Cache()

  /// The languages base forms are asked for: the two the app is written in.
  public static let languages: [NLLanguage] = [.english, .french]

  /// Whether the system gives base forms in a language on this device.
  public static func has(_ language: NLLanguage) -> Bool {
    cache.has(language)
  }

  /// The language of a text, when it is one the system gives base forms in here.
  ///
  /// - Parameter text: A question, or the start of a document.
  /// - Returns: English or French, or `nil` when the text is neither or the system has no base
  ///   forms for it.
  public static func language(of text: String) -> NLLanguage? {
    let known = languages.filter(has)
    guard !known.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    // No language is favoured: a text in another language, or one too short to tell, must come
    // back as none, and matching is then exactly what it was without base forms.
    recognizer.processString(String(text.prefix(2_000)))
    guard let language = recognizer.dominantLanguage, known.contains(language) else { return nil }
    return language
  }

  /// The base form of one word in a language, lower-cased.
  ///
  /// - Parameters:
  ///   - word: A single word, with its accents.
  ///   - language: The language of the text the word is in; `nil` gives no base form.
  /// - Returns: The base form, or `nil` when the system has none or it is the word itself.
  public static func of(_ word: String, in language: NLLanguage?) -> String? {
    guard let language else { return nil }
    let key = word.lowercased()
    guard key.count > 2, key.count < 40, key.contains(where: \.isLetter) else { return nil }
    return cache.value(for: key, in: language)
  }

  private final class Cache: @unchecked Sendable {
    // Guarded by `lock`: the tagger is not safe to use from two threads at once.
    private let lock = NSLock()
    private var known: [String: String?] = [:]
    private var available: [NLLanguage: Bool] = [:]
    private let tagger = NLTagger(tagSchemes: [.lemma])

    func has(_ language: NLLanguage) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      if let found = available[language] { return found }
      let found = NLTagger.availableTagSchemes(for: .word, language: language).contains(.lemma)
      available[language] = found
      return found
    }

    func value(for word: String, in language: NLLanguage) -> String? {
      lock.lock()
      defer { lock.unlock() }
      let key = language.rawValue + ":" + word
      if let found = known[key] { return found }
      tagger.string = word
      tagger.setLanguage(language, range: word.startIndex..<word.endIndex)
      let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
      let form = tag.flatMap { $0.isEmpty || $0 == word ? nil : $0 }
      // A document has a few thousand different words; past that, start again rather than grow.
      if known.count > 20_000 { known.removeAll(keepingCapacity: true) }
      known[key] = form
      return form
    }
  }
}
