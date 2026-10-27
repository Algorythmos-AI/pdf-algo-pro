import Foundation
import PDFKit

/// Where a document's links and outline entries go, read so that they can be pointed at other page
/// objects for the same pages: a page's copy, or the page that replaces it.
///
/// A destination names a page object, not a page number. Once its page is copied into another document
/// or replaced, a destination left as it was goes to a page outside the document, which PDFKit writes as
/// the first page (#235).
struct LinkTargets {
  private let document: PDFDocument
  private var pointers: [(page: Int, destination: PDFDestination, point: (PDFDestination) -> Void)] = []

  /// Reads targets in `document`, the document whose pages the destinations name. Its pages must still
  /// be in it when each link or entry is noted.
  init(in document: PDFDocument) {
    self.document = document
  }

  /// Notes where a link goes: its destination, or its go-to action's. A link that goes anywhere else,
  /// a web address say, is left as it is.
  mutating func note(_ annotation: PDFAnnotation) {
    if !note(annotation.destination, { annotation.destination = $0 }) {
      _ = note((annotation.action as? PDFActionGoTo)?.destination) {
        annotation.action = PDFActionGoTo(destination: $0)
      }
    }
  }

  /// Notes where an outline entry goes: its destination, or its go-to action's.
  mutating func note(_ item: PDFOutline) {
    if !note(item.destination, { item.destination = $0 }) {
      _ = note((item.action as? PDFActionGoTo)?.destination) { item.action = PDFActionGoTo(destination: $0) }
    }
  }

  /// Points each noted link and entry at `page(index)` in place of the document's page at that index,
  /// at the same point and zoom; one whose page has no counterpart is left as it is.
  func point(at page: (Int) -> PDFPage?) {
    for pointer in pointers {
      guard let target = page(pointer.page) else { continue }
      let destination = PDFDestination(page: target, at: pointer.destination.point)
      destination.zoom = pointer.destination.zoom
      pointer.point(destination)
    }
  }

  private mutating func note(_ destination: PDFDestination?, _ point: @escaping (PDFDestination) -> Void) -> Bool {
    guard let destination, let page = destination.page else { return false }
    let index = document.index(for: page)
    guard index != NSNotFound else { return false }
    pointers.append((index, destination, point))
    return true
  }
}
