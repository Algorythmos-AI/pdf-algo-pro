import DesignSystem
import SwiftUI

/// The picture on an introduction page: a phone showing what the page is about, over a made-up
/// document, with the tools or the result of that page floating beside it.
///
/// It is drawn, not a screenshot, so it holds no real document and follows the appearance. Only the
/// top of the phone shows, and its lower edge fades into the page. It is decoration: the headline
/// and the sentence say everything, so VoiceOver skips it.
struct OnboardingIllustration: View {
  let page: OnboardingPage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.playsDecorativeMotion) private var playsMotion
  @State private var hasArrived = false

  /// How much of the phone shows above the fade.
  private static let height: CGFloat = 392

  var body: some View {
    ZStack {
      // A soft pool of the page's colour behind the phone gives the picture its depth.
      Circle()
        .fill(tint.opacity(0.14))
        .frame(width: 330, height: 330)
        .blur(radius: 36)
        .offset(y: -Spacing.s300)
      DeviceMockup(width: 276) {
        switch page {
        case .scan: ScanMockupScreen()
        case .sign: SignScreen()
        case .ask: AskScreen()
        case .organize: OrganizeScreen()
        }
      }
      .fadingBottom(height: Self.height)
      accents
    }
    .frame(height: Self.height)
    .onAppear { hasArrived = true }
    .accessibilityHidden(true)
  }

  private var isStill: Bool { reduceMotion || !playsMotion }

  private var tint: Color { page == .ask ? Color.ds.intelligenceTint : Color.ds.brandTint }

  /// What the page gives, as tiles beside the phone: they arrive one after another, or are simply
  /// there when the picture is to be still.
  private var accents: some View {
    let symbols = page.accents
    return ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
      FloatingTile(systemName: symbol, tint: tint)
        .scaleEffect(isStill || hasArrived ? 1 : 0.6)
        .opacity(isStill || hasArrived ? 1 : 0)
        .offset(Self.places[index % Self.places.count])
        .animation(
          isStill ? nil : .spring(duration: 0.5, bounce: 0.35).delay(0.25 + Double(index) * 0.12), value: hasArrived)
    }
  }

  /// Where the tiles sit around the phone, from its centre: two on the right, one on the left.
  private static let places: [CGSize] = [
    CGSize(width: 142, height: -92), CGSize(width: 150, height: -20), CGSize(width: -146, height: 34),
  ]
}

extension OnboardingPage {
  /// The symbols on the tiles beside the page's phone: its tools, or what comes of it.
  var accents: [String] {
    switch self {
    case .scan: ["camera.fill", "text.viewfinder", "doc.fill"]
    case .sign: ["signature", "highlighter", "lock.fill"]
    case .ask: ["sparkles", "text.bubble.fill", "list.bullet.rectangle"]
    case .organize: ["rectangle.stack.fill", "arrow.down.right.and.arrow.up.left", "magnifyingglass"]
    }
  }
}

/// A tile that floats beside the phone, lifted off the page by its shadow.
private struct FloatingTile: View {
  let systemName: String
  let tint: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 22, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: 54, height: 54)
      .background(Color.ds.backgroundGroupedElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ds.separator, lineWidth: 0.5))
      .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
  }
}

/// A document in the reader with a line highlighted and a signature that draws itself under it.
private struct SignScreen: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.playsDecorativeMotion) private var playsMotion
  @State private var isSigned = false

  var body: some View {
    VStack(spacing: 0) {
      MockupTitleBar()
      SyntheticPage(lines: 8, highlighted: 3, space: 84)
        .overlay(alignment: .bottom) {
          VStack(spacing: Spacing.s050) {
            Signature()
              .trim(from: 0, to: isStill || isSigned ? 1 : 0)
              .stroke(Color.black, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
              .frame(width: 132, height: 54)
              .animation(Motion.once(duration: 1.6, isStill: isStill), value: isSigned)
            Capsule().fill(Color.black.opacity(0.3)).frame(width: 150, height: 1.5)
          }
          .padding(.bottom, Spacing.s200)
        }
        .padding(Spacing.s200)
      Spacer(minLength: 0)
    }
    .onAppear { isSigned = true }
  }

  private var isStill: Bool { reduceMotion || !playsMotion }
}

/// A made-up signature: loops and a tail, no letters of any name.
private struct Signature: Shape {
  nonisolated func path(in rect: CGRect) -> Path {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
    var path = Path()
    path.move(to: point(0.02, 0.72))
    path.addCurve(to: point(0.2, 0.08), control1: point(0.08, 0.5), control2: point(0.16, 0.14))
    path.addCurve(to: point(0.16, 0.92), control1: point(0.26, 0.0), control2: point(0.2, 0.7))
    path.addCurve(to: point(0.42, 0.42), control1: point(0.14, 1.04), control2: point(0.34, 0.5))
    path.addCurve(to: point(0.4, 0.74), control1: point(0.5, 0.34), control2: point(0.36, 0.7))
    path.addCurve(to: point(0.6, 0.46), control1: point(0.46, 0.8), control2: point(0.54, 0.5))
    path.addCurve(to: point(0.62, 0.72), control1: point(0.66, 0.42), control2: point(0.58, 0.7))
    path.addCurve(to: point(0.98, 0.4), control1: point(0.7, 0.78), control2: point(0.86, 0.5))
    return path
  }
}

/// A document with the assistant's answer over it: a few lines and the pages they cite.
private struct AskScreen: View {
  var body: some View {
    VStack(spacing: 0) {
      MockupTitleBar()
      SyntheticPage(lines: 7)
        .padding(Spacing.s200)
        .overlay(alignment: .bottom) { answer.offset(y: 64).padding(.horizontal, Spacing.s100) }
      Spacer(minLength: 0)
    }
  }

  private var answer: some View {
    VStack(alignment: .leading, spacing: Spacing.s100) {
      HStack(spacing: Spacing.s100) {
        IconTile(systemName: "sparkles", tone: .intelligence)
        Capsule().fill(Color.ds.labelPrimary.opacity(0.7)).frame(width: 84, height: 7)
      }
      ForEach([1, 0.92, 0.6], id: \.self) { share in
        Capsule().fill(Color.ds.fillPrimary).frame(height: 6).frame(maxWidth: .infinity)
          .scaleEffect(x: share, anchor: .leading)
      }
      HStack(spacing: Spacing.s050) {
        ForEach(0..<2, id: \.self) { _ in
          Capsule().fill(Color.ds.intelligenceFill.opacity(0.22)).frame(width: 38, height: 16)
        }
      }
    }
    .padding(Spacing.s150)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.ds.backgroundGroupedElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ds.intelligenceTint, lineWidth: 1.5)
    )
    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
  }
}

/// Pages laid out to be put in order, one of them locked.
private struct OrganizeScreen: View {
  var body: some View {
    VStack(spacing: 0) {
      MockupTitleBar()
      Grid(horizontalSpacing: Spacing.s150, verticalSpacing: Spacing.s150) {
        GridRow {
          SyntheticPage(lines: 6)
          SyntheticPage(lines: 6).overlay(alignment: .bottomTrailing) { badge("lock.fill") }
        }
        GridRow {
          SyntheticPage(lines: 6).overlay(alignment: .bottomTrailing) { badge("plus") }
          SyntheticPage(lines: 6)
        }
      }
      .padding(Spacing.s200)
      Spacer(minLength: 0)
    }
  }

  private func badge(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.caption.weight(.bold))
      .foregroundStyle(Color.ds.brandOnFill)
      .frame(width: 30, height: 30)
      .background(Color.ds.brandFill, in: Circle())
      .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
      .offset(x: 6, y: 6)
  }
}
