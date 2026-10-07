import Core
import DesignSystem
import SwiftUI

/// What document intelligence did over the last 30 days (FR-SET-005).
///
/// It shows that no document left the device. Counts only, kept on this device.
struct PrivacyReportView: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        LabeledContent {
          // The system draws a row's value in a grey just under 4.5:1 on this background.
          Text("\(model.activity?.documentsSentToCloud ?? 0)").font(.title2.bold()).monospacedDigit()
            .foregroundStyle(Color.ds.labelSecondary)
        } label: {
          Text("Documents sent to cloud AI", bundle: .module)
        }
        .accessibilityIdentifier("privacy.sentToCloud")
      } footer: {
        Text(
          "Summaries, answers and extraction run on this iPhone. A cloud option only ever runs after you turn it on.",
          bundle: .module
        )
        .foregroundStyle(Color.ds.labelSecondary)
      }
      Section {
        row(Text("On this device", bundle: .module), .onDevice)
        row(Text("Private Cloud Compute", bundle: .module), .privateCloudCompute)
        row(Text("Claude", bundle: .module), .claude)
      } header: {
        Text("AI requests in the last 30 days", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
      } footer: {
        Text("Only these counts are kept, on this iPhone: never your questions, answers or documents.", bundle: .module)
          .foregroundStyle(Color.ds.labelSecondary)
      }
    }
    .navigationTitle(Text("Privacy report", bundle: .module))
    .task { await model.loadActivity() }
  }

  private func row(_ label: Text, _ tier: IntelligenceTier) -> some View {
    LabeledContent {
      Text("\(model.activity?.requests[tier] ?? 0)").monospacedDigit().foregroundStyle(Color.ds.labelSecondary)
    } label: {
      label
    }
  }
}
