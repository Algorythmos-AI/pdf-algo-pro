import BackgroundTasks
import Foundation

/// Work a person started that the system keeps running, with its progress in a Live Activity, if they
/// leave the app (P8b, `BGContinuedProcessingTask`).
@MainActor
public protocol ContinuedWork: AnyObject {
  /// Asks the system to keep the work going; `nil` when it can't now, in which case the work runs as it
  /// always has, with a little background time.
  ///
  /// Call it only in response to a person's action, while the app is in the foreground.
  /// `onCancel` runs if the person cancels the work from the system's interface, or the system stops it.
  func begin(title: String, subtitle: String, onCancel: @escaping @MainActor () -> Void) -> (any ContinuedWorkHandle)?
}

/// One piece of continued work.
@MainActor
public protocol ContinuedWorkHandle: AnyObject {
  /// Reports progress from 0 to 1; the system cancels work that looks stuck.
  func report(progress: Double)
  /// Ends the work.
  func finish(success: Bool)
}

/// Continued work through `BGContinuedProcessingTask`.
///
/// The identifier family `<bundle identifier>.recognition.*` is declared in
/// `BGTaskSchedulerPermittedIdentifiers`. `register()` must run once before the app finishes
/// launching; each piece of work then gets its own identifier in that family.
@MainActor
public final class ContinuedProcessing: ContinuedWork {
  private let family: String
  private var pending: [String: Handle] = [:]

  /// Creates the system-backed continued work for a family of identifiers, such as
  /// `com.algorythmos.pdfalgopro.recognition`.
  public init(family: String) {
    self.family = family
  }

  /// Families already registered in this process: registering one twice raises an exception, and
  /// app-hosted tests create the app's services more than once.
  private static var registered: Set<String> = []

  /// Registers the launch handler for the family; call early in launch.
  ///
  /// Later calls do nothing.
  public func register() {
    guard !Self.registered.contains(family) else { return }
    Self.registered.insert(family)
    BGTaskScheduler.shared.register(forTaskWithIdentifier: "\(family).*", using: .main) { [weak self] task in
      MainActor.assumeIsolated {
        guard let task = task as? BGContinuedProcessingTask, let handle = self?.pending[task.identifier] else {
          task.setTaskCompleted(success: false)
          return
        }
        handle.attach(task)
      }
    }
  }

  /// Submits the work; `nil` when the system can't run it now.
  public func begin(
    title: String, subtitle: String, onCancel: @escaping @MainActor () -> Void
  )
    -> (any ContinuedWorkHandle)?
  {
    let identifier = "\(family).\(UUID().uuidString)"
    let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
    // Fail rather than queue: the work starts now either way, so a task that starts later is no use.
    request.strategy = .fail
    let handle = Handle(onCancel: onCancel) { [weak self] in self?.pending[identifier] = nil }
    pending[identifier] = handle
    do {
      try BGTaskScheduler.shared.submit(request)
      return handle
    } catch {
      pending[identifier] = nil
      return nil
    }
  }

  final class Handle: ContinuedWorkHandle {
    private let onCancel: @MainActor () -> Void
    private let onEnd: @MainActor () -> Void
    private var task: BGContinuedProcessingTask?
    private var fraction = 0.0
    private var result: Bool?

    init(onCancel: @escaping @MainActor () -> Void, onEnd: @escaping @MainActor () -> Void) {
      self.onCancel = onCancel
      self.onEnd = onEnd
    }

    func attach(_ task: BGContinuedProcessingTask) {
      self.task = task
      task.progress.totalUnitCount = 100
      task.progress.completedUnitCount = Int64(fraction * 100)
      task.expirationHandler = { [weak self] in
        Task { @MainActor in self?.onCancel() }
      }
      if let result { complete(result) }
    }

    func report(progress: Double) {
      fraction = min(max(progress, 0), 1)
      task?.progress.completedUnitCount = Int64(fraction * 100)
    }

    func finish(success: Bool) {
      result = success
      if task != nil { complete(success) }
    }

    private func complete(_ success: Bool) {
      task?.setTaskCompleted(success: success)
      task = nil
      onEnd()
    }
  }
}
