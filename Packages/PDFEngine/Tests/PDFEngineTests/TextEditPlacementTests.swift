import CoreGraphics
import Testing

@testable import PDFEngine

/// The editor for a picked line sits on the line itself, never smaller than its text, and the page
/// scrolls under it to keep it clear of the keyboard, on every screen the app runs on, in both
/// orientations, with and without the keyboard (the owner's reports, 2026-10-08).
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

  /// Line lengths, in characters: a word, a sentence, a long sentence, 200 and more.
  static let lengths = [1, 8, 30, 70, 210]

  private static let margin: CGFloat = 8
  /// A rough average character width for the size, as a share of the size.
  private static let characterWidth: CGFloat = 0.5

  /// A stand-in for the text view: wraps the text at whole characters of average width.
  private static func height(of characters: Int, size: CGFloat, width: CGFloat) -> CGFloat {
    let perLine = max(1, Int(width / (size * characterWidth)))
    let lines = max(1, (characters + perLine - 1) / perLine)
    return CGFloat(lines) * size * 1.2
  }

  @Test("The editor sits on its line, as wide as the page's text and as tall as what it holds")
  func editorOnLine() {
    for screen in Self.screens {
      // The page fits the screen; its text runs from one margin to the other.
      let columnRight = screen.width - 24
      for size in [6, 11, 15] as [CGFloat] {
        for length in Self.lengths {
          let lineWidth = min(CGFloat(length) * size * Self.characterWidth, columnRight - 24)
          for x in [24, screen.width / 2, columnRight - lineWidth] as [CGFloat] {
            for y in [0, screen.height / 2, screen.height - size] as [CGFloat] {
              let line = CGRect(x: x, y: y, width: lineWidth, height: size * 1.2)
              let column = CGRect(x: x, y: y, width: max(lineWidth, columnRight - x), height: line.height)
              let editor = TextEditPlacement.editor(over: line, column: column) {
                Self.height(of: length * 2, size: size, width: $0)
              }
              // On the line, never moved off it.
              #expect(editor.origin == line.origin, "\(screen) \(line)")
              // Wide enough for the line, and out to the page's text edge, no further.
              #expect(editor.width >= line.width && abs(editor.maxX - max(line.maxX, columnRight)) < 0.001)
              // Never shorter than what it holds, nor than the line it covers.
              let needed = Self.height(of: length * 2, size: size, width: editor.width)
              #expect(editor.height >= needed - 0.001 && editor.height >= line.height - 0.001)
            }
          }
        }
      }
    }
  }

  @Test(
    "Scrolling the page by the distance worked out brings the editor into what can be seen",
    arguments: TextEditPlacementTests.keyboards)
  func scrollBringsEditorIntoView(keyboard: CGFloat) {
    for screen in Self.screens {
      let visible = CGRect(x: 0, y: 0, width: screen.width, height: screen.height * (1 - keyboard))
      let room = visible.insetBy(dx: 0, dy: Self.margin)
      for height in [18, 60, 200, 2000] as [CGFloat] {
        for y in [-300, 0, visible.midY, visible.maxY - 10, screen.height + 100] as [CGFloat] {
          let editor = CGRect(x: 20, y: y, width: 300, height: height)
          let distance = TextEditPlacement.scrollDistance(for: editor, in: visible, margin: Self.margin)
          // Scrolling the page up by the distance moves the editor up by it.
          let after = editor.offsetBy(dx: 0, dy: -distance)
          if height <= room.height {
            #expect(after.minY >= room.minY - 0.001 && after.maxY <= room.maxY + 0.001, "\(screen) \(editor)")
          } else {
            // Taller than all the room there is: its first words are at the top.
            #expect(abs(after.minY - room.minY) < 0.001)
          }
          // An editor already in view does not move the page.
          if editor.minY >= room.minY, editor.maxY <= room.maxY { #expect(distance == 0) }
        }
      }
    }
  }

  @Test("The owner's line wraps under itself to the page's text edge, and scrolls clear of the keyboard")
  func ownersLine() {
    // The sample page, fitting a 393-point phone: text from 18 to 375.
    let line = CGRect(x: 18, y: 440, width: 330, height: 14)
    let column = CGRect(x: 18, y: 440, width: 357, height: 14)
    var asked: [CGFloat] = []
    let editor = TextEditPlacement.editor(over: line, column: column) { width in
      asked.append(width)
      return 14 * 3
    }
    #expect(editor == CGRect(x: 18, y: 440, width: 357, height: 42))
    #expect(asked == [357], "Measured at the width it is shown at")
    // The keyboard and its bar leave 460 points: the page scrolls up just enough.
    let visible = CGRect(x: 0, y: 0, width: 393, height: 460)
    let distance = TextEditPlacement.scrollDistance(for: editor, in: visible, margin: 8)
    #expect(distance == 440 + 42 - 452)
  }

  @Test("No room at all asks for no scrolling")
  func noRoom() {
    let editor = CGRect(x: 0, y: 100, width: 100, height: 20)
    let short = CGRect(x: 0, y: 0, width: 100, height: 10)
    let tall = CGRect(x: 0, y: 0, width: 100, height: 500)
    #expect(TextEditPlacement.scrollDistance(for: editor, in: short, margin: 8) == 0)
    #expect(TextEditPlacement.scrollDistance(for: .zero, in: tall, margin: 8) == 0)
  }
}
