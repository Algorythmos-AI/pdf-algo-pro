import Core
import CoreGraphics
import Foundation
import ImageIO
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
    didSet {
      guard section != oldValue else { return }
      // What the library last held, filed by the same rule, so a section never opens showing the
      // one before it. The reload that follows asks the library again.
      documents = sort.sorted(pool.filter(section.contains))
      Task { await reload() }
    }
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
  public private(set) var documents: [Core.Document] = []
  /// The documents the last search looked through.
  private var searched: [Core.Document] = []
  /// Search results for the current query, in rank order; `nil` when not searching.
  public private(set) var results: [SearchHit]?
  /// Tags in use, for sidebar sections.
  public private(set) var tags: [String] = []
  /// How many documents each fixed section holds, for Home; empty until the library has loaded.
  ///
  /// Counted with `LibrarySection.contains`, the rule the library files documents by, so a count
  /// never differs from the list it leads to.
  public private(set) var counts: [LibrarySection: Int] = [:]
  /// The few documents opened most recently, newest first, for Home's "Continue reading".
  public private(set) var recentDocuments: [Core.Document] = []
  /// How many times a link, Spotlight, a widget or an intent has asked for a section's documents.
  ///
  /// On iPhone the app opens on Home; the view goes to the document list when this changes, also when
  /// the section asked for is the one already chosen.
  public private(set) var listRequests = 0
  /// Every document the library held at the last reload, deleted ones included.
  private var pool: [Core.Document] = []
  /// The reload in progress or last finished; the next one waits for it, so reloads apply in order.
  private var reloading: Task<Void, Never>?
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
    let interval = Signposts.begin("Library.Ready")
    defer { interval.end() }
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

  /// Reloads the current section, the tags, and what Home shows: the counts and the recent documents.
  ///
  /// Reloads run one after another, in the order they were asked for. Two at once could finish out of
  /// order and leave an earlier section's documents under a later section's title.
  public func reload() async {
    let previous = reloading
    let task = Task {
      await previous?.value
      await reloadNow()
    }
    reloading = task
    await task.value
  }

  private func reloadNow() async {
    do {
      let section = section
      let listed = try await library.documents(in: section, sortedBy: sort)
      let current = section == .all ? listed : try await library.documents(in: .all, sortedBy: sort)
      let deleted =
        section == .recentlyDeleted ? listed : try await library.documents(in: .recentlyDeleted, sortedBy: sort)
      let tags = try await library.allTags()
      // The section can change while the library answers; that change's own reload follows this one.
      if section == self.section { documents = listed }
      self.tags = tags
      pool = current + deleted
      counts = Dictionary(
        uniqueKeysWithValues: LibrarySection.fixed.map { section in (section, pool.count(where: section.contains)) })
      recentDocuments = Array(
        LibrarySort.recentlyOpened.sorted(pool.filter(LibrarySection.recents.contains)).prefix(Self.recentLimit))
      if !query.isEmpty { await search() }
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  /// How many recent documents Home shows.
  static let recentLimit = 3

  /// Shows a section's documents, for a link, Spotlight, a widget or an intent.
  ///
  /// Unlike setting `section`, this also tells the view to leave Home for the document list.
  public func show(_ section: LibrarySection) {
    self.section = section
    selection = nil
    listRequests += 1
  }

  /// Searches the whole library, whichever section is showing (FR-LIB-003).
  ///
  /// A document is found wherever it is filed; in Recently Deleted, the search covers the deleted
  /// documents. An empty query clears the results.
  public func search() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      results = nil
      isSearchUnavailable = false
      return
    }
    do {
      let scope: LibrarySection = section == .recentlyDeleted ? .recentlyDeleted : .all
      searched = try await library.documents(in: scope, sortedBy: sort)
      results = try await index.search(trimmed, in: searched)
      isSearchUnavailable = false
    } catch {
      // Not "no results": the search itself failed, and saying so is honest.
      results = []
      isSearchUnavailable = true
      await telemetry.record("quality.operation.failed")
    }
  }

  /// The document for a search hit, which may be outside the section showing.
  public func document(for hit: SearchHit) -> Core.Document? {
    searched.first { $0.id == hit.documentID } ?? documents.first { $0.id == hit.documentID }
  }

  /// Whether the start-here card shows above the list.
  ///
  /// It helps with a first document, so it shows in All documents only until one of the person's own
  /// documents has been opened (the sample doesn't count), and never once there are three or more.
  /// Before, it stayed until the third document and kept saying "Open your first PDF".
  public var showsPrimaryAction: Bool {
    section == .all && documents.count < 3
      && !documents.contains { $0.lastOpenedAt != nil && $0.title != SampleContent.title }
  }

  /// What a document's file says about itself, for the info sheet (FR-LIB-008); `nil` when it can't be read.
  public func details(for document: Core.Document) async -> DocumentDetails? {
    guard let url = try? await library.fileURL(for: document.id) else { return nil }
    return await Task.detached(priority: .userInitiated) { DocumentDetails.of(fileAt: url) }.value
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
    var last: Core.Document?
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

  /// Makes a PDF from photos, one page each, adds it to the library and opens it (FR-ORG-008).
  ///
  /// Each photo is decoded with its orientation applied and its longest side at most 3,000 pixels,
  /// so a batch of large photos can't exhaust memory. Photos that can't be read are left out and
  /// counted.
  public func addPhotos(_ photos: [Data]) async {
    guard !photos.isEmpty else { return }
    isImporting = true
    defer { isImporting = false }
    let images = await Task.detached(priority: .userInitiated) { photos.compactMap(Self.image) }.value
    do {
      guard !images.isEmpty else { throw LibraryError.notAPDF }
      let title = String(
        localized: "Photos \(Date().formatted(date: .abbreviated, time: .shortened))", bundle: .module)
      let document = try await intake.add(data: ImagePDF.make(from: images), title: title)
      await reload()
      selection = DocumentSelection(id: document.id)
      if images.count < photos.count {
        errorMessage = String(
          localized: "\(photos.count - images.count) photo(s) couldn't be read and were left out.", bundle: .module)
      }
    } catch {
      errorMessage = String(localized: "Couldn't make a PDF from those photos. Nothing changed.", bundle: .module)
    }
  }

  /// A photo as an upright image, its longest side at most 3,000 pixels; `nil` when it can't be read.
  nonisolated static func image(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 3_000,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
  public func toggleFavorite(_ document: Core.Document) async {
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

  /// The documents last moved to Recently Deleted together, until the move is undone or forgotten
  /// (FR-LIB-009).
  public private(set) var lastDeleted: [DocumentID] = []

  /// Moves several documents to Recently Deleted; `undoDelete()` puts them back.
  public func delete(_ ids: [DocumentID]) async {
    for id in ids { await delete(id) }
    lastDeleted = ids
  }

  /// Puts back the documents last moved to Recently Deleted together.
  public func undoDelete() async {
    let ids = lastDeleted
    lastDeleted = []
    for id in ids { await restore(id) }
  }

  /// Forgets the last group deleted, once the chance to undo has passed.
  public func forgetLastDeleted() {
    lastDeleted = []
  }

  /// Marks or unmarks several documents as favourites.
  public func setFavorite(_ isFavorite: Bool, for ids: [DocumentID]) async {
    await perform {
      for id in ids { try await self.library.setFavorite(isFavorite, for: id) }
    }
  }

  /// The files of several documents, for sharing.
  public func fileURLs(for ids: [DocumentID]) async -> [URL] {
    var urls: [URL] = []
    for id in ids {
      if let url = try? await library.fileURL(for: id) { urls.append(url) }
    }
    return urls
  }

  /// Combines documents, in the library's order, into a new document and opens it; the originals stay.
  public func merge(_ ids: [DocumentID]) async {
    let ordered = documents.filter { ids.contains($0.id) }
    guard ordered.count > 1 else { return }
    do {
      let urls = await fileURLs(for: ordered.map(\.id))
      let data = try await Task.detached(priority: .userInitiated) { try PDFMerge.merge(urls) }.value
      let title = String(localized: "\(ordered[0].title) and \(ordered.count - 1) more", bundle: .module)
      let document = try await intake.add(data: data, title: title)
      await reload()
      selection = DocumentSelection(id: document.id)
    } catch PDFEngineError.passwordRequired {
      errorMessage = String(
        localized: "A password-protected document can't be merged. Remove its password first. Nothing changed.",
        bundle: .module)
    } catch {
      errorMessage = String(localized: "Couldn't merge those documents. Nothing changed.", bundle: .module)
    }
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
  public func thumbnail(for document: Core.Document) async -> CGImage? {
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
