#if INTERNAL_TOOLS
  import Core
  import Foundation

  /// Shows the whole first-run journey again on every new internal build (PAP-053, PAP-055).
  ///
  /// A TestFlight update keeps the app's settings, so without this an install that finished first run
  /// on one build opens every later build on Home, and the introduction and the subscription offer
  /// are never seen again. Debug and Staging builds therefore remember the last build whose first
  /// run was **completed**, and present first run from its first page whenever the build that is
  /// running is a different one.
  ///
  /// This is presentation state and nothing else. It never reads, changes or pretends anything
  /// about purchases: who has Pro, their transactions and their right to a trial stay the App
  /// Store's. Documents and every other setting stay too.
  ///
  /// The type and every use of it are compiled only where `INTERNAL_TOOLS` is defined, which is the
  /// Debug and Staging configurations (`project.yml`). An App Store build does not contain it, and
  /// there the introduction never returns uninvited (FR-ONB-002); `scripts/ci/invariants.py` and a
  /// check of the Release binary in CI hold that.
  struct InternalFirstRunReplay {
    /// Where the last build whose first run was completed is kept.
    static let key = "internal.firstRun.build"

    let defaults: UserDefaults
    /// The build that is running (`CFBundleVersion`).
    let build: String

    /// Whether this build's first run is still to be completed.
    var isDue: Bool { Self.isDue(lastCompletedBuild: defaults.string(forKey: Self.key), build: build) }

    /// Starts this launch: when this build's first run is due, marks first run as not done so that
    /// the introduction shows from its first page.
    ///
    /// - Returns: Whether this launch replays first run, the subscription offer included.
    func begin(with settings: any SettingsStoring) -> Bool {
      guard isDue else { return false }
      var current = settings.load()
      if current.hasCompletedOnboarding {
        current.hasCompletedOnboarding = false
        settings.save(current)
      }
      return true
    }

    /// Records this build as done.
    ///
    /// Called when the journey ends: the offer was closed, or a purchase led to the app.
    func complete() {
      defaults.set(build, forKey: Self.key)
    }

    /// Forgets which build was completed, so the next launch replays first run.
    func reset() {
      defaults.removeObject(forKey: Self.key)
    }

    /// Whether first run is due: no build has completed it here, or a different one did.
    static func isDue(lastCompletedBuild: String?, build: String) -> Bool {
      lastCompletedBuild != build
    }
  }
#endif
