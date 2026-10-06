import Core
import DesignSystem
import SwiftUI
import UIKit

/// The Settings screen.
public struct SettingsView: View {
  @State private var model: SettingsModel
  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
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
          // One row, not ten switches: the choices open on their own screen, so the settings people
          // look for (privacy, App Lock, storage) are on the first screen.
          NavigationLink {
            List {
              Section {
                ForEach(OnboardingIntent.offered) { intent in
                  Toggle(isOn: Binding(get: { model.isChosen(intent) }, set: { _ in model.toggle(intent) })) {
                    Self.intentTitle(intent)
                  }
                }
              } footer: {
                Text("The first choice leads the home screen.", bundle: .module)
                  .foregroundStyle(Color.ds.labelSecondary)
              }
            }
            .navigationTitle(Text("What you do most", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
          } label: {
            Text("What you do most", bundle: .module)
          }
          .accessibilityIdentifier("settings.intents")
        } header: {
          Text("Home screen", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
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
            .disabled(model.isAppLockEnabled)
          Toggle(isOn: Binding(get: { model.isAppLockEnabled }, set: { isOn in Task { await model.setAppLock(isOn) } }))
          {
            Self.lockTitle(model.lockMethod)
          }
          .disabled(model.lockMethod == nil)
          .accessibilityIdentifier("settings.appLock")
        } header: {
          Text("Privacy", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          Text(
            "Titles and tags are always searchable in Spotlight. Turn this off to keep what documents say out of system search. App Lock hides the app's screen in the app switcher and keeps document text out of Spotlight.",
            bundle: .module
          )
          .foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          LabeledContent {
            if let size = model.versionsSize {
              Text(size, format: .byteCount(style: .file))
            } else {
              ProgressView()
            }
          } label: {
            Text("Version history", bundle: .module)
          }
          .accessibilityIdentifier("settings.versionsSize")
          Button(role: .destructive) {
            model.confirmsDeleteVersions = true
          } label: {
            Text("Delete version history", bundle: .module)
          }
          .disabled((model.versionsSize ?? 0) == 0)
          .accessibilityIdentifier("settings.deleteVersions")
        } header: {
          Text("Storage", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          Text(
            "Before each save, the app keeps the version it replaces for 30 days, so a change can be undone. Deleting this history leaves your documents as they are.",
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
          NavigationLink {
            PrivacyReportView(model: model)
          } label: {
            Text("Privacy report", bundle: .module)
          }
          .accessibilityIdentifier("settings.privacyReport")
        } header: {
          Text("Privacy", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          LabeledContent {
            Text(version).foregroundStyle(Color.ds.labelSecondary)
          } label: {
            Text("Version", bundle: .module)
          }
          // App Review expects the privacy policy to be reachable in the app; each opens in the browser.
          Link(destination: link(.privacyPolicy)) { Text("Privacy Policy", bundle: .module) }
            .accessibilityIdentifier("settings.privacyPolicy")
          Link(destination: link(.termsOfUse)) { Text("Terms of Use", bundle: .module) }
            .accessibilityIdentifier("settings.termsOfUse")
          Link(destination: link(.support)) { Text("Support", bundle: .module) }
            .accessibilityIdentifier("settings.support")
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
      .confirmationDialog(
        Text("Delete version history?", bundle: .module), isPresented: $model.confirmsDeleteVersions,
        titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          Task { await model.deleteVersions() }
        } label: {
          Text("Delete version history", bundle: .module)
        }
      } message: {
        Text("Earlier versions of every document are deleted. Your documents stay as they are.", bundle: .module)
      }
      .alert(
        Text("Version history", bundle: .module),
        isPresented: Binding(get: { model.storageMessage != nil }, set: { if !$0 { model.storageMessage = nil } })
      ) {
        Button(role: .cancel) {
          model.storageMessage = nil
        } label: {
          Text("OK", bundle: .module)
        }
      } message: {
        Text(model.storageMessage ?? "")
      }
      .task { await model.loadStorage() }
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

  /// A public page's address in the language the app is shown in.
  private func link(_ page: AppLinks) -> URL {
    page.url(languageCode: locale.language.languageCode?.identifier)
  }

  static func lockTitle(_ method: AppLockMethod?) -> Text {
    switch method {
    case .faceID: Text("Require Face ID", bundle: .module)
    case .touchID: Text("Require Touch ID", bundle: .module)
    case .opticID: Text("Require Optic ID", bundle: .module)
    case .passcode: Text("Require passcode", bundle: .module)
    case nil: Text("App Lock (set a device passcode to use it)", bundle: .module)
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
