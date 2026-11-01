#if DEBUG
  import Core
  import SwiftUI

  // Previews of Settings, About and the privacy report, for the design pass (PAP-070): each screen
  // as it ships, at the largest accessibility text size, in dark appearance and right to left.

  /// Settings held in memory, so a preview never touches the app's own.
  private final class PreviewSettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings

    init(_ settings: AppSettings = AppSettings(hasCompletedOnboarding: true)) {
      self.settings = settings
    }

    func load() -> AppSettings { lock.withLock { settings } }

    func save(_ settings: AppSettings) { lock.withLock { self.settings = settings } }
  }

  /// Settings with App Lock offered through Face ID, as on a device that has it.
  @MainActor private func previewSettings() -> SettingsView {
    let model = SettingsModel(
      store: PreviewSettingsStore(), diagnostics: { "" }, onChange: { _ in }, lockMethod: .faceID,
      authenticate: { _ in true })
    return SettingsView(model: model, version: "1.0 (1)")
  }

  @MainActor private func previewPrivacyReport() -> some View {
    NavigationStack {
      PrivacyReportView(model: SettingsModel(store: PreviewSettingsStore(), diagnostics: { "" }, onChange: { _ in }))
    }
  }

  #Preview("Settings") { previewSettings() }
  #Preview("Settings, largest text") { previewSettings().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Settings, dark") { previewSettings().preferredColorScheme(.dark) }
  #Preview("Settings, right to left") { previewSettings().environment(\.layoutDirection, .rightToLeft) }

  #Preview("About") { NavigationStack { AboutView(version: "1.0 (1)") } }
  #Preview("About, largest text") {
    NavigationStack { AboutView(version: "1.0 (1)") }.environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("About, dark") { NavigationStack { AboutView(version: "1.0 (1)") }.preferredColorScheme(.dark) }
  #Preview("About, right to left") {
    NavigationStack { AboutView(version: "1.0 (1)") }.environment(\.layoutDirection, .rightToLeft)
  }

  #Preview("Privacy report") { previewPrivacyReport() }
  #Preview("Privacy report, largest text") {
    previewPrivacyReport().environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("Privacy report, dark") { previewPrivacyReport().preferredColorScheme(.dark) }
#endif
