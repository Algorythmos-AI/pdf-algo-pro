import Core
import DesignSystem
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Face ID, Touch ID, Optic ID or the passcode, through LocalAuthentication (FR-SET-002).
struct LocalAuthenticator: DeviceAuthenticating {
  func method() -> AppLockMethod? {
    let context = LAContext()
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return nil }
    switch context.biometryType {
    case .faceID: return .faceID
    case .touchID: return .touchID
    case .opticID: return .opticID
    default: return .passcode
    }
  }

  func authenticate(reason: String) async -> Bool {
    // The passcode is the fallback, so a person whose face or finger isn't recognised is never locked out.
    (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
  }
}

/// App Lock: whether the app is locked, and whether its content is covered (FR-SET-002, H3).
///
/// The app locks when it goes to the background and asks once when it comes back. While it is
/// inactive (the app switcher, a notification pulled down) the content is covered, so the system's
/// snapshot shows no document.
@MainActor
@Observable
final class AppLock {
  /// Whether the owner must confirm before the app shows anything.
  private(set) var isLocked: Bool
  /// Whether the content is covered, locked or not.
  private(set) var isCovered = false
  /// Whether a confirmation is on screen.
  private(set) var isAuthenticating = false

  @ObservationIgnored private let authenticator: any DeviceAuthenticating
  @ObservationIgnored private let isEnabled: () -> Bool
  /// Set when the app locks in the background; the next activation asks once, not after every failure.
  @ObservationIgnored private var promptsOnActivation: Bool

  init(authenticator: any DeviceAuthenticating, isEnabled: @escaping () -> Bool) {
    self.authenticator = authenticator
    self.isEnabled = isEnabled
    let locked = isEnabled()
    isLocked = locked
    promptsOnActivation = locked
  }

  /// Whether the cover shows.
  var showsCover: Bool { isLocked || isCovered }

  /// Follows the scene through the background and back.
  func scenePhaseChanged(to phase: ScenePhase) async {
    switch phase {
    case .background:
      guard isEnabled() else { return }
      isLocked = true
      isCovered = true
      promptsOnActivation = true
    case .inactive:
      // Face ID's own prompt makes the scene inactive too; the cover stays as it is then.
      if isEnabled(), !isAuthenticating { isCovered = true }
    case .active:
      if isLocked, promptsOnActivation {
        promptsOnActivation = false
        await unlock()
      }
      if !isLocked { isCovered = false }
    @unknown default:
      break
    }
  }

  /// Asks the owner to confirm, and unlocks when they do.
  func unlock() async {
    guard isLocked, !isAuthenticating else { return }
    isAuthenticating = true
    let confirmed = await authenticator.authenticate(
      reason: String(localized: "Unlock your documents", comment: "Why App Lock asks for Face ID"))
    isAuthenticating = false
    if confirmed {
      isLocked = false
      isCovered = false
    }
  }

  /// Turning App Lock off unlocks at once.
  func settingChanged() {
    if !isEnabled() {
      isLocked = false
      isCovered = false
      promptsOnActivation = false
    }
  }
}

/// What shows while the app is locked or covered: no document, title or thumbnail.
struct LockScreen: View {
  let lock: AppLock
  let method: AppLockMethod?

  var body: some View {
    ZStack {
      Color.ds.backgroundPrimary.ignoresSafeArea()
      if lock.isLocked {
        VStack(spacing: Spacing.s200) {
          Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Color.ds.labelSecondary)
            .accessibilityHidden(true)
          Text("Your documents are locked").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
          Button {
            Task { await lock.unlock() }
          } label: {
            Text(Self.unlockTitle(for: method)).frame(minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .disabled(lock.isAuthenticating)
          .accessibilityIdentifier("appLock.unlock")
        }
        .padding(Spacing.s300)
      }
    }
    .accessibilityIdentifier("appLock.cover")
  }

  static func unlockTitle(for method: AppLockMethod?) -> LocalizedStringKey {
    switch method {
    case .faceID: "Unlock with Face ID"
    case .touchID: "Unlock with Touch ID"
    case .opticID: "Unlock with Optic ID"
    case .passcode, nil: "Unlock with passcode"
    }
  }
}

/// Puts the lock screen in a window above everything in the scene, sheets included.
struct LockWindowPresenter: UIViewRepresentable {
  let lock: AppLock
  let method: AppLockMethod?

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.isHidden = true
    // The first update can come before the view is in a window; showing the cover must not wait for
    // the next change, or a locked app could show its content.
    view.onWindow = { [weak view, coordinator = context.coordinator, lock, method] in
      coordinator.update(scene: view?.window?.windowScene, lock: lock, method: method, shows: lock.showsCover)
    }
    return view
  }

  func updateUIView(_ view: AnchorView, context: Context) {
    context.coordinator.update(
      scene: view.window?.windowScene, lock: lock, method: method, shows: lock.showsCover)
  }

  /// A view that says when it joins a window.
  final class AnchorView: UIView {
    var onWindow: (() -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window != nil { onWindow?() }
    }
  }

  @MainActor
  final class Coordinator {
    private var window: UIWindow?

    func update(scene: UIWindowScene?, lock: AppLock, method: AppLockMethod?, shows: Bool) {
      guard let scene, shows || window != nil else { return }
      if window == nil {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: LockScreen(lock: lock, method: method))
        self.window = window
      }
      window?.isHidden = !shows
      if shows { window?.makeKeyAndVisible() } else { scene.windows.first { $0 !== window }?.makeKey() }
    }
  }
}
