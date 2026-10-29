import Commerce
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
  /// What a UI test's private library starts with (`-seed-library sample,tags`), comma-separated:
  /// `sample` (the synthetic sample document), `locked` (a password-protected document, for the unlock
  /// tests), `damaged` (a document whose file is then overwritten, for error recovery), `scanned` (an
  /// image-only page, for text recognition), `many` (twelve titled documents), and, applied to the
  /// sample, `tags`, `favourite` and `deleted`.
  let seeds: Set<String>
  /// Whether the synthetic sample is seeded (`-seed-library sample`).
  var seedsSample: Bool { seeds.contains("sample") }
  /// Whether a password-protected document is seeded (`-seed-library locked`).
  var seedsLocked: Bool { seeds.contains("locked") }
  /// Whether a damaged document is seeded (`-seed-library damaged`).
  var seedsDamaged: Bool { seeds.contains("damaged") }
  /// Whether the last document seeded opens at launch; `-start home` keeps Home in front, and
  /// `-start list` shows All documents.
  let opensSeededDocument: Bool
  /// Show All documents at launch (`-start list`).
  let startsOnList: Bool
  /// Whether App Lock is on at launch with a scripted confirmation that succeeds or is refused
  /// (`-app-lock confirms` or `-app-lock refuses`); `nil` leaves App Lock off and the device's own
  /// authentication in place.
  let appLockConfirms: Bool?
  /// Where the app goes once it has started (`-open-route pdfalgopro://settings`), as if the link had been
  /// opened; any link the app accepts.
  let route: Route?
  /// Make the scripted intelligence router report that Apple Intelligence is unavailable.
  let intelligenceUnavailable: Bool
  /// Use the device's own model instead of the scripted one (`-intelligence live`), for the App Store
  /// screenshots, which must show what the app really answers (Guideline 2.3.3).
  let usesLiveIntelligence: Bool
  /// Turn off UIKit animations so UI tests do not wait on them.
  let disablesAnimations: Bool
  /// Whether editing existing text is available, locked or hidden (`-text-editing locked`), so UI
  /// tests can see each state; `nil` leaves it to the build.
  let textEditing: TextEditingAccess?
  /// Show tips in a UI test (`-show-tips`), from an empty store; other UI tests see none.
  let showsTips: Bool
  /// Use an editor that can never prove an edit (`-text-editor unprovable`), so UI tests can see
  /// what the reader does then.
  let refusesTextEdits: Bool
  /// The entitlement the app reports (`-entitlement none`, `trial`, `subscribed` or `expired`), so
  /// UI tests can see each state without a store; `nil` leaves it to the build.
  let entitlement: Entitlement?
  /// Start with the day's free allowance used up (`-allowance exhausted`).
  let allowanceExhausted: Bool
  /// Make the store unable to load its products (`-store unavailable`), as without a connection.
  let storeUnavailable: Bool
  /// How a purchase ends in a UI test (`-purchase cancelled`, `failed` or `pending`); it succeeds
  /// unless a test says otherwise.
  let purchaseOutcome: PurchaseOutcome
  /// Whether the annual plan offers its free trial in a UI test: it does unless a test says the
  /// account is not eligible (`-trial ineligible`) or the plan has none (`-trial none`).
  let offersTrial: Bool
  /// The build number first run's replay sees in a UI test (`-first-run-build 24`); without it a UI
  /// test has no replay, and starts where its other arguments say.
  let firstRunBuild: String?
  /// A name under which a UI test's settings and library survive a relaunch (`-keep-state <name>`).
  ///
  /// With it one test can open the app as two builds of the same install, or open a document again after
  /// the app was killed; without it every launch starts afresh.
  let keptState: String?
  /// Whether the reader's newer controls are on (`-reading-controls off` shows the reader without
  /// them, as a Release build has it until the flag is on there); `nil` leaves it to the build.
  let readingControls: Bool?

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    #if DEBUG
      isUITesting = arguments.contains("-ui-testing")
      skipsOnboarding = arguments.contains("-skip-onboarding")
      func value(of name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
      }
      seeds = Set((value(of: "-seed-library") ?? "").split(separator: ",").map(String.init))
      let start = value(of: "-start")
      opensSeededDocument = start != "home" && start != "list"
      startsOnList = start == "list"
      appLockConfirms =
        switch value(of: "-app-lock") {
        case "confirms": true
        case "refuses": false
        default: nil
        }
      route = value(of: "-open-route").flatMap(URL.init(string:)).flatMap(DeepLink.route(for:))
      intelligenceUnavailable = arguments.contains("-intelligence-unavailable")
      usesLiveIntelligence = value(of: "-intelligence") == "live"
      disablesAnimations = arguments.contains("-disable-animations")
      let editing = arguments.firstIndex(of: "-text-editing").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      textEditing =
        switch editing {
        case "available": .available
        case "locked": .locked
        case "hidden": .hidden
        default: nil
        }
      showsTips = arguments.contains("-show-tips")
      let editor = arguments.firstIndex(of: "-text-editor").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      refusesTextEdits = editor == "unprovable"
      let entitled = arguments.firstIndex(of: "-entitlement").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      entitlement =
        switch entitled {
        case "none": Entitlement.none
        // A trial with a day left: long enough for any test, short enough to show its end date.
        case "trial": .trial(endsAt: Date().addingTimeInterval(24 * 60 * 60))
        case "subscribed": .subscribed
        case "expired": .expired
        case "billingRetry": .inBillingRetry
        default: nil
        }
      let allowance = arguments.firstIndex(of: "-allowance").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      allowanceExhausted = allowance == "exhausted"
      let store = arguments.firstIndex(of: "-store").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      storeUnavailable = store == "unavailable"
      let purchase = arguments.firstIndex(of: "-purchase").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      purchaseOutcome =
        switch purchase {
        case "cancelled": .cancelled
        case "failed": .failed
        case "pending": .pending
        default: .purchased
        }
      let trial = arguments.firstIndex(of: "-trial").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      offersTrial = trial != "ineligible" && trial != "none"
      firstRunBuild = arguments.firstIndex(of: "-first-run-build").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      keptState = arguments.firstIndex(of: "-keep-state").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      let reading = arguments.firstIndex(of: "-reading-controls").flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
      }
      readingControls =
        switch reading {
        case "on": true
        case "off": false
        default: nil
        }
    #else
      isUITesting = false
      skipsOnboarding = false
      seeds = []
      opensSeededDocument = false
      startsOnList = false
      appLockConfirms = nil
      route = nil
      intelligenceUnavailable = false
      usesLiveIntelligence = false
      disablesAnimations = false
      textEditing = nil
      showsTips = false
      refusesTextEdits = false
      entitlement = nil
      allowanceExhausted = false
      storeUnavailable = false
      purchaseOutcome = .purchased
      offersTrial = true
      firstRunBuild = nil
      keptState = nil
      readingControls = nil
    #endif
  }
}

/// Composes the live services once, at launch (ADR-0003).
///
/// It holds no logic: features receive exactly the services they need.
@MainActor
final class AppContainer {
  let settings: any SettingsStoring
  /// Where the app keeps small things beside its settings; a UI test's own, never the real one.
  let defaults: UserDefaults
  let library: any DocumentLibrary
  let index: LocalSearchIndex
  let intake: DocumentIntake
  let intelligence: any DocumentIntelligence
  let builder: SearchablePDFBuilder
  /// Recognises text in image-only documents, going on in the background and resuming after a stop (P8).
  let recognition: RecognitionCoordinator
  let telemetry: LocalTelemetry
  /// AI requests by tier, for the privacy report (FR-SET-005); about this device, so not backed up.
  let activity: AIActivityLog
  /// Problems MetricKit reported, kept on this device (P6).
  let diagnosticsLog: DiagnosticsLog
  private let metricKit: MetricKitCollector?
  /// Saved signatures, in the Keychain on this device only (FR-EDIT-004).
  ///
  /// UI tests use their own Keychain service, so they never see or change real signatures.
  let signatures: any SignatureStoring
  /// Face ID, Touch ID or the passcode, for App Lock (FR-SET-002); under test, a scripted answer.
  let authenticator: any DeviceAuthenticating
  let thumbnails = ThumbnailCache()
  /// Whether editing existing text is offered: the release flag and the Pro entitlement (FR-EDIT-001).
  let textEditing: any TextEditingAccessProviding
  /// The Pro subscription's products, named after this app's bundle identifier (ADR-0026).
  let catalog: ProductCatalog
  /// The person's entitlement, followed from launch; every gate reads it here (ADR-0026).
  let entitlements: EntitlementStore
  /// The free tier's daily allowance of scans and intelligence requests (FR-STORE-001).
  ///
  /// UI tests have no limit unless they ask for a used-up allowance, and keep their counts apart.
  let allowance: UsageAllowance
  /// Document intelligence within the free allowance, for the assistant and the Siri summary.
  ///
  /// The live AI evaluation and first run use `intelligence` itself, which is never metered.
  var meteredIntelligence: any DocumentIntelligence {
    MeteredIntelligence(base: intelligence, allowance: allowance) { [entitlements] in await entitlements.resolved() }
  }
  /// The reminder that a trial is about to end (FR-STORE-006); UI tests schedule nothing.
  let reminders: TrialReminderScheduler
  /// The App Store, for asking whether the plans can be shown and for Restore Purchases.
  ///
  /// UI tests never ask the App Store: their store has its products unless a test says otherwise.
  let store: any StoreAccessing
  /// The plans on sale and the way to buy one (ADR-0027).
  ///
  /// UI tests sell two made-up plans, and a purchase there ends as the test asked and, when it
  /// succeeds, grants the entitlement a real one would.
  let offering: any StoreOffering
  /// What edits existing text: the native editor, or under test one that cannot prove an edit.
  var textEditor: any PDFTextEditing {
    #if DEBUG
      if environment.refusesTextEdits { return UnprovableTextEditor() }
    #endif
    return ContentStreamTextEditor()
  }
  /// What recognises text in scans.
  ///
  /// In internal builds: the page read as a document, in the wider set of languages, with words.
  /// In a Release build each part waits for its flag (`ReleaseFlag.documentRecognition`,
  /// `ReleaseFlag.widerRecognition`); with both off it is English and French, line by line, as before.
  static var recognizer: any TextRecognizing {
    let lines: VisionTextRecognizer =
      AppTextEditingAccess.isInternalBuild || ReleaseFlag.widerRecognition.compiledDefault
      ? .wider : VisionTextRecognizer()
    return AppTextEditingAccess.isInternalBuild || ReleaseFlag.documentRecognition.compiledDefault
      ? VisionDocumentRecognizer(fallback: lines) : lines
  }

  /// Whether a word also finds its other forms, in library search and in the pages chosen for a
  /// question: on in internal builds, the compiled default (off) in a Release build.
  static var matchesBaseForms: Bool {
    AppTextEditingAccess.isInternalBuild || ReleaseFlag.baseFormMatching.compiledDefault
  }

  /// Whether the reader's newer controls are part of this build: on in internal builds, the
  /// compiled default (off) in a Release build, and whatever a UI test asks for.
  var offersReadingControls: Bool {
    environment.readingControls ?? (AppTextEditingAccess.isInternalBuild || ReleaseFlag.readingControls.compiledDefault)
  }
  /// Counts about the last look at a page's text, for "Report a problem"; in memory only.
  let textEditingDiagnostics = TextEditingDiagnosticsLog()
  /// The library index, opening on a background task from launch (#244).
  private let libraryIndex: OpeningLibraryIndex
  let environment: LaunchEnvironment

  init(environment: LaunchEnvironment = LaunchEnvironment()) {
    self.environment = environment
    let folders = Folders(isUITesting: environment.isUITesting, keptState: environment.keptState)
    let settings: any SettingsStoring
    let suite = environment.keptState.map { "ui-testing-kept-\($0)" } ?? "ui-testing-\(UUID().uuidString)"
    if environment.isUITesting, let defaults = UserDefaults(suiteName: suite) {
      settings = UserDefaultsSettingsStore(defaults: defaults)
      if environment.skipsOnboarding || environment.appLockConfirms != nil {
        settings.save(
          AppSettings(
            hasCompletedOnboarding: environment.skipsOnboarding, isAppLockEnabled: environment.appLockConfirms != nil))
      }
      self.defaults = defaults
    } else {
      settings = UserDefaultsSettingsStore()
      defaults = .standard
    }
    self.settings = settings
    #if DEBUG
      authenticator = environment.appLockConfirms.map { ScriptedAuthenticator(confirms: $0) } ?? LocalAuthenticator()
    #else
      authenticator = LocalAuthenticator()
    #endif

    // Opened off the main thread, with any schema migration: launch doesn't wait for it, and the
    // library shows its loading state until it is open (#244).
    let libraryIndex = OpeningLibraryIndex(storeURL: folders.indexStore)
    self.libraryIndex = libraryIndex
    let library = FileDocumentLibrary(
      documentsFolder: folders.documents, deletedFolder: folders.recentlyDeleted,
      previousVersionsFolder: folders.previousVersions, index: libraryIndex)
    self.library = library
    let spotlight: (any SpotlightIndexing)? =
      environment.isUITesting ? nil : SpotlightIndexer(includesText: { settings.load().indexesTextInSpotlight })
    let index = LocalSearchIndex(
      folder: folders.searchIndex, spotlight: spotlight, usesBaseForms: Self.matchesBaseForms)
    self.index = index
    // Refreshes still owed are kept beside the index, so the next launch does them (#236).
    let pending = PendingRefreshes(
      url: folders.indexStore.deletingLastPathComponent().appendingPathComponent("PendingRefreshes.json"))
    intake = DocumentIntake(library: library, inspector: PDFKitInspector(), index: index, pending: pending)
    let isHidden: @Sendable () -> Bool = { settings.load().isIntelligenceHidden }
    let activity = AIActivityLog(url: folders.diagnostics.appendingPathComponent("ai-activity.json"))
    self.activity = activity
    #if DEBUG
      if environment.isUITesting, !environment.usesLiveIntelligence {
        intelligence = ScriptedIntelligence(unavailable: environment.intelligenceUnavailable, isHidden: isHidden)
      } else {
        intelligence = IntelligenceRouter(
          models: [OnDeviceModel()], isHidden: isHidden, activity: activity,
          wordForms: Self.matchesBaseForms ? .base : .asWritten)
      }
    #else
      intelligence = IntelligenceRouter(
        models: [OnDeviceModel()], isHidden: isHidden, activity: activity,
        wordForms: Self.matchesBaseForms ? .base : .asWritten)
    #endif
    builder = SearchablePDFBuilder(recognizer: Self.recognizer)
    telemetry = LocalTelemetry()
    // Recognition a person starts can go on with its progress in a Live Activity (P8b). The identifier
    // family is declared in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    let continued = ContinuedProcessing(
      family: "\(Bundle.main.bundleIdentifier ?? "com.algorythmos.pdfalgopro").recognition")
    recognition = RecognitionCoordinator(
      library: library, intake: intake, builder: builder, telemetry: telemetry, folder: folders.recognition,
      continued: continued)
    diagnosticsLog = DiagnosticsLog(file: folders.diagnostics.appendingPathComponent("problems.json"))
    metricKit = environment.isUITesting ? nil : MetricKitCollector(log: diagnosticsLog)
    metricKit?.start()
    signatures =
      environment.isUITesting ? KeychainSignatureStore(service: "ui-testing-\(UUID())") : KeychainSignatureStore()
    let catalog = ProductCatalog(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.algorythmos.pdfalgopro")
    self.catalog = catalog
    let provider: any EntitlementProviding
    if environment.isUITesting || environment.entitlement != nil {
      // A UI test never asks the App Store: without an argument, nobody is entitled, and a scripted
      // purchase is what changes that.
      let scripted = ScriptedEntitlements(environment.entitlement ?? .none)
      provider = scripted
      let trial = environment.offersTrial ? TrialOffer(length: 3, unit: .day) : nil
      let plans = FixedStoreOffering.fixturePlans(yearlyID: catalog.yearly, weeklyID: catalog.weekly, trial: trial)
      offering = FixedStoreOffering(
        plans: environment.storeUnavailable ? nil : plans, outcome: environment.purchaseOutcome
      ) { plan in
        scripted.set(plan.trial == nil ? .subscribed : .trial(endsAt: Date().addingTimeInterval(3 * 24 * 60 * 60)))
      }
    } else {
      offering = StoreKitOffering()
      let store = StoreKitEntitlements(productIDs: catalog.productIDs)
      #if INTERNAL_TOOLS
        provider = InternalEntitlementOverride(base: store)
      #else
        provider = store
      #endif
    }
    entitlements = EntitlementStore(provider: provider)
    store = environment.isUITesting ? FixedStoreAccess(isAvailable: !environment.storeUnavailable) : StoreKitAccess()
    if environment.isUITesting {
      reminders = TrialReminderScheduler(
        notifications: SilentNotifications(),
        defaults: UserDefaults(suiteName: "ui-testing-reminder-\(UUID().uuidString)") ?? .standard)
    } else {
      reminders = TrialReminderScheduler(notifications: SystemNotifications())
    }
    if environment.isUITesting {
      let counts = UserDefaults(suiteName: "ui-testing-allowance-\(UUID().uuidString)") ?? .standard
      allowance = UsageAllowance(
        limits: environment.allowanceExhausted ? AllowanceLimits(scans: 0, intelligenceRequests: 0) : .free,
        store: UserDefaultsAllowanceStore(defaults: counts), isUnlimited: !environment.allowanceExhausted)
    } else {
      allowance = UsageAllowance(store: UserDefaultsAllowanceStore())
    }
    if let fixed = environment.textEditing {
      textEditing = FixedTextEditingAccess(fixed)
    } else {
      // Internal builds grant the feature, so testers reach it before the products exist in App
      // Store Connect; elsewhere the entitlement decides.
      textEditing = AppTextEditingAccess.forThisBuild(entitlements: provider)
    }
  }

  /// The diagnostics summary for "Report a problem": app, system and health only (FR-SET-003).
  func diagnostics() async -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let count = (try? await library.documents(in: .all, sortedBy: .title).count) ?? 0
    let level = await libraryIndex.level
    return DiagnosticsSummary(
      appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
      build: info["CFBundleVersion"] as? String ?? "?",
      system: ProcessInfo.processInfo.operatingSystemVersionString, libraryIndex: "\(level)", documentCount: count,
      events: await telemetry.todaysCounts(), problems: await diagnosticsLog.summary(),
      textEditing: textEditingDiagnostics.summary()
    ).text
  }

  /// Writes every document to Spotlight again, after the text setting changed (defect D11).
  ///
  /// Returns whether the library could be listed, and Spotlight took every document; when the library
  /// couldn't be listed, Spotlight is left as it is rather than written with nothing (#237), and when
  /// Spotlight failed, the migration tries again at the next launch (#360).
  @discardableResult
  func reindexSpotlight() async -> Bool {
    guard let documents = try? await library.documents(in: .all, sortedBy: .title) else { return false }
    return await index.reindexSpotlight(documents)
  }

  /// Writes every document to Spotlight again after the text setting changed (defect D11).
  ///
  /// When Spotlight didn't take them all, the launch migration is marked not done, so the next launch
  /// writes them again (#360).
  func textSettingChanged(defaults: UserDefaults = .standard) async {
    await Self.reindexAfterTextSetting(defaults: defaults, reindex: { await self.reindexSpotlight() })
  }

  /// The text-setting rewrite's steps, with what refills the index passed in.
  static func reindexAfterTextSetting(defaults: UserDefaults, reindex: () async -> Bool) async {
    guard await !reindex() else { return }
    defaults.set(1, forKey: spotlightIndexVersionKey)
  }

  /// Where the Spotlight migration records that it is done: 2 once the protected index is filled.
  static let spotlightIndexVersionKey = "spotlight.indexVersion"

  /// Moves Spotlight to the protected index once (defect D11).
  ///
  /// Empties the index earlier builds wrote to, then reindexes. Later launches do nothing.
  func migrateSpotlightIfNeeded(defaults: UserDefaults = .standard) async {
    guard !environment.isUITesting else { return }
    await Self.migrateSpotlight(
      defaults: defaults, retire: { await SpotlightIndexer.retireLegacyIndex() },
      reindex: { await self.reindexSpotlight() })
  }

  /// The Spotlight migration's steps, with what empties and what refills the index passed in.
  ///
  /// It is marked done only when the library could be listed, so a launch where listing failed tries
  /// again next time instead of leaving Spotlight empty for good (#237).
  static func migrateSpotlight(
    defaults: UserDefaults, retire: () async -> Void, reindex: () async -> Bool
  ) async {
    let key = spotlightIndexVersionKey
    guard defaults.integer(forKey: key) < 2 else { return }
    await retire()
    guard await reindex() else { return }
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

  /// - Parameters:
  ///   - isUITesting: Whether a UI test launched the app: its files go to a folder of its own.
  ///   - keptState: The UI test's `-keep-state` name: that folder is the same at every launch with it,
  ///     so the library survives a relaunch; without it each launch gets a new one.
  init(isUITesting: Bool, keptState: String? = nil) {
    let fileManager = FileManager.default
    let root: URL
    let support: URL
    if isUITesting {
      let name = keptState.map { "ui-testing-kept-\($0)" } ?? "ui-testing-\(UUID().uuidString)"
      root = fileManager.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
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

#if DEBUG
  /// An editor that can never prove a real edit, as the native editor cannot for some documents.
  ///
  /// It finds a page's text and rehearses honestly. For UI tests only (`-text-editor unprovable`).
  struct UnprovableTextEditor: PDFTextEditing {
    func text(ofPage page: Data) async -> EditablePageText { await ContentStreamTextEditor().text(ofPage: page) }

    func rehearsing(_ region: EditableTextRegion, onPage page: Data) async -> TextEditResult {
      await ContentStreamTextEditor().rehearsing(region, onPage: page)
    }

    func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult {
      TextEditResult(
        page: nil, outcomes: edits.map { _ in .refused(.notVerified) },
        proofFailure: TextEditProofFailure(.newTextMissing))
    }
  }
#endif
