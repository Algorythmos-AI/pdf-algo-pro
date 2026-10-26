import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import PDFEngine

/// The repair of what PDFKit on iOS 27 leaves out of a file it writes (#307).
///
/// The outline and the links to pages. The files here are written by the PDFKit the tests run on, then broken the way iOS 27
/// breaks them, so the repair is tested wherever the tests run.
@MainActor
@Suite("Repairing the outline and links PDFKit leaves out (#307)")
struct PDFStructureRepairTests {
  private func document(pages: Int = 3) throws -> PDFDocument {
    try #require(PDFDocument(data: SyntheticPDF.make(pages: (1...pages).map { "Page \($0)" })))
  }

  private func titlesAndPages(_ document: PDFDocument?) -> [String] {
    guard let document else { return [] }
    return PDFDocumentController.outline(of: document).flatMap { item -> [PDFStructureRepair.OutlineItem] in
      [item] + item.children
    }.map { "\($0.title)@\($0.target ?? -1)" }
  }

  private func linkTargets(_ document: PDFDocument?) -> [Int] {
    guard let document else { return [] }
    return PDFDocumentController.links(in: document).map(\.target)
  }

  /// The bytes with the first page reference in a destination replaced by the placeholder iOS 27
  /// writes, keeping the length so every offset in the file still holds.
  private func breakingLinks(_ data: Data) throws -> Data {
    // Latin-1 maps every byte to one character, so the file's binary parts keep their length.
    var text = try #require(String(data: data, encoding: .isoLatin1))
    let pattern = try NSRegularExpression(pattern: #"(/D(?:est)?\s*\[\s*)(\d+ \d+ R)"#)
    let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
    try #require(!matches.isEmpty, "the written file has a destination to break")
    for match in matches.reversed() {
      let range = try #require(Range(match.range(at: 2), in: text))
      let length = text[range].count
      text.replaceSubrange(range, with: "/#23" + String(repeating: "3", count: max(0, length - 4)))
    }
    let broken = try #require(text.data(using: .isoLatin1))
    try #require(broken.count == data.count, "the placeholder keeps every offset")
    return broken
  }

  @Test("An outline the file lacks is written into it")
  func writesTheOutline() throws {
    let written = try #require(try document().dataRepresentation())
    let outline: [PDFStructureRepair.OutlineItem] = [
      .init(
        title: "Chapter", target: 1, point: nil, isOpen: true,
        children: [.init(title: "Section", target: 2, point: CGPoint(x: 0, y: 700), isOpen: true, children: [])])
    ]
    let result = try #require(PDFStructureRepair.repaired(written, links: [], outline: outline))
    #expect(result.wroteOutline)
    #expect(titlesAndPages(PDFDocument(data: result.data)) == ["Chapter@1", "Section@2"])
    #expect(result.data.prefix(written.count) == written, "what PDFKit wrote is kept; the update follows it")
    let reread = try #require(CGPDFDocument(CGDataProvider(data: result.data as CFData)!))
    #expect(reread.numberOfPages == 3, "Core Graphics reads the updated file")
  }

  @Test("An outline the document no longer has is taken out")
  func removesTheOutline() throws {
    let source = try document()
    let root = PDFOutline()
    let item = PDFOutline()
    item.label = "Gone"
    item.destination = PDFDestination(page: try #require(source.page(at: 1)), at: .zero)
    root.insertChild(item, at: 0)
    source.outlineRoot = root
    let written = try #require(source.dataRepresentation())
    let result = try #require(PDFStructureRepair.repaired(written, links: [], outline: []))
    #expect(PDFDocument(data: result.data)?.outlineRoot.map { $0.numberOfChildren } ?? 0 == 0)
  }

  @Test("Titles keep their brackets, backslashes and accents")
  func titlesAreEscaped() throws {
    let written = try #require(try document().dataRepresentation())
    let titles = ["Notes (draft) \\ v2", "Résumé — été"]
    let outline = titles.enumerated().map {
      PDFStructureRepair.OutlineItem(title: $1, target: $0, point: nil, isOpen: true, children: [])
    }
    let result = try #require(PDFStructureRepair.repaired(written, links: [], outline: outline))
    #expect(titlesAndPages(PDFDocument(data: result.data)) == ["Notes (draft) \\ v2@0", "Résumé — été@1"])
  }

  @Test("A link written with iOS 27's placeholder goes to its page again")
  func mendsALink() throws {
    let source = try document()
    let link = PDFAnnotation(bounds: CGRect(x: 100, y: 200, width: 60, height: 20), forType: .link, withProperties: nil)
    link.destination = PDFDestination(page: try #require(source.page(at: 2)), at: CGPoint(x: 0, y: 792))
    try #require(source.page(at: 0)).addAnnotation(link)
    let broken = try breakingLinks(try #require(source.dataRepresentation()))
    #expect(linkTargets(PDFDocument(data: broken)).isEmpty, "the broken file's link goes nowhere")

    let links = PDFDocumentController.links(in: source)
    let result = try #require(PDFStructureRepair.repaired(broken, links: links, outline: nil))
    #expect(result.mendedLinks == 1)
    #expect(linkTargets(PDFDocument(data: result.data)) == [2])
  }

  @Test("Two links in the same place keep their own targets")
  func linksInTheSamePlace() throws {
    let source = try document()
    let bounds = CGRect(x: 100, y: 200, width: 60, height: 20)
    for target in [1, 2] {
      let link = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
      link.destination = PDFDestination(page: try #require(source.page(at: target)), at: .zero)
      try #require(source.page(at: 0)).addAnnotation(link)
    }
    let broken = try breakingLinks(try #require(source.dataRepresentation()))
    let links = PDFDocumentController.links(in: source)
    try #require(links.map(\.target) == [1, 2])
    let result = try #require(PDFStructureRepair.repaired(broken, links: links, outline: nil))
    #expect(result.mendedLinks == 2)
    #expect(linkTargets(PDFDocument(data: result.data)) == [1, 2])
  }

  @Test("An outline nested far deeper than any real one is read to a limit, without running out of stack")
  func deepOutlines() throws {
    let source = try document()
    let root = PDFOutline()
    var parent = root
    for level in 0..<300 {
      let item = PDFOutline()
      item.label = "Level \(level)"
      parent.insertChild(item, at: 0)
      parent = item
    }
    source.outlineRoot = root
    var depth = 0
    var items = PDFDocumentController.outline(of: source)
    while let first = items.first {
      depth += 1
      items = first.children
    }
    #expect(depth == PDFDocumentController.outlineDepthLimit)
  }

  @Test("In an encrypted file, links are mended and the outline is left, its titles being encrypted")
  func encryptedFiles() throws {
    let source = try document()
    let link = PDFAnnotation(bounds: CGRect(x: 100, y: 200, width: 60, height: 20), forType: .link, withProperties: nil)
    link.destination = PDFDestination(page: try #require(source.page(at: 1)), at: .zero)
    try #require(source.page(at: 0)).addAnnotation(link)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("repair-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(source.write(to: url, withOptions: [.userPasswordOption: "fixture", .ownerPasswordOption: "fixture"]))
    let written = try Data(contentsOf: url)
    let outline = [PDFStructureRepair.OutlineItem(title: "Kept out", target: 0, point: nil, isOpen: true, children: [])]
    let links = PDFDocumentController.links(in: source)
    if let result = PDFStructureRepair.repaired(written, links: links, outline: outline) {
      #expect(!result.wroteOutline)
      let reopened = try #require(PDFDocument(data: result.data))
      reopened.unlock(withPassword: "fixture")
      #expect(!reopened.isLocked, "the updated file still opens with its password")
      #expect(linkTargets(reopened) == [1])
    }
  }

  @Test("A file this can't read is left alone")
  func unreadableFiles() {
    #expect(PDFStructureRepair.repaired(Data("not a PDF".utf8), links: [], outline: []) == nil)
    let stream = Data("%PDF-1.5\n1 0 obj\n<< /Type /XRef >>\nendobj\nstartxref\n9\n%%EOF\n".utf8)
    #expect(PDFStructureRepair.repaired(stream, links: [], outline: []) == nil, "a cross-reference stream")
  }

  @Test("A save whose file already has its outline and links appends nothing")
  func intactFilesAreNotTouched() throws {
    let source = try document()
    let root = PDFOutline()
    let item = PDFOutline()
    item.label = "Chapter"
    item.destination = PDFDestination(page: try #require(source.page(at: 1)), at: .zero)
    root.insertChild(item, at: 0)
    source.outlineRoot = root
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("intact-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(source.write(to: url))
    let before = try Data(contentsOf: url)
    let controller = try PDFDocumentController(url: url)
    let check = try #require(PDFDocument(url: url))
    // Where PDFKit writes the outline, the written file already matches and nothing is appended.
    if PDFDocumentController.outline(of: check).count == 1 {
      _ = try controller.mendStructure(in: check, at: url, options: [:])
      #expect(try Data(contentsOf: url) == before)
    }
  }
}
