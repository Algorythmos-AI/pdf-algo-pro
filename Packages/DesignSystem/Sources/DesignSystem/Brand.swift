import SwiftUI
import UIKit

// The brand moments (design system, principle 5): the app mark, the company mark, the glow behind the
// Home header, and the tinted tiles and quick actions that carry the brand tint. Everything here sits
// in the content layer: no glass, and every colour is a token.

/// A symbol on a small tinted tile, as the system's own Settings rows show theirs.
///
/// The tile is decoration beside a title that says the same thing, so it is hidden from VoiceOver.
public struct IconTile: View {
  /// What the tile's colour says.
  public enum Tone: Sendable {
    /// Something to open or change: the brand fill.
    case brand
    /// Something the intelligence layer does: the intelligence fill.
    case intelligence
    /// Something set aside, such as deleted documents: a quiet system fill.
    case quiet
  }

  private let systemName: String
  private let tone: Tone
  @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

  /// Creates a tile for an SF Symbol.
  public init(systemName: String, tone: Tone = .brand) {
    self.systemName = systemName
    self.tone = tone
  }

  /// The tile.
  public var body: some View {
    Image(systemName: systemName)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(foreground)
      .frame(width: side, height: side)
      .background(fill, in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
      .accessibilityHidden(true)
  }

  private var fill: Color {
    switch tone {
    case .brand: Color.ds.brandFill
    case .intelligence: Color.ds.intelligenceFill
    case .quiet: Color.ds.fillSecondary
    }
  }

  private var foreground: Color {
    switch tone {
    case .brand: Color.ds.brandOnFill
    case .intelligence: Color.ds.intelligenceOnFill
    case .quiet: Color.ds.labelSecondary
    }
  }
}

/// A list row's label with a tile before its title, as the system's own Settings rows have.
public struct TileLabel: View {
  private let title: Text
  private let systemImage: String
  private let tone: IconTile.Tone

  /// Creates a label.
  public init(_ title: Text, systemImage: String, tone: IconTile.Tone = .brand) {
    self.title = title
    self.systemImage = systemImage
    self.tone = tone
  }

  /// The label.
  public var body: some View {
    HStack(spacing: Spacing.s150) {
      IconTile(systemName: systemImage, tone: tone)
      title.foregroundStyle(Color.ds.labelPrimary)
    }
  }
}

/// A soft wash of the brand tint behind a screen's header.
///
/// It is strongest at the top and gone by its lower edge, and never stronger than `Opacities.brandGlow`,
/// at which secondary text over it keeps 4.5:1 (see the design-system tests). Reduce Transparency and
/// Increase Contrast remove it.
///
/// It is drawn in opaque colours, the tint already mixed into the background it lies on, so it looks as a
/// translucent wash over that background would. The accessibility audit read text over the translucent
/// wash against the tint itself: the paywall's explanation, near-black on a near-white wash (20:1 on
/// screen), failed its contrast check (CI, 2026-10-09), and so did the buttons over the wash.
public struct BrandGlow: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  private let background: Color

  /// Creates the glow over `background`, the opaque colour of the screen behind it.
  public init(over background: Color = Color.ds.backgroundPrimary) {
    self.background = background
  }

  /// The glow, or nothing when the person has asked for less transparency or more contrast.
  public var body: some View {
    if Self.isShown(reduceTransparency: reduceTransparency, contrast: contrast) {
      // Mixed in the device's colour space, as a translucent layer is composited over an opaque one.
      LinearGradient(
        colors: [background.mix(with: Color.ds.brandTint, by: Opacities.brandGlow, in: .device), background],
        startPoint: .top, endPoint: .bottom
      )
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  /// Whether the glow is drawn: not with Reduce Transparency, and not with Increase Contrast.
  nonisolated static func isShown(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
    !reduceTransparency && contrast == .standard
  }
}

/// The app's own mark: the app icon, as an image.
///
/// `scripts/design/make_app_icon.swift` writes the image from the icon's artwork, so the two never
/// differ. It is decoration beside the app's name, so it is hidden from VoiceOver.
public struct AppMark: View {
  @ScaledMetric private var side: CGFloat
  private let limit: CGFloat

  /// Creates the mark, `side` points wide at the default text size.
  ///
  /// It grows with the text size, to at most one and a half times `side`.
  public init(side: CGFloat = 56) {
    _side = ScaledMetric(wrappedValue: side, relativeTo: .title)
    limit = side * 1.5
  }

  /// The mark.
  public var body: some View {
    let width = min(side, limit)
    let shape = RoundedRectangle(cornerRadius: width * BrandGeometry.iconCornerRatio, style: .continuous)
    Image(uiImage: Self.image)
      .resizable()
      .interpolation(.high)
      .frame(width: width, height: width)
      .clipShape(shape)
      .overlay(shape.strokeBorder(Color.ds.separator, lineWidth: 0.5))
      .accessibilityHidden(true)
  }

  /// The mark's image, read once from the package's resources.
  ///
  /// It is a file beside the package's strings, not an asset-catalog entry, so it is read by its
  /// address: looking it up by name finds nothing in a package's bundle.
  static let image: UIImage = {
    let url = Bundle.module.url(forResource: "AppMark", withExtension: "png")
    return url.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage()
  }()
}

/// The Algorythmos company mark, on the light tile that keeps its contrast in every appearance.
///
/// The mark's own colours never change, so it is never drawn straight onto a dark background (design
/// system, colour rule 7). VoiceOver reads it as "Algorythmos".
public struct CompanyMark: View {
  @ScaledMetric private var side: CGFloat
  private let limit: CGFloat

  /// Creates the mark on its tile, `side` points wide at the default text size.
  ///
  /// It grows with the text size, to at most one and a half times `side`.
  public init(side: CGFloat = 28) {
    _side = ScaledMetric(wrappedValue: side, relativeTo: .footnote)
    limit = side * 1.5
  }

  /// The mark on its tile.
  public var body: some View {
    let width = min(side, limit)
    let shape = RoundedRectangle(cornerRadius: width * BrandGeometry.iconCornerRatio, style: .continuous)
    AlgorythmosMark()
      .padding(width * 0.2)
      .frame(width: width, height: width)
      .background(Color.ds.logoTile, in: shape)
      .overlay(shape.strokeBorder(Color.ds.separator, lineWidth: 0.5))
      // A logo is not mirrored in right-to-left languages.
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityElement()
      .accessibilityLabel(Text(verbatim: "Algorythmos"))
      .accessibilityAddTraits(.isImage)
  }
}

/// The Algorythmos mark itself: the letterform and its dot, in the company's colours.
///
/// Drawn from the outline of the logo on the company website, so it is sharp at any size and needs no
/// image file. Use `CompanyMark` on screen; this view has no background of its own.
public struct AlgorythmosMark: View {
  /// Creates the mark.
  public init() {}

  /// The mark, in its own proportions.
  public var body: some View {
    ZStack {
      AlgorythmosLetterform().fill(Color.ds.logoMark, style: FillStyle(eoFill: true))
      AlgorythmosDot()
        .fill(
          LinearGradient(
            colors: [Color.ds.logoDotStart, Color.ds.logoDotEnd], startPoint: .bottomLeading, endPoint: .topTrailing))
    }
    .aspectRatio(BrandGeometry.markSize.width / BrandGeometry.markSize.height, contentMode: .fit)
  }
}

/// The measurements the brand marks share.
nonisolated enum BrandGeometry {
  /// The corner radius of an app-icon shape, as a share of its width.
  static let iconCornerRatio: CGFloat = 0.2237
  /// The canvas the company mark's outline is measured on.
  static let markSize = CGSize(width: 218, height: 258)
  /// The dot's centre and radius on that canvas.
  static let dotCentre = CGPoint(x: 184.5, y: 31.5)
  static let dotRadius: CGFloat = 31.5

  /// The letterform's outline on that canvas.
  ///
  /// A row of two numbers is a point: the first of a group starts a new outline and the rest are
  /// straight lines. A row of six is a curve (two control points, then the end point). An empty row
  /// closes the outline.
  static let letterform: [[CGFloat]] = [
    [77.5, 62.0],
    [45.8, 67.0, 17.9, 90.5, 6.6, 121.9],
    [1.5, 136.1, 0.5, 142.3, 0.6, 160.0],
    [0.6, 173.4, 1.1, 178.1, 2.8, 185.2],
    [16.4, 240.0, 67.9, 270.0, 120.0, 253.4],
    [129.5, 250.4, 138.5, 245.1, 146.5, 237.7],
    [150.0, 234.6, 153.1, 232.0, 153.4, 232.0],
    [153.7, 232.0, 154.0, 236.5, 154.0, 242.0],
    [154.0, 252.0],
    [186.0, 252.0],
    [218.0, 252.0],
    [218.0, 159.4],
    [218.0, 66.8],
    [214.3, 69.8],
    [198.4, 82.3, 176.6, 83.4, 158.8, 72.6],
    [153.0, 69.1],
    [153.0, 76.7],
    [153.0, 84.2],
    [147.8, 79.5],
    [141.2, 73.7, 127.0, 66.6, 116.5, 63.9],
    [107.3, 61.5, 87.0, 60.6, 77.5, 62.0],
    [],
    [119.0, 117.0],
    [127.3, 118.4, 134.5, 121.9, 141.0, 127.7],
    [150.1, 135.9, 154.1, 145.7, 154.0, 160.0],
    [154.0, 169.2, 152.4, 176.0, 148.6, 182.4],
    [137.6, 201.2, 111.2, 208.3, 90.4, 198.0],
    [75.2, 190.6, 66.9, 173.1, 69.2, 153.5],
    [71.5, 133.8, 85.4, 119.9, 106.0, 116.7],
    [110.6, 116.0, 112.4, 116.0, 119.0, 117.0],
    [],
  ]

  /// Maps a point on the canvas into `rect`.
  static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(
      x: rect.minX + x / markSize.width * rect.width, y: rect.minY + y / markSize.height * rect.height)
  }
}

/// The letterform of the company mark.
struct AlgorythmosLetterform: Shape {
  nonisolated func path(in rect: CGRect) -> Path {
    var path = Path()
    var starts = true
    for row in BrandGeometry.letterform {
      switch row.count {
      case 2:
        let point = BrandGeometry.point(row[0], row[1], in: rect)
        if starts { path.move(to: point) } else { path.addLine(to: point) }
        starts = false
      case 6:
        path.addCurve(
          to: BrandGeometry.point(row[4], row[5], in: rect),
          control1: BrandGeometry.point(row[0], row[1], in: rect),
          control2: BrandGeometry.point(row[2], row[3], in: rect))
      default:
        path.closeSubpath()
        starts = true
      }
    }
    return path
  }
}

/// The dot of the company mark.
struct AlgorythmosDot: Shape {
  nonisolated func path(in rect: CGRect) -> Path {
    let centre = BrandGeometry.point(BrandGeometry.dotCentre.x, BrandGeometry.dotCentre.y, in: rect)
    let radius = BrandGeometry.dotRadius / BrandGeometry.markSize.width * rect.width
    return Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
  }
}

/// One of the few actions a screen puts in front of everything else, as a tile: a symbol over a title.
///
/// One tile on a screen may be `filled`; it counts as that screen's prominent button (design system,
/// buttons). At accessibility text sizes the symbol moves beside the title so the title has the width.
public struct QuickAction: View {
  /// How much the tile stands out.
  public enum Prominence: Sendable {
    /// The screen's one prominent action: the brand fill.
    case filled
    /// Any other action: a card with the symbol in the brand tint.
    case tonal
  }

  private let title: Text
  private let systemImage: String
  private let prominence: Prominence
  private let action: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  /// Creates a tile.
  public init(_ title: Text, systemImage: String, prominence: Prominence = .tonal, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.prominence = prominence
    self.action = action
  }

  /// The tile.
  public var body: some View {
    Button(action: action) {
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(HStackLayout(spacing: Spacing.s150)) : AnyLayout(VStackLayout(spacing: Spacing.s100))
      layout {
        Image(systemName: systemImage)
          .font(.title3.weight(.semibold))
          .foregroundStyle(prominence == .filled ? Color.ds.brandOnFill : Color.ds.brandTint)
          .accessibilityHidden(true)
        title
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(prominence == .filled ? Color.ds.brandOnFill : Color.ds.labelPrimary)
          .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .center)
          .fixedSize(horizontal: false, vertical: true)
        if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
      }
    }
    // A style of its own: several buttons share a list row on Home, and a plain or default style there
    // makes a tap on the row press all of them.
    .buttonStyle(QuickActionStyle(prominence: prominence))
  }
}

private struct QuickActionStyle: ButtonStyle {
  let prominence: QuickAction.Prominence

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    configuration.label
      .padding(.horizontal, Spacing.s150)
      .padding(.vertical, Spacing.s150)
      .frame(maxWidth: .infinity, minHeight: Sizes.targetMinimum * 1.5, maxHeight: .infinity)
      .background(prominence == .filled ? Color.ds.brandFill : Color.ds.backgroundGroupedElevated, in: shape)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(shape)
  }
}

extension RGB {
  /// This colour laid over `background` at an opacity, as the eye sees it.
  ///
  /// Used to check the contrast of text over a translucent wash such as `BrandGlow`.
  public func blended(over background: RGB, opacity: Double) -> RGB {
    func mix(_ top: Double, _ bottom: Double) -> Double { top * opacity + bottom * (1 - opacity) }
    return RGB(mix(red, background.red), mix(green, background.green), mix(blue, background.blue))
  }
}
