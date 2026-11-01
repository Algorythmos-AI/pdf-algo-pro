import os

/// Points of interest for the budgets in docs/performance-budgets.md (P9).
///
/// Each interval is named as in the budget table, so a run in Instruments (the Points of Interest
/// track) lines up with the budgets. The Performance test plan measures the same operations with
/// XCTest metrics, on the simulator in CI and on a device from Xcode.
public enum Signposts {
  /// The app's signposter, in the Points of Interest category.
  public static let signposter = OSSignposter(subsystem: "com.algorythmos.pdfalgopro", category: .pointsOfInterest)

  /// Hears the name of each interval as it starts, so a test can check what a piece of work marks.
  ///
  /// A task local, so tests running side by side don't hear each other. Only tests set it.
  @TaskLocal public static var onBegin: (@Sendable (String) -> Void)?

  /// Starts an interval; end it with `end()`, usually in a `defer`.
  ///
  /// The name is a `StaticString`, so nothing from a document can get into a run's trace.
  public static func begin(_ name: StaticString) -> Interval {
    onBegin?(name.description)
    return Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
  }

  /// Runs work inside an interval.
  public static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
    let interval = begin(name)
    defer { interval.end() }
    return try work()
  }

  /// Runs asynchronous work inside an interval.
  public static func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
    let interval = begin(name)
    defer { interval.end() }
    return try await work()
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
