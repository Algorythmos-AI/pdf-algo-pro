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
/// `BGTaskSchedulerPermittedIdentifiers`. Each piece of work gets its own identifier in that family,
/// and its launch handler is registered under that full identifier just before the request is
/// submitted: the family pattern itself is not an identifier, and submitting a request whose
/// identifier has no handler makes the system end the app.
@MainActor
public final class ContinuedProcessing: ContinuedWork {
  private let family: String
  private let scheduler: any ContinuedTaskScheduling

  /// Creates the system-backed continued work for a family of identifiers, such as
  /// `com.algorythmos.pdfalgopro.recognition`.
  public convenience init(family: String) {
    self.init(family: family, scheduler: SystemTaskScheduler())
  }

  init(family: String, scheduler: any ContinuedTaskScheduling) {
    self.family = family
    self.scheduler = scheduler
  }

  /// Registers the work's handler and submits it; `nil` when the system can't run it now.
  public func begin(
    title: String, subtitle: String, onCancel: @escaping @MainActor () -> Void
  )
    -> (any ContinuedWorkHandle)?
  {
    let identifier = "\(family).\(UUID().uuidString)"
    let handle = Handle(onCancel: onCancel)
    // Never submit without a handler: without one the work simply runs as it always has.
    guard scheduler.register(identifier: identifier, handle: handle) else { return nil }
    return scheduler.submit(identifier: identifier, title: title, subtitle: subtitle) ? handle : nil
  }

  final class Handle: ContinuedWorkHandle {
    private let onCancel: @MainActor () -> Void
    private var task: BGContinuedProcessingTask?
    private var fraction = 0.0
    private var result: Bool?

    init(onCancel: @escaping @MainActor () -> Void) {
      self.onCancel = onCancel
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
    }
  }
}

/// The part of `BGTaskScheduler` continued work uses, so the order of its calls can be tested: the
/// simulator has no scheduler.
@MainActor
protocol ContinuedTaskScheduling {
  /// Registers the handler for one task identifier; `false` when the system refuses it.
  func register(identifier: String, handle: ContinuedProcessing.Handle) -> Bool
  /// Submits the request for a registered identifier; `false` when the system can't run it now.
  func submit(identifier: String, title: String, subtitle: String) -> Bool
}

@MainActor
struct SystemTaskScheduler: ContinuedTaskScheduling {
  func register(identifier: String, handle: ContinuedProcessing.Handle) -> Bool {
    // The handler keeps the handle until the system starts the task, however long that takes.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
      MainActor.assumeIsolated {
        guard let task = task as? BGContinuedProcessingTask else {
          task.setTaskCompleted(success: false)
          return
        }
        handle.attach(task)
      }
    }
  }

  func submit(identifier: String, title: String, subtitle: String) -> Bool {
    let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
    // Fail rather than queue: the work starts now either way, so a task that starts later is no use.
    request.strategy = .fail
    do {
      try BGTaskScheduler.shared.submit(request)
      return true
    } catch {
      return false
    }
  }
}
