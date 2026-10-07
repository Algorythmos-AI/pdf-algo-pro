import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

/// How one line's edit ended.
enum LineEnding: String, CaseIterable {
  /// The words were changed in the page, and proven.
  case edited
  /// The words could not be changed in the page, and can be covered: said before typing, or done
  /// after Done.
  case covered
  /// The new words do not fit; the editor says so and keeps what was typed.
  case tooLong
  /// The words can be neither changed nor covered. The editor says so and offers only Close.
  case closeOnly
  /// Anything else: typing that goes nowhere. There must be none.
  case deadEnd
}

/// Tries a small change to every line of a page and counts how each ends.
enum LineSweep {
  /// A replacement for a line that uses only its own characters and is about as wide: two
  /// neighbouring characters of its longest word change places.
  static func replacement(for text: String) -> String {
    let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard let index = words.indices.max(by: { words[$0].count < words[$1].count }), words[index].count >= 2 else {
      return text + text
    }
    var characters = Array(words[index])
    // The first pair of different characters; a word of one repeated character is doubled instead.
    guard let pair = characters.indices.dropLast().first(where: { characters[$0] != characters[$0 + 1] }) else {
      return text + text
    }
    characters.swapAt(pair, pair + 1)
    var changed = words
    changed[index] = String(characters)
    return changed.joined(separator: " ")
  }

  /// How an edit to one line ends, by the same rules the reader follows.
  static func ending(
    of region: EditableTextRegion, on snapshot: Data, with editor: ContentStreamTextEditor
  ) async -> (ending: LineEnding, detail: String) {
    guard region.capability.editsContent else {
      return (region.isUpright ? .covered : .closeOnly, "cover only")
    }
    let edit = TextEdit(region: region, replacement: replacement(for: region.text))
    let result = await editor.applying([edit], toPage: snapshot)
    switch result.outcomes.first {
    case .edited: return (.edited, "")
    case .tooLong: return (.tooLong, "")
    case .refused(let refusal) where refusal.meansNotEditableInPlace:
      let proof = result.proofFailure.map { " \($0.check.rawValue) \($0.measured)/\($0.expected)" } ?? ""
      return (region.isUpright ? .covered : .closeOnly, "\(refusal.rawValue)\(proof)")
    case .refused(let refusal): return (.deadEnd, refusal.rawValue)
    case nil: return (.deadEnd, "no outcome")
    }
  }

  /// How every line of a page ends, several lines at a time.
  ///
  /// - Returns: How many lines ended each way, and how many for each reason given.
  static func endings(
    onPage snapshot: Data
  ) async -> (counts: [LineEnding: Int], details: [String: Int], kind: PageTextKind) {
    let editor = ContentStreamTextEditor()
    let text = await editor.text(ofPage: snapshot)
    var counts: [LineEnding: Int] = [:]
    var details: [String: Int] = [:]
    await withTaskGroup(of: (LineEnding, String).self) { group in
      var waiting = text.regions[...]
      var running = 0
      // A proof draws the page three times, so only a few are made at once: more than that
      // starved the suite's timed tests on a slow machine (CI, 2026-10-07).
      while running > 0 || !waiting.isEmpty {
        while running < 3, let region = waiting.popFirst() {
          group.addTask { await ending(of: region, on: snapshot, with: editor) }
          running += 1
        }
        guard let (ending, detail) = await group.next() else { break }
        running -= 1
        counts[ending, default: 0] += 1
        if !detail.isEmpty { details["\(ending.rawValue): \(detail)", default: 0] += 1 }
      }
    }
    return (counts, details, text.kind)
  }
}

@MainActor
@Suite("Text editing: the guarantee")
struct TextEditingGuaranteeTests {
  @Test("The replacement used for sweeping keeps a line's characters and changes its words")
  func replacement() {
    #expect(LineSweep.replacement(for: "Customer: John Smith") == "uCstomer: John Smith")
    #expect(LineSweep.replacement(for: "$950.00") == "9$50.00")
    #expect(LineSweep.replacement(for: "aa") == "aaaa")
    #expect(LineSweep.replacement(for: "x") == "xx")
  }

  @Test("A line with ligatures is offered in letters and edited like any other")
  func ligatures() async throws {
    // Core Text draws "fi", "fl" and "ffi" in this face as single glyphs, and the font names each
    // as one character. The editor showed that character, and the independent reader's plain
    // letters then failed the proof, so every such line was covered instead of edited.
    let data = try TextEditFixtures.make(pages: [
      [TextEditFixtures.Line("The first office file is final", font: "Helvetica", size: 12, at: CGPoint(x: 72, y: 700))]
    ])
    let snapshot = try TextEditFixtures.singlePage(data)
    let editor = ContentStreamTextEditor()
    let region = try #require(await editor.text(ofPage: snapshot).regions.first)
    #expect(region.text == "The first office file is final", "Letters, not ligature characters")
    #expect(TextRegionBuilder.spelledOut("\u{FB01}rst o\u{FB03}ce \u{FB02}oor") == "first office floor")
    #expect(EditProof.squeezed("\u{FB01}nal  \u{FB02}ag") == "finalflag")
    let result = await editor.applying(
      [TextEdit(region: region, replacement: "The first office flyer is finished")], toPage: snapshot)
    #expect(result.outcomes.first?.isEdited == true, "\(String(describing: result.proofFailure))")
    let read = PDFDocument(data: try #require(result.page))?.page(at: 0)?.string ?? ""
    #expect(read.contains("first office flyer is finished"), "Other readers find the words as typed")
  }

  @Test("The corpus has every kind of document, each with text")
  func corpus() throws {
    let documents = try TextEditCorpus.documents()
    #expect(documents.count == TextEditCorpus.count && Set(documents.map(\.name)).count == documents.count)
  }

  // One test per document, so that a slow machine times out one page's worth of work, not the
  // whole corpus; and one document at a time, so that the corpus does not crowd out the rest of
  // the suite.
  @Test(
    "On every line of every kind of document, an edit ends as changed words", .serialized,
    .timeLimit(.minutes(10)), arguments: 0..<TextEditCorpus.count)
  func noDeadEnds(_ index: Int) async throws {
    let document = try TextEditCorpus.documents()[index]
    let pdf = try #require(PDFDocument(data: document.data), "\(document.name)")
    var counts: [LineEnding: Int] = [:]
    var details: [String: Int] = [:]
    for pageIndex in 0..<pdf.pageCount {
      let snapshot = try TextEditFixtures.singlePage(document.data, pageIndex: pageIndex)
      let page = await LineSweep.endings(onPage: snapshot)
      #expect(page.kind == .text && !page.counts.isEmpty, "\(document.name), page \(pageIndex): no text found")
      counts.merge(page.counts, uniquingKeysWith: +)
      details.merge(page.details, uniquingKeysWith: +)
    }
    let row = LineEnding.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", ")
    print("CORPUS \(document.name): \(row)\(details.isEmpty ? "" : " \(details.sorted { $0.key < $1.key })")")
    // The guarantee: nobody types and gets nothing.
    #expect(counts[.deadEnd] == nil, "\(document.name): typing that goes nowhere \(details)")
    // And more than the guarantee: every line of the corpus is one the engine can really edit. A
    // line that has to be covered, or cannot be, is a regression in the engine or a new kind of
    // page that needs a look.
    #expect(
      counts[.covered] == nil && counts[.closeOnly] == nil && counts[.tooLong] == nil, "\(document.name): \(details)")
    #expect((counts[.edited] ?? 0) >= 2)
  }
}
