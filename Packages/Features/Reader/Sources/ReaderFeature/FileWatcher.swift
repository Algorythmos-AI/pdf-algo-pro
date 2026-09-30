import Foundation

/// Hears when another app changes the open document's file (plan item H5, one writer per document).
///
/// The library folder is visible in the Files app, so another app can write a document while it is
/// open here. The watcher is registered only while the reader is in the foreground: a file presenter
/// in a suspended app can hold up other apps' file coordination.
final class FileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
  let presentedItemURL: URL?
  let presentedItemOperationQueue = OperationQueue.main
  private let onChange: @MainActor () -> Void
  @MainActor private var isWatching = false

  init(url: URL, onChange: @escaping @MainActor () -> Void) {
    presentedItemURL = url
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
}
