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
    let key = options[.userPasswordOption] as? String ?? password
    let mend = Self.mendStructure(of: check, writtenFrom: document, password: key) {
      try? Data(contentsOf: staging)
    }
    switch mend {
    case .intact:
      return check
    case .unmended(let reason):
      Self.repairLog.error("Save: \(reason, privacy: .public); kept the file as written")
      return check
    case .mended(let result):
      try result.data.write(to: staging, options: .atomic)
      guard let mended = PDFDocument(url: staging), mended.pageCount == check.pageCount else {
        throw PDFEngineError.saveFailed
      }
      unlock(mended, options: options)
      Self.repairLog.info(
        "Save: mended \(result.mendedLinks) link(s); outline written: \(result.wroteOutline)")
      return mended
    }
  }

  /// What comparing a written file with the document it was written from found.
  enum StructureMend {
    /// The file has the document's outline and links to pages, or is locked and can't be compared.
    case intact
    /// The file lacked some of them; this is the file with them put back, checked by reading it.
    case mended(PDFStructureRepair.Result)
    /// The file lacks some of them and could not be mended; why, for the log.
    case unmended(String)
  }

  /// Compares the outline and the links to pages of `check`, a file PDFKit wrote from `source`, with
  /// the source's, and puts back what PDFKit left out (#307).
  ///
  /// A save, a compressed copy and a searchable copy all go through this. The repair must read back
  /// as the source, or it is not used: a repair that came out wrong, a garbled title say, must never
  /// replace a file that was only missing something.
  ///
  /// - Parameters:
  ///   - check: The written file, opened; unlocked here with `password` when it is encrypted.
  ///   - source: The document in memory the file was written from.
  ///   - password: The written file's user password, when it has one.
  ///   - bytes: The written file's bytes, read only when something needs mending.
  /// - Returns: Whether the file was intact, mended (with the mended bytes), or could not be mended.
  nonisolated static func mendStructure(
    of check: PDFDocument, writtenFrom source: PDFDocument, password: String?, bytes: () -> Data?
  ) -> StructureMend {
    if check.isLocked, let password { check.unlock(withPassword: password) }
    guard !check.isLocked else { return .intact }
    let links = Self.links(in: source)
    let outline = Self.outline(of: source)
    let linksIntact = Set(links.map(LinkKey.init)).isSubset(of: Self.links(in: check).map(LinkKey.init))
    let outlineIntact = Self.shape(Self.outline(of: check)) == Self.shape(outline)
    guard !linksIntact || !outlineIntact else { return .intact }
    guard let written = bytes(),
      let result = PDFStructureRepair.repaired(
        written, links: linksIntact ? [] : links, outline: outlineIntact ? nil : outline, password: password ?? "")
    else { return .unmended("the outline or links were not written, and could not be repaired") }
    guard let mended = PDFDocument(data: result.data), mended.pageCount == check.pageCount else {
      return .unmended("the repaired file did not open with every page")
    }
    if mended.isLocked, let password { mended.unlock(withPassword: password) }
    let mendedLinks = Self.links(in: mended).map(LinkKey.init)
    let repairedLinks = linksIntact || Set(links.map(LinkKey.init)).isSubset(of: mendedLinks)
    let repairedOutline =
      outlineIntact || !result.wroteOutline || Self.shape(Self.outline(of: mended)) == Self.shape(outline)
    guard !mended.isLocked, repairedLinks, repairedOutline else {
      return .unmended("the repair did not read back as the document")
    }
    return .mended(result)
  }

  /// `document.dataRepresentation()`, with the outline and the links to pages that PDFKit on iOS 27
  /// leaves out put back (#307).
  ///
  /// For a document written to data rather than through `save(to:)`: the searchable copy, and the
  /// test fixtures that stand for files other apps wrote. An encrypted document is written as PDFKit
  /// writes it.
  ///
  /// - Parameters:
  ///   - document: The document to write.
  ///   - write: What writes the document; tests pass one that writes it as iOS 27 does.
  /// - Returns: The written document, mended where it needed it; `nil` when it could not be written.
  nonisolated package static func dataRepresentation(
    of document: PDFDocument, writtenBy write: (PDFDocument) -> Data? = { $0.dataRepresentation() }
  ) -> Data? {
    guard let data = write(document) else { return nil }
    guard let check = PDFDocument(data: data) else { return data }
    switch mendStructure(of: check, writtenFrom: document, password: nil, bytes: { data }) {
    case .mended(let result):
      repairLog.info("Write: mended \(result.mendedLinks) link(s); outline written: \(result.wroteOutline)")
      return result.data
    case .unmended(let reason):
      repairLog.error("Write: \(reason, privacy: .public); kept the data as written")
      return data
    case .intact:
      return data
    }
  }

  private func unlock(_ document: PDFDocument, options: [PDFDocumentWriteOption: Any]) {
    if document.isLocked, let key = options[.userPasswordOption] as? String ?? password {
      document.unlock(withPassword: key)
    }
  }

  nonisolated private static let repairLog = Logger(subsystem: "com.algorythmos.pdfalgopro", category: "save")

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

  /// An outline compared by titles, targets, web addresses, zooms to the hundredth, and nesting: where
  /// on its page an item lands and whether it shows open can read back a little differently from a
  /// correct file.
  private struct OutlineShape: Equatable {
    let title: String
    let target: Int?
    let url: String?
    let zoom: Int?
    let children: [OutlineShape]
  }

  nonisolated private static func shape(_ items: [PDFStructureRepair.OutlineItem]) -> [OutlineShape] {
    items.map {
      OutlineShape(
        title: $0.title, target: $0.target, url: $0.url?.absoluteString,
        zoom: $0.zoom.map { Int(($0 * 100).rounded()) },
        children: shape($0.children))
    }
  }

  /// Every link in a document that goes to one of its pages.
  nonisolated static func links(in document: PDFDocument) -> [PDFStructureRepair.Link] {
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
  nonisolated static let outlineDepthLimit = 100

  /// A document's outline, as titles, targets, web addresses, zooms and children.
  nonisolated static func outline(of document: PDFDocument) -> [PDFStructureRepair.OutlineItem] {
    func items(_ parent: PDFOutline, depth: Int) -> [PDFStructureRepair.OutlineItem] {
      guard depth < outlineDepthLimit else { return [] }
      return (0..<parent.numberOfChildren).compactMap { parent.child(at: $0) }.map { item in
        let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination
        let target = destination?.page.map { document.index(for: $0) }
        // PDFKit reads a destination without a zoom, or with zoom 0, as kPDFDestinationUnspecifiedValue.
        let zoom = destination.map(\.zoom).flatMap { $0.isFinite && $0 > 0 && $0 < 1_000_000 ? $0 : nil }
        return .init(
          title: item.label ?? "", target: target == NSNotFound ? nil : target, point: destination?.point,
          isOpen: item.isOpen, children: items(item, depth: depth + 1), url: (item.action as? PDFActionURL)?.url,
          zoom: zoom)
      }
    }
    return document.outlineRoot.map { items($0, depth: 0) } ?? []
  }
}
