import CoreGraphics
import Testing

@testable import PDFEngine

/// The pages scroll while something is carried near the top or bottom, and the carried item stays on
/// its page.
@Suite("Scrolling at the edges while carrying")
struct EdgeScrollingTests {
  // A view showing 0 to 800 points.
  private let top: CGFloat = 0
  private let bottom: CGFloat = 800

  @Test("Away from the edges the pages stay still")
  func stillInTheMiddle() {
    for y in [EdgeScrolling.zone + 1, 400, bottom - EdgeScrolling.zone - 1] {
      #expect(EdgeScrolling.speed(at: y, top: top, bottom: bottom) == 0, "at y \(y)")
    }
  }

  @Test("Near the top the pages scroll back, near the bottom on, faster nearer the edge")
  func directionAndSpeed() {
    let grazingTop = EdgeScrolling.speed(at: EdgeScrolling.zone - 10, top: top, bottom: bottom)
    let deepTop = EdgeScrolling.speed(at: 10, top: top, bottom: bottom)
    #expect(grazingTop < 0 && deepTop < grazingTop, "top: grazing \(grazingTop), deep \(deepTop)")
    let grazingBottom = EdgeScrolling.speed(at: bottom - EdgeScrolling.zone + 10, top: top, bottom: bottom)
    let deepBottom = EdgeScrolling.speed(at: bottom - 10, top: top, bottom: bottom)
    #expect(grazingBottom > 0 && deepBottom > grazingBottom, "bottom: grazing \(grazingBottom), deep \(deepBottom)")
    #expect(EdgeScrolling.speed(at: bottom + 50, top: top, bottom: bottom) == EdgeScrolling.fastest)
    #expect(EdgeScrolling.speed(at: top - 50, top: top, bottom: bottom) == -EdgeScrolling.fastest)
  }

  @Test("A view too short for two zones never scrolls")
  func shortView() {
    #expect(EdgeScrolling.speed(at: 5, top: 0, bottom: EdgeScrolling.zone * 2) == 0)
  }

  @Test("A step stops where the page's edge reaches the finger, so the item stays on its page")
  func stopsAtThePageEdge() {
    // Scrolling on: the page's bottom is 30 points below the finger, so 30 points at most.
    let on = EdgeScrolling.step(
      speed: 900, seconds: 0.05, finger: 770, pageTop: -400, pageBottom: 800, offset: 1000, range: 0...5000)
    #expect(on == 30)
    // Scrolling back: the page's top is 20 points above the finger.
    let back = EdgeScrolling.step(
      speed: -900, seconds: 0.05, finger: 30, pageTop: 10, pageBottom: 900, offset: 1000, range: 0...5000)
    #expect(back == -20)
    // Already at the page's edge: no further.
    let atEdge = EdgeScrolling.step(
      speed: 900, seconds: 0.05, finger: 770, pageTop: -400, pageBottom: 760, offset: 1000, range: 0...5000)
    #expect(atEdge == 0)
  }

  @Test("A step stays within the scroller's range")
  func staysInRange() {
    let pastEnd = EdgeScrolling.step(
      speed: 900, seconds: 0.05, finger: 770, pageTop: -4000, pageBottom: 4000, offset: 4990, range: 0...5000)
    #expect(pastEnd == 10)
    let pastStart = EdgeScrolling.step(
      speed: -900, seconds: 0.05, finger: 30, pageTop: -4000, pageBottom: 4000, offset: 5, range: 0...5000)
    #expect(pastStart == -5)
    let free = EdgeScrolling.step(
      speed: 640, seconds: 0.0625, finger: 770, pageTop: -4000, pageBottom: 4000, offset: 1000, range: 0...5000)
    #expect(free == 40)
  }
}
