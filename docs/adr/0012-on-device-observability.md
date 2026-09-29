# ADR-0012: On-device observability without third-party SDKs

**Status:** accepted (2026-09-28)

**Context.** Crash, hang and performance data are needed to run the product, but third-party crash and analytics SDKs collect data we do not want to hold.

**Decision.** MetricKit for crash, hang, launch and energy diagnostics; `Logger` with privacy redaction; `OSSignposter` intervals for budgets; App Store Connect and Xcode Organizer for aggregated crash data. Users can export a diagnostics summary with support requests. No third-party crash or analytics SDK.

**Alternatives considered.** Firebase Crashlytics or Sentry (third-party data processors, privacy-label impact).

**Consequences.** Less real-time alerting than a hosted service; accepted for the privacy posture. Revisited if the operations SLOs cannot be met.

**Pillars served.** PIL-5, PIL-7

**References.** [MetricKit](https://developer.apple.com/documentation/metrickit) · [Logging](https://developer.apple.com/documentation/os/logging)
