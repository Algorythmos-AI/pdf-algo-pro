import CoreGraphics
import Testing

@testable import PDFEngine

/// The editor for a picked line is never smaller than its text and never outside what can be seen,
/// on every screen the app runs on, in both orientations, at every zoom, with and without the
/// keyboard (the owner's report, 2026-10-08: a long line was cut off at the screen's edge).
@Suite("Text editing: where the editor goes")
struct TextEditPlacementTests {
  /// Screens, in points: iPhone SE, standard, Plus, Pro Max, iPad mini, iPad, iPad Pro; both ways up.
  static let screens: [CGSize] = [
    CGSize(width: 320, height: 568), CGSize(width: 375, height: 667), CGSize(width: 393, height: 852),
    CGSize(width: 430, height: 932), CGSize(width: 440, height: 956), CGSize(width: 744, height: 1133),
    CGSize(width: 1024, height: 1366), CGSize(width: 1366, height: 1024),
  ].flatMap { [$0, CGSize(width: $0.height, height: $0.width)] }

  /// Keyboard heights as a share of the screen: none, a phone's, and a short one (a hardware
  /// keyboard's bar).
  static let keyboards: [CGFloat] = [0, 0.42, 0.08]

  /// Line lengths, in characters of 11-point text: a word, a sentence, a long sentence, 200 and more.
  static let lengths = [1, 8, 30, 70, 210]

  /// Zooms the page may be at when the line is picked.
  static let zooms: [CGFloat] = [0.25, 0.5, 1, 2, 4]

  private static let margin: CGFloat = 8
  private static let pointSize: CGFloat = 11
  /// A rough average character width for the size, as a share of the size.
  private static let characterWidth: CGFloat = 0.5

  /// A stand-in for the text view: wraps the text at whole words of average width.
  private static func height(of characters: Int, size: CGFloat, width: CGFloat) -> CGFloat {
    let perLine = max(1, Int(width / (size * characterWidth)))
    let lines = max(1, (characters + perLine - 1) / perLine)
    return CGFloat(lines) * size * 1.2
  }

  @Test(
    "The zoom makes small print readable and fits the line to the width where it stays readable",
    arguments: TextEditPlacementTests.zooms)
  func zoom(current: CGFloat) {
    let range: ClosedRange<CGFloat> = 0.1...40
    for screen in Self.screens {
      let width = screen.width - 2 * Self.margin
      for length in Self.lengths {
        let lineWidth = CGFloat(length) * Self.pointSize * Self.characterWidth
        let scale = TextEditPlacement.scale(
          pointSize: Self.pointSize, lineWidth: lineWidth, current: current, range: range, width: width)
        // Readable.
        #expect(Self.pointSize * scale >= TextEditPlacement.legibleMinimum - 0.001)
        // The whole line fits, or the print is at the smallest readable size and the editor wraps.
        let fits = lineWidth * scale <= width + 0.001
        let atSmallest = abs(Self.pointSize * scale - TextEditPlacement.legibleMinimum) < 0.001
        #expect(fits || atSmallest, "\(screen) \(length) \(current) → \(scale)")
        // A zoom that was already right is left alone.
        if Self.pointSize * current >= TextEditPlacement.legibleMinimum, lineWidth * current <= width {
          #expect(scale == current)
        }
      }
    }
  }

  @Test("The zoom stays inside the page view's limits")
  func zoomLimits() {
    let tiny = TextEditPlacement.scale(pointSize: 1, lineWidth: 50, current: 1, range: 0.5...4, width: 300)
    #expect(tiny == 4)
    let huge = TextEditPlacement.scale(pointSize: 200, lineWidth: 5000, current: 1, range: 0.5...4, width: 300)
    #expect(huge == 0.5)
    #expect(TextEditPlacement.scale(pointSize: 0, lineWidth: 100, current: 9, range: 0.5...4, width: 300) == 4)
  }

  @Test(
    "The editor is inside what can be seen, above the keyboard, and as tall as its text or scrolling",
    arguments: TextEditPlacementTests.keyboards)
  func editorInView(keyboard: CGFloat) {
    for screen in Self.screens {
      let visible = CGRect(x: 0, y: 0, width: screen.width, height: screen.height * (1 - keyboard))
      let size = TextEditPlacement.legibleTarget
      for length in Self.lengths {
        let lineWidth = CGFloat(length) * size * Self.characterWidth
        // Top, middle and bottom; left edge, middle, right edge, and past either edge.
        for y in [0, visible.midY, visible.maxY - size, screen.height - size] {
          for x in [-40, 0, visible.midX, visible.maxX - lineWidth, visible.maxX - 4] {
            let line = CGRect(x: x, y: y, width: lineWidth, height: size * 1.2)
            let placed = TextEditPlacement.editor(over: line, in: visible, margin: Self.margin) {
              Self.height(of: length, size: size, width: $0 - Self.margin)
            }.frame
            let inner = visible.insetBy(dx: Self.margin, dy: Self.margin)
            #expect(placed.minY >= inner.minY - 0.001 && placed.maxY <= inner.maxY + 0.001, "\(screen) \(line)")
            #expect(placed.minX >= visible.minX && placed.maxX <= visible.maxX + 0.001, "\(screen) \(line)")
            #expect(placed.width >= 2 * Self.margin, "Room to type: \(placed)")
            let needed = Self.height(of: length, size: size, width: placed.width - Self.margin)
            // Never shorter than the text, unless held to all the height there is, where it scrolls.
            #expect(placed.height >= needed - 0.001 || abs(placed.height - inner.height) < 0.001)
          }
        }
      }
    }
  }

  @Test("A line that can be seen whole, with room under it, is edited where it is")
  func editorOverLine() {
    let visible = CGRect(x: 0, y: 0, width: 393, height: 500)
    let line = CGRect(x: 30, y: 120, width: 200, height: 18)
    let placed = TextEditPlacement.editor(over: line, in: visible, margin: 8) { _ in 18 }
    #expect(placed.isOverLine)
    #expect(placed.frame.minX == line.minX && placed.frame.minY == line.minY)
    // It runs to the visible edge, so no strip of the old words shows beside it.
    #expect(placed.frame.maxX == visible.maxX)
  }

  @Test("The owner's line, wider than the screen, starts at the margin and is shown whole")
  func editorForLongLine() {
    let visible = CGRect(x: 0, y: 0, width: 393, height: 420)
    let line = CGRect(x: 18, y: 300, width: 820, height: 22)
    var asked: [CGFloat] = []
    let placed = TextEditPlacement.editor(over: line, in: visible, margin: 8) { width in
      asked.append(width)
      return 22 * 3
    }
    #expect(!placed.isOverLine)
    #expect(placed.frame.minX == 8 && placed.frame.maxX == 393)
    #expect(placed.frame.height == 66, "All three wrapped lines")
    #expect(asked == [385], "Measured at the width it is shown at")
    #expect(placed.frame.maxY <= 412, "Above the bar and the keyboard")
  }

  @Test("Text taller than all the space there is fills it and scrolls")
  func editorTallerThanSpace() {
    let visible = CGRect(x: 0, y: 40, width: 700, height: 160)
    let line = CGRect(x: 20, y: 100, width: 300, height: 20)
    let placed = TextEditPlacement.editor(over: line, in: visible, margin: 8) { _ in 1000 }
    #expect(placed.frame == CGRect(x: 20, y: 48, width: 680, height: 144))
  }

  @Test("No space at all gives no editor rather than one with a negative size")
  func editorWithoutSpace() {
    let placed = TextEditPlacement.editor(
      over: CGRect(x: 0, y: 0, width: 10, height: 10), in: CGRect(x: 0, y: 0, width: 10, height: 10), margin: 8
    ) { _ in 20 }
    #expect(placed.frame == .zero)
  }
}
