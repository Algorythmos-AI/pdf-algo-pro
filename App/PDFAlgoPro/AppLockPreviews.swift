#if DEBUG
  import Core
  import SwiftUI

  // Previews of App Lock's cover for the design pass (PAP-070): locked with each way of unlocking,
  // at the largest accessibility text size, in dark appearance and right to left. The confirmation
  // is scripted, as in the UI tests.

  @MainActor private func lockScreen(_ method: AppLockMethod = .faceID) -> LockScreen {
    LockScreen(lock: AppLock(authenticator: ScriptedAuthenticator(confirms: true), isEnabled: { true }), method: method)
  }

  #Preview("Locked, Face ID") { lockScreen() }
  #Preview("Locked, largest text") { lockScreen().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Locked, dark") { lockScreen().preferredColorScheme(.dark) }
  #Preview("Locked, right to left") { lockScreen().environment(\.layoutDirection, .rightToLeft) }
  #Preview("Locked, Touch ID") { lockScreen(.touchID) }
  #Preview("Locked, passcode") { lockScreen(.passcode) }
#endif
