#if INTERNAL_TOOLS
  import Core
  import DesignSystem
  import Foundation
  import IntelligenceEvaluation
  import SwiftUI

  /// The internal testing section in Settings, in Debug and Staging builds only.
  ///
  /// A switch for Pro without a purchase, rows that show first run again, show the subscription
  /// offer and ask the App Store for the subscription again, and a row that opens the live AI
  /// evaluation. The text is English only: App Store builds do not contain it.
  struct EvaluationSection: View {
    let intelligence: any DocumentIntelligence
    /// Reads the entitlement again, after the switch below changed what it is.
    let onEntitlementOverride: () -> Void
    /// Closes Settings and shows the introduction, and the offer after it, as a new install sees them.
    let onReplayFirstRun: () -> Void
    /// Closes Settings and shows the subscription offer, whatever the person is entitled to.
    let onShowOffer: () -> Void
    /// Forgets which build completed first run, so the next launch replays it.
    let onResetReplay: () -> Void
    @State private var managesSubscription = false
    @State private var replayIsReset = false
    @State private var hasPro = UserDefaults.standard.bool(forKey: InternalEntitlementOverride.key)

    var body: some View {
      Section {
        Toggle(isOn: $hasPro) {
          TileLabel(Text(verbatim: "Pro without a purchase"), systemImage: "crown", tone: .quiet)
        }
        .accessibilityIdentifier("internal.entitlement.pro")
        .onChange(of: hasPro) {
          UserDefaults.standard.set(hasPro, forKey: InternalEntitlementOverride.key)
          onEntitlementOverride()
        }
        Button(action: onReplayFirstRun) {
          TileLabel(
            Text(verbatim: "Show onboarding now (simulate first launch)"), systemImage: "arrow.counterclockwise",
            tone: .quiet)
        }
        .accessibilityIdentifier("internal.replayFirstRun")
        Button {
          onResetReplay()
          replayIsReset = true
        } label: {
          TileLabel(
            Text(verbatim: replayIsReset ? "First run will show at next launch" : "Reset first run for next launch"),
            systemImage: "arrow.uturn.backward", tone: .quiet)
        }
        .disabled(replayIsReset)
        .accessibilityIdentifier("internal.resetReplay")
        Button(action: onShowOffer) {
          TileLabel(Text(verbatim: "Show the subscription offer"), systemImage: "creditcard", tone: .quiet)
        }
        .accessibilityIdentifier("internal.showOffer")
        Button(action: onEntitlementOverride) {
          TileLabel(
            Text(verbatim: "Refresh subscription status"), systemImage: "arrow.triangle.2.circlepath", tone: .quiet)
        }
        .accessibilityIdentifier("internal.refreshSubscription")
        Button {
          managesSubscription = true
        } label: {
          TileLabel(Text(verbatim: "Manage test subscription"), systemImage: "person.crop.circle", tone: .quiet)
        }
        .accessibilityIdentifier("internal.manageSubscription")
        NavigationLink {
          EvaluationView(intelligence: intelligence)
        } label: {
          TileLabel(Text(verbatim: "AI evaluation"), systemImage: "checklist", tone: .intelligence)
        }
        .accessibilityIdentifier("evaluation.open")
      } header: {
        Text(verbatim: "Internal testing").foregroundStyle(Color.ds.labelSecondary)
      } footer: {
        Text(
          verbatim:
            "Each new internal build opens on first run by itself: the introduction, then the subscription offer, whatever this Apple Account is entitled to. Purchases, Pro and trial eligibility are the App Store's and are never changed here; to buy again, cancel the test subscription and let it lapse, or use another account. Your documents and settings stay."
        )
        .foregroundStyle(Color.ds.labelSecondary)
      }
      .manageSubscriptionsSheet(isPresented: $managesSubscription)
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
