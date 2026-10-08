import AssistantFeature
import Commerce
import Core
import CoreSpotlight
import Foundation
import LibraryFeature
import OCR
import Observation
import OnboardingFeature
import PDFEngine
import PaywallFeature
import ReaderFeature
import ScanFeature
import SettingsFeature
import SwiftUI

/// App-level state and the one router every entry point goes through (ADR-0004).
///
/// The router only navigates: opening a link never deletes, sends or changes anything.
@MainActor
@Observable
final class AppModel {
  /// A sheet over the library.
  enum Sheet: String, Identifiable {
    case scan
    case settings
    /// The subscription offer, and after a purchase its confirmation (ADR-0026).
    case paywall
    var id: String { rawValue }
  }

  private(set) var settings: AppSettings
  var sheet: Sheet?
  /// Why the subscription offer is, or was last, on screen.
  private(set) var paywallTrigger: PaywallTrigger = .settings
  /// The end of a trial to tell the person about now, in the app, because no notification will.
  var trialNotice: Date?
  /// Whether the plans can be shown; `nil` until the App Store has answered.
  ///
  /// Asked for when first run starts, so that its end seldom has to wait.
  @ObservationIgnored private var plansAreAvailable: Bool?
  /// How long the end of first run waits for the App Store's answers before going on to Home.
  ///
  /// Long enough for a slow connection, short enough not to feel stuck.
  @ObservationIgnored var storePatience: Duration = .seconds(3)
  let container: AppContainer
  let library: LibraryModel
  /// App Lock (FR-SET-002).
  let lock: AppLock
  /// How this device confirms its owner, read once at launch; `nil` without a passcode.
  let lockMethod: AppLockMethod?
  /// Asks for a rating after real successes, at a calm moment (plan §6).
  let reviews: ReviewPrompter
  @ObservationIgnored private var reader: (selection: DocumentSelection, model: ReaderModel)?
  @ObservationIgnored private(set) lazy var onboarding = makeOnboarding()

  /// The introduction, from its first page.
  private func makeOnboarding() -> OnboardingModel {
    OnboardingModel(
      settings: container.settings, intelligence: container.intelligence, telemetry: container.telemetry
    ) { [weak self] in
      // The last page stays up while the App Store answers, so the offer never arrives over Home a
      // moment after Home did.
      await self?.waitForTheStore()
      self?.settings = $0
      self?.offerAfterFirstRun()
    }
  }

  init(container: AppContainer) {
    self.container = container
    #if INTERNAL_TOOLS
      // A new internal build shows first run again, once (PAP-053). Tests choose their own start.
      if !container.environment.isUITesting {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        InternalFirstRunReplay(defaults: .standard, build: build).apply(to: container.settings)
      }
    #endif
    settings = container.settings.load()
    let store = container.settings
    lock = AppLock(authenticator: container.authenticator) { store.load().isAppLockEnabled }
    lockMethod = container.authenticator.method()
    let reviews = ReviewPrompter(
      defaults: container.environment.isUITesting
        ? UserDefaults(suiteName: "ui-testing-reviews") ?? .standard : .standard,
      version: container.version, isEnabled: !container.environment.isUITesting)
    self.reviews = reviews
    Task { [telemetry = container.telemetry] in
      await telemetry.observe { event in Task { @MainActor in reviews.handle(event) } }
    }
    library = LibraryModel(
      library: container.library, intake: container.intake, index: container.index, settings: container.settings,
      telemetry: container.telemetry, thumbnails: container.thumbnails)
    IntentRouter.shared.attach(
      library: container.library, intelligence: container.meteredIntelligence, index: container.index
    ) { [weak self] route in self?.navigate(to: route) }
    if container.environment.seedsSample {
      Task { await library.addSample() }
    }
    if container.environment.seedsDamaged {
      Task { [library, container] in
        // The sample, with its file then overwritten by bytes that aren't a PDF, as a damaged file would be.
        guard let data = try? SyntheticPDF.makeSample(),
          let document = try? await container.intake.add(data: data, title: "Damaged sample"),
          let url = try? await container.library.fileURL(for: document.id)
        else { return }
        try? Data("not a PDF any more".utf8).write(to: url)
        await library.reload()
        library.open(document.id)
      }
    }
    if container.environment.seedsLocked {
      Task { [library, container] in
        // A synthetic document; its password is a fixture, known to the UI tests.
        guard let data = try? SyntheticPDF.makeEncrypted(pages: ["Locked page"], password: Self.lockedSamplePassword),
          let document = try? await container.intake.add(data: data, title: "Locked sample")
        else { return }
        await library.reload()
        library.open(document.id)
      }
    }
    Task { await container.migrateSpotlightIfNeeded() }
    // Purchases are followed from launch, so one approved or renewed while the app was closed is seen.
    container.entitlements.start()
    if !settings.hasCompletedOnboarding { askWhetherPlansAreAvailable() }
    // Text recognition the app was stopped in the middle of goes on from where it was (P8).
    Task { await container.recognition.resumePending() }
  }

  /// Asks the App Store whether the plans can be shown, ahead of the end of first run.
  private func askWhetherPlansAreAvailable() {
    Task { [weak self, container] in
      let available = await container.store.productsAreAvailable(container.catalog.ordered)
      self?.plansAreAvailable = available
    }
  }

  /// Waits, for no longer than `storePatience`, until the App Store has said whether the plans can be
  /// shown and what the person is entitled to.
  ///
  /// Both were asked for at launch, and on most connections both are known long before the last
  /// page. Without a connection the App Store answers "no" at once, so nothing is waited for then.
  func waitForTheStore() async {
    // The entitlement is followed from launch; this asks once more in case nothing has arrived yet.
    Task { [entitlements = container.entitlements] in _ = await entitlements.resolved() }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: storePatience)
    while clock.now < deadline {
      // Without plans there is no offer, whatever the entitlement turns out to be.
      if plansAreAvailable == false { return }
      if plansAreAvailable == true, container.entitlements.entitlement != nil { return }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  /// Shows first run again, from the first page of the introduction.
  ///
  /// Only the internal testing section of Settings calls it, and that section is in Debug and Staging
  /// builds alone. It is what a new install sees, the subscription offer after it included when the
  /// store has its plans, without deleting the app and the documents in it. Documents and every other
  /// setting stay.
  func replayFirstRun() {
    var current = container.settings.load()
    current.hasCompletedOnboarding = false
    container.settings.save(current)
    plansAreAvailable = nil
    onboarding = makeOnboarding()
    sheet = nil
    settings = current
    askWhetherPlansAreAvailable()
  }

  /// The password of the `-seed-library locked` document (a test fixture).
  static let lockedSamplePassword = "open-sesame"

  // MARK: - Routing

  /// Navigates to a route from a URL, Spotlight, a widget or an intent.
  func navigate(to route: Route) {
    switch route {
    case .library(let section):
      sheet = nil
      library.show(section)
    case .document(let id, let pageIndex):
      sheet = nil
      library.open(id, pageIndex: pageIndex)
    case .scan:
      startScan()
    case .settings:
      sheet = .settings
    }
  }

  // MARK: - Subscription

  /// Shows the subscription offer once, as first run ends (FR-ONB-004).
  ///
  /// Only when the plans have loaded and the person is known not to have Pro: without a connection,
  /// or when the App Store has not answered within `storePatience`, first run simply ends on Home.
  /// Nothing is stored, so the offer cannot come back at a later launch.
  func offerAfterFirstRun() {
    guard plansAreAvailable == true, let entitlement = container.entitlements.entitlement,
      !entitlement.grantsPro(at: Date())
    else { return }
    presentPaywall(.onboarding)
  }

  /// Says in the app that a trial ends within a day, for someone who has no notification for it.
  ///
  /// Asked when the app becomes active. Never over a sheet or during first run: it waits for the
  /// next time the app is opened on Home or on a document.
  func checkTrialNotice() async {
    guard sheet == nil, settings.hasCompletedOnboarding, trialNotice == nil else { return }
    let entitlement = await container.entitlements.resolved()
    guard sheet == nil else { return }
    trialNotice = container.reminders.noticeDue(for: entitlement)
  }

  /// Shows the subscription offer; it replaces a sheet that is up, such as Settings.
  func presentPaywall(_ trigger: PaywallTrigger) {
    paywallTrigger = trigger
    sheet = .paywall
  }

  /// Opens the scanner, or the offer when the day's free scans are used (FR-STORE-008).
  ///
  /// The allowance is asked before the camera opens, so a scan that was made is never refused.
  func startScan() {
    Task {
      let entitlement = await container.entitlements.resolved()
      if await container.allowance.isAllowed(.scan, entitlement: entitlement) {
        sheet = .scan
      } else {
        presentPaywall(.allowanceReached)
      }
    }
  }

  /// What Pro adds in this build, for the offer: only what the build does (FR-ONB-007).
  var paywallBenefits: [PaywallBenefit] {
    var benefits: [PaywallBenefit] = [.unlimitedScans]
    if !settings.isIntelligenceHidden { benefits.append(.unlimitedIntelligence) }
    if ReleaseFlag.textEditing.compiledDefault || AppTextEditingAccess.isInternalBuild {
      benefits.append(.textEditing)
    }
    return benefits
  }

  func makePaywall() -> PaywallModel {
    let language = Locale.current.language.languageCode?.identifier
    return PaywallModel(
      trigger: paywallTrigger, productIDs: container.catalog.ordered, benefits: paywallBenefits,
      termsOfUse: AppLinks.termsOfUse.url(languageCode: language),
      privacyPolicy: AppLinks.privacyPolicy.url(languageCode: language), entitlements: container.entitlements,
      telemetry: container.telemetry,
      setReminder: { [container] isOn, trialEndsAt in await container.reminders.set(isOn, trialEndsAt: trialEndsAt) },
      onClose: { [weak self] in
        if self?.sheet == .paywall { self?.sheet = nil }
      })
  }

  /// The subscription section at the top of Settings.
  var subscriptionSection: AnyView {
    AnyView(
      SubscriptionSection(entitlements: container.entitlements, store: container.store) { [weak self] in
        self?.presentPaywall(.settings)
      })
  }

  /// Handles a `pdfalgopro://` URL; anything else is ignored.
  func handle(_ url: URL) {
    if url.isFileURL {
      Task { await library.importFiles([url]) }
    } else if let route = DeepLink.route(for: url) {
      navigate(to: route)
    }
  }

  /// Opens a Spotlight result (FR-LIB-005).
  func handleSpotlight(_ activity: NSUserActivity) {
    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
      let id = DocumentID(string: identifier)
    else { return }
    navigate(to: .document(id, pageIndex: nil))
  }

  // MARK: - Feature models

  /// The reader for a selection, made once: the library's detail column asks again on every redraw.
  func makeReader(for selection: DocumentSelection) -> ReaderModel {
    if let reader, reader.selection == selection { return reader.model }
    let model = ReaderModel(
      selection: selection.id, pageIndex: selection.pageIndex, task: selection.task, library: container.library,
      intake: container.intake, index: container.index, settings: container.settings, telemetry: container.telemetry,
      recognition: container.recognition, signatures: container.signatures, textEditing: container.textEditing,
      textEditingDiagnostics: container.textEditingDiagnostics, textEditor: container.textEditor,
      readingControls: container.offersReadingControls)
    model.onSeePlans = { [weak self] in self?.presentPaywall(.lockedFeature) }
    model.onAllowanceUsed = { [weak self] in self?.presentPaywall(.allowanceReached) }
    reader = (selection, model)
    return model
  }

  /// Lets go of the reader once its document has closed, so opening it again starts afresh.
  func closeReader() {
    reader = nil
  }

  func makeAssistant(for context: ReaderAssistantContext) -> AssistantModel {
    let model = AssistantModel(
      task: context.task, intelligence: container.meteredIntelligence, pages: context.pages,
      telemetry: container.telemetry, onReveal: context.reveal)
    model.onSeePlans = context.seePlans
    return model
  }

  func makeScan() -> ScanModel {
    ScanModel(
      intake: container.intake, builder: container.builder, telemetry: container.telemetry,
      recognizer: AppContainer.recognizer
    ) {
      [weak self] document in
      guard let self else { return }
      sheet = nil
      Task {
        // Counted once the scan is saved: a scan that was cancelled or failed costs nothing.
        await container.allowance.recordSuccess(.scan)
        await library.reload()
        library.open(document.id)
      }
    }
  }

  /// The internal tools section in Settings (Pro without a purchase, first run again, the live AI
  /// evaluation), in Debug and Staging builds only.
  var internalTools: AnyView? {
    #if INTERNAL_TOOLS
      AnyView(
        EvaluationSection(
          intelligence: container.intelligence,
          onEntitlementOverride: { [container] in Task { await container.entitlements.refresh() } },
          onReplayFirstRun: { [weak self] in self?.replayFirstRun() }))
    #else
      nil
    #endif
  }

  func makeSettings() -> SettingsModel {
    SettingsModel(
      store: container.settings, diagnostics: { [container] in await container.diagnostics() },
      activity: container.activity,
      onChange: { [weak self] settings in
        guard let self else { return }
        let textSettingChanged = settings.indexesTextInSpotlight != self.settings.indexesTextInSpotlight
        self.settings = settings
        self.lock.settingChanged()
        if textSettingChanged { Task { await self.container.reindexSpotlight() } }
      }, versionsSize: { [container] in await container.library.versionsSize() },
      deleteVersions: { [container] in try await container.library.deleteAllVersions() }, lockMethod: lockMethod,
      authenticate: { [container] reason in await container.authenticator.authenticate(reason: reason) })
  }
}
