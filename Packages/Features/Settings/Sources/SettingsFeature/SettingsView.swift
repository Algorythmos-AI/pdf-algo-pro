import Core
import DesignSystem
import SwiftUI
import UIKit

/// The Settings screen.
public struct SettingsView: View {
  @State private var model: SettingsModel
  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss
  @State private var reportWithoutMail: String?
  private let version: String
  private let internalTools: AnyView?

  /// Creates Settings; `version` is shown in About.
  ///
  /// `internalTools` is a section the app adds in its Debug and Staging builds only, such as the live
  /// AI evaluation; App Store builds pass none.
  public init(model: SettingsModel, version: String, internalTools: AnyView? = nil) {
    _model = State(initialValue: model)
    self.version = version
    self.internalTools = internalTools
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
          Toggle(isOn: $model.isSpotlightTextIncluded) { Text("Document text in Spotlight", bundle: .module) }
            .accessibilityIdentifier("settings.spotlightText")
        } header: {
          Text("Privacy", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          Text(
            "Titles and tags are always searchable in Spotlight. Turn this off to keep what documents say out of system search.",
            bundle: .module
          )
          .foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          Toggle(isOn: $model.includesDiagnostics) { Text("Include a diagnostics summary", bundle: .module) }
          Button {
            Task {
              guard let url = await model.supportEmailURL() else { return }
              let report = await model.supportReport()
              // With no email account set up, the link opens nothing; offer the address and a copy instead.
              openURL(url) { accepted in if !accepted { reportWithoutMail = report } }
            }
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
        if let internalTools { internalTools }
      }
      .alert(
        Text("No email account is set up", bundle: .module),
        isPresented: Binding(get: { reportWithoutMail != nil }, set: { if !$0 { reportWithoutMail = nil } })
      ) {
        Button {
          UIPasteboard.general.string = reportWithoutMail
          reportWithoutMail = nil
        } label: {
          Text("Copy the report", bundle: .module)
        }
        Button(role: .cancel) {
          reportWithoutMail = nil
        } label: {
          Text("Close", bundle: .module)
        }
      } message: {
        Text("Send your report to \(SettingsModel.supportAddress) from any email app.", bundle: .module)
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
