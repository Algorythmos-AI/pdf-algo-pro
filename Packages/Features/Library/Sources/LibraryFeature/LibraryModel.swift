import Core
import CoreGraphics
import Foundation
import Observation
import PDFEngine

/// What the library shows next to a document: where to open it, and an optional assistant task.
public struct DocumentSelection: Hashable, Sendable {
  /// The document.
  public let id: DocumentID
  /// The page to open at, or `nil` for the last page read (FR-READ-006).
  public let pageIndex: Int?
  /// An assistant task to start when the document opens (from the personalised home action).
  public let task: AssistantTask?

  /// Creates a selection.
  public init(id: DocumentID, pageIndex: Int? = nil, task: AssistantTask? = nil) {
    self.id = id
    self.pageIndex = pageIndex
    self.task = task
  }
}

/// The library screen: sections, sort, search, import and the document actions (FR-LIB-001 to 006).
@MainActor
@Observable
public final class LibraryModel {
  /// Loading state.
  public enum Phase: Equatable {
    /// The index is opening.
    case loading
    /// Documents are shown.
    case loaded
  }

  // MARK: - State

  /// The section in the sidebar.
  public var section: LibrarySection = .all {
    didSet { if section != oldValue { Task { await reload() } } }
  }
  /// The sort order, remembered in settings.
  public var sort: LibrarySort {
    didSet {
      var current = settings.load()
      current.librarySort = sort
      settings.save(current)
      documents = sort.sorted(documents)
    }
  }
  /// The search text.
  public var query = ""
  /// The documents in the section.
  public private(set) var documents: [Document] = []
  /// Search results for the current query, in rank order; `nil` when not searching.
  public private(set) var results: [SearchHit]?
  /// Tags in use, for sidebar sections.
  public private(set) var tags: [String] = []
  /// Loading state.
  public private(set) var phase: Phase = .loading
  /// A message for the last failed action; the library itself is unchanged.
  public var errorMessage: String?
  /// The document shown next to the list.
  public var selection: DocumentSelection?
  /// Whether the last search failed (rather than finding nothing).
  public private(set) var isSearchUnavailable = false

  /// Whether an import is running.
  public private(set) var isImporting = false

  private let library: any DocumentLibrary
  private let intake: DocumentIntake
  private let index: any DocumentIndexing
  private let settings: any SettingsStoring
  private let telemetry: any TelemetryRecording
  private let thumbnails: ThumbnailCache
  private let now: () -> Date

  /// Creates the model.
  public init(
    library: any DocumentLibrary, intake: DocumentIntake, index: any DocumentIndexing, settings: any SettingsStoring,
    telemetry: any TelemetryRecording, thumbnails: ThumbnailCache = ThumbnailCache(),
    now: @escaping () -> Date = { Date() }
  ) {
    self.library = library
    self.intake = intake
    self.index = index
    self.settings = settings
    self.telemetry = telemetry
    self.thumbnails = thumbnails
    self.now = now
    sort = settings.load().librarySort
  }

  // MARK: - Loading

  /// Opens the library: purges expired deletions, picks up files added in the Files app, removes the
  /// search text and Spotlight entries of documents that are gone (FR-LIB-006), then loads.
  ///
  /// The housekeeping runs without the user asking, so a failure does not interrupt them: it is
  /// counted for "Report a problem" and retried on the next launch.
  public func load() async {
    do {
      for id in try await library.purgeExpired(now: now()) { await removeDerivedData(of: id) }
    } catch {
      await telemetry.record("quality.operation.failed")
    }
    do {
      let reconciliation = try await library.reconcileWithFiles()
      for id in reconciliation.removed { await removeDerivedData(of: id) }
      for document in reconciliation.added {
        do {
          _ = try await intake.refresh(document.id)
        } catch {
          await telemetry.record("quality.operation.failed")
        }
      }
    } catch {
      await telemetry.record("quality.operation.failed")
    }
    await pruneDerivedData()
    await reload()
    phase = .loaded
  }

  private func removeDerivedData(of id: DocumentID) async {
    do {
      try await index.remove(id)
    } catch {
      await telemetry.record("quality.operation.failed")
    }
  }

  /// Removes derived data the library no longer has documents for.
  ///
  /// This happens after the library index is rebuilt with new identifiers. Documents in Recently
  /// Deleted keep theirs until they are purged. Nothing is pruned when the library cannot be listed.
  private func pruneDerivedData() async {
    do {
      let current = try await library.documents(in: .all, sortedBy: .title)
      let deleted = try await library.documents(in: .recentlyDeleted, sortedBy: .title)
      _ = await index.prune(keeping: Set((current + deleted).map(\.id)))
    } catch {
      await telemetry.record("quality.operation.failed")
    }
  }

  /// Reloads the current section and tags.
  public func reload() async {
    do {
      documents = try await library.documents(in: section, sortedBy: sort)
      tags = try await library.allTags()
      if !query.isEmpty { await search() }
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  /// Searches the current section's documents; an empty query clears the results.
  public func search() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      results = nil
      isSearchUnavailable = false
      return
    }
    do {
      results = try await index.search(trimmed, in: documents)
      isSearchUnavailable = false
    } catch {
      // Not "no results": the search itself failed, and saying so is honest.
      results = []
      isSearchUnavailable = true
      await telemetry.record("quality.operation.failed")
    }
  }

  /// The document for a search hit.
  public func document(for hit: SearchHit) -> Document? {
    documents.first { $0.id == hit.documentID }
  }

  /// The home action, personalised by onboarding (FR-ONB-003).
  ///
  /// With AI hidden, an AI intent falls back to importing: AI never appears uninvited (FR-AI-009).
  public var primaryAction: HomeAction {
    let current = settings.load()
    let action = HomeAction.primary(for: current.intents)
    if current.isIntelligenceHidden, case .openAssistant = action { return .importDocument }
    return action
  }

  /// Whether AI features are hidden (FR-AI-009).
  public var isIntelligenceHidden: Bool { settings.load().isIntelligenceHidden }

  /// The assistant task the home action starts on the document it brings in, if any (F9).
  public var primaryTask: AssistantTask? {
    if case .openAssistant(let task) = primaryAction { return task }
    return nil
  }

  // MARK: - Adding

  /// Imports PDFs from Files, the share sheet or drag and drop; stops at nothing, reports failures.
  ///
  /// A single import opens the document, with `task` started in the assistant when given.
  public func importFiles(_ urls: [URL], task: AssistantTask? = nil) async {
    isImporting = true
    defer { isImporting = false }
    var failures = 0
    var last: Document?
    for url in urls {
      do {
        last = try await intake.importFile(at: url)
      } catch {
        failures += 1
      }
    }
    if failures > 0 {
      errorMessage = String(
        localized: "\(failures) file(s) couldn't be imported because they aren't readable PDFs. Nothing else changed.",
        bundle: .module)
      await telemetry.record("quality.operation.failed")
    }
    await reload()
    if let last, urls.count == 1 { selection = DocumentSelection(id: last.id, task: task) }
  }

  /// Adds the synthetic sample document ("Try a sample") and opens it, with `task` started in the
  /// assistant when given.
  public func addSample(task: AssistantTask? = nil) async {
    do {
      let document = try await intake.add(data: SyntheticPDF.makeSample(), title: SampleContent.title)
      await reload()
      selection = DocumentSelection(id: document.id, task: task)
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  /// Opens a document, optionally with an assistant task; records the first document opened.
  public func open(_ id: DocumentID, pageIndex: Int? = nil, task: AssistantTask? = nil) {
    selection = DocumentSelection(id: id, pageIndex: pageIndex, task: task)
  }

  // MARK: - Changing

  /// Renames a document.
  public func rename(_ id: DocumentID, to title: String) async {
    await perform { _ = try await self.library.rename(id, to: title) }
  }

  /// Marks or unmarks a favourite.
  public func toggleFavorite(_ document: Document) async {
    await perform { try await self.library.setFavorite(!document.isFavorite, for: document.id) }
  }

  /// Replaces a document's tags.
  public func setTags(_ tags: [String], for id: DocumentID) async {
    await perform { try await self.library.setTags(tags, for: id) }
  }

  /// Moves a document to Recently Deleted and out of Spotlight.
  public func delete(_ id: DocumentID) async {
    await perform {
      try await self.library.moveToRecentlyDeleted(id)
      if let deleted = try await self.library.document(withID: id) {
        try await self.index.index(deleted, pages: try await self.index.pages(of: id))
      }
    }
    if selection?.id == id { selection = nil }
  }

  /// Restores a document from Recently Deleted.
  public func restore(_ id: DocumentID) async {
    await perform {
      try await self.library.restore(id)
      if let restored = try await self.library.document(withID: id) {
        try await self.index.index(restored, pages: try await self.index.pages(of: id))
      }
    }
  }

  /// Deletes a document now, with its derived data (FR-LIB-006).
  public func deletePermanently(_ id: DocumentID) async {
    await perform {
      try await self.library.deletePermanently(id)
      try await self.index.remove(id)
    }
  }

  // MARK: - Thumbnails

  /// The first-page thumbnail of a document, rendered off the main actor and cached.
  public func thumbnail(for document: Document) async -> CGImage? {
    guard let url = try? await library.fileURL(for: document.id) else { return nil }
    return await thumbnails.thumbnail(for: url, version: document.modifiedAt)
  }

  // MARK: - Helpers

  private func perform(_ body: @escaping () async throws -> Void) async {
    do {
      try await body()
    } catch {
      errorMessage = Self.message(for: error)
    }
    await reload()
  }

  /// A plain-language message: what happened, what is safe (design system, error states).
  static func message(for error: any Error) -> String {
    switch error as? LibraryError {
    case .notAPDF: String(localized: "This file isn't a PDF this app can read. Nothing was added.", bundle: .module)
    case .emptyTitle: String(localized: "A document needs a name. The old name was kept.", bundle: .module)
    case .notFound: String(localized: "This document is no longer in the library.", bundle: .module)
    case .fileAccessFailed, .none:
      String(localized: "That didn't work, and your documents haven't changed. Try again.", bundle: .module)
    }
  }
}
