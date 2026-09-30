import Core
import CoreGraphics
import Foundation

/// An in-memory library for tests and previews. Files are written to a temporary folder.
public actor FakeDocumentLibrary: DocumentLibrary {
  /// The documents, keyed by identifier.
  public private(set) var documents: [DocumentID: Document] = [:]
  /// The folder that holds the fake's files.
  public let folder: URL
  private let now: @Sendable () -> Date
  /// When set, the next call throws this error.
  public var nextError: LibraryError?

  /// Creates an empty library with its own temporary folder.
  public init(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }) {
    self.now = now
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("FakeLibrary-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  /// Adds a document directly, with optional file contents.
  @discardableResult
  public func seed(_ document: Document, data: Data = Data("%PDF-1.7\n".utf8)) -> Document {
    documents[document.id] = document
    try? data.write(to: folder.appendingPathComponent(document.fileName))
    return document
  }

  /// Makes the next call throw an error.
  public func failNext(with error: LibraryError) {
    nextError = error
  }

  private func check() throws {
    if let error = nextError {
      nextError = nil
      throw error
    }
  }

  private func existing(_ id: DocumentID) throws -> Document {
    guard let document = documents[id] else { throw LibraryError.notFound }
    return document
  }

  /// Documents in a section, in the given order.
  public func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Document] {
    try check()
    return sort.sorted(documents.values.filter(section.contains))
  }

  /// One document, or `nil` when it does not exist.
  public func document(withID id: DocumentID) async throws -> Document? {
    try check()
    return documents[id]
  }

  /// Every tag in use, sorted.
  public func allTags() async throws -> [String] {
    try check()
    return Document.normalizedTags(documents.values.filter { !$0.isDeleted }.flatMap(\.tags))
  }

  /// The file URL of a document, for reading and coordinated writing.
  public func fileURL(for id: DocumentID) async throws -> URL {
    try check()
    return folder.appendingPathComponent(try existing(id).fileName)
  }

  /// Copies a PDF into the library, reading it with coordinated, security-scoped access.
  public func importDocument(from url: URL) async throws -> Document {
    try check()
    let data = try Data(contentsOf: url)
    guard data.starts(with: Data("%PDF-".utf8)) else { throw LibraryError.notAPDF }
    return seed(
      Document(title: url.deletingPathExtension().lastPathComponent, fileName: "\(UUID()).pdf", addedAt: now()),
      data: data)
  }

  /// Adds PDF data (for example a new scan) as a document.
  public func addDocument(data: Data, title: String) async throws -> Document {
    try check()
    return seed(Document(title: title, fileName: "\(UUID()).pdf", addedAt: now()), data: data)
  }

  /// Records what inspection learnt about a document's file.
  public func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws {
    try check()
    var document = try existing(id)
    document.pageCount = inspection.pageCount
    document.isEncrypted = inspection.isEncrypted
    document.hasTextLayer = inspection.hasTextLayer
    documents[id] = document
  }

  /// Renames a document; the title is trimmed and must not be empty.
  public func rename(_ id: DocumentID, to title: String) async throws -> Document {
    try check()
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw LibraryError.emptyTitle }
    var document = try existing(id)
    document.title = trimmed
    documents[id] = document
    return document
  }

  /// Marks or unmarks a favourite.
  public func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws {
    try check()
    documents[id]?.isFavorite = isFavorite
  }

  /// Replaces a document's tags.
  public func setTags(_ tags: [String], for id: DocumentID) async throws {
    try check()
    documents[id]?.tags = Document.normalizedTags(tags)
  }

  /// Records that a document was opened and the page it showed.
  public func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {
    try check()
    documents[id]?.lastOpenedAt = now()
    documents[id]?.lastPageIndex = pageIndex
  }

  /// Records that the file's contents changed (after a save).
  public func recordModified(_ id: DocumentID) async throws {
    try check()
    documents[id]?.modifiedAt = now()
  }

  /// Moves a document to Recently Deleted, where it stays for 30 days.
  public func moveToRecentlyDeleted(_ id: DocumentID) async throws {
    try check()
    documents[id]?.deletedAt = now()
  }

  /// Restores a document from Recently Deleted.
  public func restore(_ id: DocumentID) async throws {
    try check()
    documents[id]?.deletedAt = nil
  }

  /// Deletes a document's file and index entry permanently.
  public func deletePermanently(_ id: DocumentID) async throws {
    try check()
    documents[id] = nil
  }

  /// Permanently deletes documents that have been in Recently Deleted for 30 days or more.
  public func purgeExpired(now: Date) async throws -> [DocumentID] {
    try check()
    let expired = documents.values.filter { ($0.deletedAt.map { now.timeIntervalSince($0) >= 30 * 86_400 }) ?? false }
    for document in expired { documents[document.id] = nil }
    return expired.map(\.id)
  }

  /// Brings the index in line with the files: PDFs added outside the app (for example in the Files app) are added,
  /// entries whose file is gone are removed.
  ///
  /// Returns what changed; this fake never finds new files.
  public func reconcileWithFiles() async throws -> Reconciliation {
    try check()
    return Reconciliation()
  }
}

/// An inspector that returns fixed results, or reads the page texts a test stored for a URL.
public struct FakeInspector: PDFInspecting {
  /// The result for every file, unless `failure` is set.
  public let result: PDFInspection
  /// When `true`, inspection throws `LibraryError.notAPDF`.
  public let fails: Bool

  /// Creates an inspector.
  public init(
    result: PDFInspection = PDFInspection(
      pageCount: 1, isEncrypted: false, pages: [PageText(pageIndex: 0, text: "Hello")]), fails: Bool = false
  ) {
    self.result = result
    self.fails = fails
  }

  /// Inspects the PDF at a URL.
  ///
  /// - Throws: `LibraryError.notAPDF` when the file cannot be read as a PDF.
  public func inspect(_ url: URL) async throws -> PDFInspection {
    if fails { throw LibraryError.notAPDF }
    return result
  }
}

/// An in-memory search index that matches case-insensitive substrings.
public actor FakeIndex: DocumentIndexing {
  /// Page texts by document.
  public private(set) var stored: [DocumentID: [PageText]] = [:]
  /// Documents removed, in order.
  public private(set) var removed: [DocumentID] = []
  /// When `true`, searches throw, as a damaged index would.
  public private(set) var failsSearches = false

  /// Creates an empty index.
  public init() {}

  /// Makes searches fail or succeed.
  public func failSearches(_ fails: Bool) {
    failsSearches = fails
  }

  /// Stores page texts directly.
  public func seed(_ id: DocumentID, pages: [PageText]) {
    stored[id] = pages
  }

  /// Adds or replaces a document in the index (and in Spotlight, FR-LIB-005).
  public func index(_ document: Document, pages: [PageText]) async throws {
    stored[document.id] = pages
  }

  /// Removes a document and its derived text (FR-LIB-006).
  public func remove(_ id: DocumentID) async throws {
    stored[id] = nil
    removed.append(id)
  }

  /// Removes the stored text of every document not in `ids`.
  public func prune(keeping ids: Set<DocumentID>) async -> [DocumentID] {
    let stale = stored.keys.filter { !ids.contains($0) }
    for id in stale {
      stored[id] = nil
      removed.append(id)
    }
    return Array(stale)
  }

  /// The stored page texts of a document, for intelligence and reading aloud.
  public func pages(of id: DocumentID) async throws -> [PageText] {
    stored[id] ?? []
  }

  /// Documents matching a query, best first.
  public func search(_ query: String, in documents: [Document]) async throws -> [SearchHit] {
    if failsSearches { throw LibraryError.fileAccessFailed }
    return documents.compactMap { document in
      if document.title.localizedCaseInsensitiveContains(query) {
        return SearchHit(documentID: document.id, pageIndex: nil, snippet: nil)
      }
      guard let page = stored[document.id]?.first(where: { $0.text.localizedCaseInsensitiveContains(query) }) else {
        return nil
      }
      return SearchHit(documentID: document.id, pageIndex: page.pageIndex, snippet: page.text)
    }
  }
}

/// Document intelligence with scripted answers.
public actor FakeIntelligence: DocumentIntelligence {
  /// What `availability()` returns.
  public var currentAvailability: IntelligenceAvailability
  /// The answer every text task returns.
  public var answer: Answer
  /// The extraction `extractFields` returns.
  public var extraction: Extraction
  /// When set, every task throws this error.
  public var error: IntelligenceError?
  /// Questions asked, in order.
  public private(set) var questions: [String] = []
  /// The tasks run, in order.
  public private(set) var tasks: [AssistantTask] = []

  /// Creates an assistant that answers from page 1 on device.
  public init(
    availability: IntelligenceAvailability = .available(.onDevice),
    answer: Answer = Answer(
      text: "The document is about testing.", citations: [Citation(pageIndex: 0, quote: "testing")], tier: .onDevice,
      isGrounded: true),
    extraction: Extraction = Extraction(
      fields: [ExtractedField(key: "invoiceNumber", value: "INV-1", pageIndex: 0)], tier: .onDevice)
  ) {
    currentAvailability = availability
    self.answer = answer
    self.extraction = extraction
  }

  /// Changes what the fake reports and returns.
  public func configure(
    availability: IntelligenceAvailability? = nil, answer: Answer? = nil, error: IntelligenceError? = nil
  ) {
    if let availability { currentAvailability = availability }
    if let answer { self.answer = answer }
    self.error = error
  }

  /// Whether a tier can run now.
  public func availability() async -> IntelligenceAvailability { currentAvailability }

  /// Summarises the pages, citing the pages each point draws on.
  public func summarize(_ pages: [PageText]) async throws -> Answer {
    tasks.append(.summarize)
    if let error { throw error }
    return answer
  }

  /// Answers a question from the pages, or returns a not-found answer.
  public func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
    tasks.append(.ask)
    questions.append(question)
    if let error { throw error }
    return answer
  }

  /// Extracts structured fields and verifies each value against the text.
  public func extractFields(from pages: [PageText]) async throws -> Extraction {
    tasks.append(.extract)
    if let error { throw error }
    return extraction
  }

  /// Explains a contract's key terms in plain language.
  ///
  /// The UI adds the not-legal-advice disclosure.
  public func explainContract(_ pages: [PageText]) async throws -> Answer {
    tasks.append(.explainContract)
    if let error { throw error }
    return answer
  }
}

/// A recogniser that returns the same lines for every image.
public struct FakeRecognizer: TextRecognizing {
  /// The lines returned for each image.
  public let lines: [RecognizedLine]

  /// Creates a recogniser.
  public init(
    lines: [RecognizedLine] = [
      RecognizedLine(text: "Recognised text", bounds: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.05), confidence: 0.9)
    ]
  ) {
    self.lines = lines
  }

  /// Recognises the lines of text in an image.
  public func recognizeText(in image: CGImage) async throws -> [RecognizedLine] { lines }
}

/// Settings held in memory.
public final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var settings: AppSettings

  /// Creates a store with initial settings.
  public init(_ settings: AppSettings = AppSettings()) {
    self.settings = settings
  }

  /// The current settings.
  public func load() -> AppSettings {
    lock.withLock { settings }
  }

  /// Replaces the settings.
  public func save(_ settings: AppSettings) {
    lock.withLock { self.settings = settings }
  }
}

/// Telemetry that remembers the events it was given.
public actor RecordingTelemetry: TelemetryRecording {
  /// Events recorded, in order.
  public private(set) var events: [String] = []

  /// Creates an empty recorder.
  public init() {}

  /// Records an event by its `domain.object.action` name; unknown names are dropped.
  public func record(_ event: String) async {
    events.append(event)
  }
}

/// Signatures kept in memory, for tests and previews.
public actor InMemorySignatureStore: SignatureStoring {
  private var stored: [SavedSignature] = []
  /// When set, the next call throws this error.
  public var nextError: SignatureStoreError?

  /// Creates an empty store.
  public init() {}

  /// Makes the next call throw an error.
  public func failNext(with error: SignatureStoreError) {
    nextError = error
  }

  private func check() throws {
    if let error = nextError {
      nextError = nil
      throw error
    }
  }

  /// Every saved signature, oldest first.
  public func signatures() async throws -> [SavedSignature] {
    try check()
    return stored.sorted { $0.createdAt < $1.createdAt }
  }

  /// Saves a signature, replacing one with the same identity.
  public func save(_ signature: SavedSignature) async throws {
    try check()
    stored.removeAll { $0.id == signature.id }
    stored.append(signature)
  }

  /// Deletes a signature.
  public func delete(_ id: UUID) async throws {
    try check()
    stored.removeAll { $0.id == id }
  }
}
