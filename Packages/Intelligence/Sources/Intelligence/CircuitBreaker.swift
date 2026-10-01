import Foundation

/// The state of a provider's circuit breaker.
public enum CircuitState: String, Sendable, CaseIterable {
  /// Requests go through.
  case closed
  /// The provider is skipped until the cool-down ends.
  case open
  /// The cool-down ended; the next request is the probe.
  case halfOpen
}

/// A circuit breaker for one cloud provider on this device (ADR-0021; AI governance, circuit breaker).
///
/// Closed until `failureThreshold` counted failures in a row, then open for a cool-down. After the
/// cool-down the next request is the probe: success closes the breaker, failure reopens it with the
/// cool-down doubled, up to `maximumCoolDown`. The caller decides which errors count (transport
/// failures, timeouts and rate limits do; refusals and quota states do not).
///
/// `Assumption:` the defaults, 5 consecutive failures and a 60-second cool-down doubling to at most 30
/// minutes, are the values in AI governance; validated by fault-injection tests and by the fallback
/// counters in opt-in telemetry after release. The table's second trip rule (at least 50% failures
/// over the last 20 requests or 5 minutes) is not implemented yet.
public actor CircuitBreaker {
  private let failureThreshold: Int
  private let coolDown: TimeInterval
  private let maximumCoolDown: TimeInterval
  private let now: @Sendable () -> Date

  private var failures = 0
  private var openedAt: Date?
  private var currentCoolDown: TimeInterval
  private var isProbing = false

  /// Creates a closed breaker.
  ///
  /// - Parameters:
  ///   - failureThreshold: Consecutive counted failures that open the breaker; at least 1.
  ///   - coolDown: Seconds the breaker stays open after it first trips.
  ///   - maximumCoolDown: The longest cool-down after repeated failed probes.
  ///   - now: The clock.
  public init(
    failureThreshold: Int = 5, coolDown: TimeInterval = 60, maximumCoolDown: TimeInterval = 1800,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.failureThreshold = max(1, failureThreshold)
    self.coolDown = coolDown
    self.maximumCoolDown = max(coolDown, maximumCoolDown)
    self.now = now
    currentCoolDown = coolDown
  }

  /// The breaker's state now.
  public func state() -> CircuitState {
    guard let openedAt else { return .closed }
    return now().timeIntervalSince(openedAt) >= currentCoolDown ? .halfOpen : .open
  }

  /// Whether a request could be sent now, without claiming the probe; for availability checks.
  public func isAvailable() -> Bool {
    switch state() {
    case .closed: true
    case .open: false
    case .halfOpen: !isProbing
    }
  }

  /// Asks to send a request.
  ///
  /// When half-open, the first caller gets the probe and later callers are refused until its result
  /// is recorded.
  public func allowRequest() -> Bool {
    switch state() {
    case .closed:
      return true
    case .open:
      return false
    case .halfOpen:
      if isProbing { return false }
      isProbing = true
      return true
    }
  }

  /// Records a request that succeeded: the breaker closes and the cool-down resets.
  public func recordSuccess() {
    failures = 0
    openedAt = nil
    currentCoolDown = coolDown
    isProbing = false
  }

  /// Records a counted failure: the breaker opens at the threshold, and a failed probe reopens it
  /// with the cool-down doubled.
  public func recordFailure() {
    switch state() {
    case .closed:
      failures += 1
      if failures >= failureThreshold { openedAt = now() }
    case .halfOpen:
      currentCoolDown = min(currentCoolDown * 2, maximumCoolDown)
      openedAt = now()
      isProbing = false
    case .open:
      break
    }
  }
}
