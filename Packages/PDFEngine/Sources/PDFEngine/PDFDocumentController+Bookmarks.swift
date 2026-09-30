import Foundation
import PDFKit

/// Bookmarks (FR-READ-009), kept in the PDF itself as a "Bookmarks" entry of its outline.
///
/// Stored in the file, they are never lost on save, travel with the document, and show in the table
/// of contents of Preview and other PDF apps. Each points at its page, so it follows the page when
/// pages move.
extension PDFDocumentController {
  /// The outline entry that holds the bookmarks.
  ///
  /// Not translated: it is part of the file, read by any app.
  static let bookmarksLabel = "Bookmarks"

  /// The bookmarked pages, in page order.
  public var bookmarkedPages: [Int] {
    guard let folder = bookmarksFolder() else { return [] }
    return Set(children(of: folder).compactMap { pageIndex(of: $0) }).sorted()
  }

  /// Whether a page is bookmarked.
  public func isBookmarked(_ pageIndex: Int) -> Bool { bookmarkedPages.contains(pageIndex) }

  /// Bookmarks a page, or removes its bookmark, as one undo step.
  ///
  /// Returns whether the page is now bookmarked.
  @discardableResult
  public func toggleBookmark(onPage pageIndex: Int) -> Bool {
    guard !isLocked, let page = document.page(at: pageIndex) else { return false }
    let bookmarked = !isBookmarked(pageIndex)
    setBookmark(bookmarked, on: page)
    return bookmarked
  }

  func setBookmark(_ bookmarked: Bool, on page: PDFPage) {
    let root = document.outlineRoot ?? PDFOutline()
    if document.outlineRoot == nil { document.outlineRoot = root }
    let folder =
      bookmarksFolder()
      ?? {
        let folder = PDFOutline()
        folder.label = Self.bookmarksLabel
        root.insertChild(folder, at: root.numberOfChildren)
        return folder
      }()
    if bookmarked {
      let item = PDFOutline()
      let number = document.index(for: page) + 1
      item.label = String(localized: "Page \(number)")
      item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .cropBox).maxY))
      let position = children(of: folder).firstIndex { (pageIndex(of: $0) ?? .max) > number - 1 }
      folder.insertChild(item, at: position ?? folder.numberOfChildren)
    } else {
      for child in children(of: folder) where child.destination?.page == page {
        child.removeFromParent()
      }
    }
    if folder.numberOfChildren == 0 {
      folder.removeFromParent()
    } else if let first = folder.child(at: 0)?.destination {
      folder.destination = first
    }
    hasUnsavedChanges = true
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.setBookmark(!bookmarked, on: page) }
    }
  }

  private func bookmarksFolder() -> PDFOutline? {
    guard let root = document.outlineRoot else { return nil }
    return children(of: root).last { $0.label == Self.bookmarksLabel }
  }

  private func children(of item: PDFOutline) -> [PDFOutline] {
    (0..<item.numberOfChildren).compactMap { item.child(at: $0) }
  }

  private func pageIndex(of item: PDFOutline) -> Int? {
    guard let page = item.destination?.page else { return nil }
    let index = document.index(for: page)
    return index == NSNotFound ? nil : index
  }
}
