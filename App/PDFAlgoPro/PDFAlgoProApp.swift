import AssistantFeature
import CoreSpotlight
import LibraryFeature
import OSLog
import OnboardingFeature
import ReaderFeature
import ScanFeature
import SettingsFeature
import StoreKit
import SwiftUI
import TipKit
import UIKit

/// PDF Algo Pro: private, on-device document intelligence for Apple platforms.
@main
struct PDFAlgoProApp: App {
  @State private var app = AppModel(container: AppContainer())

  init() {
    let environment = LaunchEnvironment()
    if environment.disablesAnimations { UIView.setAnimationsEnabled(false) }
    Self.startTips(environment)
  }

  /// Starts TipKit, which keeps what it knows on this device and sends nothing anywhere.
  ///
  /// UI tests see no tips, so a bubble never gets between a test and what it taps, unless a test
  /// asks for them; then they start from an empty store. Without tips the app is whole, so a
  /// failure here is only logged.
  private static func startTips(_ environment: LaunchEnvironment) {
    do {
      if environment.isUITesting {
        guard environment.showsTips else { return }
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("tips-\(UUID().uuidString)")
        try Tips.configure([.datastoreLocation(.url(store)), .displayFrequency(.immediate)])
      } else {
        try Tips.configure([.displayFrequency(.immediate)])
      }
    } catch {
      Logger(subsystem: "com.algorythmos.pdfalgopro", category: "tips").error("TipKit did not start")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView(app: app)
    }
  }
}

/// The first screen: onboarding once, then the library with the reader beside it.
struct RootView: View {
  @Bindable var app: AppModel
  @Environment(\.requestReview) private var requestReview
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if app.settings.hasCompletedOnboarding {
        LibraryView(model: app.library, onScan: { app.sheet = .scan }, onSettings: { app.sheet = .settings }) {
          selection in
          ReaderView(model: app.makeReader(for: selection)) { context in
            AssistantView(model: app.makeAssistant(for: context))
          }
        }
      } else {
        OnboardingView(model: app.onboarding)
      }
    }
    .sheet(item: $app.sheet) { sheet in
      switch sheet {
      case .scan: ScanView(model: app.makeScan())
      case .settings:
        SettingsView(model: app.makeSettings(), version: app.container.version, internalTools: app.internalTools)
      }
    }
    .background(LockWindowPresenter(lock: app.lock, method: app.lockMethod))
    .onChange(of: scenePhase, initial: true) { _, phase in
      Task { await app.lock.scenePhaseChanged(to: phase) }
      // A subscription can change while the app is away: bought on another device, renewed, refunded.
      if phase == .active { Task { await app.container.entitlements.refresh() } }
    }
    // A calm moment to ask for a rating: a document or a sheet has just closed (plan §6).
    .onChange(of: app.library.selection == nil) { _, closed in
      guard closed else { return }
      app.closeReader()
      // The list follows what happened in the reader: a new lock, page count, title or thumbnail.
      Task { await app.library.reload() }
      askForReviewIfDue()
    }
    .onChange(of: app.sheet == nil) { _, closed in if closed { askForReviewIfDue() } }
    .onOpenURL { app.handle($0) }
    .onContinueUserActivity(CSSearchableItemActionType) { app.handleSpotlight($0) }
  }

  private func askForReviewIfDue() {
    if app.reviews.shouldAskNow() { requestReview() }
  }
}
