import CoreGraphics
import Foundation

/// A colour of text on a page, as red, green and blue from 0 to 1.
public struct TextColor: Hashable, Sendable {
  /// The red component.
  public let red: Double
  /// The green component.
  public let green: Double
  /// The blue component.
  public let blue: Double

  /// Creates a colour from its red, green and blue components.
  public init(_ red: Double, _ green: Double, _ blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Black, the colour of most text.
  public static let black = TextColor(0, 0, 0)
}

/// How a piece of existing text looks, so an editor can show a matching field.
public struct TextStyle: Hashable, Sendable {
  /// The PostScript name of the font the text is set in.
  public let fontName: String
  /// The size of the text on the page, in points.
  public let pointSize: Double
  /// Whether the font is bold.
  public let isBold: Bool
  /// Whether the font is italic.
  public let isItalic: Bool
  /// Whether every character has the same width.
  public let isMonospaced: Bool
  /// The text's colour.
  public let color: TextColor

  /// Creates a style.
  public init(
    fontName: String, pointSize: Double, isBold: Bool, isItalic: Bool, isMonospaced: Bool, color: TextColor
  ) {
    self.fontName = fontName
    self.pointSize = pointSize
    self.isBold = isBold
    self.isItalic = isItalic
    self.isMonospaced = isMonospaced
    self.color = color
  }
}

/// Why existing text cannot be changed in the page's own content.
///
/// A value for the interface to turn into words; the engine has no user-facing strings.
public enum TextEditRefusal: String, Hashable, Sendable, CaseIterable {
  /// The text cannot be read or matched: an unusual font, or text the engine could not interpret.
  case unsupportedFont
  /// The script needs shaping or runs right to left or top to bottom.
  case unsupportedScript
  /// The text is drawn with transparency, a pattern, an outline or as a clipping shape.
  case unsupportedDrawing
  /// Something else on the page is drawn over the text, or would be covered by the new text.
  case overlapsOtherContent
  /// The page is too large or too unusual to edit safely.
  case pageNotEditable
  /// The page has no text of its own: it is an image, for example a scan.
  case scanned
  /// The document's author does not allow its content to be changed.
  case restricted
  /// The result could not be proven correct, so nothing was changed.
  case notVerified
  /// The replacement is empty or has characters that cannot be drawn.
  case unsupportedCharacters
  /// The text changed underneath the edit (another edit, an undo, a reload); nothing was changed.
  case stale
  /// The work took longer than it is allowed; nothing was changed.
  case timedOut
}

extension TextEditRefusal {
  /// Whether this refusal says the text could not be edited in the page's content, as opposed to
  /// something being wrong with the replacement or the moment.
  ///
  /// Text refused this way can still be covered.
  public var meansNotEditableInPlace: Bool {
    switch self {
    case .notVerified, .overlapsOtherContent, .unsupportedFont, .unsupportedDrawing, .unsupportedScript,
      .pageNotEditable:
      true
    case .scanned, .restricted, .unsupportedCharacters, .stale, .timedOut: false
    }
  }
}

/// Why an edit may look slightly different from the surrounding text.
public enum TextEditLimit: String, Hashable, Sendable, CaseIterable {
  /// The exact font is not on the device and not complete in the document, so the closest match
  /// will be used.
  case fontSubstituted
}

/// What can be done with one piece of existing text.
public enum TextEditingCapability: Hashable, Sendable {
  /// The text can be changed in the page's content, in its own font.
  case direct
  /// The text can be changed in the page's content, with a limit.
  case limited(TextEditLimit)
  /// The text cannot be changed in the page's content; it can only be covered and replaced, which
  /// leaves the original text in the file.
  case visualReplacementOnly(TextEditRefusal)

  /// Whether an edit changes the page's own content (true editing), as opposed to covering it.
  public var editsContent: Bool {
    if case .visualReplacementOnly = self { false } else { true }
  }
}

/// Whether a document's existing text can be edited at all.
public enum TextEditability: Hashable, Sendable {
  /// Text can be edited.
  case editable
  /// The document is digitally signed; editing it happens in a copy.
  case signed
  /// The document's author does not allow its content to be changed.
  case restricted
}

/// What kind of text a page has.
public enum PageTextKind: Hashable, Sendable {
  /// The page has text of its own.
  case text
  /// The page shows no text of its own: it is an image, such as a scan, with or without a
  /// recognised text layer over it.
  case image
  /// The page could not be read safely, so nothing on it is offered for editing.
  case unreadable
  /// Finding the page's text took longer than it is allowed. Asking again tries again.
  case tookTooLong
}

/// The existing text of one page.
public struct EditablePageText: Hashable, Sendable {
  /// The page's regions, in the order they are drawn.
  public let regions: [EditableTextRegion]
  /// What kind of text the page has.
  public let kind: PageTextKind

  /// Creates a page's text.
  public init(regions: [EditableTextRegion], kind: PageTextKind) {
    self.regions = regions
    self.kind = kind
  }
}

/// A piece of existing text on a page that can be selected for editing: one run of text on one
/// line, in one font.
///
/// Regions are values. A future assistant can read them and propose `TextEdit`s without touching
/// the file.
public struct EditableTextRegion: Hashable, Sendable, Identifiable {
  /// Identifies the region among those of the same page content.
  ///
  /// It changes when the page changes.
  public let id: Int
  /// The text as it reads.
  public let text: String
  /// The region's bounding box in page space (PDF points, origin bottom-left, before page rotation).
  public let bounds: CGRect
  /// The angle of the text's baseline in page space, in radians; 0 for upright text.
  public let angle: Double
  /// How the text looks.
  public let style: TextStyle
  /// What can be done with it.
  public let capability: TextEditingCapability

  /// Creates a region.
  public init(
    id: Int, text: String, bounds: CGRect, angle: Double, style: TextStyle, capability: TextEditingCapability
  ) {
    self.id = id
    self.text = text
    self.bounds = bounds
    self.angle = angle
    self.style = style
    self.capability = capability
  }

  /// Whether the baseline is horizontal, so a text field can sit over the text.
  public var isUpright: Bool { abs(angle) < 0.01 }
}

/// A change to one region: replace its text.
public struct TextEdit: Hashable, Sendable {
  /// The region to change.
  public let regionID: Int
  /// The region's text when the edit was made; the edit is refused as stale if it no longer matches.
  public let original: String
  /// The new text.
  public let replacement: String
  /// How far to move the text, in page points; zero leaves it where it is.
  ///
  /// With `replacement` the same as the region's text, the edit only moves it.
  public let offset: CGVector

  /// Creates an edit of a region.
  public init(region: EditableTextRegion, replacement: String, offset: CGVector = .zero) {
    self.init(region: region, original: region.text, replacement: replacement, offset: offset)
  }

  /// Creates an edit of a region, saying what the region's text was when the edit was made.
  public init(region: EditableTextRegion, original: String, replacement: String, offset: CGVector = .zero) {
    regionID = region.id
    self.original = original
    self.replacement = replacement
    self.offset = offset
  }

  /// Whether the edit moves the text.
  public var moves: Bool { offset != .zero }
}

/// How an edit was made.
///
/// Recorded for every edit, so covering text is never counted as editing it.
public enum TextEditMode: String, Hashable, Sendable, CaseIterable {
  /// The page's content was changed and the new text is in the original font.
  case contentStream
  /// The page's content was changed and the new text is in the closest available font.
  case contentStreamWithFallbackFont
  /// The original text was covered and new text placed on top; the original is still in the file.
  case visualReplacement
}

/// What happened to one edit.
public enum TextEditOutcome: Hashable, Sendable {
  /// The edit was made.
  case edited(TextEditMode)
  /// The replacement does not fit where the text is; nothing was changed.
  case tooLong
  /// The edit was refused; nothing was changed.
  case refused(TextEditRefusal)

  /// Whether the edit was made.
  public var isEdited: Bool {
    if case .edited = self { true } else { false }
  }
}

/// Which check of the proof an edit failed, with the numbers that check measured.
///
/// For diagnosis only. It holds a fixed word and counts, never anything from the document, so it
/// can go into a problem report.
public struct TextEditProofFailure: Hashable, Sendable {
  /// The checks, in the order the proof makes them.
  public enum Check: String, Hashable, Sendable, CaseIterable {
    /// The edited page could not be read back at all.
    case reread
    /// The new text was not found where it was put.
    case newTextMissing
    /// The page has a different number of pieces of text than it should.
    case regionCount
    /// Another piece of text reads differently than before.
    case otherTextChanged
    /// Another piece of text is somewhere else, or another width.
    case otherTextMoved
    /// PDFKit, reading on its own, does not find the new text.
    case independentReader
    /// A page could not be drawn for comparing.
    case render
    /// The picture changed away from the edited text.
    case strayPixels
    /// Something else is already drawn where the new text goes.
    case occupied
    /// The new text cannot be seen.
    case noInk
  }

  /// The check that failed.
  public let check: Check
  /// What the check measured, and what it was measured against; zero where there is nothing.
  public let measured: Int
  /// The limit or the expected value.
  public let expected: Int

  /// Creates a failure.
  public init(_ check: Check, measured: Int = 0, expected: Int = 0) {
    self.check = check
    self.measured = measured
    self.expected = expected
  }
}

/// The result of applying edits to a page.
public struct TextEditResult: Sendable {
  /// The page with every edit made, as a one-page PDF; `nil` unless every edit was made.
  public let page: Data?
  /// What happened to each edit, in the order they were given.
  public let outcomes: [TextEditOutcome]
  /// The proof's check that failed, when the edits were made and then not proven.
  public let proofFailure: TextEditProofFailure?

  /// Creates a result.
  public init(page: Data?, outcomes: [TextEditOutcome], proofFailure: TextEditProofFailure? = nil) {
    self.proofFailure = proofFailure
    self.page = page
    self.outcomes = outcomes
  }
}

/// Finds the existing text of a page and changes it.
///
/// This is the boundary between the app and whatever edits page content. `ContentStreamTextEditor`
/// implements it with Core Graphics and Core Text; a commercial PDF SDK could implement it later
/// (ADR-0025) without the reader knowing. A page travels across it as a one-page PDF, so no PDFKit
/// or vendor type appears here.
public protocol PDFTextEditing: Sendable {
  /// The existing text of a page.
  ///
  /// - Parameter page: A one-page PDF.
  /// - Returns: The page's regions and what kind of text it has. A page that cannot be read safely
  ///   has no regions.
  func text(ofPage page: Data) async -> EditablePageText

  /// Applies edits to a page, all or nothing.
  ///
  /// - Parameters:
  ///   - edits: Changes to regions that `text(ofPage:)` returned for the same page.
  ///   - page: A one-page PDF.
  /// - Returns: The edited page when every edit could be made and proven; otherwise no page and the
  ///   reason for each edit.
  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult

  /// Tries out an edit to a region without keeping it; see the default.
  func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult
}

extension PDFTextEditing {
  /// Tries out an edit to learn whether this page can be edited at all: a region is replaced with
  /// its own words through the whole of `applying`, proof included, and the result is thrown away.
  ///
  /// The reader asks for this when it first finds a page's text, so that text which cannot be
  /// edited is offered for covering before the person types, not refused after.
  public func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
    await applying([TextEdit(region: region, replacement: region.text)], toPage: page)
  }
}
