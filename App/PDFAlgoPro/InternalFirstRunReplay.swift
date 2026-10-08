import Core
import Foundation

/// Shows first run again, once, the first time each new internal build is opened (PAP-053).
///
/// A TestFlight update keeps the app's settings, so someone who finished the introduction on one
/// build opens every later build on Home, and a change to first run or to the subscription offer
/// is never seen without going to Settings › Internal testing. Debug and Staging builds therefore
/// mark first run as not done when the build number differs from the one that last ran. Documents
/// and every other setting stay. App Store builds never call this: there, the introduction never
/// returns uninvited (FR-ONB-002).
struct InternalFirstRunReplay {
  /// Where the build number that last ran is kept.
  static let key = "internal.firstRun.build"

  let defaults: UserDefaults
  /// This build's number (`CFBundleVersion`).
  let build: String

  /// Marks first run as not done when this build has not run before, and remembers the build.
  ///
  /// - Returns: Whether first run will show again.
  @discardableResult
  func apply(to settings: any SettingsStoring) -> Bool {
    let last = defaults.string(forKey: Self.key)
    defaults.set(build, forKey: Self.key)
    var current = settings.load()
    guard Self.replays(lastBuild: last, build: build, hasCompletedOnboarding: current.hasCompletedOnboarding)
    else { return false }
    current.hasCompletedOnboarding = false
    settings.save(current)
    return true
  }

  /// Whether first run shows again.
  ///
  /// It does for a build that has not run before, on an install that has already been through
  /// first run. A new install shows first run anyway.
  static func replays(lastBuild: String?, build: String, hasCompletedOnboarding: Bool) -> Bool {
    hasCompletedOnboarding && lastBuild != build
  }
}
