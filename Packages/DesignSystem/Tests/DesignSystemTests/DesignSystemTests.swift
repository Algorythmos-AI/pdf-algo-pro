import Core
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite("Design tokens")
struct DesignTokenTests {
  private func rgb(_ color: UIColor, in appearance: DynamicColor.Appearance) -> RGB {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.resolvedColor(with: appearance.traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return RGB(Double(red), Double(green), Double(blue))
  }

  @Test("Brand colours resolve differently in each of the four appearances")
  func brandResolvesPerAppearance() {
    let tint = DynamicColor.uiColor(
      light: RGB(0.4275, 0.1569, 0.8510), dark: RGB(0.6549, 0.5451, 0.9804),
      lightHighContrast: RGB(0.2980, 0.1137, 0.5843), darkHighContrast: RGB(0.7686, 0.7098, 0.9922))
    let values = DynamicColor.Appearance.allCases.map { rgb(tint, in: $0) }
    #expect(Set(values.map { "\(Int($0.red * 255))" }).count == 4)
    #expect(abs(values[0].red - 0.4275) < 1 / 255)
  }

  @Test("A prominent button's label meets 4.5:1 on its fill in every appearance (colour rule 3)")
  func prominentButtonContrast() {
    let fill = UIColor(Color.ds.brandFill)
    let label = UIColor(Color.ds.brandOnFill)
    for appearance in DynamicColor.Appearance.allCases {
      let ratio = RGB.contrast(rgb(label, in: appearance), rgb(fill, in: appearance))
      #expect(ratio >= 4.5, "\(appearance): \(ratio)")
    }
  }

  @Test("Brand tint meets 4.5:1 on system backgrounds in every appearance (WCAG 2.2 AA)")
  func brandTintContrast() {
    let tint = DynamicColor.uiColor(
      light: RGB(0.4275, 0.1569, 0.8510), dark: RGB(0.6549, 0.5451, 0.9804),
      lightHighContrast: RGB(0.2980, 0.1137, 0.5843), darkHighContrast: RGB(0.7686, 0.7098, 0.9922))
    for appearance in DynamicColor.Appearance.allCases {
      for background in [SystemColorName.systemBackground, .systemGroupedBackground] {
        let ratio = RGB.contrast(rgb(tint, in: appearance), rgb(background.uiColor, in: appearance))
        #expect(ratio >= 4.5, "\(appearance) on \(background): \(ratio)")
      }
    }
  }

  @Test("Secondary label meets 4.5:1 on every system background in every appearance (WCAG 2.2 AA)")
  func secondaryLabelContrast() {
    // design/tokens.json: color.system.labelSecondary (secondaryLabel is 3.3:1 on grouped backgrounds).
    let label = DynamicColor.uiColor(
      light: RGB(0.3686, 0.3686, 0.4000), dark: RGB(0.6314, 0.6314, 0.6588),
      lightHighContrast: RGB(0.2706, 0.2706, 0.2980), darkHighContrast: RGB(0.7686, 0.7686, 0.8000))
    let backgrounds: [SystemColorName] = [
      .systemBackground, .secondarySystemBackground, .systemGroupedBackground, .secondarySystemGroupedBackground,
    ]
    for appearance in DynamicColor.Appearance.allCases {
      for background in backgrounds {
        let ratio = RGB.contrast(rgb(label, in: appearance), rgb(background.uiColor, in: appearance))
        #expect(ratio >= 4.5, "\(appearance) on \(background): \(ratio)")
      }
    }
  }

  @Test("Text over the brand glow at its strongest keeps 4.5:1 in every appearance")
  func brandGlowContrast() {
    let tint = UIColor(Color.ds.brandTint)
    let labels = [UIColor(Color.ds.labelPrimary), UIColor(Color.ds.labelSecondary)]
    for appearance in DynamicColor.Appearance.allCases {
      for background in [SystemColorName.systemBackground, .systemGroupedBackground] {
        let washed = rgb(tint, in: appearance)
          .blended(over: rgb(background.uiColor, in: appearance), opacity: Opacities.brandGlow)
        for label in labels {
          let ratio = RGB.contrast(rgb(label, in: appearance), washed)
          #expect(ratio >= 4.5, "\(appearance) on \(background): \(ratio)")
        }
      }
    }
  }

  @Test("The company mark keeps its contrast on its tile, which is the same in every appearance")
  func companyMarkContrast() {
    let tile = UIColor(Color.ds.logoTile)
    for appearance in DynamicColor.Appearance.allCases {
      #expect(rgb(tile, in: appearance) == RGB(1, 1, 1))
      #expect(RGB.contrast(rgb(UIColor(Color.ds.logoMark), in: appearance), rgb(tile, in: appearance)) >= 4.5)
      #expect(RGB.contrast(rgb(UIColor(Color.ds.logoDotEnd), in: appearance), rgb(tile, in: appearance)) >= 3)
    }
  }

  @Test func blendingMixesTowardsTheBackground() {
    #expect(RGB(1, 0, 0).blended(over: RGB(0, 0, 1), opacity: 0) == RGB(0, 0, 1))
    #expect(RGB(1, 0, 0).blended(over: RGB(0, 0, 1), opacity: 1) == RGB(1, 0, 0))
    #expect(RGB(1, 1, 1).blended(over: RGB(0, 0, 0), opacity: 0.5) == RGB(0.5, 0.5, 0.5))
  }

  @Test func contrastFormulaMatchesKnownValues() {
    #expect(abs(RGB.contrast(RGB(0, 0, 0), RGB(1, 1, 1)) - 21) < 0.01)
    #expect(abs(RGB.contrast(RGB(0.5, 0.5, 0.5), RGB(0.5, 0.5, 0.5)) - 1) < 0.01)
  }

  @Test("Spacing sits on the 8-point grid with 4-point half-steps")
  func spacingGrid() {
    let values = [
      Spacing.s0, Spacing.s050, Spacing.s100, Spacing.s150, Spacing.s200, Spacing.s300, Spacing.s400, Spacing.s500,
      Spacing.s600, Spacing.s800,
    ]
    #expect(values.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    #expect(values == values.sorted())
    #expect(Sizes.targetMinimum == 44)
  }

  @Test("Every semantic token maps to its system colour", arguments: SystemColorName.allCases)
  func systemMapping(name: SystemColorName) {
    #expect(
      UIColor(DynamicColor.system(name)).resolvedColor(with: .current) == name.uiColor.resolvedColor(with: .current))
  }

  @Test func tokensAreExposedOnColor() {
    let colors: [Color] = [
      Color.ds.brandTint, Color.ds.brandStrong, Color.ds.brandFill, Color.ds.brandOnFill, Color.ds.intelligenceTint,
      Color.ds.intelligenceFill, Color.ds.intelligenceOnFill, Color.ds.backgroundPrimary, Color.ds.labelSecondary,
      Color.ds.statusWarning,
    ]
    #expect(colors.count == 10)
  }
}

@MainActor
@Suite("Brand marks")
struct BrandMarkTests {
  @Test("The app mark's image is in the package, written by the icon script")
  func appMarkImage() throws {
    let image = try #require(UIImage(named: "AppMark", in: .module, with: nil))
    #expect(image.size.width == image.size.height)
    #expect(image.size.width >= 120)
  }

  @Test("The company mark's outline fills its frame at any size and keeps its counter")
  func companyMarkOutline() {
    for side in [CGFloat(20), 218, 1_000] {
      let rect = CGRect(x: 10, y: 20, width: side, height: side * 258 / 218)
      let letter = AlgorythmosLetterform().path(in: rect)
      let bounds = letter.boundingRect
      // The stem reaches the right edge and the bowl the left; the dot above it reaches the top.
      #expect(abs(bounds.maxX - rect.maxX) < side * 0.01)
      #expect(abs(bounds.minX - rect.minX) < side * 0.01)
      #expect(bounds.maxY <= rect.maxY + side * 0.01)
      let dot = AlgorythmosDot().path(in: rect).boundingRect
      #expect(abs(dot.minY - rect.minY) < side * 0.01)
      #expect(abs(dot.width - dot.height) < 0.001)
      // The middle of the bowl is a hole, and the stem is solid.
      let hole = BrandGeometry.point(110, 160, in: rect)
      let stem = BrandGeometry.point(190, 160, in: rect)
      #expect(!letter.contains(hole, eoFill: true))
      #expect(letter.contains(stem, eoFill: true))
    }
  }

  @Test("The glow goes when Reduce Transparency or Increase Contrast is on, and the marks still draw")
  func glowRespectsAccessibilitySettings() {
    #expect(BrandGlow.isShown(reduceTransparency: false, contrast: .standard))
    #expect(!BrandGlow.isShown(reduceTransparency: true, contrast: .standard))
    #expect(!BrandGlow.isShown(reduceTransparency: false, contrast: .increased))
    let views: [AnyView] = [
      AnyView(CompanyMark().environment(\.layoutDirection, .rightToLeft)),
      AnyView(AppMark(side: 120).environment(\.colorScheme, .dark)),
    ]
    for view in views {
      #expect(ImageRenderer(content: view).uiImage != nil)
    }
  }
}

@MainActor
@Suite("Components")
struct ComponentTests {
  @Test("Every tier has a visible name", arguments: IntelligenceTier.allCases)
  func tierNames(tier: IntelligenceTier) {
    #expect(!String(localized: TierBadge.title(for: tier)).isEmpty)
  }

  @Test func reduceMotionRemovesAnimation() {
    #expect(Motion.standard(reduceMotion: true) == nil)
    #expect(Motion.standard(reduceMotion: false) != nil)
  }

  @Test("Components render at the largest accessibility size")
  func componentsRender() {
    let views: [AnyView] = [
      AnyView(TierBadge(tier: .onDevice)), AnyView(CitationChip(citation: Citation(pageIndex: 2)) {}),
      AnyView(GeneratedFootnote()), AnyView(ContractDisclosure()),
      AnyView(
        IntentCard(symbol: "doc", title: Text(verbatim: "Title"), detail: Text(verbatim: "Detail"), isSelected: true)),
      AnyView(Button("Go") {}.buttonStyle(.primary)), AnyView(Text(verbatim: "Card").cardStyle().readableWidth()),
      AnyView(Text(verbatim: "Moving").motion(value: 1)),
      AnyView(Text(verbatim: "Tap").minimumTarget()),
      AnyView(IconTile(systemName: "doc.on.doc")), AnyView(IconTile(systemName: "sparkles", tone: .intelligence)),
      AnyView(IconTile(systemName: "trash", tone: .quiet)), AnyView(BrandGlow().frame(height: 200)),
      AnyView(AppMark()), AnyView(CompanyMark()), AnyView(AlgorythmosMark().frame(width: 100)),
      AnyView(QuickAction(Text(verbatim: "Scan"), systemImage: "doc.viewfinder", prominence: .filled) {}),
      AnyView(QuickAction(Text(verbatim: "Import"), systemImage: "plus") {}),
    ]
    for view in views {
      let renderer = ImageRenderer(content: view.frame(width: 390).environment(\.dynamicTypeSize, .accessibility5))
      #expect(renderer.uiImage != nil)
    }
  }
}
