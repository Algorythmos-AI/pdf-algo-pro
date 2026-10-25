#if DEBUG
  import Core

  /// App Lock's confirmation in a UI test: Face ID, with the answer the test chose
  /// (`-app-lock confirms` or `-app-lock refuses`), so the lock can be tested without a face.
  ///
  /// Debug builds only; the App Store build always asks the device (`LocalAuthenticator`).
  struct ScriptedAuthenticator: DeviceAuthenticating {
    /// Whether every confirmation succeeds.
    let confirms: Bool

    func method() -> AppLockMethod? { .faceID }

    func authenticate(reason: String) async -> Bool { confirms }
  }
#endif
