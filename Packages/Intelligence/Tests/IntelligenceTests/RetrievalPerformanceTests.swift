import Core
import XCTest

@testable import Intelligence

/// The retrieval budget in docs/performance-budgets.md, measured by the Performance test plan (P9).
///
/// The fast pull-request plan skips this class; `scripts/ci/perf_gate.py` compares the median of three
/// iterations with the budget row.
final class RetrievalPerformanceTests: XCTestCase {
  /// Budget: retrieval over a 500-page PDF (chunks for an answer).
  ///
  /// Measured as ranking every page for a question, the step that grows with the document.
  func testRetrievalOver500Pages() {
    let pages = (0..<500).map {
      PageText(
        pageIndex: $0,
        text: "Page \($0 + 1). Clause \($0) sets out the payment terms, the notice period and the fees due.")
    }
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    measure(metrics: [XCTClockMetric()], options: options) {
      _ = Grounding.rank(pages, for: "What is the notice period for termination?")
    }
  }

  /// The same budget with words matched in their base forms, as internal builds do.
  func testRetrievalOver500PagesWithBaseForms() {
    let pages = (0..<500).map {
      PageText(
        pageIndex: $0,
        text: "Page \($0 + 1). Clause \($0) sets out the payment terms, the notice period and the fees due.")
    }
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    measure(metrics: [XCTClockMetric()], options: options) {
      _ = Grounding.rank(pages, for: "What is the notice period for termination?", forms: .base)
    }
  }
}
