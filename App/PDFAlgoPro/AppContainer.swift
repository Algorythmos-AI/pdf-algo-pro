import Core
import DocumentStore
import Foundation
import Intelligence
import OCR
import PDFEngine
import Search
import Telemetry

/// How the app was launched. UI tests pass arguments so every run starts from a known, private
/// state; none of them exist in a normal launch.
struct LaunchEnvironment {
  /// Use temporary folders and settings that are thrown away.
  let isUITesting: Bool
  /// Start with onboarding already done.
  let skipsOnboarding: Bool
  /// Add the synthetic sample document at launch.
  let seedsSample: Bool

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    isUITesting = arguments.contains("-ui-testing")
    skipsOnboarding = arguments.contains("-ui-skip-onboarding")
    seedsSample = arguments.contains("-ui-seed-sample")
  }
}

/// Composes the live services once, at launch (ADR-0003). It holds no logic: features receive
/// exactly the services they need.
@MainActor
final class AppContainer {
  let settings: any SettingsStoring
  let library: any DocumentLibrary
  let index: LocalSearchIndex
  let intake: DocumentIntake
  let intelligence: any DocumentIntelligence
  let builder: SearchablePDFBuilder
  let telemetry: LocalTelemetry
  let thumbnails = ThumbnailCache()
  let indexLevel: LibraryIndex.StoreLevel
  let environment: LaunchEnvironment

  init(environment: LaunchEnvironment = LaunchEnvironment()) {
    self.environment = environment
    let folders = Folders(isUITesting: environment.isUITesting)
    let settings: any SettingsStoring
    if environment.isUITesting, let defaults = UserDefaults(suiteName: "ui-testing-\(UUID().uuidString)") {
      settings = UserDefaultsSettingsStore(defaults: defaults)
      if environment.skipsOnboarding { settings.save(AppSettings(hasCompletedOnboarding: true)) }
    } else {
      settings = UserDefaultsSettingsStore()
    }
    self.settings = settings

    let libraryIndex = LibraryIndex(storeURL: folders.indexStore)
    indexLevel = libraryIndex.level
    let library = FileDocumentLibrary(
      documentsFolder: folders.documents, deletedFolder: folders.recentlyDeleted, index: libraryIndex)
    self.library = library
    let spotlight: (any SpotlightIndexing)? = environment.isUITesting ? nil : SpotlightIndexer()
    let index = LocalSearchIndex(folder: folders.searchIndex, spotlight: spotlight)
    self.index = index
    intake = DocumentIntake(library: library, inspector: PDFKitInspector(), index: index)
    intelligence = IntelligenceRouter(models: [OnDeviceModel()], isHidden: { settings.load().isIntelligenceHidden })
    builder = SearchablePDFBuilder(recognizer: VisionTextRecognizer())
    telemetry = LocalTelemetry()
  }

  /// The diagnostics summary for "Report a problem": app, system and health only (FR-SET-003).
  func diagnostics() async -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let count = (try? await library.documents(in: .all, sortedBy: .title).count) ?? 0
    return DiagnosticsSummary(
      appVersion: info["CFBundleShortVersionString"] as? String ?? "?", build: info["CFBundleVersion"] as? String ?? "?",
      system: ProcessInfo.processInfo.operatingSystemVersionString, libraryIndex: "\(indexLevel)", documentCount: count,
      events: await telemetry.todaysCounts()
    ).text
  }

  /// The app version for About.
  var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
  }
}

/// Where the app keeps things. Documents are in the Documents folder, which the Files app shows as
/// "On My iPhone › PDF Algo Pro" (FR-LIB-001); derived data is in Application Support and excluded
/// from backups because it is rebuilt from the files (ADR-0006).
private struct Folders {
  let documents: URL
  let recentlyDeleted: URL
  let indexStore: URL
  let searchIndex: URL

  init(isUITesting: Bool) {
    let fileManager = FileManager.default
    let root: URL
    let support: URL
    if isUITesting {
      root = fileManager.temporaryDirectory.appendingPathComponent("ui-testing-\(UUID().uuidString)", isDirectory: true)
      support = root.appendingPathComponent("Support", isDirectory: true)
      documents = root.appendingPathComponent("Documents", isDirectory: true)
    } else {
      root = URL.documentsDirectory
      support = URL.applicationSupportDirectory
      documents = root
    }
    recentlyDeleted = support.appendingPathComponent("RecentlyDeleted", isDirectory: true)
    var derived = support.appendingPathComponent("Derived", isDirectory: true)
    try? fileManager.createDirectory(at: derived, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? derived.setResourceValues(values)
    indexStore = derived.appendingPathComponent("Library.store")
    searchIndex = derived.appendingPathComponent("SearchIndex", isDirectory: true)
  }
}
