import DesignSystem
import SwiftUI

/// The picture on an introduction page: a made-up page of text with the page's symbol on it.
///
/// It is drawn, not a screenshot, so it holds no real document and follows the appearance. It is
/// decoration: the headline and the sentence say everything, so VoiceOver skips it.
struct OnboardingIllustration: View {
  let page: OnboardingPage

  /// The widths of the made-up lines of text, as shares of the page's width.
  private static let lines: [CGFloat] = [0.55, 0.9, 0.82, 0.88, 0.6, 0.86, 0.74]
  /// The width the lines of text have to share, inside the page's margins.
  private static let textWidth: CGFloat = 152

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      sheet
      badge.offset(x: Spacing.s300, y: Spacing.s200)
    }
    .padding(.trailing, Spacing.s300)
    .padding(.bottom, Spacing.s200)
    .accessibilityHidden(true)
  }

  private var sheet: some View {
    VStack(alignment: .leading, spacing: Spacing.s150) {
      ForEach(Array(Self.lines.enumerated()), id: \.offset) { index, share in
        Capsule()
          .fill(index == 0 ? Color.ds.labelSecondary : Color.ds.fillPrimary)
          .frame(height: index == 0 ? 10 : 8)
          .frame(width: Self.textWidth * share)
      }
    }
    .padding(Spacing.s300)
    .frame(width: 200, height: 250, alignment: .topLeading)
    .background(Color.ds.backgroundGroupedElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ds.separator, lineWidth: 1))
    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
  }

  private var badge: some View {
    Image(systemName: page.symbol)
      .font(.system(size: 40, weight: .semibold))
      .foregroundStyle(page.usesIntelligence ? Color.ds.intelligenceOnFill : Color.ds.brandOnFill)
      .frame(width: 96, height: 96)
      .background(page.usesIntelligence ? Color.ds.intelligenceFill : Color.ds.brandFill, in: Circle())
      .overlay(Circle().strokeBorder(Color.ds.backgroundPrimary, lineWidth: 4))
  }
}
