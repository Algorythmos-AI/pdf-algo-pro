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
