import Compression
import Foundation

/// The object structure of a one-page PDF written by Core Graphics, read from bytes.
///
/// Text editing never parses a file from the wild. PDFKit first writes the page being edited into a
/// one-page document, and PDFKit writes with Core Graphics, which always produces a classic
/// cross-reference table, no object streams, and Flate or unfiltered streams (spike results in
/// `docs/pdf-text-editing-architecture.md`). Anything else is refused as `unsupported`, so the page
/// is simply not editable.
struct PDFFile {
  /// A stream object: its dictionary and its decoded bytes.
  struct Stream {
    let dictionary: [String: PDFObject]
    let data: [UInt8]
  }

  /// The one page of the file.
  struct Page {
    /// The page object's number.
    let number: Int
    let dictionary: [String: PDFObject]
    /// The object numbers of the content streams, in order.
    let contents: [Int]
    /// The page's resources, with inheritance applied.
    let resources: [String: PDFObject]
    /// The media box, with inheritance applied.
    let mediaBox: CGRect
  }

  let bytes: [UInt8]
  /// Where each object starts, newest update first.
  private let offsets: [Int: Int]
  private let trailer: [String: PDFObject]
  /// Where the newest cross-reference section starts.
  private let lastCrossReference: Int
  /// The trailer's `/Size`: one more than the highest object number.
  private let size: Int

  init(_ data: Data) throws {
    guard data.count <= TextEditingLimits.contentBytes * 4 else { throw PDFSyntaxError.tooLarge }
    bytes = [UInt8](data)
    lastCrossReference = try Self.startOfCrossReference(in: bytes)
    var offsets: [Int: Int] = [:]
    var newestTrailer: [String: PDFObject]?
    var next: Int? = lastCrossReference
    var seen: Set<Int> = []
    while let start = next {
      guard seen.insert(start).inserted, seen.count <= TextEditingLimits.updates else {
        throw PDFSyntaxError.malformed
      }
      let section = try Self.readSection(in: bytes, at: start)
      // The newest section is read first and wins.
      offsets.merge(section.offsets) { newest, _ in newest }
      if newestTrailer == nil { newestTrailer = section.trailer }
      next = section.trailer["Prev"]?.integer
    }
    guard let newestTrailer, let size = newestTrailer["Size"]?.integer, size > 0, size <= TextEditingLimits.objects
    else { throw PDFSyntaxError.malformed }
    self.offsets = offsets
    trailer = newestTrailer
    self.size = size
  }

  // MARK: - Cross-reference table

  private static func startOfCrossReference(in bytes: [UInt8]) throws -> Int {
    let marker = Array("startxref".utf8)
    let tail = max(0, bytes.count - 2048)
    var index = bytes.count - marker.count
    while index >= tail {
      if bytes[index] == marker[0], Array(bytes[index..<(index + marker.count)]) == marker {
        var lexer = PDFLexer(bytes, at: index + marker.count)
        guard case .integer(let offset) = try lexer.next().token, offset > 0, offset < bytes.count else {
          throw PDFSyntaxError.malformed
        }
        return offset
      }
      index -= 1
    }
    throw PDFSyntaxError.malformed
  }

  private static func readSection(
    in bytes: [UInt8], at start: Int
  ) throws -> (offsets: [Int: Int], trailer: [String: PDFObject]) {
    guard start >= 0, start < bytes.count else { throw PDFSyntaxError.malformed }
    var lexer = PDFLexer(bytes, at: start)
    // A cross-reference stream starts with an object header here instead; Core Graphics never
    // writes one.
    guard try lexer.next().token == .keyword("xref") else { throw PDFSyntaxError.unsupported }
    var offsets: [Int: Int] = [:]
    while true {
      let (token, _) = try lexer.next()
      if token == .keyword("trailer") { break }
      guard case .integer(let first) = token, case .integer(let count) = try lexer.next().token, first >= 0,
        count >= 0, count <= TextEditingLimits.objects, first <= TextEditingLimits.objects
      else { throw PDFSyntaxError.malformed }
      for index in 0..<count {
        guard case .integer(let offset) = try lexer.next().token, case .integer = try lexer.next().token,
          case .keyword(let kind) = try lexer.next().token
        else { throw PDFSyntaxError.malformed }
        if kind == "n", offset > 0, offset < bytes.count { offsets[first + index] = offset }
      }
    }
    guard let trailer = try lexer.object(references: true).dictionary else { throw PDFSyntaxError.malformed }
    return (offsets, trailer)
  }

  // MARK: - Objects

  /// The object with a number, with a stream's bytes left unread.
  func object(_ number: Int) throws -> PDFObject {
    var lexer = try lexer(atObject: number)
    return try lexer.object(references: true)
  }

  /// Follows a reference; any other object is returned as it is.
  func resolve(_ object: PDFObject?, depth: Int = 0) throws -> PDFObject {
    guard let object else { return .null }
    guard case .reference(let number) = object else { return object }
    guard depth < TextEditingLimits.depth else { throw PDFSyntaxError.tooLarge }
    guard offsets[number] != nil else { return .null }
    return try resolve(try self.object(number), depth: depth + 1)
  }

  /// A dictionary that may be given directly or by reference.
  func dictionary(_ object: PDFObject?) throws -> [String: PDFObject]? {
    try resolve(object).dictionary
  }

  /// The stream object with a number, decoded.
  func stream(_ number: Int) throws -> Stream {
    var lexer = try lexer(atObject: number)
    guard let dictionary = try lexer.object(references: true).dictionary,
      try lexer.next().token == .keyword("stream")
    else { throw PDFSyntaxError.malformed }
    var start = lexer.position
    // The keyword is followed by a line feed, or a carriage return and a line feed.
    if start < bytes.count, bytes[start] == 13 { start += 1 }
    if start < bytes.count, bytes[start] == 10 { start += 1 }
    guard let length = try resolve(dictionary["Length"]).integer, length >= 0,
      case (let end, let overflow) = start.addingReportingOverflow(length), !overflow, end <= bytes.count
    else { throw PDFSyntaxError.malformed }
    var after = PDFLexer(bytes, at: end)
    guard try after.next().token == .keyword("endstream") else { throw PDFSyntaxError.malformed }
    let raw = Array(bytes[start..<end])
    switch try filter(of: dictionary) {
    case .none: return Stream(dictionary: dictionary, data: raw)
    case .flate: return Stream(dictionary: dictionary, data: try Self.inflate(raw))
    }
  }

  private enum Filter { case none, flate }

  private func filter(of dictionary: [String: PDFObject]) throws -> Filter {
    let parameters = try resolve(dictionary["DecodeParms"])
    guard parameters == .null else { throw PDFSyntaxError.unsupported }
    switch try resolve(dictionary["Filter"]) {
    case .null: return .none
    case .name("FlateDecode"): return .flate
    case .array(let filters):
      if filters.isEmpty { return .none }
      guard filters.count == 1, try resolve(filters[0]) == .name("FlateDecode") else {
        throw PDFSyntaxError.unsupported
      }
      return .flate
    default: throw PDFSyntaxError.unsupported
    }
  }

  private func lexer(atObject number: Int) throws -> PDFLexer {
    guard let offset = offsets[number] else { throw PDFSyntaxError.malformed }
    var lexer = PDFLexer(bytes, at: offset)
    guard case .integer(number) = try lexer.next().token, case .integer = try lexer.next().token,
      try lexer.next().token == .keyword("obj")
    else { throw PDFSyntaxError.malformed }
    return lexer
  }

  /// Inflates zlib data, stopping at the content limit so a small stream cannot expand without bound.
  static func inflate(_ input: [UInt8]) throws -> [UInt8] {
    // Two bytes of zlib header come before the deflate data that `Compression` reads.
    guard input.count > 2 else { throw PDFSyntaxError.malformed }
    var position = 2
    var output: [UInt8] = []
    do {
      let filter = try InputFilter<Data>(.decompress, using: .zlib) { length in
        guard position < input.count else { return nil }
        let end = min(input.count, position + max(1, length))
        defer { position = end }
        return Data(input[position..<end])
      }
      while let chunk = try filter.readData(ofLength: 65_536), !chunk.isEmpty {
        output.append(contentsOf: chunk)
        guard output.count <= TextEditingLimits.contentBytes else { throw PDFSyntaxError.tooLarge }
      }
    } catch let error as PDFSyntaxError {
      throw error
    } catch {
      throw PDFSyntaxError.malformed
    }
    return output
  }

  // MARK: - The page

  /// The file's first page, following the page tree from the catalog.
  func firstPage() throws -> Page {
    guard let catalog = try dictionary(trailer["Root"]) else { throw PDFSyntaxError.malformed }
    var node = catalog["Pages"]
    var resources: [String: PDFObject]?
    var mediaBox: CGRect?
    for _ in 0..<TextEditingLimits.depth {
      guard case .reference(let number) = node, let dictionary = try dictionary(node) else {
        throw PDFSyntaxError.malformed
      }
      if let own = try self.dictionary(dictionary["Resources"]) { resources = own }
      if let box = try rectangle(dictionary["MediaBox"]) { mediaBox = box }
      if dictionary["Type"] == .name("Page") {
        guard let mediaBox else { throw PDFSyntaxError.malformed }
        return Page(
          number: number, dictionary: dictionary, contents: try contentNumbers(dictionary["Contents"]),
          resources: resources ?? [:], mediaBox: mediaBox)
      }
      guard let kids = try resolve(dictionary["Kids"]).array, let first = kids.first else {
        throw PDFSyntaxError.malformed
      }
      node = first
    }
    throw PDFSyntaxError.tooLarge
  }

  private func contentNumbers(_ contents: PDFObject?) throws -> [Int] {
    switch contents {
    case .reference(let number):
      // A reference to an array of streams, or to the one stream.
      if let array = try object(number).array { return try contentNumbers(.array(array)) }
      return [number]
    case .array(let items):
      return try items.map {
        guard case .reference(let number) = $0 else { throw PDFSyntaxError.malformed }
        return number
      }
    case nil, .some(.null):
      return []
    default:
      throw PDFSyntaxError.malformed
    }
  }

  /// A rectangle from an array of four numbers, normalised.
  func rectangle(_ object: PDFObject?) throws -> CGRect? {
    guard let values = try resolve(object).array, values.count == 4 else { return nil }
    let numbers = try values.map { try resolve($0).number }
    guard let x0 = numbers[0], let y0 = numbers[1], let x1 = numbers[2], let y1 = numbers[3] else { return nil }
    return CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
  }

  // MARK: - Writing

  /// The file with a page's content replaced, as an incremental update: the original bytes are kept
  /// and new versions of the content streams are appended.
  ///
  /// The new content goes into the first content stream; any others become empty, so the page
  /// object itself is never rewritten.
  func replacingContent(of page: Page, with content: [UInt8]) throws -> Data {
    guard let first = page.contents.first else { throw PDFSyntaxError.unsupported }
    var output = Data(bytes)
    if output.last != 10 { output.append(10) }
    var written: [(number: Int, offset: Int)] = []
    for number in page.contents {
      let body = number == first ? content : []
      written.append((number, output.count))
      output.append(Data("\(number) 0 obj\n<< /Length \(body.count) >>\nstream\n".utf8))
      output.append(contentsOf: body)
      output.append(Data("\nendstream\nendobj\n".utf8))
    }
    let crossReference = output.count
    var table = "xref\n"
    for entry in written.sorted(by: { $0.number < $1.number }) {
      table += "\(entry.number) 1\n\(Self.padded(entry.offset)) 00000 n \n"
    }
    guard case .reference(let root) = trailer["Root"] else { throw PDFSyntaxError.malformed }
    table += "trailer\n<< /Size \(size) /Root \(root) 0 R"
    if case .reference(let info) = trailer["Info"] { table += " /Info \(info) 0 R" }
    table += " /Prev \(lastCrossReference) >>\nstartxref\n\(crossReference)\n%%EOF\n"
    output.append(Data(table.utf8))
    return output
  }

  private static func padded(_ offset: Int) -> String {
    let digits = String(offset)
    return String(repeating: "0", count: max(0, 10 - digits.count)) + digits
  }
}
