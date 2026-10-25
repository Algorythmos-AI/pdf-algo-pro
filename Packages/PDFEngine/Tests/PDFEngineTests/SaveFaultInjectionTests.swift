import Core
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

/// A folder of its own for one test, with a synthetic document in it.
private struct Workspace {
  let folder: URL
  let url: URL
  let previous: URL
  let original: Data

  init(pages: [String] = ["Fault injection, page one", "Page two"]) throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("fault-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    url = folder.appendingPathComponent("doc.pdf")
    previous = folder.appendingPathComponent("previous.pdf")
    original = try SyntheticPDF.make(pages: pages)
    try original.write(to: url)
  }

  /// Every PDF in the folder, by name.
  var files: [String] { Self.pdfs(in: folder) }

  /// The PDFs in a folder, by name (a staged copy would be one of them).
  static func pdfs(in folder: URL) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.filter { $0.hasSuffix(".pdf") }.sorted()
  }
}

/// What the document's file held at the moment a save was stopped.
private final class DiskSnapshot: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: (data: Data, files: [String])?
  var value: (data: Data, files: [String])? { lock.withLock { storage } }
  func record(_ data: Data, files: [String]) { lock.withLock { storage = (data, files) } }
}

/// The Trust suite's save path, step by step (plan revision 3, R2).
///
/// Every step throws once; the disk is full before and during the write; the file is replaced
/// underneath between reading and writing; and the process stops between the staged write and the
/// rename. Each time the document on disk must stay whole and readable, and nothing the person had is
/// lost.
///
/// Every fault matches its own test's file, so suites running beside this one save normally.
@MainActor
@Suite("Trust: every step of a save, the disk and the file under it", .serialized)
struct SaveFaultInjectionTests {
  struct Injected: Error {}

  @Test(
    "Stopped at any step, the file on disk is a whole document: the original until the replace, then the new one",
    arguments: PDFDocumentController.SaveStep.allCases)
  func stoppedAt(_ step: PDFDocumentController.SaveStep) throws {
    let space = try Workspace()
    let controller = try PDFDocumentController(url: space.url)
    controller.addNote("Stopped", onPage: 1)
    let snapshot = DiskSnapshot()
    let url = space.url
    let folder = space.folder
    // Read the disk at the moment the save stops, as a process killed there would leave it.
    PDFDocumentController.saveFault = { current, target in
      guard current == step, target == url else { return }
      snapshot.record((try? Data(contentsOf: target)) ?? Data(), files: Workspace.pdfs(in: folder))
      throw Injected()
    }
    defer { PDFDocumentController.saveFault = nil }
    #expect(throws: PDFEngineError.saveFailed) { try controller.save(to: space.url, keepingPreviousAt: space.previous) }

    let atStop = try #require(snapshot.value, "The fault at \(step) was reached")
    let document = try #require(PDFDocument(data: atStop.data), "At \(step) the file on disk opens")
    #expect(document.pageCount == 2, "At \(step) the file on disk has every page")
    if step == .replaced {
      #expect(document.page(at: 1)?.annotations.isEmpty == false, "After the replace it is the new version")
      #expect(try Data(contentsOf: space.previous) == space.original, "and the one before it is kept")
    } else {
      #expect(atStop.data == space.original, "Before the replace it is the original, byte for byte")
      #expect(try Data(contentsOf: space.url) == space.original, "and stays so after the failed save")
    }
    let keepsPrevious = step == .keptPrevious || step == .replaced
    let expected = keepsPrevious ? ["doc.pdf", "previous.pdf"] : ["doc.pdf"]
    #expect(atStop.files == expected, "Nothing half-written sits beside the document at \(step)")
    #expect(space.files == expected, "and nothing is left there after it")
    #expect(controller.hasUnsavedChanges, "The note is still there to save")
  }

  @Test("A process stopped between the staged write and the rename leaves the original, which opens and saves again")
  func killedBetweenTheStagedWriteAndTheRename() throws {
    let space = try Workspace()
    let url = space.url
    let snapshot = DiskSnapshot()
    let controller = try PDFDocumentController(url: space.url)
    controller.addNote("Lost with the process", onPage: 0)
    // The last moment before the rename: the new file is staged and checked, the old one kept.
    PDFDocumentController.saveFault = { step, target in
      guard step == .keptPrevious, target == url else { return }
      snapshot.record((try? Data(contentsOf: target)) ?? Data(), files: [])
      throw Injected()
    }
    defer { PDFDocumentController.saveFault = nil }
    #expect(throws: PDFEngineError.saveFailed) { try controller.save(to: space.url, keepingPreviousAt: space.previous) }
    #expect(snapshot.value?.data == space.original, "Up to the rename, the document is the original")
    PDFDocumentController.saveFault = nil

    // The app starts again: the document opens as it was, and a new edit saves over it.
    let relaunched = try PDFDocumentController(url: space.url)
    #expect(relaunched.pageCount == 2 && relaunched.annotationCount(onPage: 0) == 0)
    relaunched.addNote("After the relaunch", onPage: 0)
    try relaunched.save(to: space.url, keepingPreviousAt: space.previous)
    #expect(try PDFDocumentController(url: space.url).annotationCount(onPage: 0) == 1)
    #expect(try Data(contentsOf: space.previous) == space.original)
    #expect(space.files == ["doc.pdf", "previous.pdf"])
  }

  @Test("With the disk full before the save, nothing is written and the person is told the disk is full")
  func diskFullBeforeWriting() throws {
    let space = try Workspace()
    let url = space.url
    PDFDocumentController.availableCapacity = { $0 == url ? 4_096 : nil }
    defer { PDFDocumentController.availableCapacity = nil }
    let controller = try PDFDocumentController(url: space.url)
    controller.addNote("No room", onPage: 0)
    #expect(throws: PDFEngineError.insufficientSpace) {
      try controller.save(to: space.url, keepingPreviousAt: space.previous)
    }
    #expect(try Data(contentsOf: space.url) == space.original)
    #expect(space.files == ["doc.pdf"])
    #expect(controller.hasUnsavedChanges)

    PDFDocumentController.availableCapacity = nil
    try controller.save(to: space.url)
    #expect(try PDFDocumentController(url: space.url).annotationCount(onPage: 0) == 1, "Once there is room it saves")
  }

  @Test(
    "When the disk fills during the save, the original stays whole and the person is told the disk is full",
    arguments: [PDFDocumentController.SaveStep.staged, .validated, .coordinated, .keptPrevious])
  func diskFillsDuringTheWrite(at step: PDFDocumentController.SaveStep) throws {
    let space = try Workspace()
    let url = space.url
    // A write that runs out of room fails with the file system's own error, wrapped or not.
    let full: any Error
    switch step {
    case .keptPrevious:
      full = CocoaError(.fileWriteOutOfSpace, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC) as NSError])
    case .coordinated:
      full = POSIXError(.EDQUOT)
    default:
      full = CocoaError(.fileWriteOutOfSpace)
    }
    PDFDocumentController.saveFault = { current, target in
      if current == step && target == url { throw full }
    }
    defer { PDFDocumentController.saveFault = nil }
    let controller = try PDFDocumentController(url: space.url)
    controller.addNote("Disk filled", onPage: 0)
    #expect(throws: PDFEngineError.insufficientSpace) {
      try controller.save(to: space.url, keepingPreviousAt: space.previous)
    }
    #expect(try Data(contentsOf: space.url) == space.original)
    #expect(PDFDocument(url: space.url)?.pageCount == 2)
    #expect(controller.hasUnsavedChanges)
  }

  @Test("Only a full disk reads as a full disk; any other failure is a failed save")
  func errorsAreNamed() {
    #expect(PDFDocumentController.saveError(for: CocoaError(.fileWriteOutOfSpace)) == .insufficientSpace)
    #expect(PDFDocumentController.saveError(for: POSIXError(.ENOSPC)) == .insufficientSpace)
    #expect(
      PDFDocumentController.saveError(
        for: CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC) as NSError]))
        == .insufficientSpace)
    #expect(PDFDocumentController.saveError(for: CocoaError(.fileWriteNoPermission)) == .saveFailed)
    #expect(PDFDocumentController.saveError(for: POSIXError(.EIO)) == .saveFailed)
    #expect(PDFDocumentController.saveError(for: Injected()) == .saveFailed)
  }

  @Test("A file replaced underneath between opening and saving is kept as the earlier version, not lost")
  func replacedUnderneath() throws {
    let space = try Workspace()
    let controller = try PDFDocumentController(url: space.url)
    controller.addNote("Mine", onPage: 0)
    // Another writer (a sync, another app) replaces the file atomically while it is open here.
    let theirs = try SyntheticPDF.make(pages: ["Their version", "with", "three pages"])
    try theirs.write(to: space.url, options: .atomic)

    try controller.save(to: space.url, keepingPreviousAt: space.previous)
    let saved = try PDFDocumentController(url: space.url)
    #expect(saved.pageCount == 2 && saved.annotationCount(onPage: 0) == 1, "The open document is saved whole")
    #expect(try Data(contentsOf: space.previous) == theirs, "and the version that replaced it is kept, byte for byte")
    #expect(PDFDocument(url: space.previous)?.pageCount == 3)
  }

  @Test(
    "A file replaced underneath stays whole when the save then fails",
    arguments: [PDFDocumentController.SaveStep.staged, .coordinated, .keptPrevious])
  func replacedUnderneathThenFailed(at step: PDFDocumentController.SaveStep) throws {
    let space = try Workspace()
    let url = space.url
    let controller = try PDFDocumentController(url: space.url)
    controller.addNote("Mine", onPage: 0)
    let theirs = try SyntheticPDF.make(pages: ["Their version", "with", "three pages"])
    try theirs.write(to: space.url, options: .atomic)

    PDFDocumentController.saveFault = { current, target in
      if current == step && target == url { throw Injected() }
    }
    defer { PDFDocumentController.saveFault = nil }
    #expect(throws: PDFEngineError.saveFailed) { try controller.save(to: space.url, keepingPreviousAt: space.previous) }
    #expect(try Data(contentsOf: space.url) == theirs, "The other writer's file is untouched")
    #expect(PDFDocument(url: space.url)?.pageCount == 3)
    #expect(controller.hasUnsavedChanges && controller.pageCount == 2, "and the open document still has its edit")
  }
}

/// The malformed corpus at every entry point (plan revision 3, R2): opening, inspecting, rendering,
/// searching and reading the outline never crash or hang, and a file with no PDF in it is refused with
/// the engine's errors at each of them.
@MainActor
@Suite("Malformed input: open, render and search report errors, never crash", .serialized)
struct MalformedInputTests {
  private func write(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("malformed-\(UUID().uuidString).pdf")
    try data.write(to: url)
    return url
  }

  @Test(
    "A file with no PDF in it is refused by every entry point",
    arguments: GoldenCorpus.malformed().filter(\.mustFailToOpen))
  func refused(_ item: GoldenCorpus.Malformed) async throws {
    let url = try write(item.data)
    #expect(throws: PDFEngineError.unreadable) { _ = try PDFDocumentController(url: url) }
    #expect(throws: PDFEngineError.unreadable) { _ = try PDFDocumentController(data: item.data) }
    #expect(throws: PDFEngineError.unreadable) {
      _ = try PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 200)
    }
    await #expect(throws: LibraryError.notAPDF) { _ = try await PDFKitInspector().inspect(url) }
    #expect(DocumentDetails.of(fileAt: url) == nil)
  }

  @Test(
    "Every malformed file opens or fails with the engine's error; what opens renders and searches",
    .timeLimit(.minutes(3)), arguments: GoldenCorpus.malformed())
  func openRenderSearch(_ item: GoldenCorpus.Malformed) throws {
    let url = try write(item.data)
    let controller: PDFDocumentController
    do {
      controller = try PDFDocumentController(url: url)
    } catch {
      #expect(error as? PDFEngineError == .unreadable, "\(item.name): \(error)")
      return
    }
    _ = controller.find("page")
    _ = controller.outline
    for index in 0..<min(controller.pageCount, 2) {
      do {
        let image = try PageRenderer.render(pageIndex: index, of: url, maximumPixelSize: 200)
        #expect(max(image.width, image.height) <= 200, "\(item.name), page \(index + 1)")
      } catch {
        #expect(error is PDFEngineError, "\(item.name), page \(index + 1): \(error)")
      }
    }
  }

  @Test("An outline of 10 000 entries opens whole and searches", .timeLimit(.minutes(2)))
  func longOutline() throws {
    let item = try #require(GoldenCorpus.malformed().first { $0.name == "outline with 10 000 entries" })
    let controller = try PDFDocumentController(data: item.data)
    #expect(controller.pageCount == 1)
    #expect(controller.outline.count == GoldenCorpus.outlineEntryCount)
    #expect(!controller.find("outline").isEmpty)
  }

  @Test("A page tree 2 000 levels deep opens or is refused, and never overflows the stack", .timeLimit(.minutes(2)))
  func deepPageTree() throws {
    let item = try #require(GoldenCorpus.malformed().first { $0.name == "page tree 2 000 deep" })
    let url = try write(item.data)
    guard let controller = try? PDFDocumentController(url: url) else { return }
    #expect(controller.pageCount <= 1)
    if controller.pageCount == 1 {
      _ = controller.find("deepest")
      _ = try? PageRenderer.render(pageIndex: 0, of: url, maximumPixelSize: 200)
    }
  }
}
