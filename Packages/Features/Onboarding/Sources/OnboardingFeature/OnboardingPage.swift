import SwiftUI

/// One page of the first-run introduction: one thing the installed build does (FR-ONB-001, FR-ONB-007).
public enum OnboardingPage: String, Sendable, CaseIterable, Identifiable {
  /// Scanning paper into a searchable PDF.
  case scan
  /// Filling in, signing and marking up.
  case sign
  /// Asking the on-device intelligence about a document.
  case ask
  /// Merging, reordering and protecting documents: the third page where intelligence is unavailable.
  case organize

  /// The page's name.
  public var id: String { rawValue }

  /// The page's headline.
  var title: Text {
    switch self {
    case .scan: Text("Scan to PDF", bundle: .module)
    case .sign: Text("Sign and mark up", bundle: .module)
    case .ask: Text("Ask your document", bundle: .module)
    case .organize: Text("Organise and protect", bundle: .module)
    }
  }

  /// One sentence about what the page shows.
  var detail: Text {
    switch self {
    case .scan:
      Text("Turn paper into searchable PDFs with the camera. Text is recognised on this device.", bundle: .module)
    case .sign: Text("Fill in forms, add your signature, highlight and add notes.", bundle: .module)
    case .ask:
      Text(
        "Get summaries and answers with page citations. It runs on this device, and nothing is sent anywhere.",
        bundle: .module)
    case .organize:
      Text("Merge documents, reorder pages and add a password. Your documents stay on this device.", bundle: .module)
    }
  }

  /// The symbol on the page's illustration.
  var symbol: String {
    switch self {
    case .scan: "doc.viewfinder"
    case .sign: "signature"
    case .ask: "sparkles"
    case .organize: "lock.doc"
    }
  }

  /// Whether the page is about the intelligence layer, which has its own colour.
  var usesIntelligence: Bool { self == .ask }
}
