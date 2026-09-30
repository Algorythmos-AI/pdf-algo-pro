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

  private struct Watcher {
    let canReplace: @MainActor () -> Bool
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

  /// Lets the reader showing a document hear how recognition ended.
  ///
  /// `canReplace` stops the file being replaced while the reader has unsaved changes. `onFinish` runs
  /// before the document's progress ends, so a reader that sees no progress has already heard the
  /// outcome. A later call for the same document replaces the earlier one.
  public func watch(
    _ id: DocumentID, canReplace: @escaping @MainActor () -> Bool,
    onFinish: @escaping @MainActor (Outcome) async -> Void
  ) {
    watchers[id] = Watcher(canReplace: canReplace, onFinish: onFinish)
  }

  /// Starts recognising a document, from its checkpoint if it has one; does nothing if it is running.
  ///
  /// When a person started it (`title` is the document's title), the system is asked to keep it going
  /// with its progress in a Live Activity if they leave the app (P8b). Recognition resumed at launch
  /// never asks, because the system allows that only after a person's action.
  public func start(_ id: DocumentID, startedFor title: String? = nil) {
    guard jobs[id] == nil else { return }
    progress[id] = 0
    if let title, let continued {
      handles[id] = continued.begin(
        title: String(localized: "Recognising text", bundle: .module), subtitle: title,
        onCancel: { [weak self] in self?.cancel(id) })
    }
    jobs[id] = Task { await run(id) }
  }

  /// Stops recognising a document and discards its checkpoint; the file is left as it was.
  public func cancel(_ id: DocumentID) {
    jobs[id]?.cancel()
  }

  /// Resumes every document whose recognition had not finished when the app last stopped.
  public func resumePending() async {
    for id in await checkpoints.pending() { start(id) }
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
    }
    let outcome: Outcome
    do {
      let url = try await library.fileURL(for: id)
      let previous = try await library.previousVersionURL(for: id)
      let version = try FileVersion(url)
      var done: [Int: [RecognizedLine]] = [:]
      if await checkpoints.version(of: id) == version {
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
      if watchers[id]?.canReplace() ?? true, try FileVersion(url) == version {
        // Like a save, replacing the file keeps the version from before it (FR-EDIT-008, first step).
        if let previous {
          let fileManager = FileManager.default
          if fileManager.fileExists(atPath: previous.path) { try fileManager.removeItem(at: previous) }
          try fileManager.copyItem(at: url, to: previous)
        }
        try result.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        _ = try await intake.refresh(id)
        await telemetry.record("task.core.completed")
        outcome = .replaced
        succeeded = true
      } else {
        outcome = .fileChanged
      }
    } catch is CancellationError {
      await checkpoints.remove(id)
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
/// started from, and one `<page>.json` per recognised page, so each page is written once.
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
