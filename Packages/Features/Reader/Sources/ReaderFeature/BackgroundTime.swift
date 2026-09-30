import UIKit

/// Extra time from iOS to finish work after the app moves to the background.
public enum BackgroundTime {
  /// Asks for time to finish the named work; returns the call that ends the request.
  ///
  /// If the time runs out first, the request is ended then and iOS suspends the app. Work that can
  /// take longer, like recognising text, keeps checkpoints so it can resume.
  @MainActor
  public static func begin(_ name: String) -> @MainActor () -> Void {
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
      UIApplication.shared.endBackgroundTask(identifier)
      identifier = .invalid
    }
    return {
      guard identifier != .invalid else { return }
      UIApplication.shared.endBackgroundTask(identifier)
      identifier = .invalid
    }
  }
}
