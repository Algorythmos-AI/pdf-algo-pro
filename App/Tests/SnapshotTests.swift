import DesignSystem
import LibraryFeature
import OnboardingFeature
import PaywallFeature
import ScanFeature
import SettingsFeature
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import PDFAlgoPro

/// Snapshots of the key screens in light, dark and an accessibility text size (bar item B8, W3.5).
///
/// References are recorded on the pinned CI simulator (`ci.yml`, manual run with `record_snapshots`)
/// and live in `__Snapshots__` next to this file. CI runs with `SNAPSHOT_TESTING_RECORD=never`, so a
/// missing reference fails rather than being recorded silently (docs/testing-strategy.md).
/// Nested in `AppTests`, which is serialised: building an `AppModel` attaches the one App Intents
/// router, so these must not run beside the intents tests.
extension AppTests {
  @MainActor
  @Suite("Snapshots", .serialized)
  struct SnapshotTests {
    /// The appearances every screen is checked in.
    enum Variant: String, CaseIterable {
      case light, dark, largeText

      var traits: UITraitCollection {
        switch self {
        case .light: UITraitCollection(userInterfaceStyle: .light)
        case .dark: UITraitCollection(userInterfaceStyle: .dark)
        case .largeText:
          UITraitCollection {
            $0.userInterfaceStyle = .light
            $0.preferredContentSizeCategory = .accessibilityExtraLarge
          }
        }
      }
    }

    /// Anti-aliasing differs slightly between runs; `Assumption:` 0.98, per the testing strategy.
    static let precision: Float = 0.98

    private func app(_ arguments: [String]) -> AppModel {
      AppModel(container: AppContainer(environment: LaunchEnvironment(arguments: ["-ui-testing"] + arguments)))
    }

    private func check(
      _ view: some View, fileID: StaticString = #fileID, file: StaticString = #filePath,
      testName: String = #function, line: UInt = #line, column: UInt = #column
    ) {
      for variant in Variant.allCases {
        assertSnapshot(
          of: UIHostingController(rootView: view),
          as: .image(on: .iPhone13, perceptualPrecision: Self.precision, traits: variant.traits),
          named: variant.rawValue, fileID: fileID, file: file, testName: testName, line: line, column: column)
      }
    }

    /// The first page of the introduction.
    @Test func onboarding() async {
      let app = app([])
      await app.onboarding.load()
      check(introduction(app))
    }

    /// The introduction with its pictures held still, so a reference never catches a line mid-sweep.
    private func introduction(_ app: AppModel) -> some View {
      OnboardingView(model: app.onboarding).environment(\.playsDecorativeMotion, false)
    }

    /// Its second page, about signing, marking up and putting pages in order.
    @Test func onboardingSign() async {
      let app = app([])
      await app.onboarding.load()
      await app.onboarding.advance()
      check(introduction(app))
    }

    /// Its third page where on-device intelligence is unavailable: merging, shrinking and finding.
    @Test func onboardingOrganize() async {
      let app = app(["-intelligence-unavailable"])
      await app.onboarding.load()
      await app.onboarding.advance()
      await app.onboarding.advance()
      check(introduction(app))
    }

    /// Its third page, about asking a document: the scripted intelligence is available.
    @Test func onboardingAsk() async {
      let app = app([])
      await app.onboarding.load()
      await app.onboarding.advance()
      await app.onboarding.advance()
      check(introduction(app))
    }

    /// The offer for an app's state, with its plans loaded and its picture held still.
    private func offer(_ app: AppModel, buying: Bool = false) async -> some View {
      let model = app.makePaywall()
      await model.appeared()
      if buying { await model.purchase() }
      return PaywallFlowView(model: model, store: app.container.store).environment(\.playsDecorativeMotion, false)
    }

    /// The offer as an eligible account sees it: the annual plan selected, with its trial.
    @Test func paywall() async {
      check(await offer(app(["-skip-onboarding"])))
    }

    /// The offer for an account with no trial to take.
    @Test func paywallWithoutTrial() async {
      check(await offer(app(["-skip-onboarding", "-trial", "none"])))
    }

    /// The offer when the plans cannot be loaded.
    @Test func paywallUnavailable() async {
      check(await offer(app(["-skip-onboarding", "-store", "unavailable"])))
    }

    /// The offer for someone who has Pro already.
    @Test func paywallAlreadyPro() async {
      check(await offer(app(["-skip-onboarding", "-entitlement", "subscribed"])))
    }

    /// The confirmation after a purchase. Without a trial, so that no date is in the picture: a
    /// trial's end is three days from the day the test runs.
    @Test func welcome() async {
      check(await offer(app(["-skip-onboarding", "-trial", "none"]), buying: true))
    }

    /// Home, the screen the app opens on, with nothing in the library yet.
    @Test func home() async {
      let app = app(["-skip-onboarding"])
      await app.library.load()
      check(LibraryView(model: app.library, onScan: {}, onSettings: {}) { _ in EmptyView() })
    }

    /// The document list's own empty state, one step in from Home: a section was asked for.
    @Test func emptyLibrary() async {
      let app = app(["-skip-onboarding"])
      await app.library.load()
      app.library.show(.all)
      check(LibraryView(model: app.library, onScan: {}, onSettings: {}) { _ in EmptyView() })
    }

    @Test func settings() {
      let app = app(["-skip-onboarding"])
      check(SettingsView(model: app.makeSettings(), version: "1.0 (1)"))
    }

    @Test func about() {
      check(NavigationStack { AboutView(version: "1.0 (1)") })
    }

    @Test func scan() {
      let app = app(["-skip-onboarding"])
      check(ScanView(model: app.makeScan()))
    }
  }
}
