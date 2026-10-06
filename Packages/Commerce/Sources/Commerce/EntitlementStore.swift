import Foundation
import Observation

/// The one place the app reads the person's entitlement from (ADR-0026).
///
/// It follows the provider from launch, so a purchase approved later, a renewal or a refund is seen
/// without a restart. `entitlement` is `nil` until the first answer: a gate asks `resolved()` and
/// waits for it, and never takes "not known yet" for "not entitled".
@MainActor
@Observable
public final class EntitlementStore {
  /// The entitlement, once known.
  public private(set) var entitlement: Entitlement?

  @ObservationIgnored private let provider: any EntitlementProviding
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
  @ObservationIgnored private var following: Task<Void, Never>?
  @ObservationIgnored private var trialEnd: Task<Void, Never>?

  /// Creates a store over a provider; `sleep` waits for a number of seconds, and tests pass their own.
  public init(
    provider: any EntitlementProviding, now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
  ) {
    self.provider = provider
    self.now = now
    self.sleep = sleep
  }

  /// Starts following the provider; calling it again does nothing.
  public func start() {
    guard following == nil else { return }
    following = Task { [weak self, provider] in
      for await entitlement in provider.entitlementUpdates() {
        guard let self else { return }
        self.apply(entitlement)
      }
    }
  }

  /// Asks the provider again: when the app becomes active, and when a trial's end has passed.
  public func refresh() async {
    apply(await provider.currentEntitlement())
  }

  /// The entitlement, asking the provider first when it is not known yet.
  public func resolved() async -> Entitlement {
    if let entitlement { return entitlement }
    let answer = await provider.currentEntitlement()
    if let entitlement { return entitlement }
    apply(answer)
    return answer
  }

  /// Whether Pro is available now; `false` until the entitlement is known.
  public var grantsPro: Bool { entitlement?.grantsPro(at: now()) ?? false }

  private func apply(_ entitlement: Entitlement) {
    self.entitlement = entitlement
    trialEnd?.cancel()
    trialEnd = nil
    // A trial stops granting Pro at its end, and the App Store's word on what follows (a paid
    // period, a retry, an expiry) can arrive a moment later: ask again once the end has passed.
    guard case .trial(let endsAt) = entitlement else { return }
    let wait = endsAt.timeIntervalSince(now())
    guard wait > 0 else { return }
    trialEnd = Task { [weak self, sleep] in
      await sleep(wait)
      guard !Task.isCancelled else { return }
      await self?.refresh()
    }
  }
}
