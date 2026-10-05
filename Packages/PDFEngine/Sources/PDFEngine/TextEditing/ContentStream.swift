import Foundation

/// One operator of a page's content with its operands, and where it sits in the content bytes.
struct ContentOperation: Equatable {
  /// The operator.
  ///
  /// For example `Tj` or `cm`. An inline image is one operation named `BI`.
  let name: String
  let operands: [PDFObject]
  /// The bytes from the first operand to the end of the operator.
  let range: Range<Int>
}

/// Reads a page's content into operations.
enum ContentStream {
  /// Parses decoded content.
  ///
  /// - Throws: `PDFSyntaxError` when the content is malformed or over `TextEditingLimits`.
  static func parse(_ bytes: [UInt8]) throws -> [ContentOperation] {
    guard bytes.count <= TextEditingLimits.contentBytes else { throw PDFSyntaxError.tooLarge }
    var lexer = PDFLexer(bytes)
    var operations: [ContentOperation] = []
    var operands: [PDFObject] = []
    var start: Int?
    while true {
      let (token, range) = try lexer.next()
      if token == .end { break }
      if start == nil { start = range.lowerBound }
      guard case .keyword(let name) = token else {
        guard operands.count < TextEditingLimits.objects else { throw PDFSyntaxError.tooLarge }
        operands.append(try lexer.object(from: token, references: false, depth: 0))
        continue
      }
      // `true`, `false` and `null` are operands, not operators.
      if name == "true" || name == "false" || name == "null" {
        operands.append(try lexer.object(from: token, references: false, depth: 0))
        continue
      }
      var end = range.upperBound
      if name == "BI" {
        end = try skipInlineImage(&lexer)
        operands = []
      }
      guard operations.count < TextEditingLimits.operators else { throw PDFSyntaxError.tooLarge }
      // Work that was given up on (the time limit in `PDFDocumentController`) stops here.
      if operations.count.isMultiple(of: 512) { try Task.checkCancellation() }
      operations.append(ContentOperation(name: name, operands: operands, range: (start ?? range.lowerBound)..<end))
      operands = []
      start = nil
    }
    // Operands with no operator after them mean the content was cut short.
    guard operands.isEmpty else { throw PDFSyntaxError.malformed }
    return operations
  }

  /// Moves past an inline image's dictionary and data, to just after its `EI`.
  private static func skipInlineImage(_ lexer: inout PDFLexer) throws -> Int {
    while true {
      let (token, _) = try lexer.next()
      if token == .keyword("ID") { break }
      guard token != .end else { throw PDFSyntaxError.malformed }
      if case .keyword = token { continue }
      _ = try lexer.object(from: token, references: false, depth: 0)
    }
    let bytes = lexer.bytes
    // One whitespace byte follows `ID`; the data ends at `EI` between whitespace.
    var index = lexer.position + 1
    while index + 1 < bytes.count {
      if bytes[index] == 0x45, bytes[index + 1] == 0x49, PDFLexer.isWhitespace(bytes[index - 1]),
        index + 2 >= bytes.count || PDFLexer.isWhitespace(bytes[index + 2])
      {
        lexer.position = index + 2
        return index + 2
      }
      index += 1
    }
    throw PDFSyntaxError.malformed
  }
}
