import Core
import DesignSystem
import SwiftUI

/// The Settings screen.
public struct SettingsView: View {
  @State private var model: SettingsModel
  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss
  private let version: String

  /// Creates Settings; `version` is shown in About.
  public init(model: SettingsModel, version: String) {
    _model = State(initialValue: model)
    self.version = version
  }

  /// The screen.
  public var body: some View {
    NavigationStack {
      Form {
        // First, so the AI switch is on screen without scrolling (privacy by default).
        Section {
          Toggle(isOn: $model.isIntelligenceHidden) { Text("Hide AI features", bundle: .module) }
            .accessibilityIdentifier("settings.hideAI")
        } header: {
          Text("Document intelligence", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          Text(
            "Summaries, answers and extraction run on this device with Apple Intelligence. Nothing is sent anywhere.",
            bundle: .module
          )
          .foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          ForEach(OnboardingIntent.allCases) { intent in
            Toggle(isOn: Binding(get: { model.isChosen(intent) }, set: { _ in model.toggle(intent) })) {
              Self.intentTitle(intent)
            }
          }
        } header: {
          Text("What you do most", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          Text("The first choice leads the home screen.", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          Picker(selection: $model.readerDisplayMode) {
            Text("Continuous", bundle: .module).tag(ReaderDisplayMode.continuous)
            Text("Single page", bundle: .module).tag(ReaderDisplayMode.singlePage)
          } label: {
            Text("Page layout", bundle: .module)
          }
        } header: {
          Text("Reading", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          Text(
            "Your documents stay on this device, in the PDF Algo Pro folder you can see in the Files app. The app has no account, no advertising and no tracking.",
            bundle: .module)
        } header: {
          Text("Privacy", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          Toggle(isOn: $model.includesDiagnostics) { Text("Include a diagnostics summary", bundle: .module) }
          Button {
            Task { if let url = await model.supportEmailURL() { openURL(url) } }
          } label: {
            Text("Report a problem", bundle: .module)
          }
          .accessibilityIdentifier("settings.report")
        } header: {
          Text("Help", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          Text(
            "The summary lists the app version, the system and error counts. It never includes your documents.",
            bundle: .module
          )
          .foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          LabeledContent {
            Text(version).foregroundStyle(Color.ds.labelSecondary)
          } label: {
            Text("Version", bundle: .module)
          }
          Text("Built by Algorythmos", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } header: {
          Text("About", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
      }
      .navigationTitle(Text("Settings", bundle: .module))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", bundle: .module)
          }
        }
      }
    }
  }

  static func intentTitle(_ intent: OnboardingIntent) -> Text {
    switch intent {
    case .chatWithPDF: Text("Chat with PDF", bundle: .module)
    case .summarizeDocument: Text("Summarise document", bundle: .module)
    case .extractData: Text("Extract data with AI", bundle: .module)
    case .analyzeContract: Text("Analyse contract", bundle: .module)
    case .editText: Text("Edit PDF text", bundle: .module)
    case .annotate: Text("Annotate or highlight", bundle: .module)
    case .sign: Text("Sign", bundle: .module)
    case .convert: Text("Convert PDF to Word, Excel or PowerPoint", bundle: .module)
    case .organize: Text("Merge or organise pages", bundle: .module)
    case .read: Text("Read or view", bundle: .module)
    case .scan: Text("Scan to PDF", bundle: .module)
    case .allTools: Text("All tools", bundle: .module)
    }
  }
}
