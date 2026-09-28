import Core
import DesignSystem
import SwiftUI

/// The single onboarding screen, which asks what the person does with PDFs most often.
public struct OnboardingView: View {
  @State private var model: OnboardingModel

  /// Creates the screen for a model.
  public init(model: OnboardingModel) {
    _model = State(initialValue: model)
  }

  /// The screen.
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.s300) {
          VStack(alignment: .leading, spacing: Spacing.s100) {
            Text("What do you do with PDFs most often?", bundle: .module)
              .font(.largeTitle.bold())
              .accessibilityAddTraits(.isHeader)
            Text("Choose as many as you like. You can change this later in Settings.", bundle: .module)
              .font(.callout)
              .foregroundStyle(Color.ds.labelSecondary)
          }
          group(title: Text("Ask and understand", bundle: .module), intents: model.askAndUnderstand)
          if model.intelligenceNeedsNote {
            Label {
              Text(
                "AI options need Apple Intelligence, which is off or not available on this device. The other tools work without it.",
                bundle: .module)
            } icon: {
              Image(systemName: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(Color.ds.labelSecondary)
            .accessibilityIdentifier("onboarding.intelligenceNote")
          }
          group(title: Text("Work with PDFs", bundle: .module), intents: model.workWithPDFs)
        }
        .padding(Spacing.s200)
        .readableWidth()
      }
      .background(Color.ds.backgroundGrouped)
      .navigationTitle(Text("Welcome", bundle: .module))
      .toolbarTitleDisplayMode(.inline)
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
      .safeAreaInset(edge: .bottom) {
        Button {
          Task { await model.finish() }
        } label: {
          Text("Continue", bundle: .module)
        }
        .buttonStyle(.primary)
        .padding(Spacing.s200)
        .background(.bar)
        .accessibilityIdentifier("onboarding.continue")
      }
      .task { await model.load() }
    }
  }

  private func group(title: Text, intents: [OnboardingIntent]) -> some View {
    VStack(alignment: .leading, spacing: Spacing.s100) {
      title.font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
      ForEach(intents) { intent in
        Button {
          model.toggle(intent)
        } label: {
          IntentCard(
            symbol: IntentCopy.symbol(intent), title: IntentCopy.title(intent), detail: IntentCopy.detail(intent),
            isSelected: model.isSelected(intent))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.intent.\(intent.rawValue)")
      }
    }
  }
}
