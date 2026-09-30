import LibraryFeature
import OnboardingFeature
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

    @Test func onboarding() async {
      let app = app([])
      await app.onboarding.load()
      check(OnboardingView(model: app.onboarding))
    }

    @Test func emptyLibrary() async {
      let app = app(["-skip-onboarding"])
      await app.library.load()
      check(LibraryView(model: app.library, onScan: {}, onSettings: {}) { _ in EmptyView() })
    }

    @Test func settings() {
      let app = app(["-skip-onboarding"])
      check(SettingsView(model: app.makeSettings(), version: "1.0 (1)"))
    }

    @Test func scan() {
      let app = app(["-skip-onboarding"])
      check(ScanView(model: app.makeScan()))
    }
  }
}
