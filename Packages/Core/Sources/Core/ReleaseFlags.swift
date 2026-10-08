import Foundation

/// A flag that hides work in progress until it is complete, reviewed and translated (engineering
/// playbook, "Feature flags").
///
/// This is the one typed list of release flags. Each is off unless the build turns it on: the app
/// resolves the value once, at launch, where it composes its services, and nothing arrives
/// remotely. A flag is removed within one milestone of shipping on in an App Store release; a unit
/// test fails once the app's version reaches `removeBy`, so an expired flag blocks CI instead of
/// lingering.
public enum ReleaseFlag: String, CaseIterable, Sendable {
  /// Editing the existing text of a PDF (FR-EDIT-001, ADR-0025).
  case textEditing
  /// The strip of small pages, the zoom limits and the keyboard commands in the reader (FR-READ-002).
  case readingControls
  /// Recognition in more languages, found automatically, and a text layer placed word by word
  /// (FR-SCAN-002, ADR-0008).
  case widerRecognition
  /// Finding a word in another of its forms, in library search and in the pages chosen for a
  /// question (FR-LIB-004, FR-AI-001).
  case baseFormMatching
  /// Reading a scanned page as a document, paragraph by paragraph, so columns and tables come in
  /// the order they are read (FR-SCAN-004, ADR-0008).
  case documentRecognition

  /// The value in a build that does not turn the flag on.
  ///
  /// Release flags default to off.
  public var compiledDefault: Bool { false }

  /// The hat that owns the flag (GitHub governance, "Hats").
  public var owner: String {
    switch self {
    case .textEditing: "PDF engine"
    case .readingControls: "Reader"
    case .widerRecognition: "PDF engine"
    case .baseFormMatching: "Intelligence"
    case .documentRecognition: "PDF engine"
    }
  }

  /// The app version by which the flag must be gone: the feature is then simply part of the app.
  public var removeBy: String {
    switch self {
    case .textEditing: "1.1.0"
    case .readingControls: "1.1.0"
    case .widerRecognition: "1.1.0"
    case .baseFormMatching: "1.1.0"
    case .documentRecognition: "1.1.0"
    }
  }

  /// Whether a version has reached the one the flag must be removed by.
  ///
  /// - Parameter version: A version such as `1.0.2`; parts that are not numbers count as zero.
  /// - Returns: Whether the flag should already have been removed.
  public func isOverdue(atVersion version: String) -> Bool {
    func parts(_ text: String) -> [Int] { text.split(separator: ".").map { Int($0) ?? 0 } }
    let current = parts(version)
    let limit = parts(removeBy)
    for index in 0..<max(current.count, limit.count) {
      let left = index < current.count ? current[index] : 0
      let right = index < limit.count ? limit[index] : 0
      if left != right { return left > right }
    }
    return true
  }
}

/// Whether the person may edit a document's existing text right now.
///
/// Editing components know only this value. What decides it (a release flag, a purchase, a trial)
/// is composed by the app, so packaging can change without touching the editor or the reader.
public enum TextEditingAccess: Sendable, Equatable {
  /// Editing is offered and works.
  case available
  /// Editing is shown, and needs a purchase the person has not made.
  case locked
  /// Editing is not part of this build; nothing about it is shown.
  case hidden
}

/// Says whether text editing is available.
///
/// The answer can change (a purchase, a lapse), so it is asked each time editing is about to start.
public protocol TextEditingAccessProviding: Sendable {
  /// The access now.
  func textEditingAccess() async -> TextEditingAccess
}

/// An access that never changes: for tests, previews, and builds without a store.
public struct FixedTextEditingAccess: TextEditingAccessProviding {
  private let access: TextEditingAccess

  /// Creates a provider that always gives the same answer.
  public init(_ access: TextEditingAccess) {
    self.access = access
  }

  /// The access now.
  public func textEditingAccess() async -> TextEditingAccess { access }
}
