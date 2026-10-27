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
  private let index: any LibraryStore
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
  ///   - index: The metadata index, a `LibraryIndex` in the app.
  ///   - now: The clock, injected so tests never wait.
  public init(
    documentsFolder: URL, deletedFolder: URL, previousVersionsFolder: URL? = nil, index: any LibraryStore,
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
  ///
  /// A file renamed or moved in the Files app while the app runs is found by its identity, and the
  /// entry follows it (#224). When it can't be found, this throws `LibraryError.notFound` rather than
  /// give the old name, so a save never writes a new file there beside the moved one.
  public func fileURL(for id: DocumentID) async throws -> URL {
    try await exclusively {
      let document = try await existing(id)
      let url = location(of: document)
      guard !document.isDeleted, !fileManager.fileExists(atPath: url.path) else { return url }
      guard let found = try await followMovedFile(of: document) else { throw LibraryError.notFound }
      return location(of: found)
    }
  }

  // MARK: - Adding

  /// The document whose file is at `url`, or `nil` when `url` is not in the library's folder or, for a
  /// file the library tracks, a folder inside it.
  ///
  /// The Files app shows that folder, so a file opened from there is already in the library. A PDF put
  /// at its top level since the library last looked is added in place, not copied. One in a folder
  /// inside it the library doesn't track gives `nil`, so it is imported as a copy, like a file from
  /// anywhere else: folders are not part of the library yet (PAP-030 item 7, PAP-065).
  public func document(at url: URL) async throws -> Document? {
    guard url.isFileURL, let name = libraryName(of: url) else { return nil }
    let file = documentsFolder.appendingPathComponent(name)
    return try await exclusively {
      if let known = try await index.all().first(where: { !$0.isDeleted && $0.fileName == name }) { return known }
      guard !name.contains("/") else { return nil }
      guard file.pathExtension.lowercased() == "pdf", fileManager.fileExists(atPath: file.path) else { return nil }
      let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
      let document = Document(title: file.deletingPathExtension().lastPathComponent, fileName: name, addedAt: createdAt)
      try await index.upsert(document)
      await recordIdentity(of: document)
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
    let url = documentsFolder.appendingPathComponent(fileName)
    try write(data, to: url)
    let document = Document(title: cleanTitle, fileName: fileName, addedAt: now())
    do {
      try await index.upsert(document)
    } catch {
      // Not added after all: the file would otherwise turn up as a new document at the next launch.
      try? fileManager.removeItem(at: url)
      throw error
    }
    await recordIdentity(of: document)
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
  ///
  /// The file is renamed too, in the folder it is in.
  public func rename(_ id: DocumentID, to title: String) async throws -> Document {
    try await exclusively {
      var document = try await existing(id)
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { throw LibraryError.emptyTitle }
      let cleanTitle = Self.cleanTitle(trimmed)
      var moved: Move?
      if !document.isDeleted, cleanTitle != document.title {
        let current = location(of: document)
        let newName = uniqueFileName(for: cleanTitle, in: current.deletingLastPathComponent())
        moved = try move(current, to: current.deletingLastPathComponent().appendingPathComponent(newName))
        document.fileName = Self.replacingLastComponent(of: document.fileName, with: newName)
      }
      document.title = cleanTitle
      try await upsert(document, undoing: moved)
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
      // A save can write a new file in place of the old one, with a new file number.
      await recordIdentity(of: document)
    }
  }

  // MARK: - Deleting

  /// Moves a document to Recently Deleted, where it stays for 30 days.
  ///
  /// A file in a folder inside the library's folder goes into a folder of the same name there, so
  /// restoring it can put it back where it was.
  public func moveToRecentlyDeleted(_ id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      guard !document.isDeleted else { return }
      let target = folder(of: document.fileName, under: deletedFolder)
      let newName = uniqueFileName(for: document.title, in: target.url)
      let moved = try move(location(of: document), to: target.url.appendingPathComponent(newName))
      document.fileName = target.prefix + newName
      document.deletedAt = now()
      try await upsert(document, undoing: moved)
      await recordIdentity(of: document)
    }
  }

  /// Restores a document from Recently Deleted, into the folder it was deleted from.
  ///
  /// That folder is made again if it has gone since; if it can't be, the document comes back at the
  /// top of the library's folder, since a restore must never fail over a folder.
  public func restore(_ id: DocumentID) async throws {
    try await exclusively {
      var document = try await existing(id)
      guard document.isDeleted else { return }
      let target = folder(of: document.fileName, under: documentsFolder)
      let newName = uniqueFileName(for: document.title, in: target.url)
      let moved = try move(location(of: document), to: target.url.appendingPathComponent(newName))
      document.fileName = target.prefix + newName
      document.deletedAt = nil
      try await upsert(document, undoing: moved)
      await recordIdentity(of: document)
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

  /// How long an entry whose file is gone is kept, out of the library, in case the file comes back:
  /// as long as Recently Deleted keeps a deleted document (`retention`), which is also how long its
  /// earlier versions stay (`versionRetention`).
  public static let goneRetention = retention

  /// Brings the index in line with the files: PDFs added outside the app (for example in the Files app) are added,
  /// entries whose file is gone are removed.
  ///
  /// A file renamed or moved in the Files app keeps its entry, with its identifier, tags, favourite,
  /// reading position and earlier versions (#224). Each entry's file is checked against the identity
  /// recorded for it (`FileIdentity`):
  /// - At its name with that identity, or with no identity recorded on this volume, it stays, and its
  ///   identity is recorded (for entries from schema V1, the first time).
  /// - Otherwise, the one file in the library's folder, or a folder inside it, with that identity is
  ///   the entry's, and only the entry's file name changes; so two files that swap names keep their
  ///   own details. Nothing is guessed: with no such file, more than one, or another entry's identity
  ///   pointing at the same file, an entry whose name still has a file keeps it, as before.
  /// - An entry left without a file is reported removed, and kept out of the library for
  ///   `goneRetention` with its identity: if its file comes back in that time, the entry comes back
  ///   with it, reported added so it is indexed again. After that it is deleted.
  ///
  /// Only PDFs at the top level are added. One in a folder inside it that the library doesn't track
  /// is left alone, neither added, marked nor removed: folders are not part of the library yet
  /// (PAP-030 item 7, PAP-065), only followed when a tracked file is moved into one.
  ///
  /// An entry's earlier versions stay when its file is gone, until their 30 days or the quota ends
  /// them.
  ///
  /// Returns the documents added, which still need inspecting and indexing, and the entries removed,
  /// whose derived data must be removed too.
  public func reconcileWithFiles() async throws -> Reconciliation {
    try await exclusively {
      let entries = try await index.all()
      let identities = try await index.fileIdentities()
      func recordedIdentity(of id: DocumentID) -> FileIdentity? {
        identities[id].flatMap(FileIdentity.init(stored:))
      }
      var removed: [DocumentID] = []
      var added: [Document] = []
      var files = pdfFiles(in: documentsFolder)
      // Entries whose file isn't at its name, or whose name has another file.
      var unsettled: [Document] = []
      for document in entries {
        let file = location(of: document)
        let exists = fileManager.fileExists(atPath: file.path)
        if document.isDeleted {
          if !exists {
            try await index.delete(document.id)
            removed.append(document.id)
          }
          continue
        }
        guard exists else {
          unsettled.append(document)
          continue
        }
        let current = FileIdentity.tracking(file)
        if let current, let recorded = recordedIdentity(of: document.id), recorded.isOnSameVolume(as: current),
          !recorded.isSameFile(as: current)
        {
          unsettled.append(document)
          continue
        }
        files[document.fileName] = nil
        if let current, identities[document.id] != current.stored {
          try await index.setFileIdentity(current.stored, for: document.id)
        }
      }
      pruneVersions()

      // Entries gone at an earlier reconciliation look for their file too, until their time is up.
      var wasGone: Set<DocumentID> = []
      var seekers = unsettled
      for (document, goneAt) in try await index.goneEntries() {
        if now().timeIntervalSince(goneAt) >= Self.goneRetention {
          try await index.delete(document.id)
        } else {
          wasGone.insert(document.id)
          seekers.append(document)
        }
      }
      let pool = files.compactMapValues { FileIdentity(of: $0) }
      let candidates = seekers.map { document in
        guard let identity = recordedIdentity(of: document.id) else { return [String]() }
        return pool.filter { identity.isSameFile(as: $0.value) }.map(\.key)
      }
      var taken: Set<String> = []
      var unfound: [Document] = []
      for (document, names) in zip(seekers, candidates) {
        // Only one file has its identity, and no other entry's identity is that file's.
        guard names.count == 1, let name = names.first, candidates.filter({ $0.contains(name) }).count == 1 else {
          if !wasGone.contains(document.id) { unfound.append(document) }
          continue
        }
        var found = document
        found.fileName = name
        try await index.upsert(found)
        if wasGone.contains(document.id) {
          try await index.setGone(nil, for: document.id)
          added.append(found)
        }
        await recordIdentity(of: found)
        taken.insert(name)
      }
      files = files.filter { !taken.contains($0.key) }
      for document in unfound {
        if files.removeValue(forKey: document.fileName) != nil {
          // Its name still has a file, and no other file is its own: it keeps that one.
          await recordIdentity(of: document)
        } else {
          try await index.setGone(now(), for: document.id)
          removed.append(document.id)
        }
      }

      for (name, file) in files.sorted(by: { $0.key < $1.key }) where !name.contains("/") {
        let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
        let title = file.deletingPathExtension().lastPathComponent
        let document = Document(title: title, fileName: name, addedAt: createdAt)
        try await index.upsert(document)
        if let identity = FileIdentity.tracking(file) {
          try await index.setFileIdentity(identity.stored, for: document.id)
        }
        added.append(document)
      }
      // Files in Recently Deleted without an entry (after the index was rebuilt) come back as deleted
      // documents, deleted now, so they are purged on schedule instead of staying on the device forever.
      // They may be in a folder there, kept from the folder they were deleted from.
      let knownDeleted = Set(entries.filter(\.isDeleted).map(\.fileName))
      let deletedFiles = pdfFiles(in: deletedFolder).sorted { $0.key < $1.key }
      for (name, file) in deletedFiles where !knownDeleted.contains(name) {
        let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
        let document = Document(
          title: file.deletingPathExtension().lastPathComponent, fileName: name, addedAt: createdAt,
          deletedAt: now())
        try await index.upsert(document)
        await recordIdentity(of: document)
      }
      return Reconciliation(added: added, removed: removed)
    }
  }

  /// Finds the file of an entry whose file is gone from its name, by its identity, and moves the
  /// entry to it; `nil` when there is no single such file that no entry has.
  private func followMovedFile(of document: Document) async throws -> Document? {
    guard let recorded = try await index.fileIdentities()[document.id].flatMap(FileIdentity.init(stored:)) else {
      return nil
    }
    let claimed = Set(try await index.all().filter { !$0.isDeleted }.map(\.fileName))
    let matches = pdfFiles(in: documentsFolder).filter { name, file in
      guard !claimed.contains(name), let identity = FileIdentity(of: file) else { return false }
      return recorded.isSameFile(as: identity)
    }
    guard matches.count == 1, let name = matches.first?.key else { return nil }
    var found = document
    found.fileName = name
    try await index.upsert(found)
    await recordIdentity(of: found)
    return found
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
      await recordIdentity(of: document)
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

  /// A file move that has happened, so it can be undone.
  private struct Move {
    let source: URL
    let destination: URL
  }

  private func move(_ source: URL, to destination: URL) throws -> Move {
    var coordinationError: NSError?
    var moveError: (any Error)?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(
      writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing,
      error: &coordinationError
    ) { from, to in
      do {
        try FileManager.default.moveItem(at: from, to: to)
        // An open reader's file presenter follows the file (#224).
        coordinator.item(at: from, didMoveTo: to)
      } catch {
        moveError = error
      }
    }
    guard coordinationError == nil, moveError == nil else { throw LibraryError.fileAccessFailed }
    return Move(source: source, destination: destination)
  }

  /// Writes an entry whose file was just moved; when the write fails, the file is moved back first, so
  /// the files still match the index and the change is undone as a whole, as the message says.
  private func upsert(_ document: Document, undoing moved: Move?) async throws {
    do {
      try await index.upsert(document)
    } catch {
      if let moved { _ = try? move(moved.destination, to: moved.source) }
      throw error
    }
  }

  /// Records the identity of a document's file, so the file is found again if the Files app renames
  /// or moves it; the file is marked for tracking, so it has a document identifier.
  ///
  /// A failure only costs that, until the next reconciliation records it.
  private func recordIdentity(of document: Document) async {
    guard let identity = FileIdentity.tracking(location(of: document)) else { return }
    try? await index.setFileIdentity(identity.stored, for: document.id)
  }

  /// The top-level folder iOS puts copies of files other apps hand over in, which is not part of the
  /// library.
  ///
  /// Apple's File System Programming Guide says an app can read and delete files there but not write
  /// to them, and the app imports such a file as a copy, like a file from anywhere else.
  static let inboxFolderName = "Inbox"

  /// Every PDF in `root` and the folders inside it, by path inside `root`, such as `Report.pdf` or
  /// `Work/2026/Report.pdf`.
  ///
  /// Hidden folders, packages, symbolic links to folders and the top-level `Inbox` are not looked in.
  /// Those in folders are only for following tracked files: reconciling adds none of them.
  private func pdfFiles(in root: URL) -> [String: URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .creationDateKey]
    var files: [String: URL] = [:]
    var folders: [(url: URL, prefix: String)] = [(root, "")]
    while let folder = folders.popLast() {
      for item in (try? fileManager.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: keys)) ?? [] {
        let prefix = folder.prefix
        let name = prefix + item.lastPathComponent
        let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory == true {
          let isInbox = prefix.isEmpty && item.lastPathComponent == Self.inboxFolderName
          if values?.isPackage != true, !item.lastPathComponent.hasPrefix("."), !isInbox {
            folders.append((item, name + "/"))
          }
        } else if item.pathExtension.lowercased() == "pdf" {
          files[name] = item
        }
      }
    }
    return files
  }

  /// The path of `url` inside the library's folder, or `nil` when it is elsewhere (or in a folder
  /// `pdfFiles` doesn't look in).
  private func libraryName(of url: URL) -> String? {
    let file = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let folder = documentsFolder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    guard file.count > folder.count, Array(file.prefix(folder.count)) == folder else { return nil }
    let inside = Array(file.dropFirst(folder.count))
    if inside.count > 1 {
      let folders = inside.dropLast()
      guard folders.first != Self.inboxFolderName, !folders.contains(where: { $0.hasPrefix(".") }) else { return nil }
    }
    return inside.joined(separator: "/")
  }

  /// The folder a path such as `Work/Report.pdf` names under `root`, made if needed, with the path's
  /// folder part (`Work/`); `root` and an empty part for a path with no folder, or when the folder
  /// can't be made.
  private func folder(of fileName: String, under root: URL) -> (url: URL, prefix: String) {
    guard let slash = fileName.lastIndex(of: "/") else { return (root, "") }
    let url = root.appendingPathComponent(String(fileName[..<slash]), isDirectory: true)
    do {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
      return (root, "")
    }
    return (url, String(fileName[...slash]))
  }

  /// A path inside the library's folder with its last component replaced: the same folder, a new name.
  static func replacingLastComponent(of fileName: String, with name: String) -> String {
    guard let slash = fileName.lastIndex(of: "/") else { return name }
    return String(fileName[...slash]) + name
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
