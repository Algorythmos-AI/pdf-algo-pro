import Core
import Foundation

/// The library: PDFs as real files in a folder the user can see in the Files app, plus the index
/// (ADR-0005, ADR-0006). Every file operation is coordinated and atomic, so a crash or a failed
/// write never leaves a half-written document (NFR-REL-002).
public actor FileDocumentLibrary: DocumentLibrary {
  /// How long a document stays in Recently Deleted before it is purged.
  public static let retention: TimeInterval = 30 * 24 * 60 * 60

  private let documentsFolder: URL
  private let deletedFolder: URL
  private let index: LibraryIndex
  private let now: @Sendable () -> Date
  private let fileManager = FileManager.default

  /// Creates a library.
  ///
  /// Folders are created if needed; if that fails, operations report `LibraryError.fileAccessFailed` instead of
  /// stopping the app.
  ///
  /// - Parameters:
  ///   - documentsFolder: Where documents live; the app passes its Documents folder, shown in Files.
  ///   - deletedFolder: Where Recently Deleted keeps files; not shown in Files.
  ///   - index: The metadata index.
  ///   - now: The clock, injected so tests never wait.
  public init(
    documentsFolder: URL, deletedFolder: URL, index: LibraryIndex, now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.documentsFolder = documentsFolder
    self.deletedFolder = deletedFolder
    self.index = index
    self.now = now
    for folder in [documentsFolder, deletedFolder] {
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
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
    return try await add(data, title: url.deletingPathExtension().lastPathComponent)
  }

  /// Adds PDF data (for example a new scan) as a document.
  public func addDocument(data: Data, title: String) async throws -> Document {
    try await add(data, title: title)
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
    var document = try await existing(id)
    document.pageCount = inspection.pageCount
    document.isEncrypted = inspection.isEncrypted
    document.hasTextLayer = inspection.hasTextLayer
    try await index.upsert(document)
  }

  // MARK: - Changing

  /// Renames a document; the title is trimmed and must not be empty.
  public func rename(_ id: DocumentID, to title: String) async throws -> Document {
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

  /// Marks or unmarks a favourite.
  public func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws {
    var document = try await existing(id)
    document.isFavorite = isFavorite
    try await index.upsert(document)
  }

  /// Replaces a document's tags.
  public func setTags(_ tags: [String], for id: DocumentID) async throws {
    var document = try await existing(id)
    document.tags = Document.normalizedTags(tags)
    try await index.upsert(document)
  }

  /// Records that a document was opened and the page it showed.
  public func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {
    var document = try await existing(id)
    document.lastOpenedAt = now()
    document.lastPageIndex = max(0, pageIndex)
    try await index.upsert(document)
  }

  /// Records that the file's contents changed (after a save).
  public func recordModified(_ id: DocumentID) async throws {
    var document = try await existing(id)
    document.modifiedAt = now()
    try await index.upsert(document)
  }

  // MARK: - Deleting

  /// Moves a document to Recently Deleted, where it stays for 30 days.
  public func moveToRecentlyDeleted(_ id: DocumentID) async throws {
    var document = try await existing(id)
    guard !document.isDeleted else { return }
    let newName = uniqueFileName(for: document.title, in: deletedFolder)
    try move(location(of: document), to: deletedFolder.appendingPathComponent(newName))
    document.fileName = newName
    document.deletedAt = now()
    try await index.upsert(document)
  }

  /// Restores a document from Recently Deleted.
  public func restore(_ id: DocumentID) async throws {
    var document = try await existing(id)
    guard document.isDeleted else { return }
    let newName = uniqueFileName(for: document.title, in: documentsFolder)
    try move(location(of: document), to: documentsFolder.appendingPathComponent(newName))
    document.fileName = newName
    document.deletedAt = nil
    try await index.upsert(document)
  }

  /// Deletes a document's file and index entry permanently.
  public func deletePermanently(_ id: DocumentID) async throws {
    let document = try await existing(id)
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
    try await index.delete(id)
  }

  /// Permanently deletes documents that have been in Recently Deleted for 30 days or more.
  public func purgeExpired(now date: Date) async throws -> [DocumentID] {
    let expired = try await index.all().filter { document in
      guard let deletedAt = document.deletedAt else { return false }
      return date.timeIntervalSince(deletedAt) >= Self.retention
    }
    for document in expired { try await deletePermanently(document.id) }
    return expired.map(\.id)
  }

  // MARK: - Reconciling

  /// Brings the index in line with the files: PDFs added outside the app (for example in the Files app) are added,
  /// entries whose file is gone are removed.
  ///
  /// Returns the documents added, which still need inspecting and indexing.
  public func reconcileWithFiles() async throws -> [Document] {
    let entries = try await index.all()
    for document in entries where !fileManager.fileExists(atPath: location(of: document).path) {
      try await index.delete(document.id)
    }
    let known = Set(entries.filter { !$0.isDeleted }.map(\.fileName))
    let files =
      (try? fileManager.contentsOfDirectory(at: documentsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
    var added: [Document] = []
    for file in files where file.pathExtension.lowercased() == "pdf" && !known.contains(file.lastPathComponent) {
      let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
      let document = Document(
        title: file.deletingPathExtension().lastPathComponent, fileName: file.lastPathComponent, addedAt: createdAt)
      try await index.upsert(document)
      added.append(document)
    }
    return added
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
