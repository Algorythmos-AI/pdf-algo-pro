import Foundation

/// How the reader lays out pages (FR-READ-002).
public enum ReaderDisplayMode: String, CaseIterable, Codable, Sendable {
  /// Pages scroll continuously.
  case continuous
  /// One page at a time.
  case singlePage
}

/// The user's preferences.
public struct AppSettings: Hashable, Codable, Sendable {
  /// Whether onboarding was completed or skipped; it never returns uninvited.
  public var hasCompletedOnboarding: Bool
  /// The intents chosen during onboarding, first one leading the home screen.
  public var intents: [OnboardingIntent]
  /// Whether AI features are hidden (FR-AI-009).
  public var isIntelligenceHidden: Bool
  /// The reader's page layout.
  public var readerDisplayMode: ReaderDisplayMode
  /// The library's sort order.
  public var librarySort: LibrarySort

  /// Creates settings; the defaults are what a new install starts with.
  public init(
    hasCompletedOnboarding: Bool = false,
    intents: [OnboardingIntent] = [],
    isIntelligenceHidden: Bool = false,
    readerDisplayMode: ReaderDisplayMode = .continuous,
    librarySort: LibrarySort = .recentlyOpened
  ) {
    self.hasCompletedOnboarding = hasCompletedOnboarding
    self.intents = intents
    self.isIntelligenceHidden = isIntelligenceHidden
    self.readerDisplayMode = readerDisplayMode
    self.librarySort = librarySort
  }
}

/// Where settings are kept.
public protocol SettingsStoring: Sendable {
  /// The current settings.
  func load() -> AppSettings
  /// Replaces the settings.
  func save(_ settings: AppSettings)
}

/// Settings stored as one JSON value in `UserDefaults` (declared in the privacy manifest, reason CA92.1).
public final class UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
  // `UserDefaults` is thread-safe; it is not marked `Sendable` in the SDK.
  private let defaults: UserDefaults
  private let key: String

  /// Creates a store over a defaults domain.
  public init(defaults: UserDefaults = .standard, key: String = "app.settings.v1") {
    self.defaults = defaults
    self.key = key
  }

  /// The stored settings, or defaults when none are stored or they cannot be decoded.
  public func load() -> AppSettings {
    guard let data = defaults.data(forKey: key),
      let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    else { return AppSettings() }
    return settings
  }

  /// Stores the settings.
  public func save(_ settings: AppSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: key)
  }
}
