import Core
import SwiftUI

/// The prominent button: brand fill with an explicit label colour, so dark mode keeps 4.5:1 contrast
/// (design system, colour rule 3), and at least the 44-point target size.
public struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  /// Creates the style.
  public init() {}

  /// Draws the button.
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(Color.ds.brandOnFill)
      .frame(maxWidth: .infinity, minHeight: Sizes.targetMinimum)
      .padding(.horizontal, Spacing.s200)
      .background(Color.ds.brandFill.opacity(isEnabled ? 1 : 0.4), in: Capsule())
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Capsule())
  }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
  /// The design system's prominent button.
  public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Content-layer cards: grouped background, never Liquid Glass (design system, principle 3).
public struct CardModifier: ViewModifier {
  /// Applies the card background and inset.
  public func body(content: Content) -> some View {
    content
      .padding(Spacing.s200)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.ds.backgroundGroupedElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

extension View {
  /// Shows the view as a card.
  public func cardStyle() -> some View {
    modifier(CardModifier())
  }

  /// Gives a control at least the 44-point target the HIG asks for (design system, accessibility).
  public func minimumTarget() -> some View {
    frame(minWidth: Sizes.targetMinimum, minHeight: Sizes.targetMinimum).contentShape(Rectangle())
  }

  /// Limits text to a comfortable reading width and centres it on wide windows.
  public func readableWidth() -> some View {
    frame(maxWidth: Sizes.readableWidth).frame(maxWidth: .infinity)
  }

  /// Centres the view in the space it is given, and scrolls it when it does not fit, for example at
  /// large Dynamic Type sizes, so no text is ever clipped.
  ///
  /// Use it for the whole content of a screen or sheet, never inside another vertical scroll view:
  /// there it is given no height and collapses.
  public func centeredScrolling() -> some View {
    GeometryReader { proxy in
      ScrollView {
        frame(maxWidth: .infinity).frame(minHeight: proxy.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }
}

/// The badge naming the tier that produced an answer; always shown (design system, AI answer cards).
public struct TierBadge: View {
  private let tier: IntelligenceTier

  /// Creates a badge for a tier.
  public init(tier: IntelligenceTier) {
    self.tier = tier
  }

  /// The badge.
  public var body: some View {
    Label {
      Text(Self.title(for: tier))
    } icon: {
      Image(systemName: tier == .onDevice ? "iphone" : "cloud")
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(Color.ds.intelligenceTint)
    .accessibilityElement(children: .combine)
  }

  /// The tier's name as people see it.
  public static func title(for tier: IntelligenceTier) -> LocalizedStringResource {
    switch tier {
    case .onDevice: LocalizedStringResource("On device", bundle: .atURL(Bundle.module.bundleURL))
    case .privateCloudCompute: LocalizedStringResource("Private Cloud Compute", bundle: .atURL(Bundle.module.bundleURL))
    case .claude: LocalizedStringResource("Claude by Anthropic", bundle: .atURL(Bundle.module.bundleURL))
    }
  }
}

/// A page citation chip ("p. 12").
///
/// Tapping it opens the page with the passage highlighted.
public struct CitationChip: View {
  private let citation: Citation
  private let action: () -> Void

  /// Creates a chip.
  public init(citation: Citation, action: @escaping () -> Void) {
    self.citation = citation
    self.action = action
  }

  /// The chip.
  public var body: some View {
    Button(action: action) {
      Text("p. \(citation.pageNumber)", bundle: .module)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, Spacing.s100)
        .padding(.vertical, Spacing.s050)
        .frame(minWidth: Sizes.targetMinimum, minHeight: Sizes.targetMinimum)
        .foregroundStyle(Color.ds.intelligenceTint)
        .background(Color.ds.intelligenceTint.opacity(0.12), in: Capsule())
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Source: page \(citation.pageNumber)", bundle: .module))
    .accessibilityHint(Text("Opens the page and highlights the passage.", bundle: .module))
    .accessibilityInputLabels([Text("Page \(citation.pageNumber)", bundle: .module)])
  }
}

/// The footnote under every generated answer (FR-AI-010).
public struct GeneratedFootnote: View {
  /// Creates the footnote.
  public init() {}

  /// The footnote.
  public var body: some View {
    Label {
      Text("Generated from this document. Check important details against the pages cited.", bundle: .module)
    } icon: {
      Image(systemName: "sparkles")
    }
    .font(.footnote)
    .foregroundStyle(Color.ds.labelSecondary)
  }
}

/// The persistent disclosure on every contract explanation; never dismissible.
public struct ContractDisclosure: View {
  /// Creates the disclosure.
  public init() {}

  /// The disclosure.
  public var body: some View {
    Label {
      Text("Explains the document. Not legal advice.", bundle: .module)
    } icon: {
      Image(systemName: "exclamationmark.shield")
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(Color.ds.labelPrimary)
    .padding(Spacing.s150)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.ds.statusWarning.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// An onboarding option card: a symbol, a title and a one-line description.
public struct IntentCard: View {
  private let symbol: String
  private let title: Text
  private let detail: Text
  private let isSelected: Bool

  /// Creates a card.
  public init(symbol: String, title: Text, detail: Text, isSelected: Bool) {
    self.symbol = symbol
    self.title = title
    self.detail = detail
    self.isSelected = isSelected
  }

  /// The card.
  public var body: some View {
    HStack(alignment: .top, spacing: Spacing.s150) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(Color.ds.brandTint)
        .frame(width: Sizes.targetMinimum * 0.75)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Spacing.s050) {
        title.font(.headline).foregroundStyle(Color.ds.labelPrimary)
        detail.font(.callout).foregroundStyle(Color.ds.labelSecondary)
      }
      Spacer(minLength: 0)
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(isSelected ? Color.ds.brandTint : Color.ds.labelTertiary)
        .accessibilityHidden(true)
    }
    .cardStyle()
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(isSelected ? Color.ds.brandTint : .clear, lineWidth: 2)
    )
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

/// All custom animation goes through `Motion`, which honours Reduce Motion (design system, motion).
public enum Motion {
  /// The standard animation, or none when Reduce Motion is on.
  public static func standard(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .smooth(duration: 0.25)
  }
}

extension View {
  /// Animates changes to a value with the standard motion, respecting Reduce Motion.
  public func motion<Value: Equatable>(value: Value) -> some View {
    modifier(MotionModifier(value: value))
  }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
  let value: Value
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(Motion.standard(reduceMotion: reduceMotion), value: value)
  }
}

/// A full-screen empty, unavailable or error state.
///
/// Use it instead of `ContentUnavailableView`, which draws its description in `secondaryLabel`
/// (3.3:1 on grouped backgrounds) and cannot scroll, so long text is clipped at large Dynamic Type
/// sizes. This view keeps the same layout, scrolls when the content does not fit, and uses
/// `labelSecondary` for the description (accessibility, NFR-A11Y-001). Like `centeredScrolling()`,
/// it fills a screen or sheet and must not be placed inside another vertical scroll view.
public struct EmptyState<Description: View, Actions: View>: View {
  private let title: Text
  private let systemImage: String
  private let description: Description
  private let actions: Actions

  /// Creates an empty state with a description and actions.
  public init(
    _ title: Text, systemImage: String, @ViewBuilder description: () -> Description,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.systemImage = systemImage
    self.description = description()
    self.actions = actions()
  }

  /// The state, centred when it fits and scrollable when it does not.
  public var body: some View {
    VStack(spacing: Spacing.s200) {
      Image(systemName: systemImage)
        .font(.largeTitle)
        .foregroundStyle(Color.ds.labelSecondary)
        .accessibilityHidden(true)
      title
        .font(.title2.bold())
        .foregroundStyle(Color.ds.labelPrimary)
        .accessibilityAddTraits(.isHeader)
      description
        .font(.callout)
        .foregroundStyle(Color.ds.labelSecondary)
      VStack(spacing: Spacing.s100) { actions }
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(Spacing.s300)
    .readableWidth()
    .centeredScrolling()
  }
}

extension EmptyState where Actions == EmptyView {
  /// Creates an empty state with a description and no actions.
  public init(_ title: Text, systemImage: String, @ViewBuilder description: () -> Description) {
    self.init(title, systemImage: systemImage, description: description, actions: { EmptyView() })
  }
}
