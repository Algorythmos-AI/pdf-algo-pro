import AppIntents
import Core
import Foundation

/// Where App Intents hand routes to the app (ADR-0004: every entry point goes through one router).
///
/// Intents can run before the window exists, so a route that arrives early waits until the app model
/// attaches. Intents only navigate; the user still acts.
@MainActor
final class IntentRouter {
  static let shared = IntentRouter()

  private(set) var library: (any DocumentLibrary)?
  private var handler: ((Route) -> Void)?
  private var pending: Route?

  /// Connects the running app; a route that arrived first is delivered now.
  func attach(library: any DocumentLibrary, handler: @escaping (Route) -> Void) {
    self.library = library
    self.handler = handler
    if let pending {
      self.pending = nil
      handler(pending)
    }
  }

  /// Navigates, or keeps the route until the app attaches.
  func open(_ route: Route) {
    if let handler {
      handler(route)
    } else {
      pending = route
    }
  }

  /// The documents intents can refer to: everything not in Recently Deleted.
  func documents() async -> [Document] {
    (try? await library?.documents(in: .all, sortedBy: .recentlyOpened)) ?? []
  }
}

/// A library document as Siri, Shortcuts and Spotlight see it (FR-LIB-005).
nonisolated struct DocumentEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Document")
  static let defaultQuery = DocumentEntityQuery()

  let id: String
  let title: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }

  init(_ document: Document) {
    id = document.id.description
    title = document.title
  }
}

/// Finds documents by identifier or title for intents.
nonisolated struct DocumentEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [DocumentEntity] {
    let wanted = Set(identifiers)
    return await IntentRouter.shared.documents().filter { wanted.contains($0.id.description) }.map(DocumentEntity.init)
  }

  func entities(matching string: String) async throws -> [DocumentEntity] {
    await IntentRouter.shared.documents().filter { $0.title.localizedStandardContains(string) }.map(DocumentEntity.init)
  }

  func suggestedEntities() async throws -> [DocumentEntity] {
    Array(await IntentRouter.shared.documents().prefix(10)).map(DocumentEntity.init)
  }
}

/// Opens a document in the app.
struct OpenDocumentIntent: OpenIntent {
  static let title: LocalizedStringResource = "Open Document"
  static let description = IntentDescription("Opens a document from your PDF Algo Pro library.")

  @Parameter(title: "Document")
  var target: DocumentEntity

  @MainActor
  func perform() async throws -> some IntentResult {
    if let id = DocumentID(string: target.id) {
      IntentRouter.shared.open(.document(id, pageIndex: nil))
    }
    return .result()
  }
}

/// Opens the scanner; the user still captures the pages.
nonisolated struct ScanDocumentIntent: AppIntent {
  static let title: LocalizedStringResource = "Scan Document"
  static let description = IntentDescription("Opens the scanner to make a searchable PDF on this device.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    IntentRouter.shared.open(.scan)
    return .result()
  }
}

/// Phrases for Siri and Spotlight.
nonisolated struct PDFAlgoProShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ScanDocumentIntent(),
      phrases: ["Scan a document with \(.applicationName)", "Scan with \(.applicationName)"],
      shortTitle: "Scan Document", systemImageName: "doc.viewfinder")
    AppShortcut(
      intent: OpenDocumentIntent(), phrases: ["Open \(\.$target) in \(.applicationName)"], shortTitle: "Open Document",
      systemImageName: "doc.text")
  }
}
