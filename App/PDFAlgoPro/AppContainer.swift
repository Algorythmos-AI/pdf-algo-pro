import Core
import DocumentStore
import Foundation
import Intelligence
import OCR
import PDFEngine
import Search
import Telemetry

/// How the app was launched.
///
/// UI tests pass arguments so every run starts from a known, private state (docs/testing-strategy.md,
/// UI tests). The arguments are read in Debug builds only; a Release build ignores them all.
struct LaunchEnvironment {
  /// Use temporary folders, throwaway settings and the scripted intelligence router.
  let isUITesting: Bool
  /// Start with onboarding already done.
  let skipsOnboarding: Bool
  /// Add the synthetic sample document at launch (`-seed-library sample`).
  let seedsSample: Bool
  /// Make the scripted intelligence router report that Apple Intelligence is unavailable.
  let intelligenceUnavailable: Bool
  /// Turn off UIKit animations so UI tests do not wait on them.
  let disablesAnimations: Bool

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    #if DEBUG
      isUITesting = arguments.contains("-ui-testing")
      skipsOnboarding = arguments.contains("-skip-onboarding")
      let seed = arguments.firstIndex(of: "-seed-library").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      seedsSample = seed == "sample"
      intelligenceUnavailable = arguments.contains("-intelligence-unavailable")
      disablesAnimations = arguments.contains("-disable-animations")
    #else
      isUITesting = false
      skipsOnboarding = false
      seedsSample = false
      intelligenceUnavailable = false
      disablesAnimations = false
    #endif
  }
}

/// Composes the live services once, at launch (ADR-0003).
///
/// It holds no logic: features receive exactly the services they need.
@MainActor
final class AppContainer {
  let settings: any SettingsStoring
  let library: any DocumentLibrary
  let index: LocalSearchIndex
  let intake: DocumentIntake
  let intelligence: any DocumentIntelligence
  let builder: SearchablePDFBuilder
  let telemetry: LocalTelemetry
  /// Saved signatures, in the Keychain on this device only (FR-EDIT-004).
  ///
  /// UI tests use their own Keychain service, so they never see or change real signatures.
  let signatures: any SignatureStoring
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
    let isHidden: @Sendable () -> Bool = { settings.load().isIntelligenceHidden }
    #if DEBUG
      if environment.isUITesting {
        intelligence = ScriptedIntelligence(unavailable: environment.intelligenceUnavailable, isHidden: isHidden)
      } else {
        intelligence = IntelligenceRouter(models: [OnDeviceModel()], isHidden: isHidden)
      }
    #else
      intelligence = IntelligenceRouter(models: [OnDeviceModel()], isHidden: isHidden)
    #endif
    builder = SearchablePDFBuilder(recognizer: VisionTextRecognizer())
    telemetry = LocalTelemetry()
    signatures =
      environment.isUITesting ? KeychainSignatureStore(service: "ui-testing-\(UUID())") : KeychainSignatureStore()
  }

  /// The diagnostics summary for "Report a problem": app, system and health only (FR-SET-003).
  func diagnostics() async -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let count = (try? await library.documents(in: .all, sortedBy: .title).count) ?? 0
    return DiagnosticsSummary(
      appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
      build: info["CFBundleVersion"] as? String ?? "?",
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

/// Where the app keeps things.
///
/// Documents are in the Documents folder, which the Files app shows as "On My iPhone › PDF Algo Pro" (FR-LIB-001);
/// derived data is in Application Support and excluded from backups because it is rebuilt from the files (ADR-0006).
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
