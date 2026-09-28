import Foundation

/// Brings a PDF into the library: copy, inspect, record, index (FR-LIB-004, FR-LIB-005).
///
/// If the file turns out not to be a readable PDF, the partial import is removed, so the library
/// never shows a document it cannot open.
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
  public func importFile(at url: URL) async throws -> Document {
    let document = try await library.importDocument(from: url)
    return try await finish(document)
  }

  /// Adds new PDF data, for example a finished scan.
  public func add(data: Data, title: String) async throws -> Document {
    let document = try await library.addDocument(data: data, title: title)
    return try await finish(document)
  }

  /// Re-reads a document after its file changed (for example after recognition added text).
  public func refresh(_ id: DocumentID) async throws -> Document {
    guard let document = try await library.document(withID: id) else { throw LibraryError.notFound }
    try await library.recordModified(id)
    return try await finish(document)
  }

  private func finish(_ document: Document) async throws -> Document {
    let inspection: PDFInspection
    do {
      inspection = try await inspector.inspect(library.fileURL(for: document.id))
    } catch {
      try? await library.deletePermanently(document.id)
      throw LibraryError.notAPDF
    }
    try await library.updateInspection(inspection, for: document.id)
    guard let updated = try await library.document(withID: document.id) else { throw LibraryError.notFound }
    try await index.index(updated, pages: inspection.pages)
    return updated
  }
}
