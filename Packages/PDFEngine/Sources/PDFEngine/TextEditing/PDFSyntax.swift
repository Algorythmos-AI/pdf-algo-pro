import Foundation

/// Why PDF bytes could not be read for text editing.
///
/// Every case means "this page is not editable"; none is shown to the person as it is.
enum PDFSyntaxError: Error, Equatable {
  /// The bytes are not the PDF syntax they should be at this point.
  case malformed
  /// Valid PDF, but a structure text editing does not read (an object stream, an unusual filter).
  case unsupported
  /// Over one of `TextEditingLimits`.
  case tooLarge
}

/// Bounds on what text editing will read from a page, so a hostile or huge page is refused instead
/// of exhausting memory or time.
///
/// PDFs are untrusted input.
///
/// Assumption: these starting values are generous for real documents (a dense page has a few
/// thousand operators); they are validated by the golden corpus and the device test plan.
enum TextEditingLimits {
  /// The deepest nesting of arrays and dictionaries, and of the page tree.
  static let depth = 64
  /// The most operators read from one page's content.
  static let operators = 200_000
  /// The most bytes of decoded page content, or of any one decoded stream.
  static let contentBytes = 16_000_000
  /// The most cross-reference sections followed through `/Prev`.
  static let updates = 16
  /// The most objects a cross-reference table may list.
  static let objects = 200_000
  /// The most entries one character map may define.
  static let mappings = 70_000
}

/// A parsed PDF object: only the syntax, with no meaning attached.
indirect enum PDFObject: Equatable, Sendable {
  case null
  case boolean(Bool)
  case integer(Int)
  case real(Double)
  case name(String)
  case string([UInt8])
  case array([PDFObject])
  case dictionary([String: PDFObject])
  /// An indirect reference, by object number. Generations are not kept: text editing reads files
  /// written by Core Graphics, where they are always zero.
  case reference(Int)

  /// The value as a number, for integers and reals.
  var number: Double? {
    switch self {
    case .integer(let value): Double(value)
    case .real(let value): value
    default: nil
    }
  }

  /// The value as an integer, when it is one.
  var integer: Int? {
    if case .integer(let value) = self { value } else { nil }
  }

  /// The value as a name.
  var name: String? {
    if case .name(let value) = self { value } else { nil }
  }

  /// The value as an array.
  var array: [PDFObject]? {
    if case .array(let value) = self { value } else { nil }
  }

  /// The value as a dictionary.
  var dictionary: [String: PDFObject]? {
    if case .dictionary(let value) = self { value } else { nil }
  }

  /// The value as string bytes.
  var bytes: [UInt8]? {
    if case .string(let value) = self { value } else { nil }
  }
}

/// One lexical token of PDF syntax.
enum PDFToken: Equatable {
  case integer(Int)
  case real(Double)
  case name(String)
  case string([UInt8])
  case arrayStart
  case arrayEnd
  case dictionaryStart
  case dictionaryEnd
  /// Anything else made of regular characters: an operator, `obj`, `R`, `true`, `stream` and so on.
  case keyword(String)
  case end
}

/// Reads PDF tokens and objects from bytes.
///
/// Every index is checked; nothing here can read out of bounds or recurse without limit.
struct PDFLexer {
  let bytes: [UInt8]
  var position: Int

  init(_ bytes: [UInt8], at position: Int = 0) {
    self.bytes = bytes
    self.position = max(0, min(position, bytes.count))
  }

  static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
  }

  static func isDelimiter(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25: true
    default: false
    }
  }

  /// Moves past whitespace and comments.
  mutating func skipWhitespace() {
    while position < bytes.count {
      let byte = bytes[position]
      if Self.isWhitespace(byte) {
        position += 1
      } else if byte == 0x25 {
        while position < bytes.count, bytes[position] != 10, bytes[position] != 13 { position += 1 }
      } else {
        return
      }
    }
  }

  /// The next token and the bytes it occupies.
  mutating func next() throws -> (token: PDFToken, range: Range<Int>) {
    skipWhitespace()
    let start = position
    guard position < bytes.count else { return (.end, start..<start) }
    let byte = bytes[position]
    let token: PDFToken
    switch byte {
    case 0x5B:
      position += 1
      token = .arrayStart
    case 0x5D:
      position += 1
      token = .arrayEnd
    case 0x2F:
      position += 1
      token = .name(try readName())
    case 0x28:
      position += 1
      token = .string(try readLiteralString())
    case 0x3C:
      if position + 1 < bytes.count, bytes[position + 1] == 0x3C {
        position += 2
        token = .dictionaryStart
      } else {
        position += 1
        token = .string(try readHexString())
      }
    case 0x3E:
      guard position + 1 < bytes.count, bytes[position + 1] == 0x3E else { throw PDFSyntaxError.malformed }
      position += 2
      token = .dictionaryEnd
    case 0x29, 0x7B, 0x7D:
      throw PDFSyntaxError.malformed
    default:
      token = try readRegular()
    }
    return (token, start..<position)
  }

  /// The next token without consuming it.
  func peek() throws -> PDFToken {
    var copy = self
    return try copy.next().token
  }

  private mutating func readRegular() throws -> PDFToken {
    let start = position
    while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
      position += 1
    }
    guard position > start else { throw PDFSyntaxError.malformed }
    let slice = bytes[start..<position]
    if let number = Self.number(slice) { return number }
    return .keyword(String(decoding: slice, as: UTF8.self))
  }

  /// A PDF number: an optional sign, digits, and at most one point.
  ///
  /// Anything else is a keyword.
  private static func number(_ slice: ArraySlice<UInt8>) -> PDFToken? {
    var index = slice.startIndex
    var negative = false
    if slice[index] == 0x2B || slice[index] == 0x2D {
      negative = slice[index] == 0x2D
      index += 1
    }
    var whole = 0.0
    var fraction = 0.0
    var scale = 1.0
    var digits = 0
    var seenPoint = false
    var integer: Int? = 0
    while index < slice.endIndex {
      let byte = slice[index]
      if byte == 0x2E {
        guard !seenPoint else { return nil }
        seenPoint = true
      } else if byte >= 0x30, byte <= 0x39 {
        let digit = Int(byte - 0x30)
        digits += 1
        if seenPoint {
          scale /= 10
          fraction += Double(digit) * scale
        } else {
          whole = whole * 10 + Double(digit)
          if let value = integer {
            let (product, overflowed) = value.multipliedReportingOverflow(by: 10)
            let (sum, carried) = product.addingReportingOverflow(digit)
            integer = overflowed || carried ? nil : sum
          }
        }
      } else {
        return nil
      }
      index += 1
    }
    guard digits > 0 else { return nil }
    if !seenPoint, let integer { return .integer(negative ? -integer : integer) }
    let value = whole + fraction
    return .real(negative ? -value : value)
  }

  private mutating func readName() throws -> String {
    var scalars = String.UnicodeScalarView()
    while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
      var byte = bytes[position]
      position += 1
      if byte == 0x23, position + 1 < bytes.count, let high = Self.hexValue(bytes[position]),
        let low = Self.hexValue(bytes[position + 1])
      {
        byte = high << 4 | low
        position += 2
      }
      scalars.append(Unicode.Scalar(byte))
    }
    return String(scalars)
  }

  private mutating func readLiteralString() throws -> [UInt8] {
    var result: [UInt8] = []
    var depth = 1
    while position < bytes.count {
      let byte = bytes[position]
      position += 1
      switch byte {
      case 0x28:
        depth += 1
        result.append(byte)
      case 0x29:
        depth -= 1
        if depth == 0 { return result }
        result.append(byte)
      case 0x5C:
        guard position < bytes.count else { throw PDFSyntaxError.malformed }
        let escaped = bytes[position]
        position += 1
        switch escaped {
        case 0x6E: result.append(10)
        case 0x72: result.append(13)
        case 0x74: result.append(9)
        case 0x62: result.append(8)
        case 0x66: result.append(12)
        case 0x0D:
          if position < bytes.count, bytes[position] == 0x0A { position += 1 }
        case 0x0A:
          break
        case 0x30...0x37:
          var value = Int(escaped - 0x30)
          var count = 1
          while count < 3, position < bytes.count, bytes[position] >= 0x30, bytes[position] <= 0x37 {
            value = value * 8 + Int(bytes[position] - 0x30)
            position += 1
            count += 1
          }
          result.append(UInt8(truncatingIfNeeded: value))
        default:
          result.append(escaped)
        }
      case 0x0D:
        if position < bytes.count, bytes[position] == 0x0A { position += 1 }
        result.append(10)
      default:
        result.append(byte)
      }
    }
    throw PDFSyntaxError.malformed
  }

  private mutating func readHexString() throws -> [UInt8] {
    var result: [UInt8] = []
    var pending: UInt8?
    while position < bytes.count {
      let byte = bytes[position]
      position += 1
      if byte == 0x3E {
        if let pending { result.append(pending << 4) }
        return result
      }
      if Self.isWhitespace(byte) { continue }
      guard let value = Self.hexValue(byte) else { throw PDFSyntaxError.malformed }
      if let high = pending {
        result.append(high << 4 | value)
        pending = nil
      } else {
        pending = value
      }
    }
    throw PDFSyntaxError.malformed
  }

  static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: byte - 0x30
    case 0x41...0x46: byte - 0x41 + 10
    case 0x61...0x66: byte - 0x61 + 10
    default: nil
    }
  }

  /// Reads one object.
  ///
  /// With `references` on, `12 0 R` is read as a reference (file syntax); page content has no
  /// references, so there the integers stay integers.
  mutating func object(references: Bool, depth: Int = 0) throws -> PDFObject {
    let (token, _) = try next()
    return try object(from: token, references: references, depth: depth)
  }

  /// Finishes reading the object that starts with a token already taken.
  mutating func object(from token: PDFToken, references: Bool, depth: Int) throws -> PDFObject {
    guard depth <= TextEditingLimits.depth else { throw PDFSyntaxError.tooLarge }
    switch token {
    case .integer(let value):
      if references, value >= 0 {
        var ahead = self
        if case .integer(let generation) = try ahead.next().token, generation >= 0,
          try ahead.next().token == .keyword("R")
        {
          self = ahead
          return .reference(value)
        }
      }
      return .integer(value)
    case .real(let value):
      return .real(value)
    case .name(let value):
      return .name(value)
    case .string(let value):
      return .string(value)
    case .arrayStart:
      var items: [PDFObject] = []
      while true {
        let (inner, _) = try next()
        if inner == .arrayEnd { return .array(items) }
        guard inner != .end, items.count < TextEditingLimits.objects else { throw PDFSyntaxError.malformed }
        items.append(try object(from: inner, references: references, depth: depth + 1))
      }
    case .dictionaryStart:
      var entries: [String: PDFObject] = [:]
      while true {
        let (key, _) = try next()
        if key == .dictionaryEnd { return .dictionary(entries) }
        guard case .name(let name) = key, entries.count < TextEditingLimits.objects else {
          throw PDFSyntaxError.malformed
        }
        entries[name] = try object(references: references, depth: depth + 1)
      }
    case .keyword("true"):
      return .boolean(true)
    case .keyword("false"):
      return .boolean(false)
    case .keyword("null"):
      return .null
    case .keyword, .arrayEnd, .dictionaryEnd, .end:
      throw PDFSyntaxError.malformed
    }
  }
}
