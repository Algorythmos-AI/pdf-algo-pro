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
}

/// An inspector whose task was cancelled.
private struct CancelledInspector: PDFInspecting {
  func inspect(_ url: URL) async throws -> PDFInspection { throw CancellationError() }
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
