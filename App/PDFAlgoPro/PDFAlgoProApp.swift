import AssistantFeature
import CoreSpotlight
import LibraryFeature
import OnboardingFeature
import ReaderFeature
import ScanFeature
import SettingsFeature
import SwiftUI
import UIKit

/// PDF Algo Pro: private, on-device document intelligence for Apple platforms.
@main
struct PDFAlgoProApp: App {
  @State private var app = AppModel(container: AppContainer())

  init() {
    if LaunchEnvironment().disablesAnimations { UIView.setAnimationsEnabled(false) }
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
      case .settings: SettingsView(model: app.makeSettings(), version: app.container.version)
      }
    }
    .onOpenURL { app.handle($0) }
    .onContinueUserActivity(CSSearchableItemActionType) { app.handleSpotlight($0) }
  }
}
