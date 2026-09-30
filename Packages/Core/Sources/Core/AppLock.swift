import Foundation

/// How this device confirms it is its owner, for App Lock (FR-SET-002).
public enum AppLockMethod: String, Sendable, CaseIterable {
  /// Face ID, with the passcode as a fallback.
  case faceID
  /// Touch ID, with the passcode as a fallback.
  case touchID
  /// Optic ID, with the passcode as a fallback.
  case opticID
  /// The device passcode only.
  case passcode
}

/// Confirms the device's owner is present (FR-SET-002).
public protocol DeviceAuthenticating: Sendable {
  /// How this device can confirm its owner, or `nil` when it can't (no passcode is set).
  func method() -> AppLockMethod?
  /// Asks the owner to confirm; returns whether they did.
  func authenticate(reason: String) async -> Bool
}
