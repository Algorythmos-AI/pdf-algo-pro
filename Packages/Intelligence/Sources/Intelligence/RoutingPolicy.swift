import Core

/// The routing policy: which tier answers a request, as a pure function of facts gathered by code
/// (ADR-0021; the eight steps of "How the router decides" in model selection).
///
/// The hard rules it keeps, each proven by a test:
/// - on device before Private Cloud Compute before Claude;
/// - Analyse Contract never uses Claude (PAP-020);
/// - no cloud tier without a current consent; "ask before sending" keeps the tier and asks for a
///   confirmation;
/// - the kill switch only removes tiers.
///
/// Cloud drivers are not built yet, so `IntelligenceRouter` does not call this policy today.
public enum RoutingPolicy {
  /// Decides the route for a request by running the eight steps in order.
  public static func decide(_ input: RoutingInput) -> RouteDecision {
    var remaining = IntelligenceTier.routingOrder
    var excluded: [IntelligenceTier: RouteRefusalReason] = [:]
    var lastReason = RouteRefusalReason.unavailable
    let facts = { (tier: IntelligenceTier) in input.tiers[tier] ?? TierFacts() }

    func remove(_ reason: RouteRefusalReason, where shouldRemove: (IntelligenceTier) -> Bool) {
      for tier in remaining where shouldRemove(tier) {
        excluded[tier] = reason
        lastReason = reason
      }
      remaining.removeAll { excluded[$0] != nil }
    }

    // 1. Switched off?
    remove(.switchedOff) { input.isFeatureSwitchedOff || facts($0).isSwitchedOff }
    // 2. Sensitivity.
    remove(.keepOnDevice) { input.keepOnDevice && $0.isCloud }
    remove(.taskNotAllowed) { input.task == .explainContract && $0 == .claude }
    // 3. Available?
    remove(.unavailable) { !facts($0).isAvailable }
    // 4. Consented?
    remove(.noConsent) {
      $0.isCloud && !facts($0).consent.permitsSending(currentTextVersion: facts($0).currentConsentTextVersion)
    }
    // 5. Capable?
    remove(.notCapable) { !input.requiredCapabilities.isSubset(of: facts($0).capabilities) }
    // 6. Within budget?
    remove(.overBudget) { !facts($0).isWithinBudget }
    // 7. Qualified?
    let qualified = remaining.filter { facts($0).isQualified }
    // 8. Choose the lowest qualified tier, or the lowest remaining one with a reduced-scope label.
    guard let tier = qualified.first ?? remaining.first else {
      return RouteDecision(outcome: .refuse(lastReason), excluded: excluded)
    }
    for other in remaining where other != tier && !facts(other).isQualified { excluded[other] = .notQualified }
    return RouteDecision(
      outcome: .use(
        tier: tier,
        needsConfirmation: tier.isCloud && facts(tier).consent.status == .askBeforeSending,
        isReducedScope: qualified.isEmpty),
      excluded: excluded)
  }
}
