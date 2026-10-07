import SwiftUI

/// Why the subscription offer is on screen.
///
/// It decides the headline and is recorded with the view.
public enum PaywallTrigger: String, Sendable, CaseIterable {
  /// Once, at the end of the first-run introduction.
  case onboarding
  /// The person asked for a Pro feature.
  case lockedFeature
  /// The day's free allowance is used.
  case allowanceReached
  /// The person opened it from Settings.
  case settings

  /// The offer's headline.
  var headline: Text {
    switch self {
    case .onboarding, .settings: Text("Do more with Pro", bundle: .module)
    case .lockedFeature: Text("This needs Pro", bundle: .module)
    case .allowanceReached: Text("You’ve used today’s free allowance", bundle: .module)
    }
  }

  /// The line under the headline.
  var explanation: Text {
    switch self {
    case .onboarding, .settings:
      Text("PDF Algo Pro is free to use. Pro removes the daily limits.", bundle: .module)
    case .lockedFeature:
      Text("The feature you chose is part of Pro. Everything you already use stays free.", bundle: .module)
    case .allowanceReached:
      Text("It starts again tomorrow. Pro has no daily limit.", bundle: .module)
    }
  }
}

/// One thing Pro adds.
///
/// The app lists only those the installed build does (FR-ONB-007).
public enum PaywallBenefit: String, Sendable, CaseIterable, Identifiable {
  /// No daily limit on scans saved.
  case unlimitedScans
  /// No daily limit on summaries, answers and extractions.
  case unlimitedIntelligence
  /// Changing the words already in a PDF.
  case textEditing

  /// The benefit's name.
  public var id: String { rawValue }

  var title: Text {
    switch self {
    case .unlimitedScans: Text("Unlimited scans", bundle: .module)
    case .unlimitedIntelligence: Text("Unlimited answers", bundle: .module)
    case .textEditing: Text("Edit PDF text", bundle: .module)
    }
  }

  var detail: Text {
    switch self {
    case .unlimitedScans: Text("Turn as much paper as you like into searchable PDFs.", bundle: .module)
    case .unlimitedIntelligence:
      Text("Summaries, answers and extraction on this device, with no daily limit.", bundle: .module)
    case .textEditing: Text("Change the words already in a PDF.", bundle: .module)
    }
  }

  var symbol: String {
    switch self {
    case .unlimitedScans: "doc.viewfinder"
    case .unlimitedIntelligence: "sparkles"
    case .textEditing: "character.cursor.ibeam"
    }
  }
}
