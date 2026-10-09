import CoreGraphics

/// Where the editor for a picked line goes: on the line itself, at the page's own size, growing
/// down when more is typed than the line holds.
///
/// Pure geometry, so every phone, tablet, orientation and zoom can be tested without a screen
/// (`TextEditPlacementTests`).
///
/// The editor once zoomed the page in to make small print bigger, held the page still, and moved
/// itself above the keyboard, away from its line: the page's own lines ran off the screen and the
/// editor lay over other text (the owner's reports, 2026-10-07 and 2026-10-08). Now the page keeps
/// the zoom the person chose, the editor never leaves its line, and the page scrolls under it to
/// keep it clear of the keyboard, as in Notes.
public enum TextEditPlacement {
  /// How far below the top of what can be seen a picked line that was off screen is put, as a
  /// share of that height, so the line above it is still in view.
  public static let lineDepth: CGFloat = 0.22

  /// Where the editor goes, and how big it is.
  ///
  /// It starts where the line starts and is as wide as the page's text from there, so what is typed
  /// wraps where the page's own lines end; it is as tall as what it holds, and never less than the
  /// line, which it covers.
  /// - Parameters:
  ///   - line: Where the line is on screen.
  ///   - column: The line widened to the right edge of the page's text, on screen.
  ///   - contentHeight: How tall the editor is at a given width, with all of its text laid out.
  /// - Returns: The editor's frame, in the same space as the line.
  public static func editor(over line: CGRect, column: CGRect, contentHeight: (CGFloat) -> CGFloat) -> CGRect {
    let width = max(line.width, column.maxX - line.minX)
    let height = max(contentHeight(width), line.height)
    return CGRect(x: line.minX, y: line.minY, width: width, height: height)
  }

  /// How far to scroll the page so the editor is in the part of the screen that can be seen: up
  /// for a positive distance, down for a negative one, and 0 when it is already in view.
  ///
  /// An editor taller than all the space there is shows its top, where its first words are.
  /// - Parameters:
  ///   - editor: Where the editor is on screen.
  ///   - visible: The part of the screen that is not under bars or the keyboard.
  ///   - margin: The space kept clear above and below the editor.
  /// - Returns: The distance, in screen points.
  public static func scrollDistance(for editor: CGRect, in visible: CGRect, margin: CGFloat) -> CGFloat {
    let room = visible.insetBy(dx: 0, dy: margin)
    guard room.height > 0, !editor.isEmpty else { return 0 }
    if editor.minY < room.minY || editor.height > room.height { return editor.minY - room.minY }
    if editor.maxY > room.maxY { return editor.maxY - room.maxY }
    return 0
  }

  /// How far to scroll the page, up and across, so the caret's line is in the part of the screen
  /// that can be seen, as Notes keeps the caret in view while the person types.
  ///
  /// Across matters once the page is zoomed in: the field is as wide as the page's text, which is
  /// then wider than the screen, and a wrapped line can end out of sight to the right.
  /// - Parameters:
  ///   - caret: The caret, or the end of the selection, on screen.
  ///   - visible: The part of the screen that is not under bars or the keyboard.
  ///   - margin: The space kept clear around the caret.
  /// - Returns: The distance, in screen points: positive `dy` scrolls the page up, positive `dx`
  ///   scrolls it to the left (bringing what is on the right into view).
  public static func revealDistance(for caret: CGRect, in visible: CGRect, margin: CGFloat) -> CGVector {
    let room = visible.insetBy(dx: margin, dy: margin)
    guard room.width > 0, room.height > 0, !caret.isNull, !caret.isInfinite else { return .zero }
    func distance(_ low: CGFloat, _ high: CGFloat, within lower: CGFloat, _ upper: CGFloat) -> CGFloat {
      if high - low > upper - lower || low < lower { return low - lower }
      if high > upper { return high - upper }
      return 0
    }
    return CGVector(
      dx: distance(caret.minX, caret.maxX, within: room.minX, room.maxX),
      dy: distance(caret.minY, caret.maxY, within: room.minY, room.maxY))
  }
}

/// Where the picked line is on screen, and at what zoom, as the page view last showed it.
///
/// The page view publishes it whenever it changes (a zoom, a scroll, a rotation, another size of
/// window), so the editor follows the line instead of measuring it once.
public struct TextEditAnchor: Equatable, Sendable {
  /// The text the editor is for.
  public var selection: TextRegionSelection
  /// Where the line is, in the page view's own space, which is also the space of the layer over it.
  public var lineFrame: CGRect
  /// The line widened to the right edge of the page's text, in the same space.
  public var columnFrame: CGRect
  /// View points per page point.
  public var scale: CGFloat
  /// Whether the page is shown turned (its `/Rotate`), so that text upright on the page is not
  /// upright on screen and the frames above are the line turned on its side.
  public var isPageTurned: Bool
  /// How big the page view was when the line was measured.
  ///
  /// When the screen turns, the layer over the page can take its new size before the line is
  /// measured again, on the next frame, and room made then is made for where the line used to be.
  /// The new size here says the line has been measured since.
  public var viewSize: CGSize
  /// Whether the page was moving when the line was measured.
  ///
  /// It is moved by the person, or settles by itself, as after the screen turns. It does not scroll
  /// for the editor then, so the editor waits for this to change.
  public var isPageMoving: Bool

  /// Creates an anchor.
  public init(
    selection: TextRegionSelection, lineFrame: CGRect, columnFrame: CGRect, scale: CGFloat, isPageTurned: Bool = false,
    viewSize: CGSize = .zero, isPageMoving: Bool = false
  ) {
    self.selection = selection
    self.lineFrame = lineFrame
    self.columnFrame = columnFrame
    self.scale = scale
    self.isPageTurned = isPageTurned
    self.viewSize = viewSize
    self.isPageMoving = isPageMoving
  }
}

extension TextEditAnchor {
  /// Whether the line was measured with the page view at a size: the size it has now, or the line
  /// is still where it was before the view last changed size.
  public func isMeasured(at size: CGSize) -> Bool {
    abs(viewSize.width - size.width) <= TextEditRoomRequest.tolerance
      && abs(viewSize.height - size.height) <= TextEditRoomRequest.tolerance
  }
}

/// A wish to scroll the page so the whole editor is in view, kept until the page is ready for it.
///
/// Room is asked for when the editor opens, when the keyboard or the bar takes more of the screen,
/// and when the page view changes size, as when the screen turns. A turn settles over several
/// frames: the page view and the layer over it take their new size first, the line is measured at
/// that size on the next frame, PDFKit fits the page to the new width after that, and the field
/// wraps again at the new zoom a layout pass later. Room made once, at any one of those steps, was
/// made for a line that then moved: on CI (2026-10-09) the field turned to landscape was left under
/// the bar, or scrolled under the top bar. So the request lasts until the field is seen in view, and
/// the page is scrolled for it only when the line was measured at the page view's present size, the
/// page is at rest, and the field has been laid out on that line.
///
/// Seen in view once is not the end either. PDFKit's fitting is not a scroll the page view can see
/// (`TextEditAnchor.isPageMoving` stays false), and between the new size and the new zoom the field
/// can be in view for a frame: a request that ended there left the field under the bar when the page
/// was fitted a moment later (CI, 2026-10-09, after a turn). So a field in view is looked at again
/// after `settleTime`, and the request ends only if nothing moved in between.
///
/// It is never met by moving a page the person is moving: a finger on the page ends it.
///
/// Pure, so each step of a turn can be tested without a screen (`TextEditPlacementTests`).
public struct TextEditRoomRequest: Equatable, Sendable {
  /// What to do about the request now.
  public enum Step: Equatable, Sendable {
    /// Nothing yet, until the next line or field is measured, for the reason given.
    case wait(Waiting)
    /// Scroll the page by this distance, up for a positive one, and then record it with
    /// `scrolled(for:)`.
    case scroll(CGFloat)
    /// The field is in view: record it with `sawInView(anchor:field:)` and ask again after
    /// `settleTime`, with the line and the field as they are then.
    case confirm
    /// The request is over: the field stayed in view, the person took the page, or the page was
    /// scrolled or looked at as often as one request may.
    case done
  }

  /// Why a request waits.
  public enum Waiting: String, Equatable, Sendable {
    /// The line has not been measured at the page view's present size yet.
    case notMeasured
    /// The page is moving: the person's glide or bounce.
    case moving
    /// The line has not been measured since the page was last scrolled for it.
    case scrolledHere
    /// The field has not been laid out yet.
    case noField
    /// The field is still where the line was before it moved.
    case notLaidOut
  }

  /// The most times one request scrolls the page: once, and again each time the page settles
  /// somewhere else after it (PDFKit fitting the page after a turn, the field wrapping again).
  ///
  /// `Assumption:` a turn settles within two moves after the first scroll; checked by the long-line
  /// UI test in landscape.
  public static let maximumScrolls = 3

  /// How long a field seen in view must stay where it is before the request ends, in seconds.
  ///
  /// `Assumption:` longer than the gap between the page view taking its new size and PDFKit fitting
  /// the page to it after a turn; checked by the long-line UI test in landscape.
  public static let settleTime: Double = 0.5

  /// The most times one request looks again at a field in view that moved in between, so a page that
  /// never stops moving by itself does not keep a request alive.
  public static let maximumChecks = 8

  /// Distances and differences of size smaller than this are rounding.
  public static let tolerance: CGFloat = 0.5

  /// The line the page was last scrolled for, until the line is measured where the scroll left it.
  public private(set) var scrolledFor: TextEditAnchor?

  /// How many times the page has been scrolled for this request.
  public private(set) var scrolls = 0

  /// The line and the field when the field was last seen in view, until it is looked at again.
  public private(set) var seenInView: Sighting?

  /// How many times the field has been seen in view for this request.
  public private(set) var checks = 0

  /// Where the line and the field were when the field was seen in view.
  public struct Sighting: Equatable, Sendable {
    /// Where the line was.
    public var anchor: TextEditAnchor
    /// Where the field was, in the same space.
    public var field: CGRect
  }

  /// A request for room, not yet met.
  public init() {}

  /// What to do about the request now.
  /// - Parameters:
  ///   - anchor: Where the line is, as the page view last measured it.
  ///   - field: Where the field is, as last laid out, in the same space; `nil` before it is.
  ///   - visible: The part of that space not under the bars or the keyboard.
  ///   - viewSize: The page view's size now; `nil` where there is no page view.
  ///   - margin: The space kept clear above and below the field.
  ///   - isPageTouched: Whether a finger is on the page, dragging or pinching it.
  /// - Returns: The step to take.
  public func step(
    anchor: TextEditAnchor, field: CGRect?, visible: CGRect, viewSize: CGSize?, margin: CGFloat, isPageTouched: Bool
  ) -> Step {
    // The person is moving the page: it stays where they put it.
    if isPageTouched { return .done }
    guard let viewSize, anchor.isMeasured(at: viewSize) else { return .wait(.notMeasured) }
    if anchor.isPageMoving { return .wait(.moving) }
    if anchor == scrolledFor { return .wait(.scrolledHere) }
    guard let field else { return .wait(.noField) }
    guard Self.isLaidOut(field, on: anchor.lineFrame) else { return .wait(.notLaidOut) }
    // The field is where its line is now.
    let editor = CGRect(origin: CGPoint(x: field.minX, y: anchor.lineFrame.minY), size: field.size)
    let distance = TextEditPlacement.scrollDistance(for: editor, in: visible, margin: margin)
    if abs(distance) <= Self.tolerance {
      // In view, and nothing moved since it was last seen so: the page has settled.
      if seenInView == Sighting(anchor: anchor, field: field) || checks >= Self.maximumChecks { return .done }
      return .confirm
    }
    if scrolls >= Self.maximumScrolls { return .done }
    return .scroll(distance)
  }

  /// Records that the field was seen in view, with the line where it was, so the request ends if
  /// both are still there when it is next asked.
  public mutating func sawInView(anchor: TextEditAnchor, field: CGRect) {
    seenInView = Sighting(anchor: anchor, field: field)
    checks += 1
  }

  /// Records that the page was scrolled for the line where it was, so the next step waits for the
  /// line measured where the scroll left it.
  public mutating func scrolled(for anchor: TextEditAnchor) {
    scrolledFor = anchor
    scrolls += 1
  }

  /// Whether a field was laid out on a line, rather than where the line was before it moved.
  ///
  /// It then starts at the line's top and covers it from end to end, and its height, which comes
  /// from wrapping its text at the line's zoom, is the height for this line too.
  public static func isLaidOut(_ field: CGRect, on line: CGRect) -> Bool {
    abs(field.minY - line.minY) <= 1 && field.minX <= line.minX + 1 && field.maxX >= line.maxX - 1
  }
}
