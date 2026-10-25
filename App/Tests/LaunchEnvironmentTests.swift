import Core
import Foundation
import Testing

@testable import PDFAlgoPro

/// The launch arguments that set up a UI test's world (docs/testing-strategy.md, "Launch arguments").
@Suite("Launch arguments for UI tests")
struct LaunchEnvironmentTests {
  @Test("A library is seeded from a comma-separated list, and its last document opens unless the test starts elsewhere")
  func seeds() {
    let seeded = LaunchEnvironment(arguments: ["-ui-testing", "-seed-library", "sample,tags,favourite"])
    #expect(seeded.seeds == ["sample", "tags", "favourite"])
    #expect(seeded.opensSeededDocument && !seeded.startsOnList)
    let home = LaunchEnvironment(arguments: ["-seed-library", "sample", "-start", "home"])
    #expect(!home.opensSeededDocument && !home.startsOnList)
    let list = LaunchEnvironment(arguments: ["-start", "list"])
    #expect(!list.opensSeededDocument && list.startsOnList)
    #expect(LaunchEnvironment(arguments: []).seeds.isEmpty)
  }

  @Test("App Lock starts on, with a scripted answer, only when a test asks")
  func appLock() async {
    #expect(LaunchEnvironment(arguments: ["-app-lock", "confirms"]).appLockConfirms == true)
    #expect(LaunchEnvironment(arguments: ["-app-lock", "refuses"]).appLockConfirms == false)
    #expect(LaunchEnvironment(arguments: ["-app-lock", "maybe"]).appLockConfirms == nil)
    #expect(LaunchEnvironment(arguments: []).appLockConfirms == nil)

    let container = AppContainer(environment: LaunchEnvironment(arguments: ["-ui-testing", "-app-lock", "refuses"]))
    #expect(container.settings.load().isAppLockEnabled)
    #expect(container.authenticator.method() == .faceID)
    #expect(await !container.authenticator.authenticate(reason: "A test"))
    let confirming = AppContainer(environment: LaunchEnvironment(arguments: ["-ui-testing", "-app-lock", "confirms"]))
    #expect(await confirming.authenticator.authenticate(reason: "A test"))
  }

  @Test("A route is any link the app itself accepts")
  func route() {
    #expect(LaunchEnvironment(arguments: ["-open-route", "pdfalgopro://settings"]).route == .settings)
    #expect(
      LaunchEnvironment(arguments: ["-open-route", "pdfalgopro://library/favorites"]).route == .library(.favorites))
    #expect(LaunchEnvironment(arguments: ["-open-route", "https://example.com"]).route == nil)
    #expect(LaunchEnvironment(arguments: []).route == nil)
  }
}
