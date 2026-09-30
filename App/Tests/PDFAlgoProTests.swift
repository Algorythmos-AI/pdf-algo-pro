import AppIntents
import Core
import CoreGraphics
import CoreSpotlight
import DocumentStore
import Foundation
import LibraryFeature
import ReaderFeature
import SwiftUI
import Testing

@testable import PDFAlgoPro

/// App-level composition tests.
///
/// They cover launch arguments, the one router, Spotlight hand-off, App Intents and the scripted router
/// that UI tests rely on. Serialised because App Intents share one router.
@MainActor
@Suite("App", .serialized)
struct AppTests {
  private func makeApp(_ arguments: [String] = ["-ui-testing", "-skip-onboarding"]) -> AppModel {
    AppModel(container: AppContainer(environment: LaunchEnvironment(arguments: arguments)))
  }

  @Test("Test launch arguments are read in Debug builds")
  func launchArguments() {
    let all = LaunchEnvironment(arguments: [
      "-ui-testing", "-skip-onboarding", "-seed-library", "sample", "-intelligence-unavailable", "-disable-animations",
    ])
    #expect(
      all.isUITesting && all.skipsOnboarding && all.seedsSample && all.intelligenceUnavailable && all.disablesAnimations
    )
    let none = LaunchEnvironment(arguments: ["-seed-library"])
    #expect(!none.isUITesting && !none.seedsSample && !none.skipsOnboarding)
    #expect(!LaunchEnvironment(arguments: ["-seed-library", "other"]).seedsSample)
  }

  @Test("Background time is asked for and given back, and giving it back twice is harmless (P8)")
  func backgroundTime() {
    let end = BackgroundTime.begin("Test")
    end()
    end()
  }

  @Test("Every route navigates and none acts by itself (ADR-0004)")
  func routes() throws {
    let app = makeApp()
    #expect(app.settings.hasCompletedOnboarding)
    app.navigate(to: .scan)
    #expect(app.sheet == .scan)
    app.navigate(to: .settings)
    #expect(app.sheet == .settings)
    let id = DocumentID()
    app.navigate(to: .document(id, pageIndex: 3))
    #expect(app.sheet == nil && app.library.selection == DocumentSelection(id: id, pageIndex: 3))
    app.navigate(to: .library(.favorites))
    #expect(app.library.section == .favorites && app.library.selection == nil)
    app.handle(try #require(URL(string: "pdfalgopro://scan")))
    #expect(app.sheet == .scan)
    app.handle(try #require(URL(string: "https://example.com/scan")))
    #expect(app.sheet == .scan)
  }

  @Test("Spotlight results open their document (FR-LIB-005)")
  func spotlight() {
    let app = makeApp()
    let id = DocumentID()
    let activity = NSUserActivity(activityType: CSSearchableItemActionType)
    activity.userInfo = [CSSearchableItemActivityIdentifier: id.description]
    app.handleSpotlight(activity)
    #expect(app.library.selection?.id == id)
    let unknown = NSUserActivity(activityType: CSSearchableItemActionType)
    unknown.userInfo = [CSSearchableItemActivityIdentifier: "not-an-id"]
    app.handleSpotlight(unknown)
    #expect(app.library.selection?.id == id)
  }

  @Test("App Intents find documents and navigate to them")
  func appIntents() async throws {
    let app = makeApp()
    await app.library.addSample()
    let query = DocumentEntityQuery()
    let suggested = try await query.suggestedEntities()
    #expect(suggested.map(\.title) == ["Welcome to PDF Algo Pro"])
    #expect(try await query.entities(matching: "welcome").count == 1)
    #expect(try await query.entities(matching: "nothing like this").isEmpty)
    let entity = try #require(suggested.first)
    #expect(try await query.entities(for: [entity.id]).map(\.id) == [entity.id])
    _ = entity.displayRepresentation

    app.library.selection = nil
    let open = OpenDocumentIntent()
    open.target = entity
    _ = try await open.perform()
    #expect(app.library.selection?.id.description == entity.id)
    _ = try await ScanDocumentIntent().perform()
    #expect(app.sheet == .scan)
    #expect(!PDFAlgoProShortcuts.appShortcuts.isEmpty)

    // Summarise returns the summary, labelled as generated on this device, and needs the device unlocked.
    #expect(SummarizeDocumentIntent.authenticationPolicy == .requiresAuthentication)
    let summarize = SummarizeDocumentIntent()
    summarize.target = entity
    _ = try await summarize.perform()
    let id = try #require(DocumentID(string: entity.id))
    let summary = try await IntentRouter.shared.summary(of: id)
    #expect(summary.contains("Generated on this device"))
    await #expect(throws: IntentFailure.self) { try await IntentRouter.shared.summary(of: DocumentID()) }
  }

  @Test("A route that arrives before the app attaches is delivered on attach")
  func pendingRoutes() async {
    let router = IntentRouter()
    var delivered: [Route] = []
    router.open(.scan)
    #expect(await router.documents().isEmpty)
    router.attach(library: FakeLibrary()) { delivered.append($0) }
    router.open(.settings)
    #expect(delivered == [.scan, .settings])
  }

  @Test("Feature models are composed from the container")
  func composition() async {
    let app = makeApp()
    let id = DocumentID()
    let selection = DocumentSelection(id: id, pageIndex: 2, task: .ask)
    let reader = app.makeReader(for: selection)
    #expect(app.makeReader(for: selection) === reader, "One reader per selection, however often the view asks")
    #expect(app.makeReader(for: DocumentSelection(id: id)) !== reader)
    _ = app.makeScan()
    _ = app.makeSettings()
    _ = app.onboarding
    let summary = await app.container.diagnostics()
    #expect(summary.contains("App: PDF Algo Pro") && summary.contains("Library index:"))
    #expect(!app.container.version.isEmpty)
  }

  @Test("The scripted router answers about the sample with citations, or explains why not")
  func scriptedIntelligence() async throws {
    let pages = [PageText(pageIndex: 0, text: "Welcome"), PageText(pageIndex: 1, text: "Total due: 120.00")]
    let router = ScriptedIntelligence(unavailable: false, isHidden: { false })
    #expect(await router.availability() == .available(.onDevice))
    #expect(try await router.summarize(pages).citations.map(\.pageNumber) == [1, 2])
    #expect(try await router.answer("What is the total?", from: pages).isGrounded)
    #expect(try await !router.answer("Who won?", from: pages).isGrounded)
    #expect(try await router.extractFields(from: pages).fields.count == 2)
    #expect(try await router.explainContract(pages).isGrounded)
    await #expect(throws: IntelligenceError.noText) { try await router.summarize([PageText(pageIndex: 0, text: " ")]) }
    let unavailable = ScriptedIntelligence(unavailable: true, isHidden: { false })
    await #expect(throws: IntelligenceError.unavailable(.deviceNotEligible)) { try await unavailable.summarize(pages) }
    #expect(
      await ScriptedIntelligence(unavailable: false, isHidden: { true }).availability()
        == .unavailable(.hiddenBySettings))
  }
}

/// A library with no documents.
private struct FakeLibrary: DocumentLibrary {
  func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Document] { [] }
  func document(withID id: DocumentID) async throws -> Document? { nil }
  func allTags() async throws -> [String] { [] }
  func fileURL(for id: DocumentID) async throws -> URL { throw LibraryError.notFound }
  func importDocument(from url: URL) async throws -> Document { throw LibraryError.notFound }
  func addDocument(data: Data, title: String) async throws -> Document { throw LibraryError.notFound }
  func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws {}
  func rename(_ id: DocumentID, to title: String) async throws -> Document { throw LibraryError.notFound }
  func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws {}
  func setTags(_ tags: [String], for id: DocumentID) async throws {}
  func recordOpened(_ id: DocumentID, pageIndex: Int) async throws {}
  func recordModified(_ id: DocumentID) async throws {}
  func moveToRecentlyDeleted(_ id: DocumentID) async throws {}
  func restore(_ id: DocumentID) async throws {}
  func deletePermanently(_ id: DocumentID) async throws {}
  func purgeExpired(now: Date) async throws -> [DocumentID] { [] }
  func reconcileWithFiles() async throws -> Reconciliation { Reconciliation() }
  func document(at url: URL) async throws -> Document? { nil }
}

/// The Keychain adapter runs here, hosted by the app, because the Keychain needs the app's
/// entitlements; the simulator test build is signed ad hoc for that (ci.yml, A5 in #47).
@Suite("Signatures in the Keychain", .serialized)
struct KeychainSignatureStoreTests {
  @Test("Signatures are kept on this device, replaced by identity and deleted (FR-EDIT-004)")
  func roundTrip() async throws {
    let store = KeychainSignatureStore(service: "tests-\(UUID())")
    #expect(try await store.signatures().isEmpty)
    let first = try #require(
      SavedSignature(drawn: [[CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 30)]], createdAt: .distantPast))
    var second = SavedSignature(strokes: [[.init(x: 0, y: 0), .init(x: 1, y: 1)]], aspectRatio: 2, createdAt: .now)
    try await store.save(second)
    try await store.save(first)
    #expect(try await store.signatures() == [first, second])

    second.aspectRatio = 3
    try await store.save(second)
    #expect(try await store.signatures().map(\.aspectRatio) == [5, 3])
    try await store.delete(first.id)
    try await store.delete(first.id)
    #expect(try await store.signatures() == [second])
    try await store.delete(second.id)
    #expect(try await store.signatures().isEmpty)
  }
}

@Suite("Folders")
struct FoldersTests {
  @Test("The library index is backed up; only the search text is excluded (ADR-0006 addendum)")
  func backupExclusion() throws {
    let folders = Folders(isUITesting: true)
    let derived = folders.indexStore.deletingLastPathComponent()
    let indexValues = try derived.resourceValues(forKeys: [.isExcludedFromBackupKey])
    let searchValues = try folders.searchIndex.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(indexValues.isExcludedFromBackup == false)
    #expect(searchValues.isExcludedFromBackup == true)
  }
}

/// A device whose owner confirms, or doesn't, as the test says.
private final class FakeAuthenticator: DeviceAuthenticating, @unchecked Sendable {
  var confirms = true
  var asked = 0

  func method() -> AppLockMethod? { .faceID }

  func authenticate(reason: String) async -> Bool {
    asked += 1
    return confirms
  }
}

@MainActor
@Suite("App Lock")
struct AppLockTests {
  @Test("With App Lock on, the app starts locked, asks once, and unlocks when the owner confirms (FR-SET-002)")
  func unlocksOnLaunch() async {
    let device = FakeAuthenticator()
    let lock = AppLock(authenticator: device) { true }
    #expect(lock.isLocked && lock.showsCover)
    await lock.scenePhaseChanged(to: .active)
    #expect(!lock.isLocked && !lock.showsCover)
    #expect(device.asked == 1)
  }

  @Test("A failed confirmation stays locked and doesn't ask again by itself")
  func failedConfirmation() async {
    let device = FakeAuthenticator()
    device.confirms = false
    let lock = AppLock(authenticator: device) { true }
    await lock.scenePhaseChanged(to: .active)
    #expect(lock.isLocked)
    // Face ID's prompt makes the scene inactive and active again; that must not loop.
    await lock.scenePhaseChanged(to: .inactive)
    await lock.scenePhaseChanged(to: .active)
    #expect(device.asked == 1)
    device.confirms = true
    await lock.unlock()
    #expect(!lock.isLocked)
  }

  @Test("Going to the background locks; the app switcher only covers (H3)")
  func backgroundLocks() async {
    let device = FakeAuthenticator()
    let lock = AppLock(authenticator: device) { true }
    await lock.scenePhaseChanged(to: .active)
    await lock.scenePhaseChanged(to: .inactive)
    #expect(lock.showsCover && !lock.isLocked, "The switcher's snapshot shows no document")
    await lock.scenePhaseChanged(to: .active)
    #expect(!lock.showsCover)
    await lock.scenePhaseChanged(to: .inactive)
    await lock.scenePhaseChanged(to: .background)
    #expect(lock.isLocked)
    await lock.scenePhaseChanged(to: .active)
    #expect(!lock.isLocked && device.asked == 2)
  }

  @Test(
    "The lock screen draws for every method, locked and only covered",
    arguments: [AppLockMethod.faceID, .touchID, .opticID, .passcode])
  func lockScreenDraws(method: AppLockMethod) async {
    let lock = AppLock(authenticator: FakeAuthenticator()) { true }
    let locked = LockScreen(lock: lock, method: method).frame(width: 390, height: 800)
    #expect(ImageRenderer(content: locked).uiImage != nil)
    #expect(LockScreen.unlockTitle(for: nil) == LockScreen.unlockTitle(for: .passcode))
    await lock.scenePhaseChanged(to: .active)
    await lock.scenePhaseChanged(to: .inactive)
    let covered = LockScreen(lock: lock, method: method).frame(width: 390, height: 800)
    #expect(ImageRenderer(content: covered).uiImage != nil)
  }

  @Test("With App Lock off, nothing is covered or asked")
  func off() async {
    let device = FakeAuthenticator()
    var enabled = false
    let lock = AppLock(authenticator: device) { enabled }
    await lock.scenePhaseChanged(to: .inactive)
    await lock.scenePhaseChanged(to: .background)
    await lock.scenePhaseChanged(to: .active)
    #expect(!lock.showsCover && device.asked == 0)
    enabled = true
    await lock.scenePhaseChanged(to: .background)
    #expect(lock.isLocked)
    enabled = false
    lock.settingChanged()
    #expect(!lock.isLocked && !lock.showsCover, "Turning it off unlocks")
  }
}
