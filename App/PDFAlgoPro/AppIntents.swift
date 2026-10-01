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
  /// On-device intelligence and the documents' recognised text, for intents that return results.
  private(set) var intelligence: (any DocumentIntelligence)?
  private(set) var index: (any DocumentIndexing)?
  private var handler: ((Route) -> Void)?
  private var pending: Route?

  /// Connects the running app; a route that arrived first is delivered now.
  func attach(
    library: any DocumentLibrary, intelligence: (any DocumentIntelligence)? = nil,
    index: (any DocumentIndexing)? = nil, handler: @escaping (Route) -> Void
  ) {
    self.library = library
    self.intelligence = intelligence
    self.index = index
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

  /// A summary of a document, made on this device, for Siri and Shortcuts (FR-AI-018).
  ///
  /// The text says it was generated, and names the pages it cites. It throws a message to show when
  /// the summary can't be made: AI hidden or unavailable, the document gone, or no text in it.
  func summary(of id: DocumentID) async throws -> String {
    guard let intelligence, let index, let library else { throw IntentFailure.notReady }
    guard try await library.document(withID: id) != nil else { throw IntentFailure.documentMissing }
    let answer: Answer
    do {
      answer = try await intelligence.summarize(try await index.pages(of: id))
    } catch IntelligenceError.noText {
      throw IntentFailure.noText
    } catch IntelligenceError.unavailable {
      throw IntentFailure.intelligenceUnavailable
    } catch {
      throw IntentFailure.failed
    }
    let pages = Array(Set(answer.citations.map { $0.pageIndex + 1 })).sorted()
    var text = answer.text
    if !pages.isEmpty {
      text += "\n\n" + String(localized: "Pages cited: \(pages.map(String.init).joined(separator: ", "))")
    }
    return text + "\n\n" + String(localized: "Generated on this device. Check important details in the document.")
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

/// Why an intent that returns a result couldn't, in words Siri can say.
nonisolated enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
  case notReady, documentMissing, noText, intelligenceUnavailable, failed

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notReady: "PDF Algo Pro is still starting. Try again in a moment."
    case .documentMissing: "That document is no longer in your library."
    case .noText: "That document has no text to summarise yet. Open it and recognise its text first."
    case .intelligenceUnavailable: "Summaries need Apple Intelligence on this device, and AI features turned on."
    case .failed: "The summary couldn't be made. Try again in the app."
    }
  }
}

/// Summarises a document on this device and returns the summary (FR-AI-018).
///
/// Nothing leaves the device. Because it returns what a document says, it needs the device unlocked (H3).
struct SummarizeDocumentIntent: AppIntent {
  static let title: LocalizedStringResource = "Summarise Document"
  static let description = IntentDescription(
    "Summarises a document from your library on this device, with the pages it draws on.")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "Document")
  var target: DocumentEntity

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    guard let id = DocumentID(string: target.id) else { throw IntentFailure.documentMissing }
    let summary = try await IntentRouter.shared.summary(of: id)
    return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
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
    AppShortcut(
      intent: SummarizeDocumentIntent(),
      phrases: ["Summarise \(\.$target) with \(.applicationName)", "Summarize \(\.$target) with \(.applicationName)"],
      shortTitle: "Summarise Document", systemImageName: "text.append")
  }
}
