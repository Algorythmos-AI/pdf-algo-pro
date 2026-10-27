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
  private let lanes: RefreshLanes

  /// Creates an intake over the library, an inspector and the search index.
  ///
  /// `pending` keeps the documents whose refresh hasn't worked yet, so they are refreshed at the next
  /// library load; without it, a failed refresh waits for the next change to the document. `lanes`
  /// keeps refreshes of one document from overlapping; intakes over one library share them.
  public init(
    library: any DocumentLibrary, inspector: any PDFInspecting, index: any DocumentIndexing,
    pending: PendingRefreshes? = nil, lanes: RefreshLanes = .shared
  ) {
    self.library = library
    self.inspector = inspector
    self.index = index
    self.pending = pending
    self.lanes = lanes
  }

  /// Writes down, before a change is saved, that the document will need a refresh (#236).
  ///
  /// - Parameters:
  ///   - id: The document about to change.
  ///   - protecting: Whether the change protects the document, whose words must then leave search
  ///     and Spotlight whatever else fails.
  /// - Returns: the change's number, to pass to `saveFinished(_:change:)`.
  @discardableResult
  public func willChange(_ id: DocumentID, protecting: Bool = false) async -> Int? {
    // If the list can't be written, the change still goes ahead; only its retry is lost.
    try? await pending?.add(id, protecting: protecting, saved: false)
  }

  /// Tells the intake the save of a change has ended, whether it worked or not.
  ///
  /// Until then no refresh crosses the change off: what it reads may be the file from before the
  /// save. After it, the next refresh reads the file as it is, saved or not.
  public func saveFinished(_ id: DocumentID, change: Int?) async {
    guard let change else { return }
    await pending?.saveFinished(id, change: change)
  }

  /// How many refreshes of one change are tried before it is given up.
  public static let attempts = 3

  /// Whether a refresh is still owed to the document.
  public func owes(_ id: DocumentID) async -> Bool {
    await pending?.owed(id) != nil
  }

  /// Refreshes every document a refresh is still owed to (#236).
  ///
  /// A document no longer in the library is crossed off. One whose file isn't a readable PDF any
  /// more is crossed off at once, its old text taken out of search. One that has failed
  /// `attempts` times is given up, except that a protected document is crossed off only once its
  /// words are out of search and Spotlight: that is tried every time until it works. A cancelled
  /// pass stops, and counts nothing.
  ///
  /// - Returns: how many failed again.
  @discardableResult
  public func refreshPending() async -> Int {
    guard let pending else { return 0 }
    var failed = 0
    for id in await pending.all {
      guard let owed = await pending.owed(id) else { continue }
      do {
        _ = try await run(id, recordsChange: false, changedAt: nil)
      } catch LibraryError.notFound {
        try? await pending.remove(id)
      } catch is CancellationError {
        return failed
      } catch LibraryError.notAPDF {
        // Final, and crossed off by the refresh itself once its old text is out.
        continue
      } catch {
        failed += 1
        let removedWords = owed.protects ? (try? await index.remove(id)) != nil : true
        let failures = await pending.owed(id)?.failures ?? Self.attempts
        if failures >= Self.attempts, removedWords {
          try? await pending.remove(id)
          // Given up: the file's change counts as seen, so the next launch doesn't find it again
          // and start over (#242).
          if !owed.protects { try? await library.recordModified(id) }
        }
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
      guard existing.pageCount == 0 else { return existing }
      return try await inLane(existing.id) { try await finish(existing, isNew: false) }
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
    try await run(id, recordsChange: true, changedAt: nil)
  }

  /// Re-reads a document whose file another app changed at `date`, which is recorded as its change.
  public func refresh(_ id: DocumentID, changedAt date: Date) async throws -> Document {
    try await run(id, recordsChange: true, changedAt: date)
  }

  /// Runs `body` in the document's lane: refreshes of one document never overlap (#236).
  private func inLane<T: Sendable>(_ id: DocumentID, _ body: () async throws -> T) async throws -> T {
    await lanes.enter(id)
    do {
      let result = try await body()
      await lanes.leave(id)
      return result
    } catch {
      await lanes.leave(id)
      throw error
    }
  }

  /// Runs a refresh in the document's lane.
  ///
  /// It crosses off only changes whose save had ended before it read the file, so a change made, or
  /// still being saved, while it runs still gets its own refresh (#236).
  private func run(_ id: DocumentID, recordsChange: Bool, changedAt: Date?) async throws -> Document {
    try await inLane(id) { try await runInLane(id, recordsChange: recordsChange, changedAt: changedAt) }
  }

  private func runInLane(_ id: DocumentID, recordsChange: Bool, changedAt: Date?) async throws -> Document {
    guard let document = try await library.document(withID: id) else { throw LibraryError.notFound }
    // The caller has written the file. If the list can't be written, the refresh still runs; only a
    // retry of a failure is lost.
    if recordsChange { _ = try? await pending?.add(id) }
    let covers = await pending?.coverage(id)
    do {
      let refreshed = try await finish(document, isNew: false, changedAt: changedAt ?? Date())
      if let changedAt {
        try await library.recordModified(id, at: changedAt)
      } else {
        try await library.recordModified(id)
      }
      if let covers { try? await pending?.finished(id, upTo: covers) }
      return try await library.document(withID: id) ?? refreshed
    } catch LibraryError.notAPDF {
      // Final: reading it again won't help. Its old text goes, and then nothing more is owed.
      if (try? await index.remove(id)) != nil {
        try? await pending?.remove(id)
      } else {
        _ = try? await pending?.failed(id)
      }
      throw LibraryError.notAPDF
    } catch {
      if !(error is CancellationError) { _ = try? await pending?.failed(id) }
      throw error
    }
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
    // A protected document's words leave search and Spotlight first. Removing needs no space, so
    // this works on a full disk, where everything after it may fail (#236).
    if inspection.isEncrypted { try await index.remove(document.id) }
    try await library.updateInspection(inspection, for: document.id)
    guard var updated = try await library.document(withID: document.id) else { throw LibraryError.notFound }
    if let changedAt { updated.modifiedAt = changedAt }
    try await index.index(updated, pages: inspection.pages)
    // Deleted for good while this ran: it must not come back in search or Spotlight.
    guard let current = try await library.document(withID: document.id) else {
      try await index.remove(document.id)
      throw LibraryError.notFound
    }
    // Moved to Recently Deleted while this ran: indexed as it is now, which takes it out of Spotlight.
    if current.isDeleted, !updated.isDeleted {
      try await index.index(current, pages: inspection.pages)
      return current
    }
    return updated
  }
}
