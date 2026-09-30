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
  /// Whether document text goes to system Spotlight as well as titles and tags (FR-LIB-005, T-11).
  public var isSpotlightTextIncluded: Bool
  /// Whether opening the app asks for Face ID, Touch ID or the passcode (FR-SET-002).
  public var isAppLockEnabled: Bool

  /// Creates settings; the defaults are what a new install starts with.
  public init(
    hasCompletedOnboarding: Bool = false,
    intents: [OnboardingIntent] = [],
    isIntelligenceHidden: Bool = false,
    readerDisplayMode: ReaderDisplayMode = .continuous,
    librarySort: LibrarySort = .recentlyOpened,
    isSpotlightTextIncluded: Bool = true,
    isAppLockEnabled: Bool = false
  ) {
    self.hasCompletedOnboarding = hasCompletedOnboarding
    self.intents = intents
    self.isIntelligenceHidden = isIntelligenceHidden
    self.readerDisplayMode = readerDisplayMode
    self.librarySort = librarySort
    self.isSpotlightTextIncluded = isSpotlightTextIncluded
    self.isAppLockEnabled = isAppLockEnabled
  }

  /// Whether document text goes to Spotlight: only when chosen, and never while App Lock is on (H3).
  public var indexesTextInSpotlight: Bool { isSpotlightTextIncluded && !isAppLockEnabled }

  private enum CodingKeys: String, CodingKey {
    case hasCompletedOnboarding, intents, isIntelligenceHidden, readerDisplayMode, librarySort, isSpotlightTextIncluded
    case isAppLockEnabled
  }

  /// Decodes leniently, so settings survive updates in both directions.
  ///
  /// A missing key, or a value this version does not know (a setting added or a case renamed by
  /// another version), keeps that one setting's default; the others are kept as stored. Unknown
  /// intents are dropped. Only data that is not a settings object at all fails to decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
      (try? container.decodeIfPresent(type, forKey: key)) ?? nil
    }
    let defaults = AppSettings()
    hasCompletedOnboarding = value(Bool.self, .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
    intents = value([String].self, .intents)?.compactMap(OnboardingIntent.init(rawValue:)) ?? defaults.intents
    isIntelligenceHidden = value(Bool.self, .isIntelligenceHidden) ?? defaults.isIntelligenceHidden
    readerDisplayMode =
      value(String.self, .readerDisplayMode).flatMap(ReaderDisplayMode.init(rawValue:)) ?? defaults.readerDisplayMode
    librarySort = value(String.self, .librarySort).flatMap(LibrarySort.init(rawValue:)) ?? defaults.librarySort
    isSpotlightTextIncluded = value(Bool.self, .isSpotlightTextIncluded) ?? defaults.isSpotlightTextIncluded
    isAppLockEnabled = value(Bool.self, .isAppLockEnabled) ?? defaults.isAppLockEnabled
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

  /// The stored settings; defaults when none are stored.
  ///
  /// Stored data that cannot be read at all also gives defaults, except that onboarding stays done:
  /// someone with stored settings has used the app, and onboarding never returns uninvited.
  public func load() -> AppSettings {
    guard let data = defaults.data(forKey: key) else { return AppSettings() }
    guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
      return AppSettings(hasCompletedOnboarding: true)
    }
    return settings
  }

  /// Stores the settings.
  public func save(_ settings: AppSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: key)
  }
}
