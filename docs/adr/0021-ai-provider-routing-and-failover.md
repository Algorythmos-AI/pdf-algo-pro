# ADR-0021: AI provider routing and failover

**Status:** accepted (2026-09-28)

**Context.** Cloud tiers can fail, hit limits or be withdrawn; users must never lose the core experience.

**Decision.** The router chooses a tier by task, document size, user consent, availability, cost budget and connectivity. Failover order: Claude, then Private Cloud Compute, then on-device, with a circuit breaker per provider and a remote kill switch (CloudKit public database). Offline, only on-device capabilities are offered, with clear messaging. Token budgets are checked before each request.

**Alternatives considered.** A single provider (single point of failure). Silent fallback without telling the user which tier answered (undermines consent and trust).

**Consequences.** More routing logic and tests; resilience and cost control in return. Runbook: AI provider failover.

**Pillars served.** PIL-4, PIL-6

**References.** [What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
