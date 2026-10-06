import Foundation

/// What happened the last time existing text was looked for or edited, as counts only.
///
/// It goes into the "Report a problem" summary (FR-SET-003), so it holds nothing from the document:
/// no words, no font names, no file names, no positions. Every field is a number, a yes or no, or
/// one of a fixed set of words the app chose.
public struct TextEditingDiagnostics: Sendable, Equatable {
  /// What kind of text the page had.
  public enum PageKind: String, Sendable {
    case text, image, unreadable
    case timedOut = "timed-out"
  }

  /// How the last edit ended.
  public enum EditResult: Sendable, Equatable {
    case edited
    case tooLong
    /// Refused, with the engine's own name for the reason.
    case refused(String)
  }

  /// What kind of text the page had.
  public var pageKind: PageKind
  /// How many pieces of text can be changed in their own font.
  public var direct = 0
  /// How many can be changed with a matched font.
  public var limited = 0
  /// How many can only be covered, by the engine's name for the reason.
  public var coverOnly: [String: Int] = [:]
  /// How long finding the page's text took, in milliseconds.
  public var findMilliseconds = 0
  /// Whether the page view on screen belongs to the document being edited.
  public var viewIsBound = false
  /// How many pages on screen are showing outlines.
  public var outlinedPages = 0
  /// Taps on a page while editing text, and how many of them picked text.
  public var taps = 0
  /// Taps that picked text.
  public var picks = 0
  /// How the last edit ended, if one was made.
  public var lastEdit: EditResult?
  /// How long the last edit took, in milliseconds.
  public var editMilliseconds = 0
  /// The proof's check the last unproven edit failed, as the engine's fixed name for it.
  public var proofCheck: String?
  /// What that check measured, and the value it was measured against.
  public var proofMeasured = 0
  /// The limit or expected value of that check.
  public var proofExpected = 0
  /// How the rehearsal went when the page's text was found: lines that could be edited and proven,
  /// and lines that could not.
  public var rehearsalProven = 0
  /// Lines the rehearsal could not edit and prove.
  public var rehearsalUnproven = 0
  /// Since the document was opened: edits made in the page's content.
  public var made = 0
  /// Since the document was opened: texts covered, because they could not be edited.
  public var covered = 0
  /// Since the document was opened: edits refused with nothing changed.
  public var refusals = 0

  /// Creates a record for a page.
  public init(pageKind: PageKind) {
    self.pageKind = pageKind
  }

  /// The record as lines for the diagnostics summary.
  public var lines: [String] {
    var lines = [
      "Text editing page: \(pageKind.rawValue)",
      "Text editing regions: direct \(direct), matched font \(limited), cover only \(coverOnly.values.reduce(0, +))",
    ]
    lines += coverOnly.keys.sorted().map { "Text editing cover only (\(Self.safe($0))): \(coverOnly[$0] ?? 0)" }
    lines += [
      "Text editing find: \(findMilliseconds) ms",
      "Text editing view: \(viewIsBound ? "bound" : "not bound"), outlined pages \(outlinedPages)",
      "Text editing taps: \(taps), picked \(picks)",
    ]
    switch lastEdit {
    case .edited: lines.append("Text editing last edit: made, \(editMilliseconds) ms")
    case .tooLong: lines.append("Text editing last edit: too long, \(editMilliseconds) ms")
    case .refused(let reason):
      lines.append("Text editing last edit: refused (\(Self.safe(reason))), \(editMilliseconds) ms")
    case nil: break
    }
    if let proofCheck {
      lines.append("Text editing proof: \(Self.safe(proofCheck)) \(proofMeasured)/\(proofExpected)")
    }
    lines.append("Text editing rehearsal: proven \(rehearsalProven), not proven \(rehearsalUnproven)")
    lines.append("Text editing session: made \(made), covered \(covered), refused \(refusals)")
    return lines
  }

  /// A reason reduced to letters, and cut short, so that even a wrongly filled field cannot carry
  /// a document's words into the summary.
  static func safe(_ reason: String) -> String {
    String(reason.filter { $0.isASCII && $0.isLetter }.prefix(24))
  }
}

/// Keeps the latest `TextEditingDiagnostics`, in memory only.
///
/// On the main actor, like the document controller that writes to it, so records arrive in the
/// order they were made and the latest is the latest.
@MainActor
public final class TextEditingDiagnosticsLog {
  private var latest: TextEditingDiagnostics?

  /// Creates an empty log.
  public nonisolated init() {}

  /// Replaces the record.
  public func record(_ diagnostics: TextEditingDiagnostics) {
    latest = diagnostics
  }

  /// The lines for the diagnostics summary; none when text was never edited.
  public func summary() -> [String] {
    latest?.lines ?? []
  }
}
