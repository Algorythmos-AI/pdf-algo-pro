import SwiftUI

/// One page of the first-run introduction: one benefit of what the installed build does.
///
/// Together the pages tell one story: make a PDF, work on it, get more from it (FR-ONB-001,
/// FR-ONB-007).
public enum OnboardingPage: String, Sendable, CaseIterable, Identifiable {
  /// Create: scanning paper into a searchable PDF.
  case scan
  /// Work on it: signing, marking up, and putting pages in order.
  case sign
  /// Get more from it: asking the on-device intelligence about a document.
  case ask
  /// Get more from it, where intelligence is unavailable: merging, shrinking and finding.
  case organize

  /// The page's name.
  public var id: String { rawValue }

  /// The page's headline.
  var title: Text {
    switch self {
    case .scan: Text("Scan anything to PDF", bundle: .module)
    case .sign: Text("Edit, sign and organise", bundle: .module)
    case .ask: Text("Ask your documents", bundle: .module)
    case .organize: Text("Do more with every file", bundle: .module)
    }
  }

  /// One sentence about what the page shows.
  var detail: Text {
    switch self {
    case .scan:
      Text("Point the camera at paper and get a clean, searchable PDF in seconds.", bundle: .module)
    case .sign:
      Text("Add your signature, highlight, write notes, reorder pages and lock files with a password.", bundle: .module)
    case .ask:
      Text("Summaries and answers that show the pages they come from. It all runs on this device.", bundle: .module)
    case .organize:
      Text("Merge documents, make them smaller and find any word. Everything stays on this device.", bundle: .module)
    }
  }
}
