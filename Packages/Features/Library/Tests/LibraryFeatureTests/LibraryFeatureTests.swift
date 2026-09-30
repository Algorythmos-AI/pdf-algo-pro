import Core
import CoreTestSupport
import Foundation
import ImageIO
import PDFEngine
import SwiftUI
import Testing

@testable import LibraryFeature

@MainActor
private struct Harness {
  let library = FakeDocumentLibrary()
  let index = FakeIndex()
  let settings = InMemorySettingsStore()
  let telemetry = RecordingTelemetry()
  let model: LibraryModel

  init(inspector: FakeInspector = FakeInspector(), intents: [OnboardingIntent] = []) {
    settings.save(AppSettings(hasCompletedOnboarding: true, intents: intents))
    model = LibraryModel(
      library: library, intake: DocumentIntake(library: library, inspector: inspector, index: index), index: index,
      settings: settings, telemetry: telemetry)
  }

  func file(_ name: String, data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID())-\(name)")
    try data.write(to: url)
    return url
  }
}

@MainActor
@Suite("Library model")
struct LibraryModelTests {
  @Test("Page counts and import errors read naturally in English and French, for one and for many")
  func plurals() {
    func text(_ resource: LocalizedStringResource, in language: String) -> String {
      var resource = resource
      resource.locale = Locale(identifier: language)
      return String(localized: resource)
    }
    let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
    #expect(text(LocalizedStringResource("\(1) pages · \("12 KB")", bundle: bundle), in: "en") == "1 page · 12 KB")
    #expect(text(LocalizedStringResource("\(3) pages · \("12 KB")", bundle: bundle), in: "en") == "3 pages · 12 KB")
    #expect(text(LocalizedStringResource("\(0) pages · \("12 Ko")", bundle: bundle), in: "fr") == "0 page · 12 Ko")
    #expect(text(LocalizedStringResource("\(2) pages · \("12 Ko")", bundle: bundle), in: "fr") == "2 pages · 12 Ko")
    let failed = LocalizedStringResource(
      "\(1) file(s) couldn't be imported because they aren't readable PDFs. Nothing else changed.", bundle: bundle)
    #expect(text(failed, in: "en").hasPrefix("1 file couldn't be imported because it isn't"))
    #expect(text(failed, in: "fr").hasPrefix("1 fichier n’a pas pu être importé"))
  }

  @Test("Imports add documents; unreadable files are reported and nothing else changes (FR-LIB-004)")
  func importFiles() async throws {
    let harness = Harness()
    await harness.model.load()
    #expect(harness.model.phase == .loaded && harness.model.documents.isEmpty)
    let good = try harness.file("Lease.pdf", data: Data("%PDF-1.7 lease".utf8))
    let bad = try harness.file("notes.pdf", data: Data("not a pdf".utf8))
    await harness.model.importFiles([good, bad])
    #expect(harness.model.documents.count == 1)
    #expect(harness.model.errorMessage?.contains("1 file") == true)
    #expect(await harness.telemetry.events == ["quality.operation.failed"])
    #expect(!harness.model.isImporting)
  }

  @Test("Opening a file from the library's folder opens the existing document")
  func openInPlace() async throws {
    let harness = Harness()
    let document = await harness.library.seed(Document(title: "Lease", fileName: "l.pdf", addedAt: .now, pageCount: 2))
    await harness.model.load()
    await harness.model.importFiles([harness.library.folder.appendingPathComponent("l.pdf")])
    #expect(harness.model.documents.map(\.id) == [document.id])
    #expect(harness.model.selection?.id == document.id)
    #expect(harness.model.errorMessage == nil)
  }

  @Test("A single import opens the document")
  func singleImportOpens() async throws {
    let harness = Harness()
    await harness.model.importFiles([try harness.file("One.pdf", data: Data("%PDF-1.7".utf8))])
    #expect(harness.model.selection?.id == harness.model.documents.first?.id)
  }

  @Test("The sample document can be tried from an empty library")
  func sample() async throws {
    let harness = Harness(inspector: FakeInspector())
    await harness.model.addSample()
    #expect(harness.model.documents.map(\.title) == [SampleContent.title])
    #expect(harness.model.selection != nil)
  }

  @Test("Search finds titles and text, and an empty query clears results (FR-LIB-003)")
  func search() async throws {
    let harness = Harness()
    let invoice = await harness.library.seed(Document(title: "March", fileName: "m.pdf", addedAt: .now))
    await harness.index.seed(invoice.id, pages: [PageText(pageIndex: 2, text: "Invoice total")])
    await harness.model.load()
    harness.model.query = "invoice"
    await harness.model.search()
    #expect(harness.model.results?.map(\.documentID) == [invoice.id])
    #expect(harness.model.results?.first.flatMap(harness.model.document(for:))?.title == "March")
    harness.model.query = "  "
    await harness.model.search()
    #expect(harness.model.results == nil)
  }

  @Test("Photos become a PDF in the library, one page each; unreadable ones are counted (FR-ORG-008)")
  func pdfFromPhotos() async throws {
    let harness = Harness()
    let image = try #require(SyntheticPDF.makeTextImage("Receipt", size: CGSize(width: 800, height: 1200)))
    let encoded = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    let png = encoded as Data
    await harness.model.addPhotos([png, Data("not a photo".utf8), png])
    let document = try #require(harness.model.documents.first)
    #expect(harness.model.selection?.id == document.id)
    let url = try await harness.library.fileURL(for: document.id)
    #expect(try PDFDocumentController(url: url).pageCount == 2)
    #expect(harness.model.errorMessage != nil, "The unreadable photo is counted")
    #expect(LibraryModel.image(from: Data()) == nil)
  }

  @Test("Search covers the whole library from any section, and Recently Deleted on its own (FR-LIB-003)")
  func searchWholeLibrary() async throws {
    let harness = Harness()
    let filed = await harness.library.seed(Document(title: "Lease", fileName: "l.pdf", addedAt: .now, tags: ["Home"]))
    let gone = await harness.library.seed(
      Document(title: "Old lease", fileName: "o.pdf", addedAt: .now, deletedAt: .now))
    await harness.index.seed(filed.id, pages: [PageText(pageIndex: 0, text: "Lease agreement")])
    await harness.index.seed(gone.id, pages: [PageText(pageIndex: 0, text: "Lease agreement")])
    await harness.model.load()
    harness.model.section = .favorites
    await harness.model.reload()
    #expect(harness.model.documents.isEmpty)
    harness.model.query = "lease"
    await harness.model.search()
    #expect(harness.model.results?.map(\.documentID) == [filed.id], "Found outside Favourites, not in the bin")
    #expect(harness.model.results?.first.flatMap(harness.model.document(for:))?.title == "Lease")
    harness.model.section = .recentlyDeleted
    await harness.model.reload()
    #expect(harness.model.results?.map(\.documentID) == [gone.id], "Recently Deleted searches the bin only")
  }

  @Test("The start-here card goes once one of your own documents has been opened")
  func startCard() async throws {
    let harness = Harness()
    await harness.library.seed(
      Document(title: SampleContent.title, fileName: "s.pdf", addedAt: .now, lastOpenedAt: .now))
    let mine = await harness.library.seed(Document(title: "Mine", fileName: "m.pdf", addedAt: .now))
    await harness.model.load()
    #expect(harness.model.showsPrimaryAction, "The sample being opened doesn't count")
    try await harness.library.recordOpened(mine.id, pageIndex: 0)
    await harness.model.reload()
    #expect(!harness.model.showsPrimaryAction)
    harness.model.section = .favorites
    #expect(!harness.model.showsPrimaryAction)
  }

  @Test("Document info reads the file's details, and draws at a large text size (FR-LIB-008)")
  func documentInfo() async throws {
    let harness = Harness()
    let document = await harness.library.seed(
      Document(title: "Report", fileName: "r.pdf", addedAt: .now, lastOpenedAt: .now),
      data: try SyntheticPDF.makeSample())
    let details = try #require(await harness.model.details(for: document))
    #expect(details.pageCount == 3 && details.fileSize != nil)
    let view = DocumentInfoView(document: document, details: details).frame(width: 390, height: 900)
      .environment(\.dynamicTypeSize, .accessibility3)
    #expect(ImageRenderer(content: view).uiImage != nil)
    #expect(DocumentInfoView.permission(false) != DocumentInfoView.permission(true))
    let missing = Document(title: "Gone", fileName: "g.pdf", addedAt: .now)
    #expect(await harness.model.details(for: missing) == nil)
  }

  @Test("A search that fails says so instead of showing no results")
  func searchFailure() async {
    let harness = Harness()
    await harness.model.load()
    await harness.index.failSearches(true)
    harness.model.query = "invoice"
    await harness.model.search()
    #expect(harness.model.isSearchUnavailable)
    #expect(await harness.telemetry.events.contains("quality.operation.failed"))
    await harness.index.failSearches(false)
    await harness.model.search()
    #expect(!harness.model.isSearchUnavailable)
  }

  @Test("Housekeeping failures are counted and the library still opens")
  func housekeepingFailure() async {
    let harness = Harness()
    await harness.library.failNext(with: .fileAccessFailed)
    await harness.model.load()
    #expect(harness.model.phase == .loaded)
    #expect(harness.model.errorMessage == nil)
    #expect(await harness.telemetry.events.contains("quality.operation.failed"))
  }

  @Test("Sections and sort order change what is shown, and the sort is remembered")
  func sectionsAndSort() async throws {
    let harness = Harness()
    await harness.library.seed(
      Document(title: "B", fileName: "b.pdf", addedAt: Date(timeIntervalSince1970: 1), isFavorite: true, tags: ["Work"])
    )
    await harness.library.seed(Document(title: "A", fileName: "a.pdf", addedAt: Date(timeIntervalSince1970: 2)))
    await harness.model.load()
    harness.model.sort = .title
    #expect(harness.model.documents.map(\.title) == ["A", "B"])
    #expect(harness.settings.load().librarySort == .title)
    #expect(harness.model.tags == ["Work"])
    harness.model.section = .favorites
    await harness.model.reload()
    #expect(harness.model.documents.map(\.title) == ["B"])
  }

  @Test("Delete, restore and permanent delete keep the index in step (FR-LIB-006)")
  func deletion() async throws {
    let harness = Harness()
    let document = await harness.library.seed(Document(title: "Old", fileName: "o.pdf", addedAt: .now))
    await harness.index.seed(document.id, pages: [PageText(pageIndex: 0, text: "text")])
    await harness.model.load()
    harness.model.open(document.id)
    await harness.model.delete(document.id)
    #expect(harness.model.documents.isEmpty && harness.model.selection == nil)
    await harness.model.restore(document.id)
    #expect(harness.model.documents.count == 1)
    await harness.model.deletePermanently(document.id)
    #expect(await harness.index.removed == [document.id])
    #expect(harness.model.documents.isEmpty)
  }

  @Test("Opening the library removes the search text of purged and vanished documents (FR-LIB-006)")
  func housekeepingRemovesDerivedData() async throws {
    let harness = Harness()
    let kept = await harness.library.seed(Document(title: "Kept", fileName: "k.pdf", addedAt: .now))
    let binned = await harness.library.seed(
      Document(title: "Binned", fileName: "b.pdf", addedAt: .now, deletedAt: .now.addingTimeInterval(-31 * 86_400)))
    let recent = await harness.library.seed(
      Document(title: "Recent", fileName: "r.pdf", addedAt: .now, deletedAt: .now))
    let orphan = DocumentID()
    for id in [kept.id, binned.id, recent.id, orphan] {
      await harness.index.seed(id, pages: [PageText(pageIndex: 0, text: "text")])
    }

    await harness.model.load()

    #expect(Set(await harness.index.removed) == [binned.id, orphan])
    #expect(Set(await harness.index.stored.keys) == [kept.id, recent.id], "Recently Deleted keeps its text")
    #expect(await harness.telemetry.events.isEmpty)
  }

  @Test func renameFavouriteAndTags() async throws {
    let harness = Harness()
    let document = await harness.library.seed(Document(title: "Draft", fileName: "d.pdf", addedAt: .now))
    await harness.model.load()
    await harness.model.rename(document.id, to: "Final")
    await harness.model.toggleFavorite(try #require(harness.model.documents.first))
    await harness.model.setTags(["Tax"], for: document.id)
    let stored = try #require(harness.model.documents.first)
    #expect(stored.title == "Final" && stored.isFavorite && stored.tags == ["Tax"])
    await harness.model.rename(document.id, to: "  ")
    #expect(harness.model.errorMessage == LibraryModel.message(for: LibraryError.emptyTitle))
  }

  @Test("Failures show a plain message and leave the library as it was")
  func failures() async throws {
    let harness = Harness()
    await harness.library.failNext(with: .fileAccessFailed)
    await harness.model.reload()
    #expect(harness.model.errorMessage != nil)
    for error in [LibraryError.notAPDF, .emptyTitle, .notFound, .fileAccessFailed] {
      #expect(!LibraryModel.message(for: error).isEmpty)
    }
    #expect(LibraryModel.message(for: CancellationError()) == LibraryModel.message(for: LibraryError.fileAccessFailed))
  }

  @Test("The home action follows the first onboarding intent (FR-ONB-003)")
  func primaryAction() {
    #expect(Harness(intents: [.summarizeDocument, .scan]).model.primaryAction == .openAssistant(.summarize))
    #expect(Harness().model.primaryAction == .importDocument)
  }

  @Test("With AI hidden, an AI intent offers importing instead (FR-AI-009)")
  func primaryActionRespectsHiddenAI() {
    let harness = Harness(intents: [.chatWithPDF])
    harness.settings.save(
      AppSettings(hasCompletedOnboarding: true, intents: [.chatWithPDF], isIntelligenceHidden: true))
    #expect(harness.model.primaryAction == .importDocument)
    let scanning = Harness(intents: [.scan])
    scanning.settings.save(AppSettings(hasCompletedOnboarding: true, intents: [.scan], isIntelligenceHidden: true))
    #expect(scanning.model.primaryAction == .scanDocument)
  }

  @Test("An AI intent from onboarding opens the assistant on the document it brings in (F9)")
  func intentsOpenTheAssistant() async throws {
    let summarising = Harness(intents: [.summarizeDocument])
    #expect(summarising.model.primaryTask == .summarize)
    await summarising.model.addSample(task: summarising.model.primaryTask)
    #expect(summarising.model.selection?.task == .summarize)
    await summarising.model.importFiles(
      [try summarising.file("Lease.pdf", data: Data("%PDF-1.7".utf8))], task: .explainContract)
    #expect(summarising.model.selection?.task == .explainContract)
    await summarising.model.importFiles([try summarising.file("Plain.pdf", data: Data("%PDF-1.7".utf8))])
    #expect(summarising.model.selection?.task == nil, "Imports from the toolbar just open the document")

    let hidden = Harness(intents: [.chatWithPDF])
    hidden.settings.save(AppSettings(hasCompletedOnboarding: true, intents: [.chatWithPDF], isIntelligenceHidden: true))
    #expect(hidden.model.primaryTask == nil, "Hidden AI never opens uninvited (FR-AI-009)")
    #expect(Harness(intents: [.scan]).model.primaryTask == nil)
  }

  @Test("Thumbnails render from the document's file")
  func thumbnails() async throws {
    let harness = Harness()
    let document = await harness.library.seed(
      Document(title: "Sample", fileName: "s.pdf", addedAt: .now), data: try SyntheticPDF.makeSample())
    #expect(await harness.model.thumbnail(for: document) != nil)
    #expect(await harness.model.thumbnail(for: Document(title: "x", fileName: "missing.pdf", addedAt: .now)) == nil)
  }

  @Test("Section copy exists for every section and home action")
  func copy() {
    for section in LibrarySection.fixed + [.tag("Tax")] {
      _ = LibraryView<EmptyView>.title(for: section)
      _ = LibraryView<EmptyView>.emptyTitle(for: section)
      #expect(!LibraryView<EmptyView>.symbol(for: section).isEmpty)
      #expect(!LibraryView<EmptyView>.identifier(for: section).isEmpty)
    }
    for action in [HomeAction.importDocument, .scanDocument] + AssistantTask.allCases.map(HomeAction.openAssistant) {
      _ = LibraryView<EmptyView>.primaryTitle(for: action)
      _ = LibraryView<EmptyView>.primaryDetail(for: action)
    }
  }
}

@MainActor
@Suite("Tag editor")
struct TagEditorTests {
  @Test("Tags are trimmed, never doubled by case, and suggested from other documents (F7a, FR-LIB-002)")
  func editing() {
    var editing = TagEditing(tags: ["Work", " tax "], available: ["Tax", "Travel", "Home", "work"])
    #expect(editing.tags == ["tax", "Work"])
    #expect(editing.suggestions == ["Home", "Travel"])
    editing.draft = "tr"
    #expect(editing.suggestions == ["Travel"])
    editing.draft = "  Receipts "
    editing.addDraft()
    #expect(editing.tags == ["Receipts", "tax", "Work"] && editing.draft.isEmpty)
    editing.draft = "   "
    editing.addDraft()
    editing.add("WORK")
    #expect(editing.tags == ["Receipts", "tax", "Work"])
    editing.remove("tax")
    #expect(editing.tags == ["Receipts", "Work"])
  }

  @Test("The editor draws at a large text size, with and without tags")
  func draws() {
    for tags in [[], ["Tax", "Work"]] {
      let document = Document(title: "Lease", fileName: "l.pdf", addedAt: .now, tags: tags)
      let view = TagEditor(document: document, available: ["Home"]) { _ in }
        .frame(width: 390, height: 700).environment(\.dynamicTypeSize, .accessibility3)
      #expect(ImageRenderer(content: view).uiImage != nil)
    }
  }
}
