import Foundation
import Testing

@testable import PDFAlgoPro

/// Moving Spotlight to the protected index (defect D11) at launch.
@Suite("Spotlight migration")
struct SpotlightMigrationTests {
  private func defaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "spotlight-migration-\(UUID().uuidString)"))
  }

  @Test("The migration is tried again at the next launch when the library couldn't be listed (#237)")
  func retriedAfterAFailedListing() async throws {
    let defaults = try defaults()
    var retired = 0
    await AppContainer.migrateSpotlight(defaults: defaults, retire: { retired += 1 }, reindex: { false })
    #expect(retired == 1)
    #expect(defaults.integer(forKey: "spotlight.indexVersion") < 2, "Not marked done")

    await AppContainer.migrateSpotlight(defaults: defaults, retire: { retired += 1 }, reindex: { true })
    #expect(retired == 2, "Tried again")
    #expect(defaults.integer(forKey: "spotlight.indexVersion") == 2)
    await AppContainer.migrateSpotlight(defaults: defaults, retire: { retired += 1 }, reindex: { true })
    #expect(retired == 2, "Done once, never again")
  }

  @Test("A text-setting change that Spotlight didn't fully take is written again at the next launch (#360)")
  func textSettingRetriedAtNextLaunch() async throws {
    let defaults = try defaults()
    await AppContainer.migrateSpotlight(defaults: defaults, retire: {}, reindex: { true })
    await AppContainer.reindexAfterTextSetting(defaults: defaults, reindex: { true })
    #expect(defaults.integer(forKey: "spotlight.indexVersion") == 2, "Taken: nothing to do at the next launch")

    await AppContainer.reindexAfterTextSetting(defaults: defaults, reindex: { false })
    #expect(defaults.integer(forKey: "spotlight.indexVersion") < 2, "Not taken: marked not done")
    var reindexed = 0
    await AppContainer.migrateSpotlight(
      defaults: defaults, retire: {},
      reindex: {
        reindexed += 1
        return true
      })
    #expect(reindexed == 1, "Written again at the next launch")
    #expect(defaults.integer(forKey: "spotlight.indexVersion") == 2)
  }
}
