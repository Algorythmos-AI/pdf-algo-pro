import AccessibilityIDs
import AssistantFeature
import CoreSpotlight
import DesignSystem
import LibraryFeature
import OSLog
import OnboardingFeature
import PaywallFeature
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
    // Shortly before a trial reminder is due, the system may wake the app to look whether the trial
    // still runs; a reminder for one paid or refunded meanwhile is then removed (#336).
    .backgroundTask(.appRefresh(TrialReminderScheduler.checkIdentifier)) { [app] in
      await app.checkTrialReminder()
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
        LibraryView(model: app.library, onScan: { app.startScan() }, onSettings: { app.sheet = .settings }) {
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
        SettingsView(
          model: app.makeSettings(), version: app.container.version, internalTools: app.internalTools,
          subscription: app.subscriptionSection)
      case .paywall: PaywallFlowView(model: app.makePaywall(), store: app.container.store)
      }
    }
    // The introduction's and the offer's pictures hold still where animations are off (UI tests).
    .environment(\.playsDecorativeMotion, !app.container.environment.disablesAnimations)
    .background(LockWindowPresenter(lock: app.lock, method: app.lockMethod))
    .onChange(of: scenePhase, initial: true) { _, phase in
      Task { await app.lock.scenePhaseChanged(to: phase) }
      // A subscription can change while the app is away: bought on another device, renewed, refunded.
      if phase == .active {
        Task {
          await app.container.entitlements.refresh()
          await app.checkTrialNotice()
        }
        // Files can rename or move a document while the app is away (#224).
        Task { await app.library.filesMayHaveChanged() }
      }
    }
    // A calm moment to ask for a rating: a document or a sheet has just closed (plan §6).
    .onChange(of: app.library.selection == nil) { _, closed in
      guard closed else { return }
      app.closeReader()
      // The list follows what happened in the reader: a new lock, page count, title or thumbnail.
      Task { await app.library.reload() }
      askForReviewIfDue()
    }
    // Not after the subscription offer or its confirmation: a rating is never asked for beside a
    // purchase (App Store strategy, ratings).
    .onChange(of: app.sheet) { closed, sheet in
      if sheet == nil { app.sheetClosed(closed) }
      if sheet == nil, closed != .paywall { askForReviewIfDue() }
    }
    // A trial that has ended, been refunded or become paid has nothing left to remind of. Also the
    // first answer, which can arrive before this view does (#336).
    .onChange(of: app.container.entitlements.entitlement, initial: true) { _, entitlement in
      Task { await app.container.reminders.entitlementChanged(entitlement) }
    }
    .alert(
      Text("Your trial ends soon"),
      isPresented: Binding(get: { app.trialNotice != nil }, set: { if !$0 { app.trialNotice = nil } }),
      presenting: app.trialNotice
    ) { _ in
      Button {
        app.sheet = .settings
      } label: {
        Text("Open Settings")
      }
      .accessibilityIdentifier(AccessibilityID.TrialNotice.settings)
      Button(role: .cancel) {
      } label: {
        Text("OK")
      }
    } message: { endsAt in
      Text(
        "Your PDF Algo Pro trial ends on \(endsAt, format: .dateTime.day().month(.wide)). To manage or cancel it, open the Settings app, tap your name (Apple Account), then Subscriptions. Or tap Manage subscription in PDF Algo Pro’s Settings."
      )
    }
    // App Lock turned itself off: the device has no passcode, so nothing could confirm its owner (#221).
    .alert(
      Text("App Lock is off"),
      isPresented: Binding(
        get: { app.lock.wasTurnedOffWithoutPasscode }, set: { if !$0 { app.lock.turnedOffNoticeShown() } })
    ) {
      Button(role: .cancel) {
      } label: {
        Text("OK")
      }
      .accessibilityIdentifier(AccessibilityID.AppLock.TurnedOff.ok)
    } message: {
      Text(
        "This device has no passcode, so App Lock can't confirm it's you. To use App Lock again, set a passcode in the Settings app, then turn App Lock on in PDF Algo Pro."
      )
    }
    .onOpenURL { app.handle($0) }
    .onContinueUserActivity(CSSearchableItemActionType) { app.handleSpotlight($0) }
  }

  private func askForReviewIfDue() {
    if app.reviews.shouldAskNow() { requestReview() }
  }
}
