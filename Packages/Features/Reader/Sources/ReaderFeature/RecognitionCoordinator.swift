import Core
import Foundation
import Observation
import PDFEngine

/// Recognises text in image-only documents for the whole app, so recognition goes on when the reader
/// closes, keeps going for a while in the background, and resumes after the app was stopped
/// (FR-SCAN-003, P8).
///
/// Each recognised page is kept as a checkpoint as soon as it is ready. When the app is stopped, the
/// next launch resumes from the pages already done, provided the file has not changed since. The file
/// is replaced only when recognition finished, nothing changed it meanwhile, and the reader showing it,
/// if any, has no unsaved changes.
@MainActor
@Observable
public final class RecognitionCoordinator {
  /// How recognition of a document ended.
  public enum Outcome: Equatable, Sendable {
    /// The file was replaced with its searchable version.
    case replaced
    /// The document changed while its text was being recognised, so the file was left alone.
    case fileChanged
    /// Recognition failed; the file was left alone.
    case failed
  }

  /// Progress from 0 to 1 for each document being recognised.
  public private(set) var progress: [DocumentID: Double] = [:]
  /// Documents whose recognition was stopped from the system's interface, with the pages done kept:
  /// they are not resumed at launch, and the reader offers to resume them (#253).
  public private(set) var stopped: Set<DocumentID> = []

  @ObservationIgnored private let library: any DocumentLibrary
  @ObservationIgnored private let intake: DocumentIntake
  @ObservationIgnored private let builder: SearchablePDFBuilder
  @ObservationIgnored private let telemetry: any TelemetryRecording
  @ObservationIgnored private let checkpoints: RecognitionCheckpoints
  @ObservationIgnored private let keepAlive: @MainActor (String) -> @MainActor () -> Void
  @ObservationIgnored private let continued: (any ContinuedWork)?
  /// Continued work for recognition a person started, while it runs.
  @ObservationIgnored private var handles: [DocumentID: any ContinuedWorkHandle] = [:]
  @ObservationIgnored private var jobs: [DocumentID: Task<Void, Never>] = [:]
  @ObservationIgnored private var watchers: [DocumentID: Watcher] = [:]
  /// Documents whose running recognition the system's interface is stopping, so their pages are kept.
  @ObservationIgnored private var stoppedBySystem: Set<DocumentID> = []
  /// Documents being recognised because a scan was just saved.
  @ObservationIgnored private var newScans: Set<DocumentID> = []

  private struct Watcher {
    let canReplace: @MainActor () -> Bool
    let willReplace: @MainActor () -> Void
    let onFinish: @MainActor (Outcome) async -> Void
  }

  /// Creates the coordinator.
  ///
  /// Checkpoints are kept in `folder`, which the app excludes from backup. `keepAlive` asks iOS for
  /// time to go on in the background and returns the call that ends it.
  public init(
    library: any DocumentLibrary, intake: DocumentIntake, builder: SearchablePDFBuilder,
    telemetry: any TelemetryRecording, folder: URL,
    keepAlive: @escaping @MainActor (String) -> @MainActor () -> Void = { BackgroundTime.begin($0) },
    continued: (any ContinuedWork)? = nil
  ) {
    self.library = library
    self.intake = intake
    self.builder = builder
    self.telemetry = telemetry
    checkpoints = RecognitionCheckpoints(folder: folder)
    self.keepAlive = keepAlive
    self.continued = continued
  }

  /// Whether a document's text is being recognised.
  public func isRecognizing(_ id: DocumentID) -> Bool {
    jobs[id] != nil
  }

  /// Whether a document's recognition was stopped from the system's interface and can be resumed
  /// from the pages already done.
  public func isStopped(_ id: DocumentID) -> Bool {
    stopped.contains(id)
  }

  /// Lets the reader showing a document hear how recognition ended.
  ///
  /// `canReplace` stops the file being replaced while the reader has unsaved changes. `willReplace`
  /// runs straight after the file is replaced, with no suspension in between, so the reader lets go of
  /// the document it shows before anything can save it over the searchable version. `onFinish` runs
  /// before the document's progress ends, so a reader that sees no progress has already heard the
  /// outcome. A later call for the same document replaces the earlier one.
  public func watch(
    _ id: DocumentID, canReplace: @escaping @MainActor () -> Bool,
    willReplace: @escaping @MainActor () -> Void = {},
    onFinish: @escaping @MainActor (Outcome) async -> Void
  ) {
    watchers[id] = Watcher(canReplace: canReplace, willReplace: willReplace, onFinish: onFinish)
  }

  /// Starts recognising a document, from its checkpoint if it has one; does nothing if it is running.
  ///
  /// When a person started it (`title` is the document's title), the system is asked to keep it going
  /// with its progress in a Live Activity if they leave the app (P8b). Recognition resumed at launch
  /// never asks, because the system allows that only after a person's action.
  public func start(_ id: DocumentID, startedFor title: String? = nil) {
    guard jobs[id] == nil else { return }
    stopped.remove(id)
    progress[id] = 0
    if let title, let continued {
      handles[id] = continued.begin(
        title: String(localized: "Recognising text", bundle: .module), subtitle: title,
        onCancel: { [weak self] in self?.stopForNow(id) })
    }
    jobs[id] = Task { await run(id) }
  }

  /// Starts recognising a scan that has just been saved, for the reader to open while it runs (#371).
  ///
  /// The checkpoint is written before this returns, so if the app is stopped from here on, the next
  /// launch resumes recognition by itself. `title` asks for a Live Activity, as in `start`.
  public func recognizeNewScan(_ id: DocumentID, title: String?) async {
    newScans.insert(id)
    if let url = try? await library.fileURL(for: id), let version = try? FileVersion(url) {
      try? await checkpoints.begin(id, version: version)
    }
    start(id, startedFor: title)
  }

  /// Whether the running recognition is the one a saved scan started, which nobody asked for: if the
  /// person's own changes get in its way, it is run again rather than reported.
  func isNewScan(_ id: DocumentID) -> Bool {
    newScans.contains(id)
  }

  /// Stops recognising a document and discards its checkpoint; the file is left as it was.
  ///
  /// Once the file has been replaced it is too late: the library is still brought up to date, and the
  /// reader still hears that the file was replaced.
  public func cancel(_ id: DocumentID) {
    stoppedBySystem.remove(id)
    jobs[id]?.cancel()
  }

  /// Stops recognising a document from the system's interface, keeping the pages recognised so far and
  /// the file as it was (P8b, #253).
  ///
  /// The system calls the same handler when a person taps Cancel in the Live Activity and when it ends
  /// the work itself, and says nothing of which it was. Both are taken as the person's Cancel: the file
  /// is never changed afterwards without them, so recognition is not resumed at launch, and the reader
  /// offers to resume it from the pages kept. Cancel in the reader discards them.
  func stopForNow(_ id: DocumentID) {
    guard let job = jobs[id] else { return }
    stoppedBySystem.insert(id)
    job.cancel()
  }

  /// Resumes every document whose recognition had not finished when the app last stopped.
  ///
  /// Recognition stopped from the system's interface is not resumed: it waits for the person (#253).
  /// A file that already has text was replaced just before the app stopped, before its checkpoint
  /// was discarded: it is not recognised again, which would give each page a second text layer, and
  /// the library is brought up to date with it instead (#256).
  public func resumePending() async {
    for id in await checkpoints.pending() {
      if await checkpoints.isStopped(id) {
        stopped.insert(id)
      } else if await hasText(id) {
        await checkpoints.remove(id)
        _ = try? await intake.refresh(id)
      } else {
        start(id)
      }
    }
  }

  /// Whether a document's file has text on any page; `false` when it can't be read.
  private func hasText(_ id: DocumentID) async -> Bool {
    guard let url = try? await library.fileURL(for: id) else { return false }
    return (try? await PDFKitInspector().inspect(url))?.hasTextLayer == true
  }

  /// Waits until recognition of a document has ended, if it is running.
  public func finished(_ id: DocumentID) async {
    await jobs[id]?.value
  }

  private func run(_ id: DocumentID) async {
    let endBackgroundTime = keepAlive("Recognise text")
    var succeeded = false
    defer {
      endBackgroundTime()
      handles[id]?.finish(success: succeeded)
      handles[id] = nil
      progress[id] = nil
      jobs[id] = nil
      stoppedBySystem.remove(id)
      newScans.remove(id)
    }
    let outcome: Outcome
    do {
      // Started again, it is no longer waiting for the person.
      await checkpoints.clearStopped(id)
      let url = try await library.fileURL(for: id)
      let previous = try await library.previousVersionURL(for: id)
      let version = try FileVersion(url)
      var done: [Int: [RecognizedLine]] = [:]
      // Pages kept by an earlier version of the app are recognised again, not mixed with new ones.
      if await checkpoints.version(of: id) == version, await checkpoints.isCurrentFormat(id) {
        done = await checkpoints.pages(of: id)
      } else {
        try await checkpoints.begin(id, version: version)
      }
      let checkpoints = checkpoints
      let result = try await builder.addTextLayer(
        toPDFAt: url, resuming: done,
        onPage: { index, lines in await checkpoints.add(lines, page: index, for: id) },
        progress: { value in
          Task { @MainActor [weak self] in
            // A late update must not bring back progress for a job that has ended.
            if self?.jobs[id] != nil {
              self?.progress[id] = value
              self?.handles[id]?.report(progress: value)
            }
          }
        })
      // Stopped during the last page: the builder has finished, but the file is left as it was.
      try Task.checkCancellation()
      // No suspension between these checks and the write, so no save can slip in between.
      var replaced = false
      if watchers[id]?.canReplace() ?? true, try FileVersion(url) == version {
        // Like a save, replacing the file keeps the version from before it (FR-EDIT-008, first step), and
        // is coordinated, so other apps and the library's restores never meet it half written (#270).
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(
          writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { target in
          // Another app may have written the file while this write waited its turn; theirs is kept.
          guard (try? FileVersion(target)) == version else { return }
          do {
            if let previous {
              let fileManager = FileManager.default
              if fileManager.fileExists(atPath: previous.path) { try fileManager.removeItem(at: previous) }
              try fileManager.copyItem(at: target, to: previous)
            }
            try result.data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            replaced = true
          } catch {
            writeError = error
          }
        }
        if let error = writeError ?? coordinationError { throw error }
      }
      if replaced {
        // The file is replaced, so the reader must not save the document it shows over it, and stopping
        // now is too late: the library is brought up to date even if recognition is cancelled meanwhile,
        // and the reader hears the outcome (#219).
        watchers[id]?.willReplace()
        let intake = intake
        _ = try? await Task { try await intake.refresh(id) }.value
        // The saved scan was the task, and has been counted.
        if !newScans.contains(id) { await telemetry.record("task.core.completed") }
        outcome = .replaced
        succeeded = true
      } else {
        outcome = .fileChanged
      }
    } catch is CancellationError {
      // Stopped from the system's interface, the pages done so far are kept until the person
      // resumes (#253).
      if stoppedBySystem.contains(id) {
        stopped.insert(id)
        await checkpoints.markStopped(id)
      } else {
        await checkpoints.remove(id)
      }
      return
    } catch {
      outcome = .failed
    }
    await checkpoints.remove(id)
    await watchers[id]?.onFinish(outcome)
  }
}

/// The pages recognised so far for documents whose recognition has not finished (P8).
///
/// One folder per document, named by its identifier: `version.json`, the file version recognition
/// started from, one `<page>.json` per recognised page, so each page is written once, and
/// `stopped.json` once it was stopped from the system's interface.
actor RecognitionCheckpoints {
  private let folder: URL

  init(folder: URL) {
    self.folder = folder
  }

  private func folder(of id: DocumentID) -> URL {
    folder.appendingPathComponent(id.description, isDirectory: true)
  }

  /// Starts a new checkpoint for a document, discarding any earlier one.
  func begin(_ id: DocumentID, version: FileVersion) throws {
    remove(id)
    try FileManager.default.createDirectory(at: folder(of: id), withIntermediateDirectories: true)
    try JSONEncoder().encode(version).write(to: folder(of: id).appendingPathComponent("version.json"))
    try JSONEncoder().encode(Self.format).write(to: folder(of: id).appendingPathComponent("format.json"))
  }

  /// The shape of what a checkpoint keeps: 2 since lines can carry their words.
  static let format = 2

  /// Whether a document's checkpoint was written in the shape this version writes.
  func isCurrentFormat(_ id: DocumentID) -> Bool {
    (try? Data(contentsOf: folder(of: id).appendingPathComponent("format.json")))
      .flatMap { try? JSONDecoder().decode(Int.self, from: $0) } == Self.format
  }

  /// The file version a document's checkpoint started from, if it has one.
  func version(of id: DocumentID) -> FileVersion? {
    (try? Data(contentsOf: folder(of: id).appendingPathComponent("version.json")))
      .flatMap { try? JSONDecoder().decode(FileVersion.self, from: $0) }
  }

  /// The pages recognised so far, by page index.
  func pages(of id: DocumentID) -> [Int: [RecognizedLine]] {
    let files =
      (try? FileManager.default.contentsOfDirectory(at: folder(of: id), includingPropertiesForKeys: nil)) ?? []
    var pages: [Int: [RecognizedLine]] = [:]
    for file in files {
      guard let index = Int(file.deletingPathExtension().lastPathComponent), let data = try? Data(contentsOf: file),
        let lines = try? JSONDecoder().decode([RecognizedLine].self, from: data)
      else { continue }
      pages[index] = lines
    }
    return pages
  }

  /// Keeps one recognised page.
  func add(_ lines: [RecognizedLine], page index: Int, for id: DocumentID) {
    try? JSONEncoder().encode(lines).write(
      to: folder(of: id).appendingPathComponent("\(index).json"), options: .atomic)
  }

  /// Notes that a document's recognition was stopped from the system's interface, so it is not
  /// resumed at launch.
  func markStopped(_ id: DocumentID) {
    try? JSONEncoder().encode(true).write(to: folder(of: id).appendingPathComponent("stopped.json"))
  }

  /// Whether a document's recognition was stopped from the system's interface.
  func isStopped(_ id: DocumentID) -> Bool {
    FileManager.default.fileExists(atPath: folder(of: id).appendingPathComponent("stopped.json").path)
  }

  /// Lets a document's recognition be resumed at launch again.
  func clearStopped(_ id: DocumentID) {
    try? FileManager.default.removeItem(at: folder(of: id).appendingPathComponent("stopped.json"))
  }

  /// Discards a document's checkpoint.
  func remove(_ id: DocumentID) {
    try? FileManager.default.removeItem(at: folder(of: id))
  }

  /// The documents with a checkpoint.
  func pending() -> [DocumentID] {
    let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return folders.compactMap { DocumentID(string: $0.lastPathComponent) }.filter { version(of: $0) != nil }
  }
}
