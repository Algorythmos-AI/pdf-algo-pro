import Foundation

/// Hears when another app changes the open document's file (plan item H5, one writer per document),
/// and follows the file when the Files app renames or moves it (#224).
///
/// The library folder is visible in the Files app, so another app can write a document while it is
/// open here. The watcher is registered only while the reader is in the foreground: a file presenter
/// in a suspended app can hold up other apps' file coordination.
///
/// It is nonisolated: file coordination reads `presentedItemURL` and `presentedItemOperationQueue`
/// from its own threads, and in this main-actor module they would otherwise be main-actor state that
/// the runtime refuses to read off the main thread.
nonisolated final class FileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
  let presentedItemOperationQueue = OperationQueue.main
  private let onChange: @MainActor () -> Void
  @MainActor private var isWatching = false
  private let lock = NSLock()
  private var url: URL?

  /// The file, where it is now.
  var presentedItemURL: URL? { lock.withLock { url } }

  init(url: URL, onChange: @escaping @MainActor () -> Void) {
    self.url = url
    self.onChange = onChange
  }

  /// Starts hearing changes; does nothing if already started.
  @MainActor func start() {
    guard !isWatching else { return }
    NSFileCoordinator.addFilePresenter(self)
    isWatching = true
  }

  /// Stops hearing changes; does nothing if already stopped.
  @MainActor func stop() {
    guard isWatching else { return }
    NSFileCoordinator.removeFilePresenter(self)
    isWatching = false
  }

  func presentedItemDidChange() {
    Task { @MainActor in self.onChange() }
  }

  /// Keeps watching the file at its new place, and says so, so the reader finds it there.
  func presentedItemDidMove(to newURL: URL) {
    lock.withLock { url = newURL }
    Task { @MainActor in self.onChange() }
  }
}
