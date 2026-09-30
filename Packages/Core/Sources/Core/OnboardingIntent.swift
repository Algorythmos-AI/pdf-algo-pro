import Foundation

/// An answer to the onboarding question "What do you do with PDFs most often?" (FR-ONB-001).
///
/// The order of the cases is the order on screen: the AI-first options lead.
public enum OnboardingIntent: String, CaseIterable, Codable, Sendable, Identifiable {
  /// Ask questions about a document.
  case chatWithPDF
  /// Summarise a document.
  case summarizeDocument
  /// Extract structured data with AI.
  case extractData
  /// Explain a contract (not legal advice).
  case analyzeContract
  /// Edit existing PDF text.
  case editText
  /// Annotate or highlight.
  case annotate
  /// Sign documents.
  case sign
  /// Convert PDF to Word, Excel or PowerPoint.
  case convert
  /// Merge or organise pages.
  case organize
  /// Read or view documents.
  case read
  /// Scan paper to PDF.
  case scan
  /// Show every tool.
  case allTools

  /// The intent's stable identifier.
  public var id: String { rawValue }

  /// Whether this build can do what the intent asks for, so onboarding and Settings offer it.
  ///
  /// An option is left out, not labelled "coming later", until its feature ships (FR-ONB-007); turn it
  /// on here in the pull request that ships the feature.
  public var isOffered: Bool {
    switch self {
    case .editText, .convert: false
    default: true
    }
  }

  /// The options this build offers, in the fixed order (FR-ONB-001, FR-ONB-007).
  public static var offered: [OnboardingIntent] { allCases.filter(\.isOffered) }

  /// Whether the intent is one of the AI-first options, which need document intelligence.
  public var usesIntelligence: Bool {
    switch self {
    case .chatWithPDF, .summarizeDocument, .extractData, .analyzeContract: true
    default: false
    }
  }

  /// The home-screen action this intent puts first (FR-ONB-003).
  public var primaryAction: HomeAction {
    switch self {
    case .chatWithPDF: .openAssistant(.ask)
    case .summarizeDocument: .openAssistant(.summarize)
    case .extractData: .openAssistant(.extract)
    case .analyzeContract: .openAssistant(.explainContract)
    case .scan: .scanDocument
    case .editText, .annotate, .sign, .convert, .organize, .read, .allTools: .importDocument
    }
  }
}

/// The action the home screen offers first, personalised by the onboarding intent.
public enum HomeAction: Hashable, Sendable {
  /// Import a PDF from Files.
  case importDocument
  /// Scan a paper document.
  case scanDocument
  /// Open a document and start an assistant task on it.
  case openAssistant(AssistantTask)

  /// The action for a set of intents: the first chosen intent leads; no choice means import.
  public static func primary(for intents: [OnboardingIntent]) -> HomeAction {
    intents.first?.primaryAction ?? .importDocument
  }
}

/// A task the document assistant performs.
public enum AssistantTask: String, CaseIterable, Codable, Sendable, Identifiable {
  /// Summarise the document with page citations (FR-AI-001).
  case summarize
  /// Answer questions with page citations (FR-AI-002).
  case ask
  /// Extract structured fields (FR-AI-003).
  case extract
  /// Explain a contract's key terms; never legal advice.
  case explainContract

  /// The task's stable identifier.
  public var id: String { rawValue }
}
