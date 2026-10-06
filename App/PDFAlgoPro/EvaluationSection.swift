#if INTERNAL_TOOLS
  import Core
  import DesignSystem
  import Foundation
  import IntelligenceEvaluation
  import SwiftUI

  /// The internal testing section in Settings, in Debug and Staging builds only.
  ///
  /// One row opens the live AI evaluation. The text is English only: App Store builds do not contain it.
  struct EvaluationSection: View {
    let intelligence: any DocumentIntelligence

    var body: some View {
      Section {
        NavigationLink {
          EvaluationView(intelligence: intelligence)
        } label: {
          TileLabel(Text(verbatim: "AI evaluation"), systemImage: "checklist", tone: .intelligence)
        }
        .accessibilityIdentifier("evaluation.open")
      } header: {
        Text(verbatim: "Internal testing").foregroundStyle(Color.ds.labelSecondary)
      }
    }
  }

  /// The live AI evaluation (W3.4, bar item B6).
  ///
  /// Runs every evaluation item through this device's document intelligence with the same scoring as
  /// CI, shows each metric against its release threshold, and shares the report as
  /// `ai-evaluation-live.md`, the device evidence docs/ai-evaluation-framework.md asks for. Nothing
  /// leaves the device unless the report is shared.
  struct EvaluationView: View {
    let intelligence: any DocumentIntelligence
    @State private var isRunning = false
    @State private var report: EvaluationReport?
    @State private var reportFile: URL?

    var body: some View {
      Form {
        Section {
          Button {
            Task { await run() }
          } label: {
            Text(verbatim: "Run the AI evaluation")
          }
          .disabled(isRunning)
          .accessibilityIdentifier("evaluation.run")
          if isRunning {
            ProgressView {
              Text(verbatim: "Evaluating \(EvaluationSets.all.count) items on this device…")
            }
          }
        } footer: {
          Text(
            verbatim:
              "Runs every evaluation item with this device's model and scores it as CI does. Nothing is sent anywhere unless you share the report."
          )
          .foregroundStyle(Color.ds.labelSecondary)
        }
        if let report {
          Section {
            LabeledContent {
              // A symbol as well as the words: the result is never told by colour alone.
              HStack(spacing: Spacing.s050) {
                Image(systemName: report.passes ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                  .foregroundStyle(report.passes ? Color.ds.statusSuccess : Color.ds.statusWarning)
                  .accessibilityHidden(true)
                Text(verbatim: report.passes ? "Pass" : "Below a threshold").foregroundStyle(Color.ds.labelSecondary)
              }
            } label: {
              Text(verbatim: "Result, \(report.tier?.rawValue ?? "no tier")")
            }
            .accessibilityIdentifier("evaluation.result")
            ForEach(report.metrics, id: \.name) { metric in
              LabeledContent {
                Text(verbatim: Self.describe(metric)).monospacedDigit().foregroundStyle(Color.ds.labelSecondary)
              } label: {
                Text(verbatim: metric.name)
              }
            }
            if let reportFile {
              ShareLink(item: reportFile) {
                Text(verbatim: "Share the report")
              }
            }
          }
        }
      }
      .navigationTitle(Text(verbatim: "AI evaluation"))
    }

    private func run() async {
      isRunning = true
      defer { isRunning = false }
      let report = await EvaluationRunner(intelligence: intelligence).run(EvaluationSets.all)
      let file = FileManager.default.temporaryDirectory.appendingPathComponent("ai-evaluation-live.md")
      do {
        try Data(report.markdown.utf8).write(to: file, options: .atomic)
        reportFile = file
      } catch {
        reportFile = nil
      }
      self.report = report
    }

    private static func describe(_ metric: EvaluationMetric) -> String {
      let value = String(format: "%.1f%%", metric.value * 100)
      let threshold = (metric.isMinimum ? "≥ " : "≤ ") + String(format: "%.1f%%", metric.threshold * 100)
      return "\(value) (\(threshold), n=\(metric.sampleSize))\(metric.passes ? "" : " ✗")"
    }
  }
#endif
