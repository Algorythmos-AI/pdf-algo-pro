import Foundation

/// One character code shown with a font: what it means and how far it moves the pen.
struct DecodedGlyph: Equatable {
  /// The text the code stands for; `nil` when the font gives no way to know.
  let text: String?
  /// The advance in thousandths of text space; `nil` when the font does not state it.
  let width: Double?
  /// Whether word spacing applies: a single-byte code 32 (PDF 32000-1, 9.3.3).
  let isWordSpace: Bool
}

/// What text editing needs to know about one font of a page: how to read text shown with it, how
/// wide that text is, and which typeface it is.
///
/// It only reads. New text is never encoded with a document font; it is drawn with Core Text
/// (`TextRedrawer`), because every font PDFKit writes is a subset holding just the letters already
/// on the page.
struct TextFont {
  /// The PostScript name without the subset tag (`AAAAAB+Georgia` is `Georgia`).
  let postScriptName: String
  /// Whether codes are two bytes (a composite font) or one.
  let isComposite: Bool
  /// Whether glyphs are drawn by content streams (Type 3), which text editing cannot match.
  let isType3: Bool
  /// The font descriptor's ascent and descent in thousandths, with typical values when absent.
  let ascent: Double
  let descent: Double
  /// Whether the descriptor says every glyph has the same width.
  let isFixedPitch: Bool
  /// Whether the descriptor says the font has serifs.
  let isSerif: Bool
  /// Whether the descriptor or the name says the font is italic or oblique.
  let isItalic: Bool
  /// Whether the name or the stem weight says the font is bold.
  let isBold: Bool
  /// The embedded font program, when it is one Core Text can load (TrueType or OpenType).
  let program: Data?

  private let unicode: [Int: String]
  private let widths: [Int: Double]
  private let defaultWidth: Double?

  /// Reads the glyphs a string shows.
  func glyphs(for string: [UInt8]) -> [DecodedGlyph] {
    var result: [DecodedGlyph] = []
    result.reserveCapacity(isComposite ? string.count / 2 : string.count)
    var index = 0
    while index < string.count {
      let code: Int
      if isComposite {
        guard index + 1 < string.count else { break }
        code = Int(string[index]) << 8 | Int(string[index + 1])
        index += 2
      } else {
        code = Int(string[index])
        index += 1
      }
      result.append(
        DecodedGlyph(
          text: unicode[code], width: widths[code] ?? defaultWidth, isWordSpace: !isComposite && code == 32))
    }
    return result
  }
}

extension TextFont {
  /// Reads a font dictionary from a page's resources.
  ///
  /// A font it cannot fully read still comes back, with glyphs whose text or width is `nil`; the
  /// regions shown with it are then not directly editable.
  init(dictionary: [String: PDFObject], in file: PDFFile) throws {
    let subtype = dictionary["Subtype"]?.name ?? ""
    let composite = subtype == "Type0"
    var descendant: [String: PDFObject]?
    if composite, let fonts = try file.resolve(dictionary["DescendantFonts"]).array, let first = fonts.first {
      descendant = try file.dictionary(first)
    }
    let descriptor = try file.dictionary((descendant ?? dictionary)["FontDescriptor"]) ?? [:]
    let baseName = dictionary["BaseFont"]?.name ?? descriptor["FontName"]?.name ?? ""
    let name = Self.withoutSubsetTag(baseName)
    let flags = descriptor["Flags"]?.integer ?? 0
    let lowered = name.lowercased()
    let italicAngle = try file.resolve(descriptor["ItalicAngle"]).number ?? 0
    let stem = try file.resolve(descriptor["StemV"]).number ?? 0

    postScriptName = name
    isComposite = composite
    isType3 = subtype == "Type3"
    ascent = try file.resolve(descriptor["Ascent"]).number ?? 800
    descent = try file.resolve(descriptor["Descent"]).number ?? -200
    isFixedPitch = flags & 1 != 0
    isSerif = flags & 2 != 0
    isItalic = flags & 64 != 0 || italicAngle != 0 || lowered.contains("italic") || lowered.contains("oblique")
    isBold =
      flags & 262_144 != 0 || lowered.contains("bold") || lowered.contains("black") || lowered.contains("heavy")
      || stem >= 140
    program = try Self.program(descriptor, in: file)

    var unicode: [Int: String] = [:]
    var widths: [Int: Double] = [:]
    var defaultWidth: Double?
    if composite {
      // Only identity-encoded fonts with their own character map can be read; the predefined
      // CJK maps are not built in.
      if dictionary["Encoding"] == .name("Identity-H"), let descendant {
        defaultWidth = try file.resolve(descendant["DW"]).number ?? 1000
        widths = try Self.compositeWidths(try file.resolve(descendant["W"]), in: file)
      }
    } else if !isType3 {
      unicode = try Self.simpleEncoding(dictionary["Encoding"], in: file)
      let first = try file.resolve(dictionary["FirstChar"]).integer ?? 0
      if let list = try file.resolve(dictionary["Widths"]).array, first >= 0, first <= 255 {
        for (offset, width) in list.prefix(256 - first).enumerated() {
          if let value = try file.resolve(width).number { widths[first + offset] = value }
        }
      }
      defaultWidth = try file.resolve(descriptor["MissingWidth"]).number
    }
    if case .reference(let number) = dictionary["ToUnicode"] {
      // The font's own map says what its codes mean, over any encoding.
      let map = try CharacterMap.parse(try file.stream(number).data)
      unicode.merge(map) { _, mapped in mapped }
    }
    self.unicode = unicode
    self.widths = widths
    self.defaultWidth = defaultWidth
  }

  /// `AAAAAB+Georgia-Bold` without its six-letter subset tag.
  static func withoutSubsetTag(_ name: String) -> String {
    let parts = name.split(separator: "+", maxSplits: 1)
    guard parts.count == 2, parts[0].count == 6, parts[0].allSatisfy({ $0.isASCII && $0.isUppercase }) else {
      return name
    }
    return String(parts[1])
  }

  private static func program(_ descriptor: [String: PDFObject], in file: PDFFile) throws -> Data? {
    for key in ["FontFile2", "FontFile3"] {
      if case .reference(let number) = descriptor[key] { return Data(try file.stream(number).data) }
    }
    return nil
  }

  private static func simpleEncoding(_ encoding: PDFObject?, in file: PDFFile) throws -> [Int: String] {
    var map: [Int: String] = [:]
    let resolved = try file.resolve(encoding)
    let base = resolved.name ?? resolved.dictionary?["BaseEncoding"]?.name
    let table: String.Encoding? =
      switch base {
      case "MacRomanEncoding": .macOSRoman
      case "WinAnsiEncoding": .windowsCP1252
      default: nil
      }
    if let table {
      for code in 32...255 {
        if let text = String(bytes: [UInt8(code)], encoding: table), !text.isEmpty { map[code] = text }
      }
    }
    if let differences = try file.resolve(resolved.dictionary?["Differences"]).array {
      var code = 0
      for item in differences {
        if let start = item.integer {
          code = start
        } else if let name = item.name {
          if (0...255).contains(code) { map[code] = GlyphNames.text(for: name) }
          code += 1
        }
      }
    }
    return map
  }

  private static func compositeWidths(_ object: PDFObject, in file: PDFFile) throws -> [Int: Double] {
    guard let items = object.array else { return [:] }
    var widths: [Int: Double] = [:]
    var index = 0
    while index < items.count {
      guard let first = items[index].integer, index + 1 < items.count else { break }
      if let list = try file.resolve(items[index + 1]).array {
        for (offset, width) in list.enumerated() {
          guard widths.count < TextEditingLimits.mappings else { throw PDFSyntaxError.tooLarge }
          if let value = width.number { widths[first + offset] = value }
        }
        index += 2
      } else if let last = items[index + 1].integer, index + 2 < items.count, let value = items[index + 2].number {
        guard last >= first, last - first < TextEditingLimits.mappings,
          widths.count + (last - first) < TextEditingLimits.mappings
        else { throw PDFSyntaxError.tooLarge }
        for code in first...last { widths[code] = value }
        index += 3
      } else {
        break
      }
    }
    return widths
  }
}

/// Reads a `ToUnicode` character map: which text each character code stands for.
enum CharacterMap {
  /// Parses the `bfchar` and `bfrange` sections of a character map.
  static func parse(_ bytes: [UInt8]) throws -> [Int: String] {
    var lexer = PDFLexer(bytes)
    var map: [Int: String] = [:]
    func add(_ code: Int, _ text: String?) throws {
      guard map.count < TextEditingLimits.mappings else { throw PDFSyntaxError.tooLarge }
      if let text, !text.isEmpty { map[code] = text }
    }
    while true {
      let (token, _) = try lexer.next()
      switch token {
      case .end:
        return map
      case .keyword("beginbfchar"):
        while case .string(let source) = try lexer.peek() {
          _ = try lexer.next()
          guard case .string(let target) = try lexer.next().token else { throw PDFSyntaxError.malformed }
          try add(code(source), text(target))
        }
      case .keyword("beginbfrange"):
        while case .string(let low) = try lexer.peek() {
          _ = try lexer.next()
          guard case .string(let high) = try lexer.next().token else { throw PDFSyntaxError.malformed }
          let first = code(low)
          let last = code(high)
          guard last >= first, last - first < TextEditingLimits.mappings else { throw PDFSyntaxError.malformed }
          let (target, _) = try lexer.next()
          if case .string(let start) = target {
            // Consecutive codes map to consecutive values of the last UTF-16 unit.
            guard start.count >= 2 else { throw PDFSyntaxError.malformed }
            for offset in 0...(last - first) {
              var units = start
              let low = Int(units[units.count - 2]) << 8 | Int(units[units.count - 1])
              let value = low + offset
              guard value <= 0xFFFF else { break }
              units[units.count - 2] = UInt8(value >> 8)
              units[units.count - 1] = UInt8(value & 0xFF)
              try add(first + offset, text(units))
            }
          } else if case .array(let targets) = try lexer.object(from: target, references: false, depth: 0) {
            for (offset, item) in targets.prefix(last - first + 1).enumerated() {
              if let units = item.bytes { try add(first + offset, text(units)) }
            }
          } else {
            throw PDFSyntaxError.malformed
          }
        }
      default:
        continue
      }
    }
  }

  private static func code(_ bytes: [UInt8]) -> Int {
    bytes.prefix(4).reduce(0) { $0 << 8 | Int($1) }
  }

  /// UTF-16 big-endian bytes as text.
  private static func text(_ bytes: [UInt8]) -> String? {
    guard bytes.count.isMultiple(of: 2) else { return nil }
    return String(bytes: bytes, encoding: .utf16BigEndian)
  }
}

/// What glyph names in an encoding's `/Differences` stand for.
///
/// Not the whole Adobe Glyph List: the algorithmic names (`uni20AC`, `u1F600`), single letters and
/// digits, and the named Latin punctuation and accents that appear in ordinary documents. A name it
/// does not know reads as no text, which makes the region not directly editable instead of wrong.
enum GlyphNames {
  static func text(for name: String) -> String? {
    if let known = named[name] { return known }
    if name.count == 1 { return name }
    if name.hasPrefix("uni"), name.count >= 7 {
      var scalars = String.UnicodeScalarView()
      var digits = Substring(name.dropFirst(3))
      while digits.count >= 4, let value = UInt32(digits.prefix(4), radix: 16), let scalar = Unicode.Scalar(value) {
        scalars.append(scalar)
        digits = digits.dropFirst(4)
      }
      return digits.isEmpty && !scalars.isEmpty ? String(scalars) : nil
    }
    if name.hasPrefix("u"), (5...7).contains(name.count), let value = UInt32(name.dropFirst(), radix: 16),
      let scalar = Unicode.Scalar(value)
    {
      return String(Character(scalar))
    }
    // `Aacute`, `ntilde`: a base letter and an accent name.
    if let first = name.first, first.isLetter, first.isASCII, let mark = accents[String(name.dropFirst())] {
      return (String(first) + mark).precomposedStringWithCanonicalMapping
    }
    return nil
  }

  private static let accents: [String: String] = [
    "grave": "\u{300}", "acute": "\u{301}", "circumflex": "\u{302}", "tilde": "\u{303}", "dieresis": "\u{308}",
    "ring": "\u{30A}", "cedilla": "\u{327}", "caron": "\u{30C}", "macron": "\u{304}", "breve": "\u{306}",
    "ogonek": "\u{328}", "dotaccent": "\u{307}", "hungarumlaut": "\u{30B}",
  ]

  private static let named: [String: String] = [
    "space": " ", "exclam": "!", "quotedbl": "\"", "numbersign": "#", "dollar": "$", "percent": "%",
    "ampersand": "&", "quotesingle": "'", "parenleft": "(", "parenright": ")", "asterisk": "*", "plus": "+",
    "comma": ",", "hyphen": "-", "period": ".", "slash": "/", "zero": "0", "one": "1", "two": "2", "three": "3",
    "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "colon": ":",
    "semicolon": ";", "less": "<", "equal": "=", "greater": ">", "question": "?", "at": "@",
    "bracketleft": "[", "backslash": "\\", "bracketright": "]", "asciicircum": "^", "underscore": "_",
    "grave": "`", "braceleft": "{", "bar": "|", "braceright": "}", "asciitilde": "~", "exclamdown": "¡",
    "cent": "¢", "sterling": "£", "currency": "¤", "yen": "¥", "brokenbar": "¦", "section": "§",
    "copyright": "©", "ordfeminine": "ª", "guillemotleft": "«", "logicalnot": "¬", "registered": "®",
    "degree": "°", "plusminus": "±", "mu": "µ", "paragraph": "¶", "periodcentered": "·",
    "ordmasculine": "º", "guillemotright": "»", "onequarter": "¼", "onehalf": "½", "threequarters": "¾",
    "questiondown": "¿", "AE": "Æ", "ae": "æ", "OE": "Œ", "oe": "œ", "Oslash": "Ø", "oslash": "ø",
    "germandbls": "ß", "Eth": "Ð", "eth": "ð", "Thorn": "Þ", "thorn": "þ", "Lslash": "Ł", "lslash": "ł",
    "dotlessi": "ı", "multiply": "×", "divide": "÷", "endash": "–", "emdash": "—", "quoteleft": "‘",
    "quoteright": "’", "quotesinglbase": "‚", "quotedblleft": "“", "quotedblright": "”",
    "quotedblbase": "„", "dagger": "†", "daggerdbl": "‡", "bullet": "•", "ellipsis": "…",
    "perthousand": "‰", "guilsinglleft": "‹", "guilsinglright": "›", "fraction": "⁄", "Euro": "€",
    "trademark": "™", "minus": "−", "fi": "fi", "fl": "fl", "nbspace": "\u{A0}", "sfthyphen": "\u{AD}",
  ]
}
