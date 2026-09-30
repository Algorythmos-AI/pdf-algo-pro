# ADR-0024: Remote configuration in its own package, read from the CloudKit public database

**Status:** accepted (2026-10-01)

**Context.** The [kill-switch runbook](../process/runbooks/kill-switch.md) owns the record schema and the procedure for switching a shipped feature, an AI provider or a prompt off without a new build (ADR-0021, PAP-024). It left three questions to the ADR that implements it:
- which package owns remote configuration, given that networking is allowed only in `Intelligence`, `Commerce` and `Telemetry`;
- whether Staging reads separate records;
- whether a CloudKit subscription should push changes instead of the app polling.

**Decision.**
- **Package.** A `RemoteConfig` package owns remote configuration, and it is added to the network allow-list in `scripts/ci/invariants.py`. The allow-list now also treats `import CloudKit` as networking. The package holds three parts:
  - `RemoteConfiguration`: the pure, one-way rules. A record disables a target, puts a prompt on its fallback, or lowers a limit. Nothing can be turned on or raised, and malformed, unknown, other-version and other-channel records are ignored.
  - `RemoteConfigStore`: the fetch policy and the on-device cache of the last known records. It fetches at launch, and when the app returns to the foreground if the last fetch is more than 15 minutes old (`Assumption:`, as in the runbook). A failed fetch keeps the last known records; with none, the compiled behaviour applies.
  - `CloudKitRecordSource`: reads the `RemoteSwitch` record type from the container's public database.
- **Staging.** The records gain an optional `channel` field (`staging` or `production`; absent means both). TestFlight and App Store builds both read CloudKit's production environment, so the channel is what keeps a change meant for testers away from customers. The container stays single, and Debug builds read the development environment, as the runbook's steps assume.
- **Push or poll.** The app polls, as the runbook describes. A CloudKit subscription would need push notifications and an entitlement for a benefit measured in minutes; revisit if the time-to-effect drill shows polling is too slow.
- **Wiring.** The app links the package now. It reads records only once the iCloud container and the record type's security roles exist (owner action O4, plan §7); until then the compiled behaviour applies.

**Alternatives considered.**
- Putting the code in `Telemetry`, which may already use the network. That mixes two concerns with different privacy rules.
- A separate Staging container. That doubles the console work in an incident, and the channel field does the same job.
- A server of our own. It would change the privacy label and adds an operations burden the CloudKit public database avoids.

**Consequences.**
- One more package that may use the network. `invariants.py` enforces the boundary and now covers CloudKit.
- The runbook's schema gains `channel`.
- Every record the app ignores is simply ignored: a typo in the console can't turn anything on.
- The privacy label is unchanged: the fetch sends no user data, and the public database is readable without an account (`privacy-architecture.md`, remote configuration).

**Pillars served.** PIL-5, PIL-6

**References.** [Kill-switch runbook](../process/runbooks/kill-switch.md) · [ADR-0021](0021-ai-provider-routing-and-failover.md) · [publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase) · [Environments](../process/environments.md#open-questions)
