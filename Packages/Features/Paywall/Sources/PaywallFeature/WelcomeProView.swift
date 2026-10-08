import DesignSystem
import SwiftUI

/// "Welcome to Pro": what is now available, when a trial ends, and one button to start
/// (FR-STORE-007; design system, "Purchase confirmation").
struct WelcomeProView: View {
  @Bindable var model: PaywallModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var celebrates = false

  var body: some View {
    VStack(spacing: 0) {
      content
        .centeredScrolling()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Button {
        model.close()
      } label: {
        Text("Start", bundle: .module)
      }
      .buttonStyle(.primary)
      .accessibilityIdentifier("paywall.start")
      .padding(Spacing.s200)
      .background(.bar)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("paywall.welcome.actionBar")
    }
    .background(alignment: .top) { BrandGlow().frame(height: 460).ignoresSafeArea() }
    .background(Color.ds.backgroundPrimary)
    .sensoryFeedback(.success, trigger: celebrates)
    .onAppear { celebrates = true }
  }

  private var content: some View {
    VStack(spacing: Spacing.s300) {
      Image(systemName: "checkmark")
        .font(.system(size: 46, weight: .bold))
        .foregroundStyle(Color.ds.brandOnFill)
        .frame(width: 108, height: 108)
        .background(Color.ds.brandFill, in: Circle())
        .shadow(color: Color.ds.brandFill.opacity(0.3), radius: 18, y: 8)
        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : celebrates)
        .accessibilityHidden(true)
      VStack(spacing: Spacing.s100) {
        Text("Welcome to Pro", bundle: .module)
          .font(.largeTitle.weight(.heavy))
          .foregroundStyle(Color.ds.brandTint)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("paywall.welcome")
        Text("Everything is ready for your next document.", bundle: .module)
          .font(.body)
          .foregroundStyle(Color.ds.labelSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(spacing: Spacing.s150) {
        Text("Now available to you", bundle: .module)
          .font(.subheadline)
          .foregroundStyle(Color.ds.labelSecondary)
        // Side by side while three fit and the text is of an ordinary size; a list otherwise.
        if benefitsFitSideBySide {
          BenefitTiles(benefits: model.benefits).cardStyle()
        } else {
          BenefitList(benefits: model.benefits).cardStyle()
        }
      }
      if let trialEndsAt = model.trialEndsAt {
        trial(endsAt: trialEndsAt)
      }
    }
    .padding(Spacing.s300)
    .readableWidth()
  }

  private var benefitsFitSideBySide: Bool {
    !typeSize.isAccessibilitySize && (2...3).contains(model.benefits.count)
  }

  /// When the trial ends, and the one place the app asks to remind (and so for notifications).
  private func trial(endsAt: Date) -> some View {
    VStack(alignment: .leading, spacing: Spacing.s100) {
      Text("Your trial ends on \(endsAt, format: .dateTime.day().month(.wide).year()).", bundle: .module)
        .font(.subheadline)
        .accessibilityIdentifier("paywall.welcome.trialEnd")
      Toggle(isOn: $model.wantsReminder) {
        Text("Remind me the day before", bundle: .module)
      }
      .accessibilityIdentifier("paywall.welcome.reminder")
      .onChange(of: model.wantsReminder) { Task { await model.reminderChanged() } }
      Text("You can cancel at any time in Settings, under Subscription.", bundle: .module)
        .font(.footnote)
        .foregroundStyle(Color.ds.labelSecondary)
    }
    .cardStyle()
  }
}

/// What Pro adds, side by side: a symbol over each name, with a hairline between.
struct BenefitTiles: View {
  let benefits: [PaywallBenefit]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(benefits) { benefit in
        VStack(spacing: Spacing.s100) {
          Image(systemName: benefit.symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.ds.brandTint)
            .accessibilityHidden(true)
          benefit.title
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.s050)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.benefit.\(benefit.rawValue)")
        if benefit != benefits.last {
          Divider()
        }
      }
    }
    // As tall as its names need: a divider alone would take all the height it is offered.
    .fixedSize(horizontal: false, vertical: true)
  }
}
