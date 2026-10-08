import CoreGraphics

/// Where the editor for a picked line goes, worked out from the line, the space that can be seen,
/// and the size of what is typed: the editor is never smaller than its text, and never wider or
/// taller than what can be seen.
///
/// Pure geometry, so every phone, tablet, orientation and zoom can be tested without a screen
/// (`TextEditPlacementTests`).
///
/// The editor used to be one unbroken line in a field that stopped at the screen's edge, on a page
/// zoomed by the size of the print alone. A line wider than the screen at that zoom was cut off,
/// with the caret out of sight and the page held still under the editor (the owner's reports,
/// 2026-10-07 and 2026-10-08). Here the zoom also fits the line's width where the print stays
/// readable, and where it cannot, the editor wraps the line, so no part of it is ever out of view.
public enum TextEditPlacement {
  /// The smallest the picked text is on screen, in points, before the page zooms in to edit it.
  ///
  /// `Assumption:` 13-point text is the smallest that is comfortable to type into on a phone, close
  /// to the system's smallest text style; checked in the device test plan.
  public static let legibleMinimum: CGFloat = 13
  /// The size small print is zoomed to on screen for editing, in points.
  ///
  /// `Assumption:` close to the system's body text size, so editing reads like any text field.
  public static let legibleTarget: CGFloat = 15
  /// How far below the top of what can be seen the picked line is put, as a share of that height,
  /// so the line above it is still in view.
  public static let lineDepth: CGFloat = 0.22
  /// The narrowest the editor is, as a share of the width that can be seen, so a few words fit on
  /// each of its lines even for text that starts close to the right edge.
  public static let minimumWidthShare: CGFloat = 0.5
  /// The lowest a line can be on screen and still be typed over in place, in points.
  ///
  /// Text smaller than this, where the page could not zoom far enough, is typed in the bar.
  public static let minimumInPlaceHeight: CGFloat = 12

  /// The zoom to edit a line at.
  ///
  /// The zoom changes only when it must: to make small print readable, and to bring a line that is
  /// wider than the screen back inside it as long as the print stays readable.
  /// - Parameters:
  ///   - pointSize: The size of the line's text, in page points.
  ///   - lineWidth: How wide the line is, in page points.
  ///   - scale: The zoom now: view points per page point.
  ///   - range: The smallest and largest zoom the page view allows.
  ///   - width: How much of the view's width the line can use, in view points.
  /// - Returns: The zoom, inside `range`.
  public static func scale(
    pointSize: CGFloat, lineWidth: CGFloat, current scale: CGFloat, range: ClosedRange<CGFloat>, width: CGFloat
  ) -> CGFloat {
    guard pointSize > 0, scale > 0, scale.isFinite else { return clamp(scale, to: range) }
    var target = scale
    if pointSize * target < legibleMinimum { target = legibleTarget / pointSize }
    if lineWidth > 0, width > 0, lineWidth * target > width {
      // As much of the line as fits, but never smaller than readable: past that, the editor wraps.
      target = max(width / lineWidth, legibleMinimum / pointSize)
    }
    return clamp(target, to: range)
  }

  /// Where the editor goes.
  public struct Frame: Equatable, Sendable {
    /// The editor's frame, in the same space as the line and the visible area.
    public var frame: CGRect
    /// Whether the editor lies over the line itself, where the old words are.
    public var isOverLine: Bool
  }

  /// Where the editor goes, and how big it is.
  ///
  /// - The text starts where the line starts when the whole line can be seen; otherwise it starts at
  ///   the visible area's margin and uses the whole width there is, wrapping as it needs. The page
  ///   view's own zoom (`scale(pointSize:lineWidth:current:range:width:)`) brings a line inside the
  ///   view wherever the print stays readable, so the editor lies over the line whenever it can.
  /// - It runs to the visible area's edge, so no strip of the old words shows beside it, and grows
  ///   down to fit what is typed.
  /// - It lies over the line when it fits there; otherwise it is moved up just enough to stay above
  ///   whatever is below the visible area (the keyboard and its bar), and when even that is too
  ///   little room, it fills the visible area and scrolls.
  /// - Parameters:
  ///   - line: Where the line is on screen.
  ///   - visible: The part of the screen that is not under bars or the keyboard.
  ///   - margin: The space kept clear at the visible area's edges.
  ///   - contentHeight: How tall the editor is at a given width, with all of its text laid out.
  /// - Returns: The editor's frame, inside `visible`, and whether it lies over the line.
  public static func editor(
    over line: CGRect, in visible: CGRect, margin: CGFloat, contentHeight: (CGFloat) -> CGFloat
  ) -> Frame {
    let inner = visible.insetBy(dx: margin, dy: margin)
    guard inner.width > 0, inner.height > 0 else { return Frame(frame: .zero, isOverLine: false) }
    let lineIsInView = line.minX >= visible.minX && line.maxX <= visible.maxX
    let minimumWidth = visible.width * minimumWidthShare
    let startsAtLine = lineIsInView && visible.maxX - line.minX >= minimumWidth
    // A line that starts close to the right edge: the editor keeps a usable width and starts
    // further left. A line wider than what can be seen: the editor uses all of the width.
    let x = startsAtLine ? line.minX : lineIsInView ? min(line.minX, visible.maxX - minimumWidth) : inner.minX
    let width = visible.maxX - x
    let height = max(contentHeight(width), lineIsInView ? line.height : 0)
    let fitsOverLine = line.minY >= inner.minY && line.minY + height <= inner.maxY
    if startsAtLine, fitsOverLine {
      return Frame(frame: CGRect(x: x, y: line.minY, width: width, height: height), isOverLine: true)
    }
    let shown = min(height, inner.height)
    let y = min(max(line.minY, inner.minY), inner.maxY - shown)
    return Frame(frame: CGRect(x: x, y: y, width: width, height: shown), isOverLine: false)
  }

  private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    min(range.upperBound, max(range.lowerBound, value))
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
  /// View points per page point.
  public var scale: CGFloat

  /// Creates an anchor.
  public init(selection: TextRegionSelection, lineFrame: CGRect, scale: CGFloat) {
    self.selection = selection
    self.lineFrame = lineFrame
    self.scale = scale
  }
}
