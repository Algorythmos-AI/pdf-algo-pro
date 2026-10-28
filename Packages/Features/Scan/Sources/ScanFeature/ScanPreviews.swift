#if DEBUG
  import CoreGraphics
  import Core
  import Foundation
  import PDFEngine
  import SwiftUI

  // Previews of the scanner for the design pass (PAP-070): ready to scan, and reviewing two
  // made-up pages, at the largest accessibility text size, in dark appearance and right to left.
  // Nothing is saved: the library below keeps nothing.

  /// A library that holds nothing and accepts nothing.
  private struct PreviewLibrary: DocumentLibrary {
    func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Core.Document] { [] }
    func document(withID id: DocumentID) async throws -> Core.Document? { nil }
    func allTags() async throws -> [String] { [] }
    func fileURL(for id: DocumentID) async throws -> URL { throw LibraryError.notFound }
    func document(at url: URL) async throws -> Core.Document? { nil }
    func importDocument(from url: URL) async throws -> Core.Document { throw LibraryError.fileAccessFailed }
    func addDocument(data: Data, title: String) async throws -> Core.Document { throw LibraryError.fileAccessFailed }
    func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws {}
    func rename(_ id: DocumentID, to title: String) async throws -> Core.Document { throw LibraryError.notFound }
    func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws {}
    func setTags(_ tags: [String], for id: DocumentID) async throws {}
    func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {}
    func recordModified(_ id: DocumentID) async throws {}
    func moveToRecentlyDeleted(_ id: DocumentID) async throws {}
    func restore(_ id: DocumentID) async throws {}
    func deletePermanently(_ id: DocumentID) async throws {}
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

  private struct PreviewInspector: PDFInspecting {
    func inspect(_ url: URL) async throws -> PDFInspection { throw LibraryError.notAPDF }
  }

  private struct PreviewIndex: DocumentIndexing {
    func index(_ document: Core.Document, pages: [PageText]) async throws {}
    func remove(_ id: DocumentID) async throws {}
    func prune(keeping ids: Set<DocumentID>) async -> [DocumentID] { [] }
    func pages(of id: DocumentID) async throws -> [PageText] { [] }
    func search(_ query: String, in documents: [Core.Document]) async throws -> [SearchHit] { [] }
  }

  /// A recogniser that finds no text.
  private struct PreviewRecognizer: TextRecognizing {
    func recognizeText(in image: CGImage) async throws -> [RecognizedLine] { [] }
  }

  /// Telemetry that keeps nothing.
  private struct PreviewTelemetry: TelemetryRecording {
    func record(_ event: String) async {}
  }

  /// A blank A4-shaped page with a few grey bars where text would be.
  private func samplePage() -> CGImage? {
    let width = 420
    let height = 594
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(gray: 0.7, alpha: 1)
    for line in 0..<12 {
      context.fill(CGRect(x: 40, y: height - 80 - line * 32, width: line % 4 == 3 ? 200 : 340, height: 12))
    }
    return context.makeImage()
  }

  /// The scanner, ready or reviewing pages.
  private struct ScanPreview: View {
    let reviewing: Bool
    @State private var model: ScanModel

    init(reviewing: Bool = false) {
      self.reviewing = reviewing
      let library = PreviewLibrary()
      let recognizer = PreviewRecognizer()
      _model = State(
        initialValue: ScanModel(
          intake: DocumentIntake(library: library, inspector: PreviewInspector(), index: PreviewIndex()),
          builder: SearchablePDFBuilder(recognizer: recognizer), telemetry: PreviewTelemetry(),
          onFinish: { _ in }))
    }

    var body: some View {
      ScanView(model: model)
        .task {
          guard reviewing else { return }
          await model.review([samplePage(), samplePage()].compactMap(\.self))
        }
    }
  }

  #Preview("Ready") { ScanPreview() }
  #Preview("Ready, largest text") { ScanPreview().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Ready, dark") { ScanPreview().preferredColorScheme(.dark) }
  #Preview("Ready, right to left") { ScanPreview().environment(\.layoutDirection, .rightToLeft) }

  #Preview("Reviewing") { ScanPreview(reviewing: true) }
  #Preview("Reviewing, largest text") {
    ScanPreview(reviewing: true).environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("Reviewing, dark") { ScanPreview(reviewing: true).preferredColorScheme(.dark) }
  #Preview("Reviewing, right to left") {
    ScanPreview(reviewing: true).environment(\.layoutDirection, .rightToLeft)
  }
#endif
