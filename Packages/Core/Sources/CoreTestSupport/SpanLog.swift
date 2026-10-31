import Core
import Foundation

/// Keeps the names of the intervals a piece of work marks (`Signposts`), in the order they start.
public final class SpanLog: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []

  /// Creates an empty log.
  public init() {}

  /// The names, in the order they started.
  public var names: [String] {
    lock.withLock { recorded }
  }

  /// Runs work, keeping the name of each interval it marks.
  public func watching(_ work: () async throws -> Void) async rethrows {
    try await Signposts.$onBegin.withValue({ [self] name in lock.withLock { recorded.append(name) } }, operation: work)
  }
}
