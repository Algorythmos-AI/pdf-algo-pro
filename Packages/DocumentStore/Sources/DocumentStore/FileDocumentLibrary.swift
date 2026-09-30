import Core
import Foundation

/// The library: PDFs as real files in a folder the user can see in the Files app, plus the index
/// (ADR-0005, ADR-0006). Every file operation is coordinated and atomic, so a crash or a failed
/// write never leaves a half-written document (NFR-REL-002), and changes run one at a time, so two
/// changes to the same document never undo each other.
public actor FileDocumentLibrary: DocumentLibrary {
  /// How long a document stays in Recently Deleted before it is purged.
  public static let retention: TimeInterval = 30 * 24 * 60 * 60

  private let documentsFolder: URL
  private let deletedFolder: URL
  private let previousVersionsFolder: URL?
  private let index: LibraryIndex
  private let now: @Sendable () -> Date
  private let fileManager = FileManager.default
  private var isChanging = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  /// Creates a library.
  ///
  /// Folders are created if needed; if that fails, operations report `LibraryError.fileAccessFailed` instead of
  /// stopping the app.
  ///
  /// - Parameters:
  ///   - documentsFolder: Where documents live; the app passes its Documents folder, shown in Files.
  ///   - deletedFolder: Where Recently Deleted keeps files; not shown in Files.
  ///   - previousVersionsFolder: Where each document's version from before its last save is kept, not
  ///     shown in Files; `nil` keeps none.
  ///   - index: The metadata index.
  ///   - now: The clock, injected so tests never wait.
  public init(
    documentsFolder: URL, deletedFolder: URL, previousVersionsFolder: URL? = nil, index: LibraryIndex,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.documentsFolder = documentsFolder
    self.deletedFolder = deletedFolder
    self.previousVersionsFolder = previousVersionsFolder
    self.index = index
    self.now = now
    for folder in [documentsFolder, deletedFolder] + [previousVersionsFolder].compactMap(\.self) {
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    if let previousVersionsFolder { Self.migrateSingleVersions(in: previousVersionsFolder, now: now()) }
  }

  // MARK: - Reading

  /// Documents in a section, in the given order.
  public func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Document] {
    sort.sorted(try await index.all().filter(section.contains))
  }

  /// One document, or `nil` when it does not exist.
  public func document(withID id: DocumentID) async throws -> Document? {
    try await index.document(id)
  }

  /// Every tag in use, sorted.
  public func allTags() async throws -> [String] {
    Document.normalizedTags(try await index.all().filter { !$0.isDeleted }.flatMap(\.tags))
  }

  /// The file URL of a document, for reading and coordinated writing.
  public func fileURL(for id: DocumentID) async throws -> URL {
    location(of: try await existing(id))
  }

  // MARK: - Adding

  /// The document whose file is at `url`, or `nil` when `url` is not in the library's folder.
  ///
  /// The Files app shows that folder, so a file opened from there is already in the library. A PDF put
  /// there since the library last looked is added in place, not copied.
  public func document(at url: URL) async throws -> Document? {
    let file = url.resolvingSymlinksInPath().standardizedFileURL
    let folder = documentsFolder.resolvingSymlinksInPath().standardizedFileURL
    guard file.isFileURL, file.deletingLastPathComponent().path == folder.path else { return nil }
    return try await exclusively {
      let name = file.lastPathComponent
      if let known = try await index.all().first(where: { !$0.isDeleted && $0.fileName == name }) { return known }
      guard file.pathExtension.lowercased() == "pdf", fileManager.fileExists(atPath: file.path) else { return nil }
      let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
      let document = Document(title: file.deletingPathExtension().lastPathComponent, fileName: name, addedAt: createdAt)
      try await index.upsert(document)
      return document
    }
  }

  /// Copies a PDF into the library, reading it with coordinated, security-scoped access.
  public func importDocument(from url: URL) async throws -> Document {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var coordinationError: NSError?
    var data: Data?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: .withoutChanges, error: &coordinationError
    ) {
      data = try? Data(contentsOf: $0, options: .mappedIfSafe)
    }
    guard coordinationError == nil, let data else { throw LibraryError.fileAccessFailed }
    return try await exclusively { try await add(data, title: url.deletingPathExtension().lastPathComponent) }
  }

  /// Adds PDF data (for example a new scan) as a document.
  public func addDocument(data: Data, title: String) async throws -> Document {
    try await exclusively { try await add(data, title: title) }
  }

  private func add(_ data: Data, title: String) async throws -> Document {
    guard data.starts(with: Data("%PDF-".utf8)) else { throw LibraryError.notAPDF }
    let cleanTitle = Self.cleanTitle(title)
    let fileName = uniqueFileName(for: cleanTitle, in: documentsFolder)
    try write(data, to: documentsFolder.appendingPathComponent(fileName))
    let document = Document(title: cleanTitle, fileName: fileName, addedAt: now())
    try await index.upsert(document)
    return document
  }

  /// Records what inspection learnt about a document's file.
  public func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      document.pageCount = inspection.pageCount
      document.isEncrypted = inspection.isEncrypted
      document.hasTextLayer = inspection.hasTextLayer
      try await index.upsert(document)
    }
  }

  // MARK: - Changing

  /// Renames a document; the title is trimmed and must not be empty.
  public func rename(_ id: DocumentID, to title: String) async throws -> Document {
    try await exclusively {
      var document = try await existing(id)
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { throw LibraryError.emptyTitle }
      let cleanTitle = Self.cleanTitle(trimmed)
      if !document.isDeleted, cleanTitle != document.title {
        let newName = uniqueFileName(for: cleanTitle, in: documentsFolder)
        try move(location(of: document), to: documentsFolder.appendingPathComponent(newName))
        document.fileName = newName
      }
      document.title = cleanTitle
      try await index.upsert(document)
      return document
    }
  }

  /// Marks or unmarks a favourite.
  public func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      document.isFavorite = isFavorite
      try await index.upsert(document)
    }
  }

  /// Replaces a document's tags.
  public func setTags(_ tags: [String], for id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      document.tags = Document.normalizedTags(tags)
      try await index.upsert(document)
    }
  }

  /// Records that a document was opened and the page it showed.
  public func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {
    try await exclusively {
      var document = try await existing(id)
      document.lastOpenedAt = now()
      document.lastPageIndex = max(0, pageIndex)
      try await index.upsert(document)
    }
  }

  /// Records that the file's contents changed (after a save).
  public func recordModified(_ id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      document.modifiedAt = now()
      try await index.upsert(document)
    }
  }

  // MARK: - Deleting

  /// Moves a document to Recently Deleted, where it stays for 30 days.
  public func moveToRecentlyDeleted(_ id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      guard !document.isDeleted else { return }
      let newName = uniqueFileName(for: document.title, in: deletedFolder)
      try move(location(of: document), to: deletedFolder.appendingPathComponent(newName))
      document.fileName = newName
      document.deletedAt = now()
      try await index.upsert(document)
    }
  }

  /// Restores a document from Recently Deleted.
  public func restore(_ id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      guard document.isDeleted else { return }
      let newName = uniqueFileName(for: document.title, in: documentsFolder)
      try move(location(of: document), to: documentsFolder.appendingPathComponent(newName))
      document.fileName = newName
      document.deletedAt = nil
      try await index.upsert(document)
    }
  }

  /// Deletes a document's file and index entry permanently.
  public func deletePermanently(_ id: DocumentID) async throws {
    try await exclusively { try await remove(existing(id)) }
  }

  private func remove(_ document: Document) async throws {
    let url = location(of: document)
    if fileManager.fileExists(atPath: url.path) {
      var coordinationError: NSError?
      var removeError: (any Error)?
      NSFileCoordinator(filePresenter: nil).coordinate(
        writingItemAt: url, options: .forDeleting, error: &coordinationError
      ) {
        do { try FileManager.default.removeItem(at: $0) } catch { removeError = error }
      }
      guard coordinationError == nil, removeError == nil else { throw LibraryError.fileAccessFailed }
    }
    removePreviousVersion(of: document.id)
    try await index.delete(document.id)
  }

  /// Permanently deletes documents that have been in Recently Deleted for 30 days or more.
  public func purgeExpired(now date: Date) async throws -> [DocumentID] {
    try await exclusively {
      let expired = try await index.all().filter { document in
        guard let deletedAt = document.deletedAt else { return false }
        return date.timeIntervalSince(deletedAt) >= Self.retention
      }
      for document in expired { try await remove(document) }
      return expired.map(\.id)
    }
  }

  // MARK: - Reconciling

  /// Brings the index in line with the files: PDFs added outside the app (for example in the Files app) are added,
  /// entries whose file is gone are removed.
  ///
  /// Returns the documents added, which still need inspecting and indexing, and the entries removed,
  /// whose derived data must be removed too.
  public func reconcileWithFiles() async throws -> Reconciliation {
    try await exclusively {
      let entries = try await index.all()
      var removed: [DocumentID] = []
      for document in entries where !fileManager.fileExists(atPath: location(of: document).path) {
        removePreviousVersion(of: document.id)
        try await index.delete(document.id)
        removed.append(document.id)
      }
      let known = Set(entries.filter { !$0.isDeleted }.map(\.fileName))
      let files =
        (try? fileManager.contentsOfDirectory(at: documentsFolder, includingPropertiesForKeys: [.creationDateKey]))
        ?? []
      var added: [Document] = []
      for file in files where file.pathExtension.lowercased() == "pdf" && !known.contains(file.lastPathComponent) {
        let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
        let document = Document(
          title: file.deletingPathExtension().lastPathComponent, fileName: file.lastPathComponent, addedAt: createdAt)
        try await index.upsert(document)
        added.append(document)
      }
      // Files in Recently Deleted without an entry (after the index was rebuilt) come back as deleted
      // documents, deleted now, so they are purged on schedule instead of staying on the device forever.
      let knownDeleted = Set(entries.filter(\.isDeleted).map(\.fileName))
      let deletedFiles =
        (try? fileManager.contentsOfDirectory(at: deletedFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
      for file in deletedFiles
      where file.pathExtension.lowercased() == "pdf" && !knownDeleted.contains(file.lastPathComponent) {
        let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
        try await index.upsert(
          Document(
            title: file.deletingPathExtension().lastPathComponent, fileName: file.lastPathComponent, addedAt: createdAt,
            deletedAt: now()))
      }
      return Reconciliation(added: added, removed: removed)
    }
  }

  // MARK: - Earlier versions (FR-EDIT-008)

  /// How long earlier versions are kept.
  public static let versionRetention: TimeInterval = 30 * 24 * 60 * 60

  /// The most space earlier versions may take.
  ///
  /// It is the lesser of 2 GB and 5% of the free space (`Assumption:`, plan §3 B1). The oldest go first.
  static func versionQuota(available: Int64?) -> Int64 {
    let cap: Int64 = 2_000_000_000
    guard let available else { return cap }
    return min(cap, available / 20)
  }

  /// Where the next save keeps the version it replaces, or `nil` when this library keeps none.
  ///
  /// Each call gives a new place in the document's history. Versions past the retention, and the
  /// oldest ones over the quota, are removed first.
  public func previousVersionURL(for id: DocumentID) async throws -> URL? {
    _ = try await existing(id)
    guard let folder = versionsFolder(of: id) else { return nil }
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    pruneVersions()
    return uniqueVersionURL(in: folder)
  }

  /// A new version's place, named by the time now, a millisecond later if that name is taken.
  private func uniqueVersionURL(in folder: URL) -> URL {
    var date = now()
    var url = folder.appendingPathComponent(Self.versionName(date))
    while fileManager.fileExists(atPath: url.path) {
      date = date.addingTimeInterval(0.001)
      url = folder.appendingPathComponent(Self.versionName(date))
    }
    return url
  }

  /// Whether an earlier version is kept.
  public func hasPreviousVersion(of id: DocumentID) async -> Bool {
    !versionFiles(of: id).isEmpty
  }

  /// The kept earlier versions of a document, newest first.
  public func versions(of id: DocumentID) async -> [DocumentVersion] {
    versionFiles(of: id).map { url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return DocumentVersion(id: url.lastPathComponent, savedAt: Self.savedAt(url), size: size)
    }
  }

  /// Puts back the newest earlier version.
  public func restorePreviousVersion(of id: DocumentID) async throws {
    guard let newest = await versions(of: id).first else { throw LibraryError.notFound }
    try await restore(newest, of: id)
  }

  /// Puts an earlier version back; the current file becomes the newest kept version, so restoring can
  /// itself be undone the same way.
  ///
  /// - Throws: `LibraryError.notFound` when the version isn't kept; `LibraryError.fileAccessFailed`
  ///   when the swap fails, in which case the files are as they were.
  public func restore(_ version: DocumentVersion, of id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      guard let folder = versionsFolder(of: id) else { throw LibraryError.notFound }
      let earlier = folder.appendingPathComponent(version.id)
      guard fileManager.fileExists(atPath: earlier.path) else { throw LibraryError.notFound }
      let kept = uniqueVersionURL(in: folder)
      var coordinationError: NSError?
      var swapError: (any Error)?
      NSFileCoordinator(filePresenter: nil).coordinate(
        writingItemAt: location(of: document), options: .forReplacing, writingItemAt: earlier,
        options: .forReplacing, error: &coordinationError
      ) { current, earlier in
        let fileManager = FileManager.default
        do {
          // The current file is kept first, so nothing is lost whatever happens next.
          try fileManager.copyItem(at: current, to: kept)
        } catch {
          swapError = error
          return
        }
        do {
          _ = try fileManager.replaceItemAt(current, withItemAt: earlier)
        } catch {
          try? fileManager.removeItem(at: kept)
          swapError = error
        }
      }
      guard coordinationError == nil, swapError == nil else { throw LibraryError.fileAccessFailed }
      document.modifiedAt = now()
      try await index.upsert(document)
    }
  }

  /// The space every kept version takes, in bytes.
  public func versionsSize() async -> Int64 {
    allVersionFiles().reduce(0) { total, url in
      total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  /// Deletes every kept version of every document.
  public func deleteAllVersions() async throws {
    guard let root = previousVersionsFolder else { return }
    for item in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
      try fileManager.removeItem(at: item)
    }
  }

  /// A version's file name: the time of the save in milliseconds, zero-padded so names sort by time.
  static func versionName(_ date: Date) -> String {
    String(format: "%015lld.pdf", Int64(date.timeIntervalSince1970 * 1000))
  }

  private static func savedAt(_ url: URL) -> Date {
    let millis = Double(url.deletingPathExtension().lastPathComponent) ?? 0
    return Date(timeIntervalSince1970: millis / 1000)
  }

  private func versionsFolder(of id: DocumentID) -> URL? {
    previousVersionsFolder?.appendingPathComponent(id.rawValue.uuidString, isDirectory: true)
  }

  /// A document's version files, newest first.
  private func versionFiles(of id: DocumentID) -> [URL] {
    guard let folder = versionsFolder(of: id) else { return [] }
    let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return files.filter { $0.pathExtension == "pdf" && Double($0.deletingPathExtension().lastPathComponent) != nil }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
  }

  private func allVersionFiles() -> [URL] {
    guard let root = previousVersionsFolder else { return [] }
    let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return folders.flatMap { folder in
      ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
        .filter { $0.pathExtension == "pdf" }
    }
  }

  /// Removes versions past the retention, then the oldest while the total is over the quota.
  private func pruneVersions() {
    let cutoff = Self.versionName(now().addingTimeInterval(-Self.versionRetention))
    var files = allVersionFiles().sorted { $0.lastPathComponent < $1.lastPathComponent }
    for file in files where file.lastPathComponent < cutoff { try? fileManager.removeItem(at: file) }
    files = files.filter { $0.lastPathComponent >= cutoff }
    let available = previousVersionsFolder.flatMap {
      try? $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
    }
    let quota = Self.versionQuota(available: available)
    var total = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    for file in files where total > quota {
      total -= Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
      try? fileManager.removeItem(at: file)
    }
  }

  /// Moves the single earlier version the first release kept (`<id>.pdf`) into the document's history
  /// (bar item B11): nothing kept before is lost.
  private static func migrateSingleVersions(in root: URL, now: Date) {
    let fileManager = FileManager.default
    let files =
      (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for file in files where file.pathExtension == "pdf" {
      let name = file.deletingPathExtension().lastPathComponent
      guard UUID(uuidString: name) != nil else { continue }
      let folder = root.appendingPathComponent(name, isDirectory: true)
      try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      let saved = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
      try? fileManager.moveItem(at: file, to: folder.appendingPathComponent(versionName(saved)))
    }
  }

  private func removePreviousVersion(of id: DocumentID) {
    guard let folder = versionsFolder(of: id), fileManager.fileExists(atPath: folder.path) else { return }
    try? fileManager.removeItem(at: folder)
  }

  // MARK: - One change at a time

  /// Runs a change once every earlier change has finished, in arrival order.
  ///
  /// Actor isolation alone is not enough: a change reads an entry, may move its file, and writes the
  /// entry back, and each index call is a suspension point. Without this, a second change could read
  /// the same entry in between and later write back its stale copy, undoing a deletion or a rename.
  private func exclusively<T>(_ change: () async throws -> T) async rethrows -> T {
    if isChanging {
      // The finishing change hands over directly, so `isChanging` stays true.
      await withCheckedContinuation { waiting.append($0) }
    } else {
      isChanging = true
    }
    defer {
      if waiting.isEmpty { isChanging = false } else { waiting.removeFirst().resume() }
    }
    return try await change()
  }

  // MARK: - Files

  private func existing(_ id: DocumentID) async throws -> Document {
    guard let document = try await index.document(id) else { throw LibraryError.notFound }
    return document
  }

  private func location(of document: Document) -> URL {
    (document.isDeleted ? deletedFolder : documentsFolder).appendingPathComponent(document.fileName)
  }

  private func write(_ data: Data, to url: URL) throws {
    var coordinationError: NSError?
    var writeError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) {
      do {
        try data.write(to: $0, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch {
        writeError = error
      }
    }
    guard coordinationError == nil, writeError == nil else { throw LibraryError.fileAccessFailed }
  }

  private func move(_ source: URL, to destination: URL) throws {
    var coordinationError: NSError?
    var moveError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing,
      error: &coordinationError
    ) { from, to in
      do { try FileManager.default.moveItem(at: from, to: to) } catch { moveError = error }
    }
    guard coordinationError == nil, moveError == nil else { throw LibraryError.fileAccessFailed }
  }

  private func uniqueFileName(for title: String, in folder: URL) -> String {
    let base = Self.safeFileName(title)
    var candidate = "\(base).pdf"
    var counter = 2
    while fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
      candidate = "\(base) \(counter).pdf"
      counter += 1
    }
    return candidate
  }

  /// A title with surrounding whitespace removed; an empty title becomes "Untitled".
  static func cleanTitle(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled" : trimmed
  }

  /// A file name safe on every Apple file system: no path separators, colons or control characters,
  /// no leading dot, at most 120 characters.
  static func safeFileName(_ title: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
    var name = title.components(separatedBy: forbidden).joined(separator: "-")
    while name.hasPrefix(".") { name.removeFirst() }
    name = String(name.prefix(120)).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "Document" : name
  }
}
