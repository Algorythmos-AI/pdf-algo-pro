import Commerce
import Core
import Foundation
import Testing

@testable import PDFAlgoPro

/// Every new internal build replays first run, the offer included, without touching purchases
/// (PAP-053, PAP-057). The app under test is a Debug build, which has the replay.
// Inside the App suite, which is serialised: every `AppModel` attaches the one App Intents router.
extension AppTests {
  @MainActor
  @Suite("First run again on every new internal build", .serialized)
  struct InternalFirstRunReplayTests {
    private func makeDefaults() throws -> UserDefaults {
      try #require(UserDefaults(suiteName: "first-run-replay-\(UUID().uuidString)"))
    }

    /// The app as a build of an install whose state is kept under a name.
    private func makeApp(build: String, state: String, _ arguments: [String] = []) -> AppModel {
      let launch = ["-ui-testing", "-keep-state", state, "-first-run-build", build] + arguments
      return AppModel(container: AppContainer(environment: LaunchEnvironment(arguments: launch)))
    }

    /// Goes through first run and closes the offer that follows it, as the person would.
    private func completeFirstRun(_ app: AppModel) async {
      await app.onboarding.skip()
      #expect(app.sheet == .paywall && app.paywallTrigger == .onboarding)
      app.sheet = nil
      app.sheetClosed(.paywall)
    }

    @Test("First run is due until this build has completed it")
    func rule() {
      #expect(InternalFirstRunReplay.isDue(lastCompletedBuild: nil, build: "24"), "A new install")
      #expect(InternalFirstRunReplay.isDue(lastCompletedBuild: "23", build: "24"), "A new build")
      #expect(!InternalFirstRunReplay.isDue(lastCompletedBuild: "24", build: "24"), "The same build")
    }

    @Test("Only first run is reset; every other setting stays, and the build is done only once completed")
    func beginAndComplete() throws {
      let defaults = try makeDefaults()
      let settings = UserDefaultsSettingsStore(defaults: defaults)
      settings.save(AppSettings(hasCompletedOnboarding: true, intents: [.scan], isAppLockEnabled: true))
      let replay = InternalFirstRunReplay(defaults: defaults, build: "24")
      #expect(replay.begin(with: settings))
      #expect(settings.load() == AppSettings(hasCompletedOnboarding: false, intents: [.scan], isAppLockEnabled: true))
      #expect(replay.isDue, "Leaving half-way replays it at the next launch")
      replay.complete()
      #expect(!replay.isDue && !replay.begin(with: settings))
      replay.reset()
      #expect(replay.isDue, "Reset for the next launch")
    }

    @Test("Build N shows first run and the offer; the same build again opens on Home; build N+1 shows both again")
    func buildAfterBuild() async {
      let state = UUID().uuidString
      let first = makeApp(build: "24", state: state)
      #expect(!first.settings.hasCompletedOnboarding, "A fresh install opens on first run")
      await completeFirstRun(first)

      let again = makeApp(build: "24", state: state)
      #expect(again.settings.hasCompletedOnboarding && again.sheet == nil, "The same build opens on Home")

      let next = makeApp(build: "25", state: state)
      #expect(!next.settings.hasCompletedOnboarding, "The next build opens on first run, with no reinstall")
      await completeFirstRun(next)
      #expect(makeApp(build: "25", state: state).settings.hasCompletedOnboarding)
    }

    @Test("Leaving on the offer does not complete the build: the next launch replays first run")
    func leftOnTheOffer() async {
      let state = UUID().uuidString
      let app = makeApp(build: "24", state: state)
      await app.onboarding.skip()
      #expect(app.sheet == .paywall)
      #expect(!makeApp(build: "24", state: state).settings.hasCompletedOnboarding)
    }

    @Test("An account that has Pro still sees the offer on a replay, and its entitlement is untouched")
    func replayWithPro() async {
      let app = makeApp(build: "24", state: UUID().uuidString, ["-entitlement", "subscribed"])
      await app.onboarding.skip()
      #expect(app.sheet == .paywall, "The presentation replays whatever the account is entitled to")
      let offer = app.makePaywall()
      await offer.appeared()
      #expect(offer.alreadyHasPro, "And says the truth about the account")
      await offer.purchase()
      #expect(offer.phase == .offer, "Nothing is sold to it")
      #expect(await app.container.entitlements.resolved() == .subscribed, "The entitlement is as it was")
    }

    @Test("A replay shows the offer even when the plans cannot be loaded, where it says so")
    func replayWithoutPlans() async {
      let app = makeApp(build: "24", state: UUID().uuidString, ["-store", "unavailable"])
      await app.onboarding.skip()
      #expect(app.sheet == .paywall)
      let offer = app.makePaywall()
      await offer.appeared()
      #expect(offer.plans == .unavailable)
    }

    @Test("Without a build named, a test has no replay: first run is as a customer has it")
    func noReplayUnlessAsked() async {
      let app = AppModel(
        container: AppContainer(
          environment: LaunchEnvironment(arguments: ["-ui-testing", "-entitlement", "subscribed"])))
      await app.onboarding.skip()
      #expect(app.sheet == nil, "Someone who has Pro is shown no offer after first run")
    }
  }
}
