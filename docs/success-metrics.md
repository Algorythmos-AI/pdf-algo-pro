# Success metrics

How PDF Algo Pro measures whether it is working: one north-star metric, the funnel metrics behind
it, and quality objectives. Definitions are public so everyone measures the same thing. Numeric
business targets (conversion, retention, revenue) are held in the confidential edition of the
business documents; quality targets are public because they are commitments to users.

Owner: Product · Reviewed: each milestone

## North-star metric

**Weekly users who complete a document task with an answer they keep.** A user counts in a week when
they complete at least one core task (read to a later page, edit and save, scan to a searchable PDF,
sign, organise) **and** at least one intelligence result they do not immediately discard (an answer
or summary they copy, share or leave open, or an extraction they export).

Why: it combines the everyday PDF job with the differentiator (document intelligence), and it rises
only when both are useful. It is measured with privacy-preserving, opt-in aggregated telemetry,
which ships in V2 with the relay (FR-SET-004 in the [PRD](prd.md), decision PAP-027 in the
[decision register](decision-register.md)). Until then it is not measured directly. App Store
Connect proxies stand in for it: sessions per active device, weekly active devices, and day-7 and
day-30 retention cohorts from App Analytics ([analytics strategy](analytics-strategy.md)).

## Funnel metrics

Definitions follow the acquisition, activation, retention, revenue and referral stages, plus
intelligence and feature adoption.

| Stage | Metric | Definition | Source |
|---|---|---|---|
| Acquisition | Product page conversion | App Store product page views that become first downloads | App Store Connect |
| Acquisition | Source mix | Downloads by source (search, browse, web referrer, app referrer) | App Store Connect |
| Activation | First value | New installs that complete a core task within the first session | Opt-in aggregated telemetry |
| Activation | Onboarding intent fulfilled | Users whose first task matches the intent they chose at onboarding | Opt-in aggregated telemetry |
| Engagement | Weekly active users | Users with at least one opened document in the week | App Store Connect, telemetry |
| Engagement | Tasks per active user | Core tasks completed per weekly active user | Opt-in aggregated telemetry |
| Retention | Day-7 and day-30 retention | Share of an install cohort active on days 7 and 30 | App Store Connect retention |
| Revenue | Trial start rate | Users who start a trial, per activated user | App Store Server Notifications |
| Revenue | Trial-to-paid conversion | Trials that convert to a paid period | App Store Server Notifications |
| Revenue | Renewal and refund rates | Subscription renewals; refunds per purchase | App Store Server Notifications |
| Intelligence | AI adoption | Weekly users who run at least one intelligence feature | Opt-in aggregated telemetry |
| Intelligence | Tier mix | Share of intelligence requests served on device, by Private Cloud Compute, by Claude | Opt-in aggregated telemetry |
| Intelligence | Answer kept rate | Answers and summaries kept (copied, shared, exported) per answer shown | Opt-in aggregated telemetry |
| Features | Feature adoption | Weekly users per feature area (scan, sign, edit, organise, convert) | Opt-in aggregated telemetry |
| Referral | Shares | Documents shared from the app per weekly active user | Opt-in aggregated telemetry |

No metric uses document content, personal data or a persistent user identifier.

## Quality objectives (public targets)

| Objective | Target | Measured by |
|---|---|---|
| Crash-free sessions | at least 99.8% (TestFlight gate and in production) | App Store Connect, MetricKit |
| Launch and document performance | the [performance budgets](performance-budgets.md) | XCTest metrics, MetricKit |
| AI answers with correct page citations | at least 95% on the evaluation set before release | [AI evaluation framework](ai-evaluation-framework.md) |
| OCR character error rate, printed English and French | at most 2% on the OCR corpus | OCR accuracy suite ([testing strategy](testing-strategy.md)) |
| Accessibility audit | no failures in automated audits; manual VoiceOver pass each release | UI tests, release checklist |
| App Store rating | target held privately | App Store Connect |
| Support first response | within two business days | Support mailbox |

`Assumption:` the crash-free, AI citation, OCR and support first-response targets are initial
values set by the product; they are reviewed against measured baselines at the end of the MVP.
Validation plan: crash-free sessions are checked against internal and external TestFlight crash
data in App Store Connect and the Xcode Organizer; first response is checked against the support
log from the external beta onwards. The App Store rating target is held privately.

## Business targets

Targets for conversion, retention, revenue and the north-star metric are set per milestone in the
confidential edition of the business documents (held privately) and summarised here only as
direction: from the V1 launch, grow the App Store Connect proxies (sessions per active device,
retention cohorts); from V2, when opt-in telemetry ships, grow the north-star metric month on month.
In both periods retention and conversion stay at or above the assumptions in the financial model.
