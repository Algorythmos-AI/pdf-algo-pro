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
  /// The space earlier versions of documents take, in bytes; `nil` until measured (FR-EDIT-008).
  public private(set) var versionsSize: Int64?
  /// Whether "Delete version history" is asking for confirmation.
  public var confirmsDeleteVersions = false
  /// A message when deleting the version history failed.
  public var storageMessage: String?

  private let store: any SettingsStoring
  private let diagnostics: () async -> String
  private let onChange: (AppSettings) -> Void
  private let measureVersions: () async -> Int64
  private let removeVersions: () async throws -> Void

  /// Creates the model.
  ///
  /// - Parameters:
  ///   - store: Where settings are kept.
  ///   - diagnostics: Builds the diagnostics summary (no document content) when the user asks.
  ///   - onChange: Tells the app the settings changed.
  ///   - versionsSize: Measures the space earlier versions of documents take.
  ///   - deleteVersions: Deletes every earlier version; the documents themselves are untouched.
  public init(
    store: any SettingsStoring, diagnostics: @escaping () async -> String,
    onChange: @escaping (AppSettings) -> Void, versionsSize: @escaping () async -> Int64 = { 0 },
    deleteVersions: @escaping () async throws -> Void = {}
  ) {
    self.store = store
    self.diagnostics = diagnostics
    self.onChange = onChange
    measureVersions = versionsSize
    removeVersions = deleteVersions
    settings = store.load()
  }

  /// Hides or shows AI features everywhere.
  public var isIntelligenceHidden: Bool {
    get { settings.isIntelligenceHidden }
    set { update { $0.isIntelligenceHidden = newValue } }
  }

  /// Whether document text goes to system Spotlight; titles and tags always do (FR-LIB-005, T-11).
  public var isSpotlightTextIncluded: Bool {
    get { settings.isSpotlightTextIncluded }
    set { update { $0.isSpotlightTextIncluded = newValue } }
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

  // MARK: - Storage

  /// Measures the version history, for the Storage section.
  public func loadStorage() async {
    versionsSize = await measureVersions()
  }

  /// Deletes every earlier version of every document; the documents themselves stay as they are.
  public func deleteVersions() async {
    do {
      try await removeVersions()
    } catch {
      storageMessage = String(
        localized: "Some earlier versions couldn't be deleted. Your documents haven't changed. Try again.",
        bundle: .module)
    }
    await loadStorage()
  }

  private func update(_ change: (inout AppSettings) -> Void) {
    change(&settings)
    store.save(settings)
    onChange(settings)
  }
}
