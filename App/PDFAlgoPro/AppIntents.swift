import AppIntents
import Core
import Foundation

/// Where App Intents hand routes to the app (ADR-0004: every entry point goes through one router).
///
/// Intents can run before the window exists, so a route that arrives early waits until the app model
/// attaches. Intents only navigate; the user still acts.
///
/// While App Lock is locked, intents return nothing of a document: no summary and no titles (FR-AI-018).
@MainActor
final class IntentRouter {
  static let shared = IntentRouter()

  private(set) var library: (any DocumentLibrary)?
  /// On-device intelligence and the documents' recognised text, for intents that return results.
  private(set) var intelligence: (any DocumentIntelligence)?
  private(set) var index: (any DocumentIndexing)?
  /// Whether App Lock is keeping the library closed until its owner confirms (FR-SET-002).
  private var isLocked: () -> Bool = { false }
  private var handler: ((Route) -> Void)?
  private var pending: Route?
  /// Tells the system to read `suggestedEntities()` again: the only way Siri learns document names.
  private var refreshPhrases: () -> Void = {}
  /// What the system last heard, so that an unchanged library asks nothing of it.
  private var knownVocabulary: [String]?

  /// Connects the running app; a route that arrived first is delivered now.
  func attach(
    library: any DocumentLibrary, intelligence: (any DocumentIntelligence)? = nil,
    index: (any DocumentIndexing)? = nil, isLocked: @escaping () -> Bool,
    refreshPhrases: @escaping () -> Void = { PDFAlgoProShortcuts.updateAppShortcutParameters() },
    handler: @escaping (Route) -> Void
  ) {
    self.library = library
    self.intelligence = intelligence
    self.index = index
    self.isLocked = isLocked
    self.handler = handler
    self.refreshPhrases = refreshPhrases
    knownVocabulary = nil
    if let pending {
      self.pending = nil
      handler(pending)
    }
    Task { await vocabularyMayHaveChanged() }
  }

  /// Tells Siri the document names, at launch and whenever they or App Lock change.
  ///
  /// Without this a phrase with a document in it can never match. While App Lock is locked the list
  /// is empty, so the titles also leave Siri, Spotlight and the Shortcuts app until it is unlocked.
  func vocabularyMayHaveChanged() async {
    let vocabulary = await spokenDocuments().map(\.title)
    guard vocabulary != knownVocabulary else { return }
    knownVocabulary = vocabulary
    refreshPhrases()
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
  /// the summary can't be made: App Lock locked, AI hidden or unavailable, the document gone, or no
  /// text in it.
  func summary(of id: DocumentID) async throws -> String {
    // The intent asks for the device to be unlocked; App Lock is the app's own lock on top (#222).
    guard !isLocked() else { throw IntentFailure.locked }
    guard let intelligence, let index, let library else { throw IntentFailure.notReady }
    guard try await library.document(withID: id) != nil else { throw IntentFailure.documentMissing }
    let answer: Answer
    do {
      answer = try await intelligence.summarize(try await index.pages(of: id))
    } catch IntelligenceError.noText {
      throw IntentFailure.noText
    } catch IntelligenceError.unavailable(let reason) {
      throw reason == .dailyAllowanceUsed ? IntentFailure.allowanceUsed : IntentFailure.unavailable(reason)
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

  /// The documents Siri and Shortcuts may list or find by title: none while App Lock is locked (#222).
  func listedDocuments() async -> [Document] {
    isLocked() ? [] : await documents()
  }

  /// The most recently opened documents, whose names Siri listens for.
  ///
  /// Assumption: the system takes 1,000 phrases from an app, and each document multiplies the phrases
  /// that name one, so 50 documents stay inside that. Validate on a device with a larger library.
  func spokenDocuments() async -> [Document] {
    Array(await listedDocuments().prefix(50))
  }

  /// Documents whose titles fit what was said, closest first; the most recently opened wins a tie.
  ///
  /// Throws while App Lock is locked, so that Siri says why rather than that nothing matched.
  func documents(matching spoken: String) async throws -> [Document] {
    guard !isLocked() else { throw IntentFailure.locked }
    return await documents()
      .enumerated()
      .compactMap { offset, document in
        DocumentTitleMatch.rank(of: document.title, for: spoken).map { (rank: $0, offset: offset, document: document) }
      }
      .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
      .map(\.document)
  }
}

/// How well a title fits a name as Siri heard it, which is rarely how the title is written.
///
/// A spoken "tax return 2025" has to find "Tax-Return_2025 (final)", and "resume" to find "Résumé".
nonisolated enum DocumentTitleMatch {
  /// Words people say before a name and that titles rarely start with, in English and French.
  private static let leadingWords: Set<String> = [
    "a", "an", "my", "the", "l", "la", "le", "les", "ma", "mes", "mon", "un", "une",
  ]

  /// Lower is closer; nil when the title doesn't fit.
  static func rank(of title: String, for spoken: String) -> Int? {
    let titleWords = words(in: title)
    var heard = words(in: spoken)
    while heard.count > 1, leadingWords.contains(heard[0]) { heard.removeFirst() }
    guard !heard.isEmpty else { return nil }
    if titleWords == heard { return 0 }
    if titleWords.starts(with: heard) { return 1 }
    if heard.allSatisfy({ word in titleWords.contains { $0.hasPrefix(word) } }) { return 2 }
    // "budget 2026" for "Budget2026", and the other way round.
    return titleWords.joined().contains(heard.joined()) ? 3 : nil
  }

  private static func words(in text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }
}

/// A library document as Siri, Shortcuts and Spotlight see it (FR-LIB-005).
nonisolated struct DocumentEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Document")
  static let defaultQuery = DocumentEntityQuery()

  let id: String
  let title: String
  /// When it last changed, which tells apart two documents with one title when Siri asks which.
  let modified: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", subtitle: "\(modified)", image: .init(systemName: "doc.text"))
  }

  init(_ document: Document) {
    id = document.id.description
    title = document.title
    modified = document.modifiedAt.formatted(date: .abbreviated, time: .omitted)
  }
}

/// Finds documents by identifier or title for intents.
nonisolated struct DocumentEntityQuery: EntityStringQuery {
  /// The documents with these identifiers, even while App Lock is locked.
  ///
  /// The system already holds them (a saved shortcut), so nothing new is disclosed, and Open Document
  /// still opens the app, where the lock asks first.
  func entities(for identifiers: [String]) async throws -> [DocumentEntity] {
    let wanted = Set(identifiers)
    return await IntentRouter.shared.documents().filter { wanted.contains($0.id.description) }.map(DocumentEntity.init)
  }

  func entities(matching string: String) async throws -> [DocumentEntity] {
    try await IntentRouter.shared.documents(matching: string).map(DocumentEntity.init)
  }

  func suggestedEntities() async throws -> [DocumentEntity] {
    await IntentRouter.shared.spokenDocuments().map(DocumentEntity.init)
  }
}

/// Opens a document in the app.
struct OpenDocumentIntent: OpenIntent {
  static let title: LocalizedStringResource = "Open Document"
  static let description = IntentDescription("Opens a document from your PDF Algo Pro library.")
  static let openAppWhenRun = true
  // Siri on a locked phone would otherwise answer with titles when it asks which document.
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "Document", requestValueDialog: "Which document?")
  var target: DocumentEntity

  static var parameterSummary: some ParameterSummary { Summary("Open \(\.$target)") }

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
nonisolated enum IntentFailure: Error, Equatable, CustomLocalizedStringResourceConvertible {
  case notReady, locked, documentMissing, noText, allowanceUsed, failed
  case unavailable(IntelligenceUnavailableReason)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notReady: "PDF Algo Pro is still starting. Try again in a moment."
    case .locked: "PDF Algo Pro is locked. Open it and unlock it, then try again."
    case .documentMissing: "That document is no longer in your library."
    case .noText: "That document has no text to summarise yet. Open it and recognise its text first."
    case .unavailable(.hiddenBySettings): "AI features are turned off in PDF Algo Pro. Turn them on in its Settings."
    case .unavailable(.appleIntelligenceNotEnabled): "Summaries need Apple Intelligence. Turn it on in Settings."
    case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready on this device. Try again later."
    case .unavailable(.requestTooLarge): "That document is too long to summarise here."
    case .unavailable: "Summaries need Apple Intelligence on this device, and AI features turned on."
    case .allowanceUsed: "You’ve used today’s free summaries. They start again tomorrow, and Pro has no daily limit."
    case .failed: "The summary couldn't be made. Try again in the app."
    }
  }
}

/// Summarises a document on this device and returns the summary (FR-AI-018).
///
/// Nothing leaves the device. Because it returns what a document says, it needs the device unlocked (H3),
/// and with App Lock on, the app unlocked too (FR-AI-018).
struct SummarizeDocumentIntent: AppIntent {
  static let title: LocalizedStringResource = "Summarise Document"
  static let description = IntentDescription(
    "Summarises a document from your library on this device, with the pages it draws on.")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: "Document", requestValueDialog: "Which document?")
  var target: DocumentEntity

  static var parameterSummary: some ParameterSummary { Summary("Summarise \(\.$target)") }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    guard let id = DocumentID(string: target.id) else { throw IntentFailure.documentMissing }
    let summary = try await IntentRouter.shared.summary(of: id)
    return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
  }
}

/// Phrases for Siri and Spotlight.
///
/// French ones are in AppShortcuts.xcstrings; `invariants.py` checks both.
///
/// The phrases with no document in them are how a title Siri doesn't know is reached: it asks which.
nonisolated struct PDFAlgoProShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ScanDocumentIntent(),
      phrases: [
        "Scan a document with \(.applicationName)", "Scan with \(.applicationName)", "Scan in \(.applicationName)",
      ],
      shortTitle: "Scan Document", systemImageName: "doc.viewfinder")
    AppShortcut(
      intent: OpenDocumentIntent(),
      phrases: [
        "Open \(\.$target) in \(.applicationName)", "Open \(\.$target) with \(.applicationName)",
        "Open my \(\.$target) in \(.applicationName)", "Show \(\.$target) in \(.applicationName)",
        "Open a document in \(.applicationName)",
      ],
      shortTitle: "Open Document", systemImageName: "doc.text")
    AppShortcut(
      intent: SummarizeDocumentIntent(),
      phrases: [
        "Summarise \(\.$target) with \(.applicationName)", "Summarize \(\.$target) with \(.applicationName)",
        "Summarise \(\.$target) in \(.applicationName)", "Summarize \(\.$target) in \(.applicationName)",
        "Summarise my \(\.$target) in \(.applicationName)", "Summarize my \(\.$target) in \(.applicationName)",
        "Summarise a document with \(.applicationName)", "Summarize a document with \(.applicationName)",
      ],
      shortTitle: "Summarise Document", systemImageName: "text.append")
  }
}
