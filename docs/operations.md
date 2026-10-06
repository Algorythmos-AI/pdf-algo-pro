# Operations

How PDF Algo Pro is run once it is in people's hands: what is monitored and where, how crashes and
logs are handled without third-party SDKs, how incidents are classified and handled, the kill
switches, backups and disaster recovery, the support workflow, the service targets, and what on-call
means while one maintainer runs the product. Step-by-step procedures live in the runbooks linked
below; this document explains the operating model around them.

Owner: Operations · Reviewed: each milestone, after every SEV1 or SEV2, and before each App Store release

## Summary

| Area | Decision |
|---|---|
| Monitoring | Apple-native sources: MetricKit, Xcode Organizer, App Store Connect, TestFlight feedback, ratings and reviews; relay health once `pdf-algo-pro-backend` exists |
| Crash reporting | No third-party SDK; symbols uploaded with every build; dSYMs kept per release |
| Logging | `Logger` with fixed categories and privacy redaction; a user-exportable diagnostics summary with no document content |
| Incidents | Four severities; SEV1 mitigated within 24 hours (target) |
| Kill switches | Read-only remote configuration in the CloudKit public database; switches can only turn features off |
| Backup | User documents stay in the user's own iCloud Drive; we hold no server copies |
| Support | Email and in-app report with opt-in diagnostics; first response within two business days (target) |

## Monitoring

| Source | What it shows | Cadence | Notes |
|---|---|---|---|
| **MetricKit** (on device) | Daily metric reports (launch, hangs, hitches, memory, energy, disk writes) and immediate diagnostic reports (crashes, hangs, CPU and disk exceptions); iOS 27 delivers them through `MetricManager` as asynchronous sequences ([MetricKit](https://developer.apple.com/documentation/metrickit)) | Continuous on device | Kept on the device in V1; summarised into the diagnostics export; not uploaded ([analytics strategy](analytics-strategy.md)) |
| **Xcode Organizer** | Crashes, hangs, launch time, memory, energy, disk writes, by app version, from users who share analytics and from all TestFlight users ([Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)) | Daily on business days; twice daily during a phased release | Compared with [performance budgets](performance-budgets.md) |
| **App Store Connect** | Crash counts, sessions and retention in App Analytics; subscription reports; review status ([App Analytics](https://developer.apple.com/app-store-connect/analytics/)) | Daily on business days | Crash-free sessions measured here and in Organizer |
| **TestFlight feedback** | Screenshot feedback and crash feedback from testers ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)) | Daily during betas | Triaged like support requests |
| **Ratings and reviews** | Ratings and written reviews per storefront | Daily on business days | Bug reports become issues without personal details ([App Store strategy](app-store-strategy.md)) |
| **Relay health** (later) | Availability, error rate, latency, provider errors, spend against caps for `pdf-algo-pro-backend` | Automated alerts once it exists | Added before the Claude tier reaches general availability ([ADR-0009](adr/0009-tiered-ai-and-consent.md)) |

A field regression against a performance budget opens a `performance` issue at `priority:p1` or
higher ([performance budgets](performance-budgets.md)).

**Decision: Apple-native monitoring only.** **Rationale.** It keeps the "Data Not Collected" privacy
label and matches the organisation's shipping iOS app ([ADR-0012](adr/0012-on-device-observability.md)).
**Trade-offs.** No real-time alerting for the app itself; Apple's data covers only users who share
analytics, and daily metric reports lag by a day. **Alternatives considered.** Firebase Crashlytics or
Sentry (third-party processors, identifiers, label impact); uploading MetricKit payloads to our own
server (label impact before the backend exists). **Risks.** A crash spike noticed hours late;
mitigated by daily checks and a phased release that exposes 1% of automatic updates on day one.
**Future scalability impact.** Opt-in aggregated performance buckets can be added through the
telemetry pipeline once the backend exists; a team can add alerting on the relay without changing the
app.

## Crash reporting

- **No third-party crash SDK.** Crash reports come from TestFlight and the App Store through Xcode
  Organizer and App Store Connect; TestFlight users share crash reports automatically
  ([Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)).
- **Symbolication.** Release builds produce dSYMs, and symbols are included when Xcode Cloud uploads
  the build, so reports arrive symbolicated
  ([Building your app to include debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)).
  The archive and dSYMs for every build submitted to the App Store are copied from the Xcode Cloud
  artefacts to private release storage and kept while that version is supported, plus
  `Assumption:` one year.
- **Triage.** Each new crash signature becomes a `bug` issue with the app version, OS version, the
  symbolicated frames and the count; never a user's document or personal data. Severity follows the
  incident table below.
- **Reports from users.** When a user reports a crash that is not in Organizer, support asks them to
  share the crash log from Settings › Privacy & Security › Analytics & Improvements › Analytics Data,
  as Apple describes (same source).

## Logging

- **`Logger` only**, subsystem `com.algorythmos.pdfalgopro`, with fixed categories: `app`, `library`,
  `document`, `reader`, `editor`, `scan`, `ocr`, `intelligence`, `search`, `commerce`, `telemetry`,
  `sync`, `background` ([Logger](https://developer.apple.com/documentation/os/logger)).
- **Privacy redaction.** Dynamic values are private by default; public values are limited to
  enumerations, counts, durations and error codes. Values needed for correlation use a hashed private
  mask ([OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy)).
- **Never logged, at any level:** document text, file names or paths, page contents, OCR output, AI
  prompts or answers, signatures, form values, purchase receipts, or anything that identifies a person
  ([data classification](data-classification.md)).
- **Levels.** `debug` for development detail (not persisted); `info` for state changes; `notice` for
  user-visible outcomes; `error` for recoverable failures; `fault` for broken invariants.
- **Signposts.** `OSSignposter` intervals measure the performance budgets (for example
  `Document.FirstPage`), with no content in their metadata.
- **Enforcement.** The `invariants` gate rejects `print`, `NSLog`, and interpolation of document or
  file values into public log arguments ([quality gates](process/quality-gates.md)).

### Diagnostics summary

Settings › Help › "Create diagnostics summary" builds a plain-text summary the user can read in full
before sharing:

| Included | Never included |
|---|---|
| App version and build; OS version; device model class; interface language | Document names, paths, contents or counts by name |
| Free-storage band; iCloud Drive on or off; Low Power Mode and thermal state | AI prompts, answers or extracted data |
| Feature flag and kill-switch states; which cloud AI tiers have consent (yes or no) | Email addresses, Apple Account details, purchase receipts |
| The last 50 error codes (domain, code, time to the hour) | Log messages with dynamic text |
| MetricKit summary for the last seven days (launch bands, hang and crash counts) | Call stacks from other apps |
| Text editing, for the last page looked at: kind of page, counts of regions by what can be done with them, milliseconds taken, taps and picks, how the last edit ended, which check of the proof failed and its numbers, how the rehearsal went, and edits made, covered and refused since the document was opened ([architecture](pdf-text-editing-architecture.md#diagnostics)) | The page's words, font names, page numbers, positions, the text typed |

The user shares it through the share sheet or attaches it to a support email; nothing is sent
automatically.

## Incident response

Severity is set by user harm, not by effort to fix. The procedure (declare, mitigate, communicate,
fix, review) is in [process/runbooks/incident-response.md](process/runbooks/incident-response.md).

| Severity | Examples | Mitigation target | Communication |
|---|---|---|---|
| **SEV1** | Loss or corruption of user documents; document content leaving the device without consent; a crash on launch for many users; purchases or restores failing for everyone; an actively exploited vulnerability | Within 24 hours | Status note on the support page; release note; direct replies to affected reports |
| **SEV2** | A core task broken for many users with no data loss (scan, sign, save, open); a cloud AI tier down with fallback working; crash-free sessions below target on a release | Within `Assumption:` 3 business days | Support page note if user-visible |
| **SEV3** | A feature degraded with a workaround; a performance budget missed in the field; a localisation error | Next planned release | Release note |
| **SEV4** | Cosmetic issues; documentation errors | Backlog | None |

Mitigation tools, in order of speed: pause the phased release (up to 30 days in total;
[Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases));
flip a kill switch; switch AI routing to another tier; ship a hotfix
([process/runbooks/ios-hotfix.md](process/runbooks/ios-hotfix.md)). iOS has no binary rollback, so
switches and phased release are the first line ([release management](release-management.md)).

Security reports go through GitHub private vulnerability reporting or info@algorythmos.com.au with
the subject `SECURITY: pdf-algo-pro`, and are acknowledged within five business days (organisation
default). Every SEV1 and SEV2 gets a blameless review within five business days, recorded in the
[decision register](decision-register.md) when it changes a decision, and in
[working memory](working-memory.md) while open.

## Kill switches

- **Mechanism.** A small set of records in the CloudKit public database holds remote configuration;
  the app has read-only access
  ([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase);
  [iOS architecture review](ios-architecture-review.md)). The record schema, target names, fetch
  policy, fallback to cached and compiled values, and the two-step change (development environment
  first, then production) are owned by the
  [kill-switch runbook](process/runbooks/kill-switch.md); this section does not restate them.
- **Switches only turn things off.** Remote configuration can disable a feature, a cloud AI tier or a
  prompt version; it can never enable functionality that App Review has not seen (Guideline 2.3.1,
  [App Store strategy](app-store-strategy.md)). Releases roll out through phased release, not remote
  flags.
- **On-device features never depend on the configuration.**
- **Initial switches.** `ai.provider.claude`, `ai.provider.pcc`, `ai.provider.ondevice`,
  `ai.prompt.<id>` for each shipped prompt, `feature.<name>` for each new V1 feature, and
  `feature.telemetry-upload` once telemetry exists.
- **Procedure and audit.** Changes are made by a person, recorded with the reason in the incident
  record, and reverted deliberately, as the runbook describes.

## Backup strategy

| What | Where it lives | Backup |
|---|---|---|
| **User documents** | The user's own iCloud Drive container, or on the device if iCloud is off ([ADR-0005](adr/0005-document-storage-and-identity.md)) | The user's iCloud and device backups. **We hold no server copies of documents.** Deleted documents stay in Recently Deleted for 30 days |
| Library metadata (tags, favourites, reading positions) | The user's CloudKit private database, which we cannot read | Rebuildable from the files; the index is never the record ([ADR-0006](adr/0006-swiftdata-persistence.md)) |
| Saved signatures | On the device with complete data protection | Not synced unless the user turns it on; re-creatable |
| Source code and public documents | `Algorythmos-AI/pdf-algo-pro` on GitHub | A scheduled mirror clone to storage the maintainer controls, `Assumption:` weekly, with a restore test each milestone |
| Confidential business documents | The private companion repository | The same mirror routine, encrypted at rest |
| Release artefacts (archives, dSYMs) | Private release storage | Kept per the crash-reporting section above |
| App Store metadata (text, screenshots) | Kept as files in the repository before upload | Covered by the repository backup |
| Remote configuration | CloudKit public database | Exported to the repository as JSON after every change |

**Export guidance for users.** The help pages explain that documents are ordinary PDF files: they are
visible in the Files app under "PDF Algo Pro", can be dragged or shared anywhere, and are included in
iCloud and device backups. Uninstalling the app does not delete files in iCloud Drive. Users who turn
iCloud off are told their documents are only on that device.

## Disaster recovery

| Scenario | Effect | Response |
|---|---|---|
| **AI provider outage** (Claude or Private Cloud Compute) | Cloud answers fail or slow down | The router fails over to the next tier with a circuit breaker and tells the user which tier answered; offline, only on-device features are offered ([ADR-0021](adr/0021-ai-provider-routing-and-failover.md), [process/runbooks/ai-provider-failover.md](process/runbooks/ai-provider-failover.md)). Private Cloud Compute also has per-user daily quotas that Apple does not publish; a quota error is handled like an outage for that user |
| **AI cost or quota conditions change** | A tier becomes too costly or restricted | Disable the tier with its kill switch; route to the others; revisit [model selection](model-selection.md) |
| **Signing certificate or profile expiry** | Builds cannot be signed or uploaded | Xcode Cloud manages signing; expiry dates and the yearly programme renewal are on a calendar with reminders 30 days ahead; checked each milestone |
| **Hotfix rejected in review** | A fix cannot reach users | Keep the phased release paused and the feature switched off; address the rejection; request expedited review, which Apple grants on a limited basis for critical bug fixes with reproduction steps; appeal to the App Review Board if the rejection seems mistaken ([App Review](https://developer.apple.com/distribute/app-review/), [process/runbooks/ios-hotfix.md](process/runbooks/ios-hotfix.md)) |
| **Loss of access to the developer account** | No new builds, releases or App Store Connect changes; the shipped app keeps working | Follow Apple's documented account-recovery process; two-factor devices and recovery details are kept current and reviewed each milestone; a continuity arrangement is documented privately |
| **GitHub outage** | Pull requests, Actions gates and Xcode Cloud builds (which fetch from GitHub) stop | Work continues locally; urgent fixes wait, or, for a SEV1, a locally built and archived release is uploaded from Xcode, with the gates run locally and recorded |
| **CloudKit outage** | Metadata sync and remote configuration unavailable | The app works offline by design; metadata syncs when service returns; kill switches fall back to cached values, then compiled defaults |
| **Backend outage** (once it exists) | Claude tier, telemetry upload and server-side entitlements unavailable | Claude tier fails over; telemetry keeps counters on the device; StoreKit on the device keeps entitlements working |
| **Maintainer unavailable** | Slower response | See on-call below; no release is in progress during planned absence |

## Support workflow

- **Channels.** Email to info@algorythmos.com.au with the subject "PDF Algo Pro support" (a dedicated
  support address is an open question), the support page linked from the product page, and an in-app
  "Report a problem" that opens a pre-filled email with the app version and, only if the user ticks
  the box, the diagnostics summary.
- **No documents by email.** Support never asks for a user's document; if a sample is essential, the
  user is asked to create a synthetic copy.
- **Triage.** Requests are reproduced, then filed as GitHub issues using the repository labels: `bug`
  or `enhancement`; `priority:p0` to `priority:p3`; `status:triage`; area labels such as `pdf`, `ocr`,
  `ai`, `accessibility`, `performance`, `ios`, `ipad`. Issues never contain names, email addresses or
  document content, only a reference to the support thread. Security issues never go into public
  issues ([GitHub governance](github-governance.md)).
- **Priority mapping.** SEV1 → `priority:p0`; SEV2 → `priority:p1`; SEV3 → `priority:p2`; SEV4 →
  `priority:p3`.
- **Closing the loop.** When a fix ships, the reporter is told which version contains it; the
  release notes credit the fix without naming the person ([changelog strategy](changelog-strategy.md)).
- **Refunds.** Refunds are handled by Apple; support explains how to request one and never promises
  an outcome.

## Service objectives

All figures are **targets**, not measured results. Quality targets are public commitments from
[success metrics](success-metrics.md) and [performance budgets](performance-budgets.md).

| Objective | Target | Measured by | If missed |
|---|---|---|---|
| Crash-free sessions | At least 99.8% per release, over the TestFlight external beta and in production | App Store Connect, Xcode Organizer | Pause the phased release; stabilisation work before new features |
| Cold launch to first frame, baseline iPhone | p95 600 ms (p50 400 ms) | `XCTApplicationLaunchMetric`; MetricKit launch histograms ([performance budgets](performance-budgets.md)) | `performance` issue, `priority:p1` |
| Open a 500-page PDF to first page | p95 600 ms | Signpost `Document.FirstPage` | `performance` issue |
| Support first response | Within two business days | Support mailbox | Reviewed at the milestone |
| Security report acknowledgement | Within five business days | Security mailbox and GitHub private reporting | Reviewed immediately |
| SEV1 mitigation | Within 24 hours of detection | Incident log | Blameless review |
| SEV2 mitigation | Within `Assumption:` 3 business days | Incident log | Blameless review |
| AI answers with correct page citations | At least 95% on the evaluation set before release | [AI evaluation framework](ai-evaluation-framework.md) | Release blocked |
| Relay availability (once it exists) | `Assumption:` 99.5% monthly | Relay monitoring | Failover to other tiers; review |

Business days are Monday to Friday in Sydney, excluding New South Wales public holidays.

## On-call for a solo maintainer

PDF Algo Pro is run today by one maintainer. On-call is designed so that is sustainable, and so it
can become a rotation as people join ([GitHub governance](github-governance.md)).

- **Hours.** Monitoring and support happen on business days, `Assumption:` 9:00 to 17:00 Sydney time.
  Outside those hours, only SEV1 is handled, on a best-effort basis.
- **Detection.** Daily checks of Organizer, App Store Connect, reviews and the support and security
  mailboxes on business days; twice daily during the seven days of a phased release. Relay alerts,
  once the relay exists, go to the maintainer's phone.
- **Mitigate from anywhere.** Pausing a phased release, changing a kill switch and replying to support
  can each be done from a phone, so a SEV1 can be contained without a Mac.
- **Escalation.** There is no second person today. For issues outside the maintainer's control, the
  escalation paths are Apple Developer support and App Review (expedited review), and the AI
  provider's support channel.
- **Holidays and planned absence.** No App Store release in the five business days before an absence;
  any phased release is completed or paused; kill switches are checked; the support mailbox
  auto-reply states when replies will resume; the absence is noted in [working memory](working-memory.md).
- **When the team grows.** A weekly rotation with a primary and a secondary, handover notes, and the
  same runbooks; the Operations hat stays accountable for this document.

## Open questions

- A dedicated support email address and support page URL (readiness item: privacy and support URLs
  live; see the [readiness review](readiness-review.md)).
- Where release artefacts and repository mirrors are stored, and who else can reach them in an
  emergency (held privately).
- Support in French: reply in French, or in English with a note.
- Relay alerting tool, once `pdf-algo-pro-backend` exists, without adding a data processor that sees
  document content.
