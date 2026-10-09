import Core
import DesignSystem
import SwiftUI

/// The first-run introduction: three pages, each with a phone that shows the capability, a headline,
/// a sentence and one Continue button that stays in the same place (design system, "First-run
/// introduction").
public struct OnboardingView: View {
  @State private var model: OnboardingModel
  /// Whether the last change of page went forwards, which decides the side the next page enters from.
  @State private var movesForward = true
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.layoutDirection) private var layoutDirection

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
            movesForward = true
            Task { await model.advance() }
          } label: {
            // The words keep their place while the app decides what follows the last page.
            Text("Continue", bundle: .module)
              .opacity(model.isFinishing ? 0 : 1)
              .overlay { if model.isFinishing { ProgressView().tint(Color.ds.brandOnFill) } }
          }
          .buttonStyle(.primary)
          .disabled(model.isFinishing)
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
          .disabled(model.isFinishing)
          .accessibilityIdentifier("onboarding.skip")
        }
      }
      .task { await model.load() }
      // A new page is a new screen to VoiceOver, which then reads its headline.
      .onChange(of: model.index) { AccessibilityNotification.ScreenChanged().post() }
    }
  }

  private var pageContent: some View {
    VStack(spacing: Spacing.s200) {
      // At the largest text sizes the words need the room; the picture says nothing they do not.
      if !typeSize.isAccessibilitySize {
        OnboardingIllustration(page: model.page)
      }
      VStack(spacing: Spacing.s150) {
        model.page.title
          .font(.largeTitle.weight(.heavy))
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
    // The new page comes in from the side the person is moving towards.
    .transition(.push(from: movesForward == (layoutDirection == .leftToRight) ? .trailing : .leading))
    .motion(value: model.index)
    .contentShape(Rectangle())
    // A swipe turns the page, as the dots suggest; Continue does the same for everyone else.
    .gesture(
      DragGesture(minimumDistance: 24).onEnded { drag in
        guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
        let towardsNext = (drag.translation.width < 0) == (layoutDirection == .leftToRight)
        movesForward = towardsNext
        Task { await towardsNext ? model.goForward() : model.goBack() }
      })
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
