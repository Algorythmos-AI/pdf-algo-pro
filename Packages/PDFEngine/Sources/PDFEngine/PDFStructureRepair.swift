import CoreGraphics
import Foundation

/// Puts back, as an incremental update, the outline and the link destinations PDFKit leaves out of a
/// file it writes (#307).
///
/// On iOS 27.0, PDFKit writes the outline the document had when it was opened, whatever it holds now,
/// so bookmarks added, renamed or removed are lost; and it writes every link that goes to a page with a
/// placeholder (`/Dest [ /#23233 … ]`) instead of the page, so every such link goes nowhere. The save
/// reads back what it wrote and, where it differs from the document, appends one update to the file:
/// new versions of the broken links, a new outline, and a new catalog pointing to it. The bytes PDFKit
/// wrote are kept as they are; an update is how PDF itself adds to a file (ISO 32000-1, 7.5.6).
///
/// It understands what PDFKit writes: a cross-reference table, not a stream. Anything else, it leaves
/// alone and says so by returning `nil`. In an encrypted file it mends links, which hold no strings, and
/// writes the outline only under the standard handler as PDFKit writes it (revision 3 with RC4 on iOS 27,
/// revision 4 with AES-128 on macOS), encrypting the titles with the password (#309). An outline item
/// keeps the zoom its page opens at and, when it opens one, its web address, encrypted like its title
/// (#356).
enum PDFStructureRepair {
  /// A link as the document has it: on which page, where, and the page it goes to.
  struct Link: Equatable {
    let pageIndex: Int
    let rect: CGRect
    let target: Int
    let point: CGPoint?
  }

  /// An outline item as the document has it.
  struct OutlineItem: Equatable {
    let title: String
    let target: Int?
    let point: CGPoint?
    let isOpen: Bool
    let children: [OutlineItem]
    /// The web address the item opens, when it opens one rather than a page (#356).
    let url: URL?
    /// The zoom its page opens at, when it sets one (#356).
    let zoom: CGFloat?

    init(
      title: String, target: Int?, point: CGPoint?, isOpen: Bool, children: [OutlineItem], url: URL? = nil,
      zoom: CGFloat? = nil
    ) {
      self.title = title
      self.target = target
      self.point = point
      self.isOpen = isOpen
      self.children = children
      self.url = url
      self.zoom = zoom
    }
  }

  /// What a repair did.
  struct Result {
    let data: Data
    let mendedLinks: Int
    let wroteOutline: Bool
  }

  /// The file with `links` and `outline` written into an update.
  ///
  /// - Parameters:
  ///   - data: the file as PDFKit wrote it.
  ///   - links: every link to a page the file should have, with the page it goes to.
  ///   - outline: the outline the file should have; an empty array removes it; `nil` leaves it alone.
  ///   - password: the user password of an encrypted file, to encrypt the outline's titles; empty when it
  ///     opens without one.
  /// - Returns: the updated file and what was mended, or `nil` when the file isn't one this can read or
  ///   nothing needed mending.
  static func repaired(_ data: Data, links: [Link], outline: [OutlineItem]?, password: String = "") -> Result? {
    guard var file = WrittenPDF(data: data) else { return nil }
    let security = file.isEncrypted ? file.standardSecurity(password: password) : nil
    var mended = 0
    // Each link claims one annotation, the first unclaimed one in the page's order with its rectangle,
    // so two links in the same place keep their own targets.
    var claimed: Set<Int> = []
    for link in links {
      guard let pageRef = file.pageReferences[safe: link.pageIndex],
        let targetRef = file.pageReferences[safe: link.target],
        let page = file.dictionary(pageRef),
        let annots = file.array(page["Annots"])
      else { continue }
      for case .reference(let number, let generation) in annots where !claimed.contains(number) {
        guard var annotation = file.dictionary(.reference(number, generation)),
          annotation["Subtype"] == .name("Link"),
          let rect = file.rect(annotation["Rect"]),
          rect.isClose(to: link.rect)
        else { continue }
        annotation.remove("A")
        annotation["Dest"] = destination(targetRef, link.point, nil)
        file.replace(number, generation, with: .dictionary(annotation))
        claimed.insert(number)
        mended += 1
        break
      }
    }
    var wroteOutline = false
    if let outline, !file.isEncrypted || security != nil, var catalog = file.dictionary(file.root) {
      if outline.isEmpty {
        catalog.remove("Outlines")
      } else {
        guard let reference = file.addOutline(outline, security: security, destination: destination) else {
          return nil
        }
        catalog["Outlines"] = reference
      }
      if case .reference(let number, let generation) = file.root {
        file.replace(number, generation, with: .dictionary(catalog))
        wroteOutline = true
      }
    }
    guard mended > 0 || wroteOutline else { return nil }
    return Result(data: file.updated(), mendedLinks: mended, wroteOutline: wroteOutline)
  }

  /// `[page /XYZ x y zoom]`: the page at that point, or at its top when there is none, at that zoom, or
  /// at the zoom it is read at when there is none.
  private static func destination(_ page: WrittenPDFValue, _ point: CGPoint?, _ zoom: CGFloat?) -> WrittenPDFValue {
    func coordinate(_ value: CGFloat?) -> WrittenPDFValue {
      guard let value, value.isFinite, abs(value) < 1_000_000 else { return .null }
      return .number(String(format: "%.2f", Double(value)))
    }
    var scale = WrittenPDFValue.null
    if let zoom, zoom.isFinite, zoom > 0, zoom < 1_000_000 { scale = .number(String(format: "%.4f", Double(zoom))) }
    return .array([page, .name("XYZ"), coordinate(point?.x), coordinate(point?.y), scale])
  }
}

// MARK: - The objects of a PDF file

/// A PDF value, kept close to how it is written so that what isn't changed is written back the same.
enum WrittenPDFValue: Equatable {
  case null
  case boolean(Bool)
  /// A number as written.
  case number(String)
  /// A name, without its slash, as written (escapes included).
  case name(String)
  /// A string, literal or hexadecimal, exactly as written, delimiters included.
  case string(Data)
  case array([WrittenPDFValue])
  case dictionary(WrittenPDFDictionary)
  case reference(Int, Int)

  var serialized: Data {
    switch self {
    case .null: Data("null".utf8)
    case .boolean(let value): Data((value ? "true" : "false").utf8)
    case .number(let value): Data(value.utf8)
    case .name(let value): Data(("/" + value).utf8)
    case .string(let raw): raw
    case .array(let values):
      values.reduce(into: Data("[".utf8)) { $0 += Data(" ".utf8) + $1.serialized } + Data(" ]".utf8)
    case .dictionary(let dictionary): dictionary.serialized
    case .reference(let number, let generation): Data("\(number) \(generation) R".utf8)
    }
  }
}

/// A PDF dictionary whose keys keep their order.
struct WrittenPDFDictionary: Equatable {
  private(set) var entries: [(key: String, value: WrittenPDFValue)] = []

  static func == (lhs: WrittenPDFDictionary, rhs: WrittenPDFDictionary) -> Bool {
    lhs.entries.map(\.key) == rhs.entries.map(\.key) && lhs.entries.map(\.value) == rhs.entries.map(\.value)
  }

  subscript(key: String) -> WrittenPDFValue? {
    get { entries.first { $0.key == key }?.value }
    set {
      if let index = entries.firstIndex(where: { $0.key == key }) {
        if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
      } else if let newValue {
        entries.append((key, newValue))
      }
    }
  }

  mutating func remove(_ key: String) { self[key] = nil }

  var serialized: Data {
    var data = Data("<<".utf8)
    for (key, value) in entries {
      data += Data(" /\(key) ".utf8) + value.serialized
    }
    return data + Data(" >>".utf8)
  }
}

/// A PDF file read through its cross-reference table, with the objects an update replaces or adds.
///
/// Not text editing's `PDFFile`, which reads one page into decoded values: rewriting a link or the
/// catalog of an encrypted file needs every value it leaves alone written back byte for byte, in order.
struct WrittenPDF {
  private let bytes: [UInt8]
  private var offsets: [Int: Int] = [:]
  private let trailer: WrittenPDFDictionary
  private let previousStart: Int
  private var size: Int
  private var changed: [(number: Int, generation: Int, value: WrittenPDFValue)] = []

  var root: WrittenPDFValue { trailer["Root"] ?? .null }
  var isEncrypted: Bool { trailer["Encrypt"] != nil }
  private(set) var pageReferences: [WrittenPDFValue] = []

  init?(data: Data) {
    bytes = [UInt8](data)
    guard let start = WrittenPDF.startOfCrossReference(bytes), start < bytes.count else { return nil }
    previousStart = start
    var reader = WrittenPDFReader(bytes: bytes, position: start)
    // Every section, newest first, following /Prev; the newest entry for an object wins.
    var section: Int? = start
    var newest: WrittenPDFDictionary?
    var visited: Set<Int> = []
    while let at = section, !visited.contains(at) {
      visited.insert(at)
      reader.position = at
      guard reader.keyword() == "xref", let entries = reader.crossReferenceEntries(),
        reader.keyword() == "trailer", case .dictionary(let dictionary)? = reader.value()
      else { return nil }
      for (number, offset) in entries where offsets[number] == nil { offsets[number] = offset }
      if newest == nil { newest = dictionary }
      if case .number(let previous)? = dictionary["Prev"], let value = Int(previous) {
        section = value
      } else {
        section = nil
      }
    }
    guard let newest, case .number(let total)? = newest["Size"], let count = Int(total) else { return nil }
    trailer = newest
    size = count
    pageReferences = pages(from: dictionary(root)?["Pages"], depth: 0)
    guard !pageReferences.isEmpty else { return nil }
  }

  /// The byte offset `startxref` gives, read from the end of the file.
  private static func startOfCrossReference(_ bytes: [UInt8]) -> Int? {
    let tail = String(decoding: bytes.suffix(1024), as: UTF8.self)
    guard let range = tail.range(of: "startxref", options: .backwards) else { return nil }
    let digits = tail[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber }
    return Int(digits)
  }

  private func pages(from node: WrittenPDFValue?, depth: Int) -> [WrittenPDFValue] {
    guard depth < 64, let node, let dictionary = dictionary(node) else { return [] }
    if dictionary["Type"] == .name("Page") { return [node] }
    guard let kids = array(dictionary["Kids"]) else { return [] }
    return kids.flatMap { pages(from: $0, depth: depth + 1) }
  }

  /// The object a value stands for: the value itself, or what its reference points to.
  func resolve(_ value: WrittenPDFValue?) -> WrittenPDFValue? {
    guard case .reference(let number, _)? = value else { return value }
    if let latest = changed.last(where: { $0.number == number }) { return latest.value }
    guard let offset = offsets[number], offset < bytes.count else { return nil }
    var reader = WrittenPDFReader(bytes: bytes, position: offset)
    guard reader.objectHeader() == number else { return nil }
    return reader.value()
  }

  func dictionary(_ value: WrittenPDFValue?) -> WrittenPDFDictionary? {
    guard case .dictionary(let dictionary)? = resolve(value) else { return nil }
    return dictionary
  }

  func array(_ value: WrittenPDFValue?) -> [WrittenPDFValue]? {
    guard case .array(let values)? = resolve(value) else { return nil }
    return values
  }

  func rect(_ value: WrittenPDFValue?) -> CGRect? {
    guard let values = array(value), values.count == 4 else { return nil }
    let numbers = values.compactMap { value -> Double? in
      guard case .number(let text) = value else { return nil }
      return Double(text)
    }
    guard numbers.count == 4 else { return nil }
    return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
      .standardized
  }

  mutating func replace(_ number: Int, _ generation: Int, with value: WrittenPDFValue) {
    changed.removeAll { $0.number == number }
    changed.append((number, generation, value))
  }

  private mutating func add(_ value: WrittenPDFValue) -> WrittenPDFValue {
    let number = size
    size += 1
    changed.append((number, 0, value))
    return .reference(number, 0)
  }

  /// Writes an outline's objects and returns a reference to its root.
  ///
  /// An item goes to its page, at its point and zoom, or else opens its web address (#356), whose
  /// string is encrypted like the titles.
  mutating func addOutline(
    _ items: [PDFStructureRepair.OutlineItem], security: PDFStandardSecurity?,
    destination: (WrittenPDFValue, CGPoint?, CGFloat?) -> WrittenPDFValue
  ) -> WrittenPDFValue? {
    var failed = false
    // Numbers first, so every item can point to its parent and its neighbours.
    let rootNumber = size
    size += 1
    var dictionaries: [(Int, WrittenPDFDictionary)] = []
    func visibleCount(_ items: [PDFStructureRepair.OutlineItem]) -> Int {
      items.reduce(0) { $0 + 1 + ($1.isOpen ? visibleCount($1.children) : 0) }
    }
    func place(_ items: [PDFStructureRepair.OutlineItem], parent: Int) -> (first: Int, last: Int)? {
      let numbers = items.map { _ -> Int in
        size += 1
        return size - 1
      }
      for (index, item) in items.enumerated() {
        var dictionary = WrittenPDFDictionary()
        if let security {
          guard let sealed = security.encrypt(WrittenPDF.textBytes(item.title), object: numbers[index], generation: 0)
          else {
            failed = true
            continue
          }
          dictionary["Title"] = .string(WrittenPDF.hex(sealed))
        } else {
          dictionary["Title"] = .string(WrittenPDF.textString(item.title))
        }
        dictionary["Parent"] = .reference(parent, 0)
        if index > 0 { dictionary["Prev"] = .reference(numbers[index - 1], 0) }
        if index < items.count - 1 { dictionary["Next"] = .reference(numbers[index + 1], 0) }
        if let target = item.target, let page = pageReferences[safe: target] {
          dictionary["Dest"] = destination(page, item.point, item.zoom)
        } else if let url = item.url {
          // A URI is ASCII (ISO 32000-1, 12.6.4.7); written in hexadecimal, it needs no escaping.
          let address = Array(url.absoluteString.utf8)
          var uri = WrittenPDFDictionary()
          uri["S"] = .name("URI")
          if let security {
            guard let sealed = security.encrypt(address, object: numbers[index], generation: 0) else {
              failed = true
              continue
            }
            uri["URI"] = .string(WrittenPDF.hex(sealed))
          } else {
            uri["URI"] = .string(WrittenPDF.hex(address))
          }
          dictionary["A"] = .dictionary(uri)
        }
        if let children = place(item.children, parent: numbers[index]) {
          dictionary["First"] = .reference(children.first, 0)
          dictionary["Last"] = .reference(children.last, 0)
          let count = visibleCount(item.children)
          dictionary["Count"] = .number(String(item.isOpen ? count : -count))
        }
        dictionaries.append((numbers[index], dictionary))
      }
      guard let first = numbers.first, let last = numbers.last else { return nil }
      return (first, last)
    }
    var root = WrittenPDFDictionary()
    root["Type"] = .name("Outlines")
    if let top = place(items, parent: rootNumber) {
      root["First"] = .reference(top.first, 0)
      root["Last"] = .reference(top.last, 0)
      root["Count"] = .number(String(visibleCount(items)))
    }
    guard !failed else { return nil }
    changed.append((rootNumber, 0, .dictionary(root)))
    for (number, dictionary) in dictionaries { changed.append((number, 0, .dictionary(dictionary))) }
    return .reference(rootNumber, 0)
  }

  /// A text string's bytes: ASCII as it is, anything else as UTF-16 with a byte order mark.
  static func textBytes(_ text: String) -> [UInt8] {
    if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) { return Array(text.utf8) }
    return [0xFE, 0xFF] + Array(text.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
  }

  /// A hexadecimal string token for bytes.
  static func hex(_ bytes: [UInt8]) -> Data {
    Data(("<" + bytes.map { String(format: "%02X", $0) }.joined() + ">").utf8)
  }

  /// The bytes of a string token, literal or hexadecimal, as written.
  static func stringBytes(_ token: Data) -> [UInt8]? {
    let raw = [UInt8](token)
    guard let first = raw.first else { return nil }
    if first == UInt8(ascii: "<") {
      let digits = raw.dropFirst().filter { WrittenPDFReader.hexValue($0) != nil }
      var bytes: [UInt8] = []
      var index = digits.startIndex
      while index < digits.endIndex {
        let high = WrittenPDFReader.hexValue(digits[index]) ?? 0
        let next = digits.index(after: index)
        let low = next < digits.endIndex ? WrittenPDFReader.hexValue(digits[next]) ?? 0 : 0
        bytes.append(high << 4 | low)
        index = next < digits.endIndex ? digits.index(after: next) : next
      }
      return bytes
    }
    guard first == UInt8(ascii: "("), raw.count >= 2 else { return nil }
    var bytes: [UInt8] = []
    var index = 1
    while index < raw.count - 1 {
      let byte = raw[index]
      guard byte == UInt8(ascii: "\\"), index + 1 < raw.count - 1 else {
        bytes.append(byte)
        index += 1
        continue
      }
      let escaped = raw[index + 1]
      index += 2
      switch escaped {
      case UInt8(ascii: "n"): bytes.append(10)
      case UInt8(ascii: "r"): bytes.append(13)
      case UInt8(ascii: "t"): bytes.append(9)
      case UInt8(ascii: "b"): bytes.append(8)
      case UInt8(ascii: "f"): bytes.append(12)
      case 10, 13: break
      case UInt8(ascii: "0")...UInt8(ascii: "7"):
        var value = Int(escaped - UInt8(ascii: "0"))
        var digits = 1
        while digits < 3, index < raw.count - 1, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(raw[index]) {
          value = value * 8 + Int(raw[index] - UInt8(ascii: "0"))
          index += 1
          digits += 1
        }
        bytes.append(UInt8(truncatingIfNeeded: value))
      default: bytes.append(escaped)
      }
    }
    return bytes
  }

  /// The handler that encrypts strings added to this file, when it is one this can write for.
  func standardSecurity(password: String) -> PDFStandardSecurity? {
    guard let encrypt = dictionary(trailer["Encrypt"]), encrypt["Filter"] == .name("Standard"),
      let cipher = stringCipher(encrypt),
      case .string(let ownerToken)? = resolve(encrypt["O"]), let owner = Self.stringBytes(ownerToken),
      case .string(let userToken)? = resolve(encrypt["U"]), let user = Self.stringBytes(userToken),
      case .number(let permissionText)? = resolve(encrypt["P"]), let permissions = Int32(permissionText),
      case .string(let idToken)? = array(trailer["ID"])?.first, let firstID = Self.stringBytes(idToken)
    else { return nil }
    let encryptsMetadata = encrypt["EncryptMetadata"] != .boolean(false)
    return PDFStandardSecurity(
      cipher: cipher, owner: owner, user: user, permissions: permissions, firstID: firstID,
      encryptsMetadata: encryptsMetadata, password: password)
  }

  /// The cipher an `/Encrypt` dictionary uses for strings, when it is one PDFKit writes: RC4 at revision 3
  /// (iOS 27) or AES-128 at revision 4 (macOS).
  private func stringCipher(_ encrypt: WrittenPDFDictionary) -> PDFStandardSecurity.Cipher? {
    switch (encrypt["V"], encrypt["R"]) {
    case (.number("2")?, .number("3")?):
      var bits = 40
      if case .number(let text)? = resolve(encrypt["Length"]) {
        guard let value = Int(text) else { return nil }
        bits = value
      }
      guard (40...128).contains(bits), bits.isMultiple(of: 8) else { return nil }
      return .rc4(keyLength: bits / 8)
    case (.number("4")?, .number("4")?):
      guard encrypt["StrF"] == .name("StdCF"), let filters = dictionary(encrypt["CF"]),
        let standard = dictionary(filters["StdCF"]), standard["CFM"] == .name("AESV2")
      else { return nil }
      return .aes128
    default:
      return nil
    }
  }

  /// A PDF text string: plain where it can be, otherwise UTF-16 with a byte order mark, in hexadecimal.
  static func textString(_ text: String) -> Data {
    if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
      var escaped = ""
      for character in text {
        if character == "(" || character == ")" || character == "\\" { escaped.append("\\") }
        escaped.append(character)
      }
      return Data("(\(escaped))".utf8)
    }
    let hex = ([0xFE, 0xFF] + Array(text.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
      .map { String(format: "%02X", $0) }.joined()
    return Data("<\(hex)>".utf8)
  }

  /// The file with one update appended: the changed and added objects, their cross-reference section
  /// and a trailer that points back to the one before.
  func updated() -> Data {
    var data = Data(bytes)
    if data.last != 0x0A { data.append(0x0A) }
    var written: [(number: Int, generation: Int, offset: Int)] = []
    for (number, generation, value) in changed {
      written.append((number, generation, data.count))
      data += Data("\(number) \(generation) obj\n".utf8) + value.serialized + Data("\nendobj\n".utf8)
    }
    let start = data.count
    data += Data("xref\n".utf8)
    for entry in written.sorted(by: { $0.number < $1.number }) {
      data += Data("\(entry.number) 1\n".utf8)
      data += Data(String(format: "%010ld %05ld n\r\n", entry.offset, entry.generation).utf8)
    }
    var newTrailer = WrittenPDFDictionary()
    newTrailer["Size"] = .number(String(size))
    newTrailer["Root"] = trailer["Root"]
    for key in ["Info", "ID", "Encrypt"] { newTrailer[key] = trailer[key] }
    newTrailer["Prev"] = .number(String(previousStart))
    data += Data("trailer\n".utf8) + newTrailer.serialized + Data("\nstartxref\n\(start)\n%%EOF\n".utf8)
    return data
  }
}

/// Reads PDF tokens and values from bytes.
struct WrittenPDFReader {
  let bytes: [UInt8]
  var position: Int

  private static func isWhitespace(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32].contains(byte) }

  static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
    default: nil
    }
  }
  private static func isDelimiter(_ byte: UInt8) -> Bool { Array("()<>[]{}/%".utf8).contains(byte) }

  private mutating func skipWhitespace() {
    while position < bytes.count {
      if WrittenPDFReader.isWhitespace(bytes[position]) {
        position += 1
      } else if bytes[position] == UInt8(ascii: "%") {
        while position < bytes.count, bytes[position] != 10, bytes[position] != 13 { position += 1 }
      } else {
        return
      }
    }
  }

  /// A run of regular characters: a keyword, a number or a name's body.
  private mutating func regular() -> String {
    let start = position
    while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
      position += 1
    }
    return String(decoding: bytes[start..<position], as: UTF8.self)
  }

  mutating func keyword() -> String {
    skipWhitespace()
    return regular()
  }

  /// `n g obj`, returning n.
  mutating func objectHeader() -> Int? {
    guard let number = Int(keyword()), Int(keyword()) != nil, keyword() == "obj" else { return nil }
    return number
  }

  /// The entries of one cross-reference section: object number and offset of each object in use.
  mutating func crossReferenceEntries() -> [(Int, Int)]? {
    var entries: [(Int, Int)] = []
    while true {
      let mark = position
      let word = keyword()
      guard let first = Int(word) else {
        position = mark
        return entries
      }
      guard let count = Int(keyword()), count >= 0, count < 10_000_000 else { return nil }
      for index in 0..<count {
        guard let offset = Int(keyword()), Int(keyword()) != nil else { return nil }
        let kind = keyword()
        if kind == "n" { entries.append((first + index, offset)) } else if kind != "f" { return nil }
      }
    }
  }

  mutating func value(depth: Int = 0) -> WrittenPDFValue? {
    guard depth < 64 else { return nil }
    skipWhitespace()
    guard position < bytes.count else { return nil }
    switch bytes[position] {
    case UInt8(ascii: "/"):
      position += 1
      return .name(regular())
    case UInt8(ascii: "("):
      return literalString()
    case UInt8(ascii: "<"):
      if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "<") { return dictionary(depth: depth) }
      let start = position
      while position < bytes.count, bytes[position] != UInt8(ascii: ">") { position += 1 }
      position += 1
      return .string(Data(bytes[start..<min(position, bytes.count)]))
    case UInt8(ascii: "["):
      position += 1
      var values: [WrittenPDFValue] = []
      while true {
        skipWhitespace()
        guard position < bytes.count else { return nil }
        if bytes[position] == UInt8(ascii: "]") {
          position += 1
          return .array(values)
        }
        guard let value = value(depth: depth + 1) else { return nil }
        values.append(value)
      }
    default:
      let word = regular()
      switch word {
      case "true": return .boolean(true)
      case "false": return .boolean(false)
      case "null": return .null
      case "": return nil
      default:
        // `n g R` is a reference; a lone number is a number.
        if let number = Int(word) {
          let mark = position
          if let generation = Int(keyword()), keyword() == "R" { return .reference(number, generation) }
          position = mark
        }
        return .number(word)
      }
    }
  }

  private mutating func dictionary(depth: Int) -> WrittenPDFValue? {
    position += 2
    var dictionary = WrittenPDFDictionary()
    while true {
      skipWhitespace()
      guard position + 1 < bytes.count else { return nil }
      if bytes[position] == UInt8(ascii: ">"), bytes[position + 1] == UInt8(ascii: ">") {
        position += 2
        return .dictionary(dictionary)
      }
      guard case .name(let key)? = value(depth: depth + 1), let entry = value(depth: depth + 1) else { return nil }
      dictionary[key] = entry
    }
  }

  private mutating func literalString() -> WrittenPDFValue? {
    let start = position
    var nesting = 0
    while position < bytes.count {
      let byte = bytes[position]
      if byte == UInt8(ascii: "\\") {
        position += 2
        continue
      }
      if byte == UInt8(ascii: "(") { nesting += 1 }
      if byte == UInt8(ascii: ")") {
        nesting -= 1
        if nesting == 0 {
          position += 1
          return .string(Data(bytes[start..<position]))
        }
      }
      position += 1
    }
    return nil
  }
}

extension CGRect {
  /// Whether two rectangles agree to within half a point on every edge.
  fileprivate func isClose(to other: CGRect) -> Bool {
    abs(minX - other.minX) < 0.5 && abs(minY - other.minY) < 0.5 && abs(maxX - other.maxX) < 0.5
      && abs(maxY - other.maxY) < 0.5
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
