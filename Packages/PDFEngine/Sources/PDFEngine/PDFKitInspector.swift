import Core
import Foundation
import PDFKit

/// Reads page counts, encryption and page text with PDFKit, off the main actor.
public actor PDFKitInspector: PDFInspecting {
  /// Creates an inspector.
  public init() {}

  /// Inspects the PDF at a URL.
  ///
  /// - Throws: `LibraryError.notAPDF` when PDFKit cannot read the file.
  public func inspect(_ url: URL) async throws -> PDFInspection {
    guard let document = PDFDocument(url: url) else { throw LibraryError.notAPDF }
    if document.isLocked {
      return PDFInspection(pageCount: document.pageCount, isEncrypted: true, pages: [])
    }
    var pages: [PageText] = []
    pages.reserveCapacity(document.pageCount)
    for index in 0..<document.pageCount {
      try Task.checkCancellation()
      pages.append(PageText(pageIndex: index, text: document.page(at: index)?.string ?? ""))
    }
    return PDFInspection(pageCount: document.pageCount, isEncrypted: document.isEncrypted, pages: pages)
  }
}
