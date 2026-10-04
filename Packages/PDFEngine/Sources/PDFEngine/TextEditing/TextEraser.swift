import Foundation

/// Removes regions' text from a page's content without changing anything else the content does.
///
/// A showing operator has two effects: it paints glyphs and it moves the pen. Erasing keeps the
/// second whenever a later operator relies on it, so every operator after the erased text sees the
/// same state as before and paints exactly where it did.
enum TextEraser {
  /// The content with the regions' showing operators removed.
  ///
  /// - Parameters:
  ///   - regions: The regions to erase.
  ///   - content: The page's interpreted content.
  ///   - bytes: The decoded content the operations' ranges refer to.
  /// - Returns: The new content.
  /// - Throws: `PDFSyntaxError.unsupported` when an advance that must be kept cannot be written.
  static func erasing(_ regions: [TextRegion], in content: PageContent, bytes: [UInt8]) throws -> [UInt8] {
    let erased = Set(regions.flatMap(\.runs))
    var replacements: [(range: Range<Int>, text: String)] = []
    for index in erased.sorted() {
      let run = content.runs[index]
      let operation = content.operations[run.operation]
      var parts: [String] = []
      switch operation.name {
      case "'":
        parts.append("T*")
      case "\"":
        let numbers = operation.operands.compactMap(\.number)
        guard numbers.count >= 2 else { throw PDFSyntaxError.malformed }
        parts.append("\(number(numbers[0])) Tw \(number(numbers[1])) Tc T*")
      default:
        break
      }
      // The run after this one starts at this one's end; unless it is erased too, the pen must
      // still get there.
      if run.hasDependents, !erased.contains(index + 1) {
        let unit = run.fontSize * run.horizontalScale
        guard let advance = run.advance, unit.isFinite, abs(unit) > 1e-9 else { throw PDFSyntaxError.unsupported }
        parts.append("[\(number(-advance * 1000 / unit))] TJ")
      }
      replacements.append((operation.range, parts.joined(separator: " ")))
    }
    // A replacement-text span whose text is all gone would still read as its replacement text.
    for (spanIndex, span) in content.spans.enumerated() {
      let inside = content.runs.indices.filter { content.runs[$0].span == spanIndex }
      guard !inside.isEmpty, inside.allSatisfy(erased.contains), let end = span.end else { continue }
      replacements.append((content.operations[span.begin].range, ""))
      replacements.append((content.operations[end].range, ""))
    }

    replacements.sort { $0.range.lowerBound < $1.range.lowerBound }
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count)
    var position = 0
    for replacement in replacements {
      guard replacement.range.lowerBound >= position, replacement.range.upperBound <= bytes.count else {
        throw PDFSyntaxError.malformed
      }
      output.append(contentsOf: bytes[position..<replacement.range.lowerBound])
      output.append(contentsOf: Array(replacement.text.utf8))
      position = replacement.range.upperBound
    }
    output.append(contentsOf: bytes[position...])
    return output
  }

  /// A number as PDF syntax: plain decimals, never an exponent.
  static func number(_ value: Double) -> String {
    let rounded = (value * 10_000).rounded() / 10_000
    if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
    return String(rounded)
  }
}
