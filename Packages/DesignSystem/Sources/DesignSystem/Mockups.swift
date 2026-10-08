import SwiftUI

// The pictures the introduction and the subscription offer share: a phone drawn in SwiftUI with one of
// the app's own screens in it, over a made-up document. Nothing here is a screenshot or a photograph,
// so no real document is shown, the picture follows the appearance, and it costs no download size.
// Every picture is decoration beside words that say the same thing, so VoiceOver skips it.

extension EnvironmentValues {
  /// Whether the pictures may move by themselves (a scan line that sweeps, a signature that draws).
  ///
  /// The app turns it off where nothing should move unasked: in UI tests, which wait for the screen
  /// to be still. Reduce Motion stops the same movement whatever this says.
  @Entry public var playsDecorativeMotion: Bool = true
}

/// A phone, drawn: a dark body with rounded corners, the sensor island, and a screen of its own.
///
/// Its height follows its width. A page that has no room for all of it shows the top and lets the
/// rest fade (`fadingBottom()`).
public struct DeviceMockup<Screen: View>: View {
  private let width: CGFloat
  private let screen: Screen

  /// Creates a phone `width` points wide around a screen.
  public init(width: CGFloat = 264, @ViewBuilder screen: () -> Screen) {
    self.width = width
    self.screen = screen()
  }

  /// The phone.
  public var body: some View {
    let bezel = width * 0.034
    let corner = width * 0.17
    let body = RoundedRectangle(cornerRadius: corner, style: .continuous)
    screen
      .frame(width: width - bezel * 2, height: (width - bezel * 2) * 2.1)
      .background(Color.ds.backgroundGrouped)
      .clipShape(RoundedRectangle(cornerRadius: corner - bezel, style: .continuous))
      .overlay(alignment: .top) {
        Capsule().fill(Color.black).frame(width: width * 0.3, height: width * 0.085).padding(.top, width * 0.032)
      }
      .padding(bezel)
      // A phone's body is black in every appearance; the hairline keeps its edge on a dark background.
      .background(Color.black, in: body)
      .overlay(body.strokeBorder(Color.ds.separator, lineWidth: 1))
      .accessibilityHidden(true)
  }
}

extension View {
  /// Shows the top `height` points of a picture and fades its lower edge into whatever is behind it.
  public func fadingBottom(height: CGFloat) -> some View {
    frame(height: height, alignment: .top)
      .mask {
        LinearGradient(
          stops: [
            .init(color: .black, location: 0), .init(color: .black, location: 0.72),
            .init(color: .clear, location: 1),
          ],
          startPoint: .top, endPoint: .bottom)
      }
  }
}

/// The bar at the top of a screen in a mockup: the brand fill with a stroke where the title would be.
public struct MockupTitleBar: View {
  /// Creates the bar.
  public init() {}

  /// The bar.
  public var body: some View {
    Color.ds.brandFill
      .frame(height: 78)
      .overlay(alignment: .bottomLeading) {
        Capsule().fill(Color.ds.brandOnFill).frame(width: 72, height: 9).padding(Spacing.s150)
      }
  }
}

/// A made-up sheet of paper: a heading and lines where text would be.
///
/// Paper is white and its ink dark in every appearance, as a document is in the reader.
public struct SyntheticPage: View {
  /// The widths of the lines, as shares of the page's width; they repeat for a longer page.
  private static let shares: [CGFloat] = [0.5, 0.94, 0.86, 0.9, 0.62, 0.92, 0.78, 0.88, 0.7, 0.93, 0.56]
  private let lines: Int
  private let highlighted: Int?
  private let space: CGFloat

  /// Creates a page with a number of lines; `highlighted` marks one of them as a highlighter would,
  /// and `space` leaves that much paper empty under the last line, for a signature.
  public init(lines: Int = 9, highlighted: Int? = nil, space: CGFloat = 0) {
    self.lines = lines
    self.highlighted = highlighted
    self.space = space
  }

  /// The page.
  public var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(0..<lines, id: \.self) { index in
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(Color.black.opacity(index == 0 ? 0.6 : 0.16))
          .frame(height: index == 0 ? 7 : 5)
          .frame(maxWidth: .infinity)
          .scaleEffect(x: Self.shares[index % Self.shares.count], anchor: .leading)
          .background {
            if index == highlighted {
              RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.yellow.opacity(0.55)).padding(-3)
            }
          }
      }
    }
    .padding(Spacing.s150)
    .padding(.bottom, space)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
  }
}

/// The scanner's screen in a mockup: a sheet of paper on a dark desk, the corners the camera found,
/// and the line that sweeps down the page while it reads.
public struct ScanMockupScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.playsDecorativeMotion) private var playsMotion
  @State private var sweeps = false

  /// Creates the screen.
  public init() {}

  /// The screen.
  public var body: some View {
    ZStack {
      // What the camera sees around the paper.
      LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
      SyntheticPage(lines: 22)
        .padding(.horizontal, Spacing.s300)
        .padding(.top, 62)
        .padding(.bottom, Spacing.s400)
        .overlay {
          GeometryReader { proxy in
            ScanLine()
              .offset(y: proxy.size.height * (isStill ? 0.42 : (sweeps ? 0.9 : 0.14)))
              .animation(Motion.loop(duration: 2.6, isStill: isStill), value: sweeps)
          }
          .padding(.horizontal, Spacing.s150)
        }
        .overlay {
          CornerBrackets()
            .stroke(Color.ds.brandFill, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .padding(.horizontal, Spacing.s150)
            .padding(.top, 52)
            .padding(.bottom, Spacing.s300)
        }
    }
    .onAppear { sweeps = true }
  }

  private var isStill: Bool { reduceMotion || !playsMotion }
}

/// The scanner's line: a bright edge with the light it leaves behind it.
private struct ScanLine: View {
  var body: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [Color.ds.brandFill.opacity(0), Color.ds.brandFill.opacity(0.32)], startPoint: .top, endPoint: .bottom
      )
      .frame(height: 54)
      Capsule().fill(Color.ds.brandFill).frame(height: 3)
    }
    .offset(y: -57)
  }
}

/// The four corners a scanner draws around the page it has found.
struct CornerBrackets: Shape {
  nonisolated func path(in rect: CGRect) -> Path {
    let arm = min(rect.width, rect.height) * 0.16
    let radius = arm * 0.45
    var path = Path()
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
      (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
      (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1), (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
    ]
    for (corner, dx, dy) in corners {
      path.move(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
      path.addLine(to: CGPoint(x: corner.x, y: corner.y + radius * dy))
      path.addQuadCurve(to: CGPoint(x: corner.x + radius * dx, y: corner.y), control: corner)
      path.addLine(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
    }
    return path
  }
}
