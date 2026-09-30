import os

/// Points of interest for the budgets in docs/performance-budgets.md (P9).
///
/// Each interval is named as in the budget table, so a run in Instruments (the Points of Interest
/// track) lines up with the budgets. The Performance test plan measures the same operations with
/// XCTest metrics, on the simulator in CI and on a device from Xcode.
public enum Signposts {
  /// The app's signposter, in the Points of Interest category.
  public static let signposter = OSSignposter(subsystem: "com.algorythmos.pdfalgopro", category: .pointsOfInterest)

  /// Starts an interval; end it with `end()`, usually in a `defer`.
  public static func begin(_ name: StaticString) -> Interval {
    Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
  }

  /// An interval that has started.
  public struct Interval: Sendable {
    let name: StaticString
    let state: OSSignpostIntervalState

    /// Ends the interval.
    public func end() {
      Signposts.signposter.endInterval(name, state)
    }
  }
}
