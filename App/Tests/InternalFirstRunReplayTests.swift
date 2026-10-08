import Core
import Foundation
import Testing

@testable import PDFAlgoPro

/// A new internal build shows first run again, once (PAP-053).
@MainActor
@Suite("First run again on a new internal build")
struct InternalFirstRunReplayTests {
  private func makeDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "first-run-replay-\(UUID().uuidString)"))
  }

  @Test("An install that finished first run on an earlier build sees it again on a new one, once")
  func newBuild() throws {
    let defaults = try makeDefaults()
    let settings = UserDefaultsSettingsStore(defaults: defaults)
    settings.save(AppSettings(hasCompletedOnboarding: true, intents: [.scan], isAppLockEnabled: true))
    defaults.set("23", forKey: InternalFirstRunReplay.key)

    #expect(InternalFirstRunReplay(defaults: defaults, build: "24").apply(to: settings))
    var expected = AppSettings(hasCompletedOnboarding: false, intents: [.scan], isAppLockEnabled: true)
    #expect(settings.load() == expected, "Only first run is reset; every other setting stays")

    // The person goes through first run; the same build opened again leaves it done.
    expected.hasCompletedOnboarding = true
    settings.save(expected)
    #expect(!InternalFirstRunReplay(defaults: defaults, build: "24").apply(to: settings))
    #expect(settings.load() == expected)
  }

  @Test("An install from before builds were remembered sees first run again once")
  func noBuildRemembered() throws {
    let defaults = try makeDefaults()
    let settings = UserDefaultsSettingsStore(defaults: defaults)
    settings.save(AppSettings(hasCompletedOnboarding: true))
    #expect(InternalFirstRunReplay(defaults: defaults, build: "24").apply(to: settings))
    #expect(defaults.string(forKey: InternalFirstRunReplay.key) == "24")
  }

  @Test("A new install is left alone: first run shows anyway, and the build is remembered")
  func newInstall() throws {
    let defaults = try makeDefaults()
    let settings = UserDefaultsSettingsStore(defaults: defaults)
    #expect(!InternalFirstRunReplay(defaults: defaults, build: "24").apply(to: settings))
    #expect(settings.load() == AppSettings())
    #expect(defaults.string(forKey: InternalFirstRunReplay.key) == "24")
  }

  @Test("The same build never replays, whatever first run's state")
  func sameBuild() {
    #expect(!InternalFirstRunReplay.replays(lastBuild: "24", build: "24", hasCompletedOnboarding: true))
    #expect(!InternalFirstRunReplay.replays(lastBuild: "24", build: "24", hasCompletedOnboarding: false))
    #expect(!InternalFirstRunReplay.replays(lastBuild: "23", build: "24", hasCompletedOnboarding: false))
    #expect(InternalFirstRunReplay.replays(lastBuild: "23", build: "24", hasCompletedOnboarding: true))
  }
}
