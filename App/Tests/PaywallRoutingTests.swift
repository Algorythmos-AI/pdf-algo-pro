import Commerce
import Core
import Foundation
import LibraryFeature
import PaywallFeature
import Testing

@testable import PDFAlgoPro

/// When the app shows the subscription offer, and when it must not (ADR-0026).
// Inside the App suite, which is serialised: every `AppModel` attaches the one App Intents router.
extension AppTests {
  @MainActor
  @Suite("The subscription offer's routing", .serialized)
  struct PaywallRoutingTests {
    private func makeApp(_ arguments: [String] = []) -> AppModel {
      AppModel(container: AppContainer(environment: LaunchEnvironment(arguments: ["-ui-testing"] + arguments)))
    }

    /// Gives the tasks the app starts at launch (the plans, the entitlement) the time to finish.
    private func settle(_ app: AppModel) async {
      _ = await app.container.entitlements.resolved()
      for _ in 0..<50 { await Task.yield() }
    }

    /// Waits for a sheet the app decides on in a task.
    private func eventually(_ app: AppModel, shows sheet: AppModel.Sheet?) async -> Bool {
      for _ in 0..<2_000 {
        if app.sheet == sheet { return true }
        await Task.yield()
      }
      return app.sheet == sheet
    }

    @Test("First run ends on the offer, once, with first run already saved as done")
    func afterFirstRun() async {
      let app = makeApp()
      await settle(app)
      #expect(app.sheet == nil && !app.settings.hasCompletedOnboarding)
      await app.onboarding.skip()
      #expect(app.settings.hasCompletedOnboarding, "Leaving the app on the offer leads to Home next time")
      #expect(app.sheet == .paywall && app.paywallTrigger == .onboarding)
    }

    @Test("Finishing the last page does the same as Skip")
    func afterTheLastPage() async {
      let app = makeApp()
      await settle(app)
      await app.onboarding.advance()
      await app.onboarding.advance()
      #expect(app.sheet == nil)
      await app.onboarding.advance()
      #expect(app.sheet == .paywall && app.paywallTrigger == .onboarding)
    }

    @Test(
      "No offer after first run without plans to show, or for someone who has Pro",
      arguments: [["-store", "unavailable"], ["-entitlement", "subscribed"], ["-entitlement", "trial"]])
    func noOffer(arguments: [String]) async {
      let app = makeApp(arguments)
      await settle(app)
      await app.onboarding.skip()
      #expect(app.settings.hasCompletedOnboarding && app.sheet == nil)
    }

    @Test("First run ends on the offer even when its end comes before the App Store's answers")
    func waitsForTheStore() async {
      let app = makeApp()
      // Straight after launch, with nothing settled: the last page waits for the answers.
      await app.onboarding.skip()
      #expect(app.settings.hasCompletedOnboarding)
      #expect(app.sheet == .paywall && app.paywallTrigger == .onboarding)
    }

    @Test("Without plans to show nothing is waited for, however patient first run is")
    func noWaitWithoutPlans() async {
      let app = makeApp(["-store", "unavailable"])
      app.storePatience = .seconds(600)
      let clock = ContinuousClock()
      let started = clock.now
      await app.onboarding.skip()
      #expect(app.settings.hasCompletedOnboarding && app.sheet == nil)
      #expect(clock.now - started < .seconds(60), "The store's no is an answer; first run goes on to Home")
    }

    @Test("Asked before the App Store has answered, there is no offer, and none shows later")
    func beforeTheStoreAnswers() async {
      let app = makeApp()
      // Straight after launch: neither the plans nor the entitlement are known yet.
      app.offerAfterFirstRun()
      #expect(app.sheet == nil, "Nothing is waited for")
      await settle(app)
      #expect(app.sheet == nil, "And nothing shows once the answers arrive")
    }

    @Test("A launch after first run shows no offer")
    func laterLaunch() async {
      let app = makeApp(["-skip-onboarding"])
      await settle(app)
      #expect(app.settings.hasCompletedOnboarding && app.sheet == nil)
      app.offerAfterFirstRun()
      #expect(app.sheet == nil, "The plans are only asked for during first run")
    }

    @Test("Scan opens the scanner while the day's allowance lasts, and the offer once it is used")
    func scan() async {
      let free = makeApp(["-skip-onboarding"])
      free.startScan()
      #expect(await eventually(free, shows: .scan))

      let used = makeApp(["-skip-onboarding", "-allowance", "exhausted"])
      used.startScan()
      #expect(await eventually(used, shows: .paywall))
      #expect(used.paywallTrigger == .allowanceReached)

      let pro = makeApp(["-skip-onboarding", "-allowance", "exhausted", "-entitlement", "subscribed"])
      pro.navigate(to: .scan)
      #expect(
        await eventually(pro, shows: .scan), "A link or an intent that asks for the scanner is gated the same way")
    }

    @Test("The offer replaces Settings when asked for there, and closing it leaves nothing up")
    func fromSettings() async {
      let app = makeApp(["-skip-onboarding"])
      app.sheet = .settings
      app.presentPaywall(.settings)
      #expect(app.sheet == .paywall && app.paywallTrigger == .settings)
      let model = app.makePaywall()
      #expect(model.trigger == .settings && model.productIDs == app.container.catalog.ordered)
      model.close()
      #expect(app.sheet == nil)
      app.sheet = .settings
      model.close()
      #expect(app.sheet == .settings, "Closing an offer that is no longer up closes nothing else")
    }

    @Test("A trial that ends within a day is said once in the app, never over a sheet or during first run")
    func trialNotice() async {
      // The trial argument gives a trial with a day left, which is when the notice is due.
      let app = makeApp(["-skip-onboarding", "-entitlement", "trial"])
      app.sheet = .settings
      await app.checkTrialNotice()
      #expect(app.trialNotice == nil, "Not over a sheet")
      app.sheet = nil
      await app.checkTrialNotice()
      #expect(app.trialNotice != nil)
      app.trialNotice = nil
      await app.checkTrialNotice()
      #expect(app.trialNotice == nil, "Once per trial")

      let firstRun = makeApp(["-entitlement", "trial"])
      await firstRun.checkTrialNotice()
      #expect(firstRun.trialNotice == nil, "Not during first run")
      let free = makeApp(["-skip-onboarding"])
      await free.checkTrialNotice()
      #expect(free.trialNotice == nil)
    }

    @Test("The offer lists only what this build does")
    func benefits() async {
      let app = makeApp(["-skip-onboarding"])
      #expect(app.paywallBenefits.prefix(2) == [.unlimitedScans, .unlimitedIntelligence])
      // Tests run an internal build, where text editing is on.
      #expect(app.paywallBenefits.contains(.textEditing))
      let settings = app.makeSettings()
      settings.isIntelligenceHidden = true
      #expect(!app.paywallBenefits.contains(.unlimitedIntelligence), "Hidden AI is not sold")
    }

    @Test("The reader's explanation that editing needs Pro can open the offer")
    func fromTheReader() async throws {
      let app = makeApp(["-skip-onboarding"])
      let reader = app.makeReader(for: DocumentSelection(id: DocumentID()))
      let open = try #require(reader.onSeePlans)
      open()
      #expect(app.sheet == .paywall && app.paywallTrigger == .lockedFeature)
    }

    @Test("The internal switch gives Pro whatever the store says, and passes the store through when off")
    func internalOverride() async {
      let base = FixedEntitlements(.expired)
      #expect(await InternalEntitlementOverride(base: base, isOn: { true }).currentEntitlement() == .subscribed)
      #expect(await InternalEntitlementOverride(base: base, isOn: { false }).currentEntitlement() == .expired)
      var seen: [Entitlement] = []
      for await entitlement in InternalEntitlementOverride(base: base, isOn: { true }).entitlementUpdates() {
        seen.append(entitlement)
      }
      #expect(seen == [.subscribed])
      seen = []
      for await entitlement in InternalEntitlementOverride(base: base, isOn: { false }).entitlementUpdates() {
        seen.append(entitlement)
      }
      #expect(seen == [.expired])
    }
  }
}
