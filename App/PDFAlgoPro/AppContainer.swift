import Core
import DocumentStore
import Foundation
import Intelligence
import OCR
import PDFEngine
import ReaderFeature
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
  /// Recognises text in image-only documents, going on in the background and resuming after a stop (P8).
  let recognition: RecognitionCoordinator
  let telemetry: LocalTelemetry
  /// Problems MetricKit reported, kept on this device (P6).
  let diagnosticsLog: DiagnosticsLog
  private let metricKit: MetricKitCollector?
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
      documentsFolder: folders.documents, deletedFolder: folders.recentlyDeleted,
      previousVersionsFolder: folders.previousVersions, index: libraryIndex)
    self.library = library
    let spotlight: (any SpotlightIndexing)? =
      environment.isUITesting ? nil : SpotlightIndexer(includesText: { settings.load().isSpotlightTextIncluded })
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
    recognition = RecognitionCoordinator(
      library: library, intake: intake, builder: builder, telemetry: telemetry, folder: folders.recognition)
    diagnosticsLog = DiagnosticsLog(file: folders.diagnostics.appendingPathComponent("problems.json"))
    metricKit = environment.isUITesting ? nil : MetricKitCollector(log: diagnosticsLog)
    metricKit?.start()
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
      events: await telemetry.todaysCounts(), problems: await diagnosticsLog.summary()
    ).text
  }

  /// Writes every document to Spotlight again, after the text setting changed (defect D11).
  func reindexSpotlight() async {
    await index.reindexSpotlight((try? await library.documents(in: .all, sortedBy: .title)) ?? [])
  }

  /// Moves Spotlight to the protected index once (defect D11).
  ///
  /// Empties the index earlier builds wrote to, then reindexes. Later launches do nothing.
  func migrateSpotlightIfNeeded(defaults: UserDefaults = .standard) async {
    let key = "spotlight.indexVersion"
    guard !environment.isUITesting, defaults.integer(forKey: key) < 2 else { return }
    await SpotlightIndexer.retireLegacyIndex()
    await reindexSpotlight()
    defaults.set(2, forKey: key)
  }

  /// The app version for About.
  var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
  }
}

/// Where the app keeps things.
///
/// Documents are in the Documents folder, which the Files app shows as "On My iPhone › PDF Algo Pro" (FR-LIB-001).
///
/// The library index in Application Support is backed up: it holds what the files cannot give back (favourites, tags,
/// reading positions, deletion dates). Only the search text, which is rebuilt from the files, is excluded from backups
/// (ADR-0006 addendum).
struct Folders {
  let documents: URL
  let recentlyDeleted: URL
  /// Each document's version from before its last save (FR-EDIT-008, first step): not backed up, so a
  /// restored device starts without them.
  let previousVersions: URL
  let indexStore: URL
  let searchIndex: URL
  /// MetricKit summaries: about this device, so not backed up.
  let diagnostics: URL
  /// Pages recognised so far for unfinished text recognition: work in progress, so not backed up.
  let recognition: URL

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
    var search = derived.appendingPathComponent("SearchIndex", isDirectory: true)
    try? fileManager.createDirectory(at: search, withIntermediateDirectories: true)
    // Earlier builds excluded all of Derived; clear that, so the index store is backed up again.
    Self.setExcludedFromBackup(false, &derived)
    Self.setExcludedFromBackup(true, &search)
    var previous = derived.appendingPathComponent("PreviousVersions", isDirectory: true)
    try? fileManager.createDirectory(at: previous, withIntermediateDirectories: true)
    Self.setExcludedFromBackup(true, &previous)
    previousVersions = previous
    indexStore = derived.appendingPathComponent("Library.store")
    searchIndex = search
    var diagnostics = support.appendingPathComponent("Diagnostics", isDirectory: true)
    try? fileManager.createDirectory(at: diagnostics, withIntermediateDirectories: true)
    Self.setExcludedFromBackup(true, &diagnostics)
    self.diagnostics = diagnostics
    var recognition = derived.appendingPathComponent("Recognition", isDirectory: true)
    try? fileManager.createDirectory(at: recognition, withIntermediateDirectories: true)
    Self.setExcludedFromBackup(true, &recognition)
    self.recognition = recognition
  }

  private static func setExcludedFromBackup(_ excluded: Bool, _ url: inout URL) {
    var values = URLResourceValues()
    values.isExcludedFromBackup = excluded
    try? url.setResourceValues(values)
  }
}
