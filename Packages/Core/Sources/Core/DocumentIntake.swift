import Foundation

/// Brings a PDF into the library: copy, inspect, record, index (FR-LIB-004, FR-LIB-005).
///
/// If a file this intake has just added turns out not to be a readable PDF, the partial import is
/// removed, so the library never shows a document it cannot open. A document that was already in the
/// library is never deleted because it could not be read this time: the error is passed on and the
/// file stays where it is.
public struct DocumentIntake: Sendable {
  private let library: any DocumentLibrary
  private let inspector: any PDFInspecting
  private let index: any DocumentIndexing

  /// Creates an intake over the library, an inspector and the search index.
  public init(library: any DocumentLibrary, inspector: any PDFInspecting, index: any DocumentIndexing) {
    self.library = library
    self.inspector = inspector
    self.index = index
  }

  /// Imports a file from outside the library.
  ///
  /// A file already in the library's folder, opened from the Files app, opens its document instead of
  /// being copied again. One added there since the last launch is inspected and indexed first.
  public func importFile(at url: URL) async throws -> Document {
    if let existing = try await library.document(at: url) {
      return existing.pageCount == 0 ? try await finish(existing, isNew: false) : existing
    }
    let document = try await library.importDocument(from: url)
    return try await finish(document, isNew: true)
  }

  /// Adds new PDF data, for example a finished scan.
  public func add(data: Data, title: String) async throws -> Document {
    let document = try await library.addDocument(data: data, title: title)
    return try await finish(document, isNew: true)
  }

  /// Re-reads a document after its file changed (for example after recognition added text).
  ///
  /// - Throws: the inspection error when the file cannot be read; the document is kept.
  public func refresh(_ id: DocumentID) async throws -> Document {
    guard let document = try await library.document(withID: id) else { throw LibraryError.notFound }
    try await library.recordModified(id)
    return try await finish(document, isNew: false)
  }

  private func finish(_ document: Document, isNew: Bool) async throws -> Document {
    let inspection: PDFInspection
    do {
      inspection = try await inspector.inspect(library.fileURL(for: document.id))
    } catch {
      guard isNew else { throw error }
      try? await library.deletePermanently(document.id)
      if error is CancellationError { throw error }
      throw LibraryError.notAPDF
    }
    try await library.updateInspection(inspection, for: document.id)
    guard let updated = try await library.document(withID: document.id) else { throw LibraryError.notFound }
    try await index.index(updated, pages: inspection.pages)
    return updated
  }
}
