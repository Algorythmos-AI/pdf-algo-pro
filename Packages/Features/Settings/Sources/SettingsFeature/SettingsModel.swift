import Core
import Foundation
import Observation

/// Settings (FR-AI-009, FR-ONB-003, FR-SET-003).
@MainActor
@Observable
public final class SettingsModel {
  /// The current settings; every change is saved at once.
  public private(set) var settings: AppSettings
  /// Whether "Report a problem" attaches the diagnostics summary; off until the user turns it on.
  public var includesDiagnostics = false

  private let store: any SettingsStoring
  private let diagnostics: () async -> String
  private let onChange: (AppSettings) -> Void

  /// Creates the model.
  ///
  /// - Parameters:
  ///   - store: Where settings are kept.
  ///   - diagnostics: Builds the diagnostics summary (no document content) when the user asks.
  ///   - onChange: Tells the app the settings changed.
  public init(
    store: any SettingsStoring, diagnostics: @escaping () async -> String, onChange: @escaping (AppSettings) -> Void
  ) {
    self.store = store
    self.diagnostics = diagnostics
    self.onChange = onChange
    settings = store.load()
  }

  /// Hides or shows AI features everywhere.
  public var isIntelligenceHidden: Bool {
    get { settings.isIntelligenceHidden }
    set { update { $0.isIntelligenceHidden = newValue } }
  }

  /// The reader's page layout.
  public var readerDisplayMode: ReaderDisplayMode {
    get { settings.readerDisplayMode }
    set { update { $0.readerDisplayMode = newValue } }
  }

  /// Whether an intent personalises the home screen.
  public func isChosen(_ intent: OnboardingIntent) -> Bool {
    settings.intents.contains(intent)
  }

  /// Adds or removes a home-screen intent; the order of choice is kept.
  public func toggle(_ intent: OnboardingIntent) {
    update { settings in
      if let index = settings.intents.firstIndex(of: intent) {
        settings.intents.remove(at: index)
      } else {
        settings.intents.append(intent)
      }
    }
  }

  /// Where problem reports go.
  public static let supportAddress = "info@algorythmos.com.au"

  /// The support email, with the diagnostics summary only when the user chose to include it.
  public func supportEmailURL() async -> URL? {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = Self.supportAddress
    components.queryItems = [
      URLQueryItem(name: "subject", value: "PDF Algo Pro support"),
      URLQueryItem(name: "body", value: await supportReport()),
    ]
    return components.url
  }

  /// The report text, for copying when no email account is set up.
  public func supportReport() async -> String {
    var body = String(localized: "Describe what happened:\n\n", bundle: .module)
    if includesDiagnostics {
      body += "\n\n---\n\(await diagnostics())"
    }
    return body
  }

  private func update(_ change: (inout AppSettings) -> Void) {
    change(&settings)
    store.save(settings)
    onChange(settings)
  }
}
