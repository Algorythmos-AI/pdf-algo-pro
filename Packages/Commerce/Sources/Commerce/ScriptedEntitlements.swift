import Synchronization

/// An entitlement that changes when it is told to: for tests, previews, and UI tests, where a
/// scripted purchase has to lead to Pro without an App Store.
public final class ScriptedEntitlements: EntitlementProviding {
  private struct State {
    var entitlement: Entitlement
    var continuations: [Int: AsyncStream<Entitlement>.Continuation] = [:]
    var nextID = 0
  }

  private let state: Mutex<State>

  /// Creates a provider that reports an entitlement.
  public init(_ entitlement: Entitlement = .none) {
    state = Mutex(State(entitlement: entitlement))
  }

  /// Changes the entitlement and sends it to every stream.
  public func set(_ entitlement: Entitlement) {
    let continuations = state.withLock { state in
      state.entitlement = entitlement
      return Array(state.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(entitlement)
    }
  }

  /// The entitlement last set.
  public func currentEntitlement() async -> Entitlement {
    state.withLock { $0.entitlement }
  }

  /// The entitlement last set, then each one set afterwards.
  public func entitlementUpdates() -> AsyncStream<Entitlement> {
    let (stream, continuation) = AsyncStream.makeStream(of: Entitlement.self)
    let id = state.withLock { state in
      state.nextID += 1
      state.continuations[state.nextID] = continuation
      continuation.yield(state.entitlement)
      return state.nextID
    }
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { $0.continuations[id] = nil }
    }
    return stream
  }
}
