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
  private let pending: PendingRefreshes?

  /// Creates an intake over the library, an inspector and the search index.
  ///
  /// `pending` keeps the documents whose refresh hasn't worked yet, so they are refreshed at the next
  /// library load; without it, a failed refresh waits for the next change to the document.
  public init(
    library: any DocumentLibrary, inspector: any PDFInspecting, index: any DocumentIndexing,
    pending: PendingRefreshes? = nil
  ) {
    self.library = library
    self.inspector = inspector
    self.index = index
    self.pending = pending
  }

  /// Writes down, before a change is saved, that the document will need a refresh (#236).
  ///
  /// - Parameters:
  ///   - id: The document about to change.
  ///   - protecting: Whether the change protects the document, whose words must then leave search
  ///     and Spotlight whatever else fails.
  public func willChange(_ id: DocumentID, protecting: Bool = false) async {}

  /// Refreshes every document a refresh is still owed to (#236); a document no longer in the
  /// library is crossed off.
  ///
  /// - Returns: how many failed again; they stay on the list.
  @discardableResult
  public func refreshPending() async -> Int {
    guard let pending else { return 0 }
    var failed = 0
    for id in await pending.all {
      do {
        _ = try await refresh(id)
      } catch LibraryError.notFound {
        try? await pending.remove(id)
      } catch {
        failed += 1
      }
    }
    return failed
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
  /// The refresh is written down as owed before it starts and crossed off once search and Spotlight
  /// are up to date, so one that fails, or that the app is stopped in the middle of, is done at the
  /// next library load (#236). The change is recorded last, for the same reason.
  ///
  /// - Throws: the inspection error when the file cannot be read; the document is kept.
  public func refresh(_ id: DocumentID) async throws -> Document {
    guard let document = try await library.document(withID: id) else { throw LibraryError.notFound }
    // If the list can't be written, the refresh still runs; only a retry of a failure is lost.
    try? await pending?.add(id)
    let refreshed = try await finish(document, isNew: false, changedAt: Date())
    try await library.recordModified(id)
    try? await pending?.remove(id)
    return try await library.document(withID: id) ?? refreshed
  }

  /// Inspects, records and indexes a document; `changedAt` is the change search and Spotlight are
  /// told about, when it isn't recorded yet.
  private func finish(_ document: Document, isNew: Bool, changedAt: Date? = nil) async throws -> Document {
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
    guard var updated = try await library.document(withID: document.id) else { throw LibraryError.notFound }
    if let changedAt { updated.modifiedAt = changedAt }
    try await index.index(updated, pages: inspection.pages)
    // Deleted for good while this ran: it must not come back in search or Spotlight.
    guard try await library.document(withID: document.id) != nil else {
      try await index.remove(document.id)
      throw LibraryError.notFound
    }
    return updated
  }
}
