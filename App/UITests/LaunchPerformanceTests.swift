import XCTest

/// The launch budget in docs/performance-budgets.md, measured by the Performance test plan (P9).
///
/// The fast pull-request plan skips this class; `scripts/ci/perf_gate.py` compares the median of three
/// launches with the budget row.
@MainActor
final class LaunchPerformanceTests: XCTestCase {
  /// Budget: cold launch to the first frame.
  ///
  /// The library opens with nothing to show.
  func testColdLaunchToTheFirstFrame() {
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
      let app = XCUIApplication()
      app.launchArguments = ["-ui-testing", "-skip-onboarding"]
      app.launch()
    }
  }
}
