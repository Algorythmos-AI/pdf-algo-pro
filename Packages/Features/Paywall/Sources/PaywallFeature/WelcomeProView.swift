import DesignSystem
import SwiftUI

/// "Welcome to Pro": what is now available, when a trial ends, and one button to start
/// (FR-STORE-007; design system, "Purchase confirmation").
struct WelcomeProView: View {
  @Bindable var model: PaywallModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    .background(alignment: .top) { BrandGlow().frame(height: 360).ignoresSafeArea() }
    .background(Color.ds.backgroundPrimary)
    .sensoryFeedback(.success, trigger: celebrates)
    .onAppear { celebrates = true }
  }

  private var content: some View {
    VStack(spacing: Spacing.s300) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 72))
        .foregroundStyle(Color.ds.brandFill)
        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : celebrates)
        .accessibilityHidden(true)
      VStack(spacing: Spacing.s100) {
        Text("Welcome to Pro", bundle: .module)
          .font(.largeTitle.bold())
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("paywall.welcome")
        Text("Everything is ready for your next document.", bundle: .module)
          .font(.body)
          .foregroundStyle(Color.ds.labelSecondary)
          .multilineTextAlignment(.center)
      }
      BenefitList(benefits: model.benefits).cardStyle()
      if let trialEndsAt = model.trialEndsAt {
        trial(endsAt: trialEndsAt)
      }
    }
    .padding(Spacing.s300)
    .readableWidth()
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
