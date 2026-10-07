import Core
import DesignSystem
import SwiftUI

/// The first-run introduction: three pages, each with a picture, a headline, a sentence and one
/// Continue button that stays in the same place (design system, "First-run introduction").
public struct OnboardingView: View {
  @State private var model: OnboardingModel
  @Environment(\.dynamicTypeSize) private var typeSize

  /// Creates the introduction for a model.
  public init(model: OnboardingModel) {
    _model = State(initialValue: model)
  }

  /// The introduction.
  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        pageContent
          .centeredScrolling()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Below the page, not over it: text scrolled under a translucent bar loses its contrast.
        VStack(spacing: Spacing.s200) {
          progress
          Button {
            Task { await model.advance() }
          } label: {
            Text("Continue", bundle: .module)
          }
          .buttonStyle(.primary)
          .accessibilityIdentifier("onboarding.continue")
        }
        .padding(Spacing.s200)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.actionBar")
      }
      .background(alignment: .top) { BrandGlow().frame(height: 360).ignoresSafeArea() }
      .background(Color.ds.backgroundPrimary)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            Task { await model.skip() }
          } label: {
            Text("Skip", bundle: .module)
          }
          .accessibilityIdentifier("onboarding.skip")
        }
      }
      .task { await model.load() }
      // A new page is a new screen to VoiceOver, which then reads its headline.
      .onChange(of: model.index) { AccessibilityNotification.ScreenChanged().post() }
    }
  }

  private var pageContent: some View {
    VStack(spacing: Spacing.s400) {
      // At the largest text sizes the words need the room; the picture says nothing they do not.
      if !typeSize.isAccessibilitySize {
        OnboardingIllustration(page: model.page)
      }
      VStack(spacing: Spacing.s150) {
        model.page.title
          .font(.largeTitle.bold())
          .multilineTextAlignment(.center)
          // As tall as its lines need: a headline that wraps at a large text size is never cut.
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          // Where the person is, read with the headline: the dots below are only to look at.
          .accessibilityValue(Text("Page \(model.index + 1) of \(model.pages.count)", bundle: .module))
          .accessibilityIdentifier("onboarding.page.\(model.page.rawValue)")
        model.page.detail
          .font(.body)
          .foregroundStyle(Color.ds.labelSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Spacing.s300)
    .readableWidth()
    .id(model.page)
    .motion(value: model.index)
  }

  /// Where the person is in the introduction, to look at; VoiceOver hears it with the headline.
  private var progress: some View {
    HStack(spacing: Spacing.s100) {
      ForEach(model.pages.indices, id: \.self) { index in
        Capsule()
          .fill(index == model.index ? Color.ds.brandFill : Color.ds.fillPrimary)
          .frame(width: index == model.index ? 24 : 8, height: 8)
      }
    }
    .motion(value: model.index)
    .accessibilityHidden(true)
  }
}
