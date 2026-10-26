import CoreGraphics
import Foundation
import PDFKit
import os

extension PDFDocumentController {
  /// Reads back the outline and the links to pages the save wrote, and mends them where PDFKit left
  /// them out (#307); returns the document as it is now on disk.
  ///
  /// Only a file that differs from the document is touched, so where PDFKit writes them correctly this
  /// does nothing. A file that still differs after the repair is kept as written: the rest of the
  /// document is saved, as it was before this step existed.
  func mendStructure(
    in check: PDFDocument, at staging: URL, options: [PDFDocumentWriteOption: Any]
  ) throws -> PDFDocument {
    unlock(check, options: options)
    guard !check.isLocked else { return check }
    let links = Self.links(in: document)
    let outline = Self.outline(of: document)
    let linksIntact = Set(links.map(LinkKey.init)).isSubset(of: Self.links(in: check).map(LinkKey.init))
    let outlineIntact = Self.shape(Self.outline(of: check)) == Self.shape(outline)
    guard !linksIntact || !outlineIntact else { return check }
    let key = options[.userPasswordOption] as? String ?? password ?? ""
    guard let written = try? Data(contentsOf: staging),
      let result = PDFStructureRepair.repaired(
        written, links: linksIntact ? [] : links, outline: outlineIntact ? nil : outline, password: key)
    else {
      Self.repairLog.error("Save: the outline or links were not written, and could not be repaired")
      return check
    }
    try result.data.write(to: staging, options: .atomic)
    guard let mended = PDFDocument(url: staging), mended.pageCount == check.pageCount else {
      throw PDFEngineError.saveFailed
    }
    unlock(mended, options: options)
    // The repair must read back as the document, or what PDFKit wrote is kept instead: a repair that
    // came out wrong, a garbled title say, must never replace a file that was only missing something.
    let mendedLinks = Self.links(in: mended).map(LinkKey.init)
    let repairedLinks = linksIntact || Set(links.map(LinkKey.init)).isSubset(of: mendedLinks)
    let repairedOutline =
      outlineIntact || !result.wroteOutline || Self.shape(Self.outline(of: mended)) == Self.shape(outline)
    guard !mended.isLocked, repairedLinks, repairedOutline else {
      try written.write(to: staging, options: .atomic)
      Self.repairLog.error("Save: the repair did not read back as the document; kept the file as written")
      guard let kept = PDFDocument(url: staging) else { throw PDFEngineError.saveFailed }
      unlock(kept, options: options)
      return kept
    }
    Self.repairLog.info(
      "Save: mended \(result.mendedLinks) link(s); outline written: \(result.wroteOutline)")
    return mended
  }

  private func unlock(_ document: PDFDocument, options: [PDFDocumentWriteOption: Any]) {
    if document.isLocked, let key = options[.userPasswordOption] as? String ?? password {
      document.unlock(withPassword: key)
    }
  }

  private static let repairLog = Logger(subsystem: "com.algorythmos.pdfalgopro", category: "save")

  /// A link compared by where it is and where it goes, to the nearest point.
  private struct LinkKey: Hashable {
    let page: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let target: Int

    init(_ link: PDFStructureRepair.Link) {
      page = link.pageIndex
      x = Int(link.rect.minX.rounded())
      y = Int(link.rect.minY.rounded())
      width = Int(link.rect.width.rounded())
      height = Int(link.rect.height.rounded())
      target = link.target
    }
  }

  /// An outline compared by titles, targets and nesting: where on its page an item lands and whether it
  /// shows open can read back a little differently from a correct file.
  private struct OutlineShape: Equatable {
    let title: String
    let target: Int?
    let children: [OutlineShape]
  }

  private static func shape(_ items: [PDFStructureRepair.OutlineItem]) -> [OutlineShape] {
    items.map { OutlineShape(title: $0.title, target: $0.target, children: shape($0.children)) }
  }

  /// Every link in a document that goes to one of its pages.
  static func links(in document: PDFDocument) -> [PDFStructureRepair.Link] {
    var links: [PDFStructureRepair.Link] = []
    for index in 0..<document.pageCount {
      guard let page = document.page(at: index) else { continue }
      for annotation in page.annotations where annotation.type == "Link" {
        let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
        guard let destination, let target = destination.page.map({ document.index(for: $0) }),
          target != NSNotFound
        else { continue }
        links.append(
          .init(pageIndex: index, rect: annotation.bounds.standardized, target: target, point: destination.point))
      }
    }
    return links
  }

  /// How deep an outline is read.
  ///
  /// Real outlines are a few levels deep; a file nested deeper than this
  /// is read to this depth, the same on both sides of the comparison, so a hostile file can't exhaust
  /// the stack during a save.
  static let outlineDepthLimit = 100

  /// A document's outline, as titles, targets and children.
  static func outline(of document: PDFDocument) -> [PDFStructureRepair.OutlineItem] {
    func items(_ parent: PDFOutline, depth: Int) -> [PDFStructureRepair.OutlineItem] {
      guard depth < outlineDepthLimit else { return [] }
      return (0..<parent.numberOfChildren).compactMap { parent.child(at: $0) }.map { item in
        let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination
        let target = destination?.page.map { document.index(for: $0) }
        return .init(
          title: item.label ?? "", target: target == NSNotFound ? nil : target, point: destination?.point,
          isOpen: item.isOpen, children: items(item, depth: depth + 1))
      }
    }
    return document.outlineRoot.map { items($0, depth: 0) } ?? []
  }
}
