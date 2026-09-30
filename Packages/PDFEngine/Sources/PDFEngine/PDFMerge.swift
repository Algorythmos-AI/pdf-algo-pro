import Foundation
import PDFKit

/// Combines documents into one (FR-ORG-001, merge; FR-LIB-009, from a selection in the library).
public enum PDFMerge {
  /// A new PDF with every page of each document, in order, with their annotations.
  ///
  /// - Throws: `PDFEngineError.passwordRequired` when a document is locked; `PDFEngineError.unreadable`
  ///   when one isn't a readable PDF; `PDFEngineError.saveFailed` when no PDF could be made.
  public static func merge(_ urls: [URL]) throws -> Data {
    let merged = PDFDocument()
    for url in urls {
      guard let document = PDFDocument(url: url) else { throw PDFEngineError.unreadable }
      guard !document.isLocked else { throw PDFEngineError.passwordRequired }
      for index in 0..<document.pageCount {
        guard let page = document.page(at: index)?.copy() as? PDFPage else { throw PDFEngineError.saveFailed }
        merged.insert(page, at: merged.pageCount)
      }
    }
    guard merged.pageCount > 0, let data = merged.dataRepresentation() else { throw PDFEngineError.saveFailed }
    return data
  }
}
