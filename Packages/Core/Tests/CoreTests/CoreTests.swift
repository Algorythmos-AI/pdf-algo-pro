import CoreTestSupport
import Foundation
import Testing

@testable import Core

@Suite("Document values")
struct DocumentTests {
  @Test("Tags are trimmed, de-duplicated ignoring case, and sorted")
  func tagsAreNormalized() {
    let document = Document(
      title: "A", fileName: "a.pdf", addedAt: .now, tags: [" Tax ", "invoice", "tax", "", "Contracts"])
    #expect(document.tags == ["Contracts", "invoice", "Tax"])
  }

  @Test func identifiersRoundTripThroughStrings() throws {
    let id = DocumentID()
    #expect(DocumentID(string: id.description) == id)
    #expect(DocumentID(string: "not-a-uuid") == nil)
    let decoded = try JSONDecoder().decode(DocumentID.self, from: JSONEncoder().encode(id))
    #expect(decoded == id)
  }

  @Test func modifiedDateDefaultsToAddedDate() {
    let added = Date(timeIntervalSince1970: 100)
    #expect(Document(title: "A", fileName: "a.pdf", addedAt: added).modifiedAt == added)
  }
}

@Suite("Library sections and sorting")
struct LibrarySectionTests {
  let base = Date(timeIntervalSince1970: 1_000_000)

  func make(
    _ title: String, opened: Double? = nil, added: Double = 0, favorite: Bool = false, tags: [String] = [],
    deleted: Bool = false
  ) -> Document {
    Document(
      title: title, fileName: "\(title).pdf", addedAt: base.addingTimeInterval(added),
      lastOpenedAt: opened.map { base.addingTimeInterval($0) }, isFavorite: favorite, tags: tags,
      deletedAt: deleted ? base : nil)
  }

  @Test func sectionsSelectTheRightDocuments() {
    let plain = make("plain")
    let opened = make("opened", opened: 5)
    let favorite = make("favorite", favorite: true)
    let tagged = make("tagged", tags: ["Tax"])
    let deleted = make("deleted", opened: 9, favorite: true, tags: ["Tax"], deleted: true)
    let all = [plain, opened, favorite, tagged, deleted]
    #expect(all.filter(LibrarySection.all.contains).map(\.title) == ["plain", "opened", "favorite", "tagged"])
    #expect(all.filter(LibrarySection.recents.contains).map(\.title) == ["opened"])
    #expect(all.filter(LibrarySection.favorites.contains).map(\.title) == ["favorite"])
    #expect(all.filter(LibrarySection.tag("tax").contains).map(\.title) == ["tagged"])
    #expect(all.filter(LibrarySection.recentlyDeleted.contains).map(\.title) == ["deleted"])
  }

  @Test func recentlyOpenedPutsOpenedDocumentsFirstThenNewestAdded() {
    let documents = [
      make("old", added: 1), make("new", added: 2), make("seen", opened: 1), make("seenLater", opened: 2),
    ]
    #expect(LibrarySort.recentlyOpened.sorted(documents).map(\.title) == ["seenLater", "seen", "new", "old"])
  }

  @Test func titleSortIsNumericAware() {
    let documents = [make("Invoice 10"), make("Invoice 2"), make("apple")]
    #expect(LibrarySort.title.sorted(documents).map(\.title) == ["apple", "Invoice 2", "Invoice 10"])
  }

  @Test func dateAddedIsNewestFirst() {
    #expect(LibrarySort.dateAdded.sorted([make("a", added: 1), make("b", added: 3)]).map(\.title) == ["b", "a"])
  }
}

@Suite("Onboarding intents")
struct OnboardingIntentTests {
  @Test("The AI-first options lead, in the order the PRD fixes (FR-ONB-001)")
  func orderMatchesThePRD() {
    #expect(
      OnboardingIntent.allCases == [
        .chatWithPDF, .summarizeDocument, .extractData, .analyzeContract, .editText, .annotate, .sign, .convert,
        .organize, .read, .scan, .allTools,
      ])
    let aiFirst = OnboardingIntent.allCases.prefix(4).allSatisfy { $0.usesIntelligence }
    let aiLater = OnboardingIntent.allCases.dropFirst(4).contains { $0.usesIntelligence }
    #expect(aiFirst && !aiLater)
  }

  @Test(arguments: [
    (OnboardingIntent.chatWithPDF, HomeAction.openAssistant(.ask)),
    (.summarizeDocument, .openAssistant(.summarize)),
    (.extractData, .openAssistant(.extract)),
    (.analyzeContract, .openAssistant(.explainContract)),
    (.scan, .scanDocument),
    (.read, .importDocument),
    (.sign, .importDocument),
  ])
  func intentsPersonaliseThePrimaryAction(intent: OnboardingIntent, action: HomeAction) {
    #expect(intent.primaryAction == action)
  }

  @Test func firstChosenIntentLeadsAndNoChoiceMeansImport() {
    #expect(HomeAction.primary(for: [.scan, .chatWithPDF]) == .scanDocument)
    #expect(HomeAction.primary(for: []) == .importDocument)
  }
}

@Suite("Deep links")
struct DeepLinkTests {
  let id = DocumentID()

  @Test func documentLinksRoundTripWithOneBasedPages() throws {
    let url = DeepLink.url(for: id, pageIndex: 4)
    #expect(url.absoluteString == "pdfalgopro://document/\(id)?page=5")
    #expect(DeepLink.route(for: url) == .document(id, pageIndex: 4))
    #expect(DeepLink.route(for: DeepLink.url(for: id)) == .document(id, pageIndex: nil))
  }

  @Test(arguments: [
    ("pdfalgopro://library", Route.library(.all)),
    ("pdfalgopro://library/favorites", .library(.favorites)),
    ("pdfalgopro://library/recents", .library(.recents)),
    ("pdfalgopro://library/deleted", .library(.recentlyDeleted)),
    ("PDFALGOPRO://scan", .scan),
    ("pdfalgopro://settings", .settings),
  ])
  func knownLinksParse(string: String, route: Route) throws {
    #expect(DeepLink.route(for: try #require(URL(string: string))) == route)
  }

  @Test(arguments: [
    "https://example.com/document/x", "pdfalgopro://document/not-a-uuid", "pdfalgopro://library/unknown",
    "pdfalgopro://scan/now", "pdfalgopro://delete/everything", "pdfalgopro://document",
  ])
  func untrustedOrMalformedLinksAreRejected(string: String) throws {
    #expect(DeepLink.route(for: try #require(URL(string: string))) == nil)
  }

  @Test("The Staging app's scheme opens the same routes")
  func stagingSchemeIsAccepted() throws {
    #expect(DeepLink.route(for: try #require(URL(string: "pdfalgopro-staging://scan"))) == .scan)
    #expect(
      DeepLink.route(for: try #require(URL(string: "pdfalgopro-staging://library/favorites"))) == .library(.favorites))
    #expect(DeepLink.route(for: try #require(URL(string: "pdfalgopro-other://scan"))) == nil)
  }

  @Test func zeroOrNegativePagesAreIgnored() throws {
    let url = try #require(URL(string: "pdfalgopro://document/\(id)?page=0"))
    #expect(DeepLink.route(for: url) == .document(id, pageIndex: nil))
  }

  @Test func routesAreCodableForSceneRestoration() throws {
    for route in [Route.library(.tag("Tax")), .document(id, pageIndex: 2), .scan, .settings] {
      #expect(try JSONDecoder().decode(Route.self, from: JSONEncoder().encode(route)) == route)
    }
  }
}

@Suite("Intelligence values")
struct IntelligenceValueTests {
  @Test func citationsShowOneBasedPageNumbers() {
    #expect(Citation(pageIndex: 11).pageNumber == 12)
  }

  @Test func notFoundAnswersAreUngrounded() {
    let answer = Answer.notFound(tier: .onDevice)
    #expect(!answer.isGrounded && answer.citations.isEmpty)
  }

  @Test func availabilityReportsWhetherATierIsReady() {
    #expect(IntelligenceAvailability.available(.onDevice).isAvailable)
    #expect(!IntelligenceAvailability.unavailable(.modelNotReady).isAvailable)
  }

  @Test func extractionExportsQuotedCSV() {
    let extraction = Extraction(
      fields: [
        ExtractedField(key: "party", value: "Acme \"Ltd\", Paris", pageIndex: 1),
        ExtractedField(key: "total", value: "12", pageIndex: nil),
      ],
      tier: .onDevice)
    #expect(extraction.csv == "field,value,page\r\n\"party\",\"Acme \"\"Ltd\"\", Paris\",2\r\n\"total\",\"12\",\r\n")
    #expect(extraction.fields[0].isVerified && !extraction.fields[1].isVerified)
  }

  @Test("The CSV file has a byte order mark and the locale's separator (H2)")
  func csvFile() throws {
    let extraction = Extraction(
      fields: [
        ExtractedField(key: "total", value: "1 234,56 €", pageIndex: 0),
        ExtractedField(key: "note", value: "=1+1", pageIndex: nil),
      ],
      tier: .onDevice)
    let french = extraction.csvFile(locale: Locale(identifier: "fr_FR"))
    #expect(french.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
    let frenchText = try #require(String(data: french.dropFirst(3), encoding: .utf8))
    #expect(frenchText == "field;value;page\r\n\"total\";\"1 234,56 €\";1\r\n\"note\";\"'=1+1\";\r\n")
    let english = try #require(
      String(data: extraction.csvFile(locale: Locale(identifier: "en_AU")).dropFirst(3), encoding: .utf8))
    #expect(english.hasPrefix("field,value,page\r\n\"total\",\"1 234,56 €\",1\r\n"))
  }

  @Test("A notice is the CSV's last row, in the same three columns (EU AI Act Art 50(2), L3)")
  func csvNotice() throws {
    let extraction = Extraction(
      fields: [ExtractedField(key: "total", value: "12", pageIndex: 0)], tier: .onDevice)
    let notice = "Made by \"AI\"; may contain errors."
    #expect(
      extraction.csv(notice: notice)
        == "field,value,page\r\n\"total\",\"12\",1\r\n\"notice\",\"Made by \"\"AI\"\"; may contain errors.\",\r\n")
    let french = try #require(
      String(
        data: extraction.csvFile(locale: Locale(identifier: "fr_FR"), notice: notice).dropFirst(3), encoding: .utf8))
    #expect(
      french == "field;value;page\r\n\"total\";\"12\";1\r\n\"notice\";\"Made by \"\"AI\"\"; may contain errors.\";\r\n")
    // Without a notice, nothing changes.
    #expect(extraction.csv == "field,value,page\r\n\"total\",\"12\",1\r\n")
    #expect(
      extraction.csvFile(locale: Locale(identifier: "fr_FR"), notice: nil)
        == extraction.csvFile(locale: Locale(identifier: "fr_FR")))
  }

  @Test(
    "Extracted values a spreadsheet would run as formulas are made inert (CSV injection, H2)",
    arguments: [
      ("=HYPERLINK(\"https://example.com\")", "'=HYPERLINK(\"https://example.com\")"),
      ("@SUM(A1)", "'@SUM(A1)"), ("+cmd|' /C calc'!A0", "'+cmd|' /C calc'!A0"), ("-2+3", "'-2+3"),
      ("\tTAB", "'\tTAB"), ("\rCR", "'\rCR"), ("-12.50", "-12.50"), ("+33 1 23 45 67 89", "+33 1 23 45 67 89"),
      ("-1\u{202F}234,56", "-1\u{202F}234,56"), ("-", "'-"), ("INV-2026-0042", "INV-2026-0042"), ("", ""),
    ])
  func csvInjection(value: String, expected: String) {
    #expect(Extraction.neutralized(value) == expected)
    let csv = Extraction(fields: [ExtractedField(key: "total", value: value, pageIndex: nil)], tier: .onDevice).csv
    #expect(csv.contains("\"" + expected.replacingOccurrences(of: "\"", with: "\"\"") + "\""))
  }

  @Test func inspectionDetectsATextLayer() {
    #expect(PDFInspection(pageCount: 1, isEncrypted: false, pages: [PageText(pageIndex: 0, text: "x")]).hasTextLayer)
    #expect(!PDFInspection(pageCount: 1, isEncrypted: false, pages: [PageText(pageIndex: 0, text: " \n")]).hasTextLayer)
  }
}

@Suite("Settings")
struct SettingsTests {
  @Test func userDefaultsStoreRoundTripsAndDefaultsWhenEmpty() throws {
    let suite = "settings-test-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    #expect(store.load() == AppSettings())
    let changed = AppSettings(
      hasCompletedOnboarding: true, intents: [.scan], isIntelligenceHidden: true, readerDisplayMode: .singlePage,
      librarySort: .title)
    store.save(changed)
    #expect(UserDefaultsSettingsStore(defaults: defaults).load() == changed)
  }

  @Test("Unreadable settings fall back to defaults without reopening onboarding")
  func corruptSettingsFallBackToDefaults() throws {
    let suite = "settings-test-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("{".utf8), forKey: "app.settings.v1")
    #expect(UserDefaultsSettingsStore(defaults: defaults).load() == AppSettings(hasCompletedOnboarding: true))
  }

  @Test("Settings from another version keep every value this version understands")
  func settingsSurviveVersionChanges() throws {
    // An older build that had no library sort yet, and a newer one with an unknown sort, intent and key.
    let older =
      #"{"hasCompletedOnboarding":true,"intents":["scan"],"isIntelligenceHidden":true,"readerDisplayMode":"singlePage"}"#
    let newer =
      #"{"hasCompletedOnboarding":true,"intents":["scan","teleport"],"isIntelligenceHidden":false,"readerDisplayMode":"continuous","librarySort":"byMood","futureSetting":42}"#
    let decodedOlder = try JSONDecoder().decode(AppSettings.self, from: Data(older.utf8))
    #expect(
      decodedOlder
        == AppSettings(
          hasCompletedOnboarding: true, intents: [.scan], isIntelligenceHidden: true, readerDisplayMode: .singlePage))
    let decodedNewer = try JSONDecoder().decode(AppSettings.self, from: Data(newer.utf8))
    #expect(decodedNewer == AppSettings(hasCompletedOnboarding: true, intents: [.scan]))
    let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(decodedNewer))
    #expect(roundTrip == decodedNewer)
    // The page strip is on until switched off; the choice is kept, and a value that is not a
    // yes or no keeps the default.
    #expect(decodedOlder.showsPageStrip)
    let hidden = try JSONDecoder().decode(
      AppSettings.self, from: JSONEncoder().encode(AppSettings(showsPageStrip: false)))
    #expect(!hidden.showsPageStrip)
    let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showsPageStrip":"sometimes"}"#.utf8))
    #expect(odd.showsPageStrip)
    // A build from before the diagnostics choice was stored gets the default, on (PAP-041); a stored
    // "off" is kept.
    #expect(decodedOlder.includesDiagnostics && AppSettings().includesDiagnostics)
    let turnedOff = try JSONDecoder().decode(
      AppSettings.self, from: JSONEncoder().encode(AppSettings(includesDiagnostics: false)))
    #expect(!turnedOff.includesDiagnostics)
    #expect(decodedOlder.isSpotlightTextIncluded, "Settings from before the Spotlight switch keep text in Spotlight")
    let off = AppSettings(isSpotlightTextIncluded: false)
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off)) == off)
    #expect(!decodedOlder.isAppLockEnabled, "Settings from before App Lock leave it off")
    let locked = AppSettings(isAppLockEnabled: true)
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(locked)) == locked)
    #expect(!locked.indexesTextInSpotlight && AppSettings().indexesTextInSpotlight && !off.indexesTextInSpotlight)
  }
}

@Suite("Document intake")
struct DocumentIntakeTests {
  @Test("Importing copies, inspects, records and indexes the document")
  func importIndexesTheDocument() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let inspection = PDFInspection(
      pageCount: 2, isEncrypted: false,
      pages: [PageText(pageIndex: 0, text: "Lease"), PageText(pageIndex: 1, text: "")])
    let intake = DocumentIntake(library: library, inspector: FakeInspector(result: inspection), index: index)
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("Lease \(UUID()).pdf")
    try Data("%PDF-1.7 test".utf8).write(to: source)

    let document = try await intake.importFile(at: source)

    #expect(document.pageCount == 2 && document.hasTextLayer && !document.isEncrypted)
    #expect(try await index.pages(of: document.id) == inspection.pages)
  }

  @Test("Opening a file already in the library opens that document instead of copying it")
  func fileInTheLibraryIsNotCopied() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let known = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast, pageCount: 3))
    let fresh = await library.seed(Document(title: "New", fileName: "new.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index)

    #expect(try await intake.importFile(at: library.folder.appendingPathComponent("lease.pdf")) == known)
    #expect(await index.stored[known.id] == nil, "An inspected document is not inspected again")
    let inspected = try await intake.importFile(at: library.folder.appendingPathComponent("new.pdf"))
    #expect(inspected.id == fresh.id && inspected.pageCount > 0)
    #expect(await index.stored[fresh.id] != nil, "A document never inspected is inspected and indexed")
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 2)
  }

  @Test("A file already in the library is kept when it cannot be read")
  func fileInTheLibraryIsKeptWhenUnreadable() async throws {
    let library = FakeDocumentLibrary()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(fails: true), index: FakeIndex())
    await #expect(throws: (any Error).self) {
      try await intake.importFile(at: library.folder.appendingPathComponent("lease.pdf"))
    }
    #expect(try await library.document(withID: seeded.id) != nil)
  }

  @Test("A file that cannot be read as a PDF leaves no document behind")
  func unreadableFileIsRolledBack() async throws {
    let library = FakeDocumentLibrary()
    let intake = DocumentIntake(library: library, inspector: FakeInspector(fails: true), index: FakeIndex())
    await #expect(throws: LibraryError.notAPDF) {
      try await intake.add(data: Data("%PDF-broken".utf8), title: "Broken")
    }
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
  }

  @Test func refreshReinspectsAChangedFile() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let seeded = await library.seed(Document(title: "Scan", fileName: "scan.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index)
    let refreshed = try await intake.refresh(seeded.id)
    #expect(refreshed.hasTextLayer)
    #expect(refreshed.modifiedAt > seeded.modifiedAt)
    await #expect(throws: LibraryError.notFound) { try await intake.refresh(DocumentID()) }
  }

  @Test("A document already in the library is kept when it cannot be re-read")
  func refreshNeverDeletesTheDocument() async throws {
    let library = FakeDocumentLibrary()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(fails: true), index: FakeIndex())
    await #expect(throws: LibraryError.notAPDF) { try await intake.refresh(seeded.id) }
    #expect(try await library.document(withID: seeded.id) != nil)
  }

  @Test("A cancelled import is rolled back and reports the cancellation, not a bad file")
  func cancelledImportIsRolledBack() async throws {
    let library = FakeDocumentLibrary()
    let intake = DocumentIntake(library: library, inspector: CancelledInspector(), index: FakeIndex())
    await #expect(throws: CancellationError.self) {
      try await intake.add(data: Data("%PDF-1.7\n".utf8), title: "Scan")
    }
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
  }

  @Test("A refresh that fails is written down and done at the next library load (#236)")
  func failedRefreshIsRetried() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index, pending: pending)
    await index.failNextIndex()
    await #expect(throws: (any Error).self) { try await intake.refresh(seeded.id) }
    #expect(await pending.all == [seeded.id], "Still owed a refresh")
    #expect(try await library.document(withID: seeded.id)?.modifiedAt == seeded.modifiedAt, "Not recorded as done")

    #expect(await intake.refreshPending() == 0)

    #expect(await pending.all.isEmpty)
    #expect(await index.stored[seeded.id] != nil, "Search and Spotlight caught up")
    _ = try await intake.refresh(seeded.id)
    #expect(await pending.all.isEmpty, "A refresh that works leaves nothing owed")
  }

  @Test("A document no longer in the library is crossed off the refreshes still owed (#236)")
  func goneDocumentIsCrossedOff() async throws {
    let pending = PendingRefreshes(url: nil)
    let gone = DocumentID()
    try await pending.add(gone)
    let intake = DocumentIntake(
      library: FakeDocumentLibrary(), inspector: FakeInspector(), index: FakeIndex(), pending: pending)
    #expect(await intake.refreshPending() == 0)
    #expect(await pending.all.isEmpty)
  }

  @Test("A document deleted for good stays owed until it is out of search and Spotlight (#360)")
  func goneDocumentStaysOwedUntilRemoved() async throws {
    let pending = PendingRefreshes(url: nil)
    let index = FakeIndex()
    let gone = DocumentID()
    let protected = DocumentID()
    try await pending.add(gone)
    try await pending.add(protected, protecting: true)
    await index.failSpotlightRemoval(true)
    let intake = DocumentIntake(
      library: FakeDocumentLibrary(), inspector: FakeInspector(), index: index, pending: pending)

    _ = await intake.refreshPending()

    #expect(Set(await pending.all) == [gone, protected], "Not crossed off while Spotlight still has them")
    for _ in 0..<4 { _ = await intake.refreshPending() }
    #expect(await pending.all == [protected], "Given up after three tries, unless it is protected")
    await index.failSpotlightRemoval(false)
    _ = await intake.refreshPending()
    #expect(await pending.all.isEmpty)
    #expect(await index.removed == [protected])
  }

  @Test("A new document whose search or Spotlight entry fails is kept and not reported; it catches up later (#360)")
  func newDocumentIndexFailureIsOwed() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index, pending: pending)
    await index.failIndexing(true)

    let added = try await intake.add(data: Data("%PDF-1.7\n".utf8), title: "Scan")

    #expect(try await library.document(withID: added.id) != nil)
    #expect(added.pageCount == 1, "Recorded as read")
    #expect(await pending.all == [added.id], "Search and Spotlight are owed")
    await index.failIndexing(false)
    #expect(await intake.refreshPending() == 0)
    #expect(await pending.all.isEmpty)
    #expect(await index.inSpotlight.contains(added.id))
  }

  @Test("A library change whose Spotlight part fails is owed; a protected entry is tried until it is gone (#360)")
  func catchUpIsOwed() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    var payslip = Document(title: "Payslip", fileName: "p.pdf", addedAt: .distantPast)
    payslip.isEncrypted = true
    let binned = await library.seed(payslip)
    try await index.index(binned, pages: [])
    let intake = DocumentIntake(
      library: library, inspector: FakeInspector(result: PDFInspection(pageCount: 0, isEncrypted: true, pages: [])),
      index: index, pending: pending)
    try await library.moveToRecentlyDeleted(binned.id)
    await index.failSpotlightRemoval(true)

    #expect(await intake.catchUp(binned.id, protecting: true) == false)
    for _ in 0..<5 { _ = await intake.refreshPending() }

    #expect(await pending.all == [binned.id], "Never given up while Spotlight has it")
    #expect(await index.inSpotlight.contains(binned.id))
    await index.failSpotlightRemoval(false)
    _ = await intake.refreshPending()
    #expect(await !index.inSpotlight.contains(binned.id))
    #expect(await pending.all.isEmpty)
    #expect(await intake.catchUp(binned.id), "Nothing owed when it works")
    #expect(await pending.all.isEmpty)
  }

  @Test("The refreshes still owed survive a relaunch (#236)")
  func pendingRefreshesPersist() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pending-\(UUID().uuidString).json")
    let id = DocumentID()
    try await PendingRefreshes(url: url).add(id)
    let relaunched = PendingRefreshes(url: url)
    #expect(await relaunched.all == [id])
    try await relaunched.remove(id)
    #expect(await PendingRefreshes(url: url).all.isEmpty)
  }

  @Test("A document deleted while its refresh runs doesn't come back in search or Spotlight")
  func deletedDuringRefreshIsNotIndexed() async throws {
    let library = FakeDocumentLibrary()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let index = DeletingIndex(library: library, deleting: seeded.id)
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index)
    await #expect(throws: LibraryError.notFound) { try await intake.refresh(seeded.id) }
    #expect(await index.fake.stored[seeded.id] == nil)
  }

  // MARK: - Second R1 review

  private let locked = PDFInspection(pageCount: 0, isEncrypted: true, pages: [])

  @Test("A protected document's words leave search and Spotlight even when the disk stays full (#236)")
  func protectedWordsLeaveOnAFullDisk() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    await index.seed(seeded.id, pages: [PageText(pageIndex: 0, text: "private words")])
    await index.failIndexing(true)
    let intake = DocumentIntake(
      library: library, inspector: FakeInspector(result: locked), index: index, pending: PendingRefreshes(url: nil))
    await #expect(throws: (any Error).self) { try await intake.refresh(seeded.id) }
    #expect(await index.stored[seeded.id] == nil, "Removing needs no space")
    #expect(await index.removed == [seeded.id], "Spotlight's entry goes with it")
  }

  @Test("A refresh that began before a change doesn't cross off the refresh that change is owed (#236)")
  func earlierRefreshLeavesALaterChangeOwed() async throws {
    let library = FakeDocumentLibrary()
    let pending = PendingRefreshes(url: nil)
    let gate = InspectionGate()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(
      library: library, inspector: GatedInspector(gate: gate), index: FakeIndex(), pending: pending)
    let earlier = Task { try await intake.refresh(seeded.id) }
    await gate.waitForArrival()
    await intake.willChange(seeded.id)
    await gate.open()
    _ = try await earlier.value
    #expect(await pending.all == [seeded.id], "The later change still needs its refresh")
  }

  @Test("A file that isn't a readable PDF any more is crossed off at once, and its old text goes (#236)")
  func unreadableFileIsCrossedOff() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    await index.seed(seeded.id, pages: [PageText(pageIndex: 0, text: "old words")])
    try await pending.add(seeded.id)
    let intake = DocumentIntake(
      library: library, inspector: FakeInspector(fails: true), index: index, pending: pending)
    _ = await intake.refreshPending()
    #expect(await pending.all.isEmpty)
    #expect(await index.stored[seeded.id] == nil)
  }

  @Test("A refresh that keeps failing is given up after three tries (#236)")
  func retriesStop() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    try await pending.add(seeded.id)
    await index.failIndexing(true)
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index, pending: pending)
    for _ in 0..<3 { _ = await intake.refreshPending() }
    #expect(await pending.all.isEmpty)
  }

  @Test("Taking a protected document's words out of search is never given up (#236)")
  func protectedRemovalIsKept() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index, pending: pending)
    await intake.willChange(seeded.id, protecting: true)
    await index.failIndexing(true)
    await index.failRemoving(true)
    for _ in 0..<5 { _ = await intake.refreshPending() }
    #expect(await pending.all == [seeded.id])
    await index.failRemoving(false)
    _ = await intake.refreshPending()
    #expect(await pending.all.isEmpty, "Once the words are out, the rest may be given up")
  }

  @Test("A document moved to Recently Deleted while its refresh runs is not put back in Spotlight")
  func binnedDuringRefreshStaysOutOfSpotlight() async throws {
    let library = FakeDocumentLibrary()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let index = DeletingIndex(library: library, deleting: seeded.id, toRecentlyDeleted: true)
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index)
    _ = try? await intake.refresh(seeded.id)
    #expect(await index.fake.indexed.last?.isDeleted == true, "Spotlight's last word is that it is deleted")
  }

  // MARK: - Third R1 review

  @Test("A refresh while a password is being saved doesn't cross off the change; one after the save does (#236)")
  func changeBeingSavedStaysOwed() async throws {
    let library = FakeDocumentLibrary()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: FakeIndex(), pending: pending)
    let change = await intake.willChange(seeded.id, protecting: true)

    // The launch pass reaches the document while the save is still writing: it reads the old file.
    _ = await intake.refreshPending()

    #expect(await pending.all == [seeded.id], "Still owed: what it read was from before the save")
    #expect(await pending.owed(seeded.id)?.protects == true)
    await intake.saveFinished(seeded.id, change: change)
    _ = try await intake.refresh(seeded.id)
    #expect(await pending.all.isEmpty, "A refresh after the save crosses it off")
  }

  @Test("Two refreshes of one document never overlap, so a stale one can't overwrite a newer result (#236)")
  func refreshesOfOneDocumentRunInTurn() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let gate = InspectionGate()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let inspector = ScriptedInspector(
      gate: gate,
      results: [
        PDFInspection(pageCount: 1, isEncrypted: false, pages: [PageText(pageIndex: 0, text: "old words")]),
        PDFInspection(pageCount: 0, isEncrypted: true, pages: []),
      ])
    let intake = DocumentIntake(library: library, inspector: inspector, index: index)
    let stale = Task { try await intake.refresh(seeded.id) }
    await gate.waitForArrival()
    let newer = Task { try await intake.refresh(seeded.id) }
    try await Task.sleep(for: .milliseconds(100))
    await gate.open()
    _ = try await stale.value
    _ = try await newer.value
    #expect(await index.stored[seeded.id] == [], "The newer, locked result is the last word")
    #expect(try await library.document(withID: seeded.id)?.isEncrypted == true)
  }

  @Test("A protecting change whose save failed doesn't take an unprotected document's words out of search")
  func failedProtectionLeavesWordsIn() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    await index.seed(seeded.id, pages: [PageText(pageIndex: 0, text: "ordinary words")])
    let intake = DocumentIntake(library: library, inspector: FakeInspector(), index: index, pending: pending)
    let change = await intake.willChange(seeded.id, protecting: true)
    await intake.saveFinished(seeded.id, change: change)  // The save failed: the file is as it was.
    await index.failIndexing(true)
    for _ in 0..<5 { _ = await intake.refreshPending() }
    #expect(await index.stored[seeded.id] == [PageText(pageIndex: 0, text: "ordinary words")])
  }

  @Test("Removing a password clears the protection a change was owed")
  func removingThePasswordClearsProtection() async throws {
    let pending = PendingRefreshes(url: nil)
    let id = DocumentID()
    try await pending.add(id, protecting: true)
    try await pending.add(id, protecting: false)
    #expect(await pending.owed(id)?.protects == false)
  }

  @Test("A document with only an owner password stays in search when the disk is full")
  func ownerPasswordOnlyStaysSearchable() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let words = [PageText(pageIndex: 0, text: "readable words")]
    await index.seed(seeded.id, pages: words)
    await index.failIndexing(true)
    let readable = PDFInspection(pageCount: 1, isEncrypted: true, pages: words)
    let intake = DocumentIntake(library: library, inspector: FakeInspector(result: readable), index: index)
    await #expect(throws: (any Error).self) { try await intake.refresh(seeded.id) }
    #expect(await index.stored[seeded.id] == words, "It opens without a password, so its words stay")
  }

  @Test("A file that isn't a PDF any more is given up after three tries even when its text can't be removed")
  func unreadableFileIsGivenUp() async throws {
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    try await pending.add(seeded.id)
    await index.failRemoving(true)
    let intake = DocumentIntake(
      library: library, inspector: FakeInspector(fails: true), index: index, pending: pending)
    for _ in 0..<3 { _ = await intake.refreshPending() }
    #expect(await pending.all.isEmpty)
  }

  @Test(
    "A file changed outside the app keeps its tags and favourite and takes the new text; its page resets only if the page count changed (#242)",
    arguments: [-3_600.0, 3_600.0], [8, 10])
  func replacedFileStartsAgain(changedBy offset: TimeInterval, pages: Int) async throws {
    // The owner's decisions on #242, "Keep tags" and "Reset if pages change", for a replacement older
    // than the document (found by its file identity) and one newer (found by its date): both are read
    // again with a date. The entry had 8 pages and was being read on page 6.
    let library = FakeDocumentLibrary()
    let index = FakeIndex()
    let recorded = Date(timeIntervalSince1970: 1_000_000)
    let seeded = await library.seed(
      Document(
        title: "Invoice", fileName: "invoice.pdf", addedAt: recorded, lastPageIndex: 5, pageCount: 8,
        isFavorite: true, tags: ["Paid"]))
    await index.seed(seeded.id, pages: [PageText(pageIndex: 0, text: "old words")])
    let replacement = [PageText(pageIndex: 0, text: "new words")]
    let inspector = FakeInspector(result: PDFInspection(pageCount: pages, isEncrypted: false, pages: replacement))
    let intake = DocumentIntake(library: library, inspector: inspector, index: index)

    _ = try await intake.refresh(seeded.id, changedAt: recorded.addingTimeInterval(offset))

    let after = try #require(try await library.document(withID: seeded.id))
    #expect(after.tags == ["Paid"], "Tags kept")
    #expect(after.isFavorite, "Favourite kept")
    let expected = pages == 8 ? 5 : 0
    #expect(after.lastPageIndex == expected, "Page \(after.lastPageIndex + 1), not page \(expected + 1)")
    #expect(after.pageCount == pages)
    #expect(await index.stored[seeded.id] == replacement, "Only the new file's words are searchable")
  }

  @Test("A cancelled refresh stays owed, and isn't counted as a failure (#236)")
  func cancelledRefreshStaysOwed() async throws {
    let library = FakeDocumentLibrary()
    let pending = PendingRefreshes(url: nil)
    let seeded = await library.seed(Document(title: "Lease", fileName: "lease.pdf", addedAt: .distantPast))
    let intake = DocumentIntake(
      library: library, inspector: CancelledInspector(), index: FakeIndex(), pending: pending)
    await #expect(throws: CancellationError.self) { try await intake.refresh(seeded.id) }
    #expect(await pending.owed(seeded.id)?.failures == 0, "Owed, with no failure counted")
    #expect(await intake.refreshPending() == 0)
    #expect(await pending.owed(seeded.id)?.failures == 0, "Still owed after a cancelled pass")
    #expect(try await library.document(withID: seeded.id)?.modifiedAt == seeded.modifiedAt, "Not recorded as done")
  }
}

/// An inspector that returns its results in turn, the first held at a gate.
private actor ScriptedInspector: PDFInspecting {
  let gate: InspectionGate
  private var results: [PDFInspection]
  private var calls = 0

  init(gate: InspectionGate, results: [PDFInspection]) {
    self.gate = gate
    self.results = results
  }

  func inspect(_ url: URL) async throws -> PDFInspection {
    calls += 1
    let result = results.removeFirst()
    if calls == 1 { await gate.pass() }
    return result
  }
}

/// An inspector whose task was cancelled.
private struct CancelledInspector: PDFInspecting {
  func inspect(_ url: URL) async throws -> PDFInspection { throw CancellationError() }
}

/// A search index during whose write the document is deleted for good, as when the person deletes
/// it while its refresh runs.
private struct DeletingIndex: DocumentIndexing {
  let library: FakeDocumentLibrary
  let deleting: DocumentID
  /// Moves it to Recently Deleted instead of deleting it for good.
  var toRecentlyDeleted = false
  let fake = FakeIndex()

  func index(_ document: Document, pages: [PageText]) async throws {
    if toRecentlyDeleted {
      if try await library.document(withID: deleting)?.isDeleted == false {
        try await library.moveToRecentlyDeleted(deleting)
      }
    } else {
      try await library.deletePermanently(deleting)
    }
    try await fake.index(document, pages: pages)
  }

  func remove(_ id: DocumentID) async throws { try await fake.remove(id) }

  func prune(keeping ids: Set<DocumentID>) async -> [DocumentID] { await fake.prune(keeping: ids) }

  func pages(of id: DocumentID) async throws -> [PageText] { try await fake.pages(of: id) }

  func search(_ query: String, in documents: [Document]) async throws -> [SearchHit] {
    try await fake.search(query, in: documents)
  }
}

@Suite("Signatures")
struct SignatureTests {
  @Test("Drawn strokes are fitted to a unit box that keeps their shape (FR-EDIT-004)")
  func fitting() throws {
    let signature = try #require(
      SavedSignature(drawn: [[CGPoint(x: 10, y: 20), CGPoint(x: 210, y: 70)], [], [CGPoint(x: 110, y: 45)]]))
    #expect(signature.aspectRatio == 4)
    #expect(signature.strokes == [[.init(x: 0, y: 0), .init(x: 1, y: 1)], [.init(x: 0.5, y: 0.5)]])
    let line = try #require(SavedSignature(drawn: [[CGPoint(x: 0, y: 5), CGPoint(x: 100, y: 5)]]))
    #expect(line.aspectRatio == 10, "A straight line still gets some height")
    #expect(SavedSignature(drawn: []) == nil)
    #expect(SavedSignature(drawn: [[CGPoint(x: 3, y: 3)]]) == nil, "A dot is not a signature")
  }

  @Test("The in-memory store keeps signatures in order, replaces by identity and can fail")
  func fakeStore() async throws {
    let store = InMemorySignatureStore()
    let older = SavedSignature(strokes: [], aspectRatio: 1, createdAt: .distantPast)
    var newer = SavedSignature(strokes: [], aspectRatio: 2, createdAt: .now)
    try await store.save(newer)
    try await store.save(older)
    newer.aspectRatio = 3
    try await store.save(newer)
    #expect(try await store.signatures().map(\.aspectRatio) == [1, 3])
    try await store.delete(older.id)
    #expect(try await store.signatures() == [newer])
    await store.failNext(with: .keychain(-25300))
    await #expect(throws: SignatureStoreError.keychain(-25300)) { try await store.signatures() }
  }
}

@Suite("Rating requests")
struct ReviewPolicyTests {
  @Test("Asked only after three successes on two days, not in the first session, once per version (plan §6)")
  func due() {
    var policy = ReviewPolicy()
    policy.startSession()
    policy.recordSuccess(on: "2026-10-01")
    policy.recordSuccess(on: "2026-10-01")
    policy.recordSuccess(on: "2026-10-02")
    #expect(!policy.isDue(version: "1.0", sessionHadError: false), "Not in the first session")
    policy.startSession()
    #expect(policy.isDue(version: "1.0", sessionHadError: false))
    #expect(!policy.isDue(version: "1.0", sessionHadError: true), "Never after an error")
    policy.asked(in: "1.0")
    #expect(!policy.isDue(version: "1.0", sessionHadError: false), "Once per version")
    #expect(policy.isDue(version: "1.1", sessionHadError: false))
  }

  @Test("Successes on a single day aren't enough")
  func oneDay() {
    var policy = ReviewPolicy()
    policy.startSession()
    policy.startSession()
    for _ in 0..<5 { policy.recordSuccess(on: "2026-10-01") }
    #expect(!policy.isDue(version: "1.0", sessionHadError: false))
    #expect(policy.successDays == ["2026-10-01"])
    #expect(
      ReviewPolicy.day(of: Date(timeIntervalSince1970: 0), calendar: Calendar(identifier: .gregorian)).count == 10)
  }
}
