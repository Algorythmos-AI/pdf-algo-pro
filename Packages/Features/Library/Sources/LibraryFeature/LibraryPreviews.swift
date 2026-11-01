#if DEBUG
  import Core
  import Foundation
  import SwiftUI

  // Previews of Home and the document list for the design pass (PAP-070): empty and with made-up
  // documents, at the largest accessibility text size, in dark appearance and right to left.
  // Thumbnails are blank: the documents have no files.

  /// A library held in memory, with no files: enough for the screens to list what it holds.
  private actor PreviewLibrary: DocumentLibrary {
    private var stored: [DocumentID: Document]

    init(_ documents: [Document]) {
      stored = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
    }

    func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Document] {
      sort.sorted(stored.values.filter(section.contains))
    }
    func document(withID id: DocumentID) async throws -> Document? { stored[id] }
    func allTags() async throws -> [String] {
      Document.normalizedTags(stored.values.filter { !$0.isDeleted }.flatMap(\.tags))
    }
    func fileURL(for id: DocumentID) async throws -> URL { throw LibraryError.notFound }
    func document(at url: URL) async throws -> Document? { nil }
    func importDocument(from url: URL) async throws -> Document { throw LibraryError.fileAccessFailed }
    func addDocument(data: Data, title: String) async throws -> Document { throw LibraryError.fileAccessFailed }
    func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws {}
    func rename(_ id: DocumentID, to title: String) async throws -> Document {
      guard var document = stored[id] else { throw LibraryError.notFound }
      document.title = title
      stored[id] = document
      return document
    }
    func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws { stored[id]?.isFavorite = isFavorite }
    func setTags(_ tags: [String], for id: DocumentID) async throws { stored[id]?.tags = tags }
    func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {}
    func resetReadingPosition(_ id: DocumentID) async throws {}
    func recordModified(_ id: DocumentID) async throws {}
    func moveToRecentlyDeleted(_ id: DocumentID) async throws { stored[id]?.deletedAt = Date() }
    func restore(_ id: DocumentID) async throws { stored[id]?.deletedAt = nil }
    func deletePermanently(_ id: DocumentID) async throws { stored[id] = nil }
    func purgeExpired(now: Date) async throws -> [DocumentID] { [] }
    func reconcileWithFiles() async throws -> Reconciliation { Reconciliation() }
    func previousVersionURL(for id: DocumentID) async throws -> URL? { nil }
    func hasPreviousVersion(of id: DocumentID) async -> Bool { false }
    func restorePreviousVersion(of id: DocumentID) async throws { throw LibraryError.notFound }
    func versions(of id: DocumentID) async -> [DocumentVersion] { [] }
    func restore(_ version: DocumentVersion, of id: DocumentID) async throws { throw LibraryError.notFound }
    func versionsSize() async -> Int64 { 0 }
    func deleteAllVersions() async throws {}
  }

  /// An inspector that is never reached: the previews import nothing.
  private struct PreviewInspector: PDFInspecting {
    func inspect(_ url: URL) async throws -> PDFInspection { throw LibraryError.notAPDF }
  }

  /// A search index that finds titles only.
  private struct PreviewIndex: DocumentIndexing {
    func index(_ document: Document, pages: [PageText]) async throws {}
    func remove(_ id: DocumentID) async throws {}
    func prune(keeping ids: Set<DocumentID>) async -> [DocumentID] { [] }
    func pages(of id: DocumentID) async throws -> [PageText] { [] }
    func search(_ query: String, in documents: [Document]) async throws -> [SearchHit] {
      documents.filter { $0.title.localizedCaseInsensitiveContains(query) }
        .map { SearchHit(documentID: $0.id, pageIndex: nil, snippet: nil) }
    }
  }

  /// Settings held in memory, so a preview never touches the app's own.
  private final class PreviewSettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings = AppSettings(hasCompletedOnboarding: true)

    func load() -> AppSettings { lock.withLock { settings } }

    func save(_ settings: AppSettings) { lock.withLock { self.settings = settings } }
  }

  /// Telemetry that keeps nothing.
  private struct PreviewTelemetry: TelemetryRecording {
    func record(_ event: String) async {}
  }

  /// Made-up documents: titles, tags and dates only.
  private let sampleDocuments: [Document] = {
    let day: TimeInterval = 86_400
    let now = Date()
    return [
      Document(
        title: "Lease renewal", fileName: "lease.pdf", addedAt: now - 9 * day, lastOpenedAt: now - day, pageCount: 6,
        isFavorite: true, tags: ["Home"], hasTextLayer: true),
      Document(
        title: "Electricity bill, September", fileName: "bill.pdf", addedAt: now - 20 * day,
        lastOpenedAt: now - 3 * day, pageCount: 2, tags: ["Bills"], hasTextLayer: true),
      Document(title: "Scan 12 Oct 2026", fileName: "scan.pdf", addedAt: now - 16 * day, pageCount: 1),
      Document(
        title: "Conference programme", fileName: "programme.pdf", addedAt: now - 30 * day, pageCount: 24,
        hasTextLayer: true),
    ]
  }()

  /// The library over the given documents, on Home or on one of its sections.
  private struct LibraryPreview: View {
    let section: LibrarySection?
    @State private var model: LibraryModel

    init(documents: [Document] = [], section: LibrarySection? = nil) {
      self.section = section
      let library = PreviewLibrary(documents)
      let index = PreviewIndex()
      _model = State(
        initialValue: LibraryModel(
          library: library, intake: DocumentIntake(library: library, inspector: PreviewInspector(), index: index),
          index: index, settings: PreviewSettingsStore(), telemetry: PreviewTelemetry()))
    }

    var body: some View {
      LibraryView(model: model, onScan: {}, onSettings: {}) { _ in EmptyView() }
        .task {
          guard let section else { return }
          await model.load()
          model.show(section)
        }
    }
  }

  #Preview("Home, empty") { LibraryPreview() }
  #Preview("Home, empty, largest text") { LibraryPreview().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Home, empty, dark") { LibraryPreview().preferredColorScheme(.dark) }

  #Preview("Home") { LibraryPreview(documents: sampleDocuments) }
  #Preview("Home, largest text") {
    LibraryPreview(documents: sampleDocuments).environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("Home, dark") { LibraryPreview(documents: sampleDocuments).preferredColorScheme(.dark) }
  #Preview("Home, right to left") {
    LibraryPreview(documents: sampleDocuments).environment(\.layoutDirection, .rightToLeft)
  }

  #Preview("All documents") { LibraryPreview(documents: sampleDocuments, section: .all) }
  #Preview("All documents, largest text") {
    LibraryPreview(documents: sampleDocuments, section: .all).environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("All documents, dark") {
    LibraryPreview(documents: sampleDocuments, section: .all).preferredColorScheme(.dark)
  }
  #Preview("All documents, right to left") {
    LibraryPreview(documents: sampleDocuments, section: .all).environment(\.layoutDirection, .rightToLeft)
  }

  #Preview("All documents, empty") { LibraryPreview(section: .all) }
  #Preview("Favourites") { LibraryPreview(documents: sampleDocuments, section: .favorites) }
  #Preview("Recently deleted, empty") { LibraryPreview(documents: sampleDocuments, section: .recentlyDeleted) }
#endif
