import CoreGraphics

/// How the pages scroll while something is carried near the top or bottom of the view: a selected
/// annotation, or a line of text held to be moved.
///
/// Holding still never scrolls the pages under a carried annotation (#188, #194), so without this a
/// shape could only be taken as far as the screen shows. Near an edge the pages scroll that way, faster
/// the nearer the finger, as Notes and Files do. The carried item stays on its page: the scrolling stops
/// where the page's edge reaches the finger.
enum EdgeScrolling {
  /// How far from the top or the bottom, in points, a finger starts the pages scrolling.
  static let zone: CGFloat = 72
  /// The fastest scroll, in points a second, with the finger at the edge or beyond it.
  static let fastest: CGFloat = 900

  /// The scroll speed, in points a second, for a finger at `y` in a view showing `top` to `bottom`:
  /// negative scrolls back toward the start, positive on toward the end, zero away from the edges.
  ///
  /// It grows with the square of how far into the zone the finger is, so a finger that only grazes
  /// the zone moves the pages slowly enough to place something exactly.
  static func speed(at y: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
    guard bottom - top > 2 * zone else { return 0 }
    if y < top + zone {
      let depth = min(1, (top + zone - y) / zone)
      return -fastest * depth * depth
    }
    if y > bottom - zone {
      let depth = min(1, (y - (bottom - zone)) / zone)
      return fastest * depth * depth
    }
    return 0
  }

  /// How far to scroll in one step: `speed` for `seconds`, within the scroller's `range` of offsets,
  /// and no further than brings the carried item's page edge to the finger.
  ///
  /// - Parameters:
  ///   - speed: from `speed(at:top:bottom:)`, in points a second.
  ///   - seconds: how long this step lasts.
  ///   - finger: where the finger is, in the view's coordinates.
  ///   - pageTop: where the top of the carried item's page is now, in the same coordinates.
  ///   - pageBottom: where the bottom of that page is now.
  ///   - offset: the scroller's offset now.
  ///   - range: the offsets the scroller can take.
  /// - Returns: the change of offset; positive scrolls on toward the end of the document.
  static func step(
    speed: CGFloat, seconds: CGFloat, finger: CGFloat, pageTop: CGFloat, pageBottom: CGFloat, offset: CGFloat,
    range: ClosedRange<CGFloat>
  ) -> CGFloat {
    var change = speed * seconds
    // Scrolling on moves the page up the screen: it stops once the page's bottom is at the finger.
    // Scrolling back moves it down: it stops once the page's top is at the finger.
    change = change > 0 ? min(change, max(0, pageBottom - finger)) : max(change, min(0, pageTop - finger))
    return min(max(offset + change, range.lowerBound), range.upperBound) - offset
  }
}
