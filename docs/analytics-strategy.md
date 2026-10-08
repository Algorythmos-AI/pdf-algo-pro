# Analytics strategy

How PDF Algo Pro learns whether it is working without watching its users: which data sources are
used, what is measured and how, the event taxonomy for the opt-in telemetry, how consent works, and
how the tracking plan is governed. This is the public edition. Metric definitions are public so
everyone measures the same thing; numeric targets for acquisition, conversion, retention and revenue
are held privately and are not published here.

Owner: Product and Privacy · Reviewed: each milestone, and whenever the tracking plan changes

## Posture

**Minimal, non-identifiable and aggregated.** PDF Algo Pro measures counts of what happens in the
product, never who did it and never what was in the document. Disclosure is honest, and consent is
asked where required. Three things are never collected, in any form, by any source we control:

1. **Document content**: text, images, file names, page contents, AI prompts or answers, OCR output,
   signatures, form values.
2. **Personal information**: names, email addresses, contacts, location, advertising identifiers,
   device identifiers, persistent install identifiers, IP addresses kept beyond servicing a request.
3. **Business data** found in documents: amounts, parties, dates, clauses, anything extracted.

This follows [ADR-0017](adr/0017-privacy-first-telemetry.md), the privacy pillar (PIL-5), and
founder principle 1 ([founder principles](founder-principles.md)). It is also part of the product's
case to users: competitors' App Store privacy labels list data linked to the user, and several list
identifiers used for tracking ([competitive moat](competitive-moat.md)).

## Principles

1. **Apple-native first.** Use what Apple already measures, with Apple's own consent and privacy
   thresholds, before building anything ([ADR-0012](adr/0012-on-device-observability.md)).
2. **Aggregate on the device.** The device turns events into daily counts before anything leaves it;
   no event stream exists anywhere.
3. **Opt in, not opt out.** First-party telemetry is off until the user turns it on, and paid
   features never depend on it (Guideline 5.1.1(ii) in the
   [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
4. **Allow-list everything.** Only events and property values in the tracking plan can be sent;
   properties are enumerations or buckets, never free text.
5. **Every event serves a metric.** An event with no metric in [success metrics](success-metrics.md)
   is not added.
6. **No third-party analytics or crash SDKs**, ever ([ADR-0012](adr/0012-on-device-observability.md)).
7. **Measure honestly.** Opt-in data is a biased sample; reports say so and show the sample size.

## Sources by phase

| Phase | Sources | What it answers |
|---|---|---|
| **Now until `pdf-algo-pro-backend` exists** | App Store Connect App Analytics; App Store Connect subscription and sales reports; Xcode Organizer and App Store Connect crash and performance metrics; TestFlight feedback; ratings and reviews | Acquisition, retention cohorts, conversion to paid, crashes, launch and hang trends |
| **Once the backend exists** | Adds App Store Server Notifications V2 (subscription lifecycle) and the opt-in first-party telemetry | Activation, onboarding intent, feature and intelligence adoption, tier mix, the north-star metric |

Until the backend exists there is no first-party telemetry at all, and the App Store privacy label
stays "Data Not Collected" ([App Store strategy](app-store-strategy.md)).

## Apple-native sources

### App Store Connect App Analytics

- **Acquisition:** impressions, product page views, conversion, first-time downloads and
  redownloads, by source: App Store Search, App Store Browse, App Referrers, Web Referrers and campaign
  links ([App Analytics](https://developer.apple.com/app-store-connect/analytics/)).
- **Custom product pages and product page optimisation:** downloads and conversion per custom
  product page, and treatment results for optimisation tests (same source;
  [Custom product pages](https://developer.apple.com/app-store/custom-product-pages/)).
- **Engagement and retention:** active devices, sessions, retention, and cohorts by download date,
  source or offer start date; peer-group benchmarks built with differential privacy (same source).
- **Privacy:** usage metrics include only users who agreed to share diagnostics and usage with app
  developers, and some sources need a minimum amount of data before they appear (same source). Apple
  collects this data, so it is not part of the developer's privacy label
  ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)).
- **Campaign links** use the App Store's provider and campaign parameters on links we publish
  (support site, social posts); nothing personal is put in a URL.

### App Store Server Notifications V2

Once `pdf-algo-pro-backend` exists, the App Store sends signed (JWS) notifications for subscription
events to it ([App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2)).
The relay verifies them and uses them for entitlements; analytics receives only daily counts derived
from them.

| Metric | Notification type and subtype ([notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)) |
|---|---|
| Trial starts | `SUBSCRIBED` / `INITIAL_BUY` where the transaction's `offerDiscountType` is a free trial |
| Paid starts without a trial | `SUBSCRIBED` / `INITIAL_BUY` with no introductory offer |
| Trial-to-paid conversion | The first `DID_RENEW` after a trial, for the same original transaction |
| Renewals | `DID_RENEW` |
| Intent to churn | `DID_CHANGE_RENEWAL_STATUS` / `AUTO_RENEW_DISABLED` |
| Churn | `EXPIRED` (subtype `VOLUNTARY`, `BILLING_RETRY` and others) |
| Billing problems | `DID_FAIL_TO_RENEW`, `GRACE_PERIOD_EXPIRED` |
| Win-back | `SUBSCRIBED` / `RESUBSCRIBE` |
| Refunds | `REFUND` |

Pairing a trial with its later renewal needs the original transaction identifier, a pseudonymous
purchase identifier. Analytics never stores it: the relay keeps a salted hash only for as long as the
entitlement needs it, and emits daily counts. Before the backend exists, the same measures come from
App Store Connect's subscription reports.

### MetricKit and Xcode Organizer

MetricKit delivers on-device metric reports about the previous 24 hours at most once a day and
diagnostic reports immediately; in iOS 27 `MetricManager` delivers them as asynchronous sequences
([MetricKit](https://developer.apple.com/documentation/metrickit)). In V1 the app keeps these
reports on the device: they feed the user-exportable diagnostics summary and development builds
([operations](operations.md)). Field performance and crash trends come from Xcode Organizer and App
Store Connect, which Apple collects from users who share analytics and from all TestFlight users
([Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)).
When opt-in telemetry exists, it may add coarse performance buckets (for example launch-time bands)
from MetricKit, never call stacks or logs.

## Opt-in first-party telemetry

### Design

1. **Events become counters on the device.** Each allow-listed event increments a counter keyed by
   the event name and its allowed property values, for the current local day. No timestamps finer
   than a day, no sequence of events, no per-document keys.
2. **Unique-per-period flags.** Metrics that need unique users (weekly actives, the north-star
   metric, first value) are computed on the device, which reports a flag at most once per period (for
   example once per ISO week). Summing flags across devices gives a count of devices without any
   identifier.
3. **Coarse context only.** Each batch carries the schema version, app version (major and minor),
   OS major version, device class (phone or tablet), interface language (English, French or other)
   and whether the on-device model is available. Nothing else.
4. **Batched, delayed upload.** Closed days are uploaded at most once a day, with a random delay,
   over HTTPS to `pdf-algo-pro-backend`. Each batch has a random identifier used once, so batches from
   one device cannot be linked. No App Attest or DeviceCheck token is attached, because the
   attestation key would itself link batches from one install; forged data is handled with
   plausibility checks and rate limits.
5. **No IP retention.** The relay uses the connection address only to service the request and
   does not log it.
6. **Minimum counts before anything is shown.** A reported cell (a metric for one combination of
   dimensions on one day) is shown only when at least k devices contributed; smaller cells are merged
   into "other" or rolled up weekly. `Assumption:` k = 20, validated against expected early volumes;
   this is a k-anonymity-style threshold, not a formal guarantee.
7. **User-visible.** Settings shows the last batch sent, in readable form.

### Decision: on-device aggregation with opt-in upload

**Rationale.** It answers the activation and adoption questions that Apple's sources cannot (for
example "did the first task match the onboarding intent?") while keeping data non-identifiable by
construction. **Trade-offs.** No funnels per user, no session replay, no event-level debugging, and
an opt-in sample that is smaller and biased towards engaged users. **Alternatives considered.**
Third-party analytics SDKs (data processors, identifiers, privacy-label impact); event-level
first-party logging (identifiable in practice through sequences and timing); no in-app telemetry at
all (blind to activation, the stage the product most needs to learn about). **Risks.** Small
opted-in samples early on (reported with sample sizes; weekly roll-ups); a label that changes once
telemetry ships (planned, and explained in release notes); abuse of an unauthenticated endpoint
(plausibility checks, rate limits, and no effect on the product if data is polluted). **Future
scalability impact.** The same pipeline serves iPad, Mac and visionOS by adding a device class value;
formal differential privacy can be added at the aggregation step if volumes justify it.

## Funnel and metric definitions

Definitions match [success metrics](success-metrics.md). The funnel is
**onboarding → paywall view (first run) → first document → first core task → paywall view (later) →
trial → paid**. The paywall's `trigger` tells the first-run view from the later ones.

| Stage | Metric | Definition | Source |
|---|---|---|---|
| Onboarding | Onboarding completion | Installs that complete or skip onboarding, per install that starts it | Telemetry: `onboarding.flow.*` |
| Onboarding | Intent mix | Share of each intent chosen | Telemetry: `onboarding.intent.selected` |
| First document | First document opened | Installs that open a first document, by source (Files, Share extension, scan, sample) | Telemetry: `activation.first_document.opened` |
| First core task | **First value** | New installs that complete a core task within the first session | Telemetry: `activation.first_value.reached` with `in_first_session = true` |
| First core task | **Onboarding intent fulfilled** | Users whose first task matches the intent they chose at onboarding | Telemetry: `activation.first_value.reached` with `matches_intent = true` |
| Paywall view | Paywall reach | Activated installs that see the paywall, by trigger | Telemetry: `commerce.paywall.viewed` |
| Trial | **Trial start rate** | Users who start a trial, per activated user | App Store Server Notifications (trial starts) ÷ telemetry (activated users); cross-checked with `commerce.trial.started` |
| Paid | **Trial-to-paid conversion** | Trials that convert to a paid period | App Store Server Notifications |
| Paid | **Renewal and refund rates** | Renewals; refunds per purchase | App Store Server Notifications |
| Acquisition | **Product page conversion**; **source mix** | Product page views that become first downloads; downloads by source | App Analytics |
| Engagement | **Weekly active users** | Users with at least one opened document in the week | App Analytics active devices; telemetry `engagement.week.recorded` |
| Engagement | **Tasks per active user** | Core tasks completed per weekly active user | Telemetry |
| Retention | **Day-7 and day-30 retention** | Share of an install cohort active on days 7 and 30 | App Analytics retention |
| Intelligence | **AI adoption**; **tier mix**; **answer kept rate** | Weekly users running an intelligence feature; share of requests per tier; answers kept per answer shown | Telemetry |
| Features | **Feature adoption** | Weekly users per feature area | Telemetry |
| Referral | **Shares** | Documents shared from the app per weekly active user | Telemetry |
| North star | **Weekly users who complete a document task with an answer they keep** | A week counts when a device completes a core task and keeps an intelligence result | Telemetry: `engagement.week.recorded` with `north_star = true` |

**Core task** means: read to a later page, edit and save, scan to a searchable PDF, sign, organise,
convert, or annotate. **Kept** means copied, shared, exported, or left open for at least
`Assumption:` 30 seconds.

**How sources combine.** Sources are never joined per user. Ratios across sources (for example trial
starts from App Store notifications over activated users from telemetry) are ratios of aggregates,
and the telemetry side is scaled by the opted-in share, estimated by comparing telemetry's weekly
devices with App Analytics active devices. `Assumption:` this scaling is good enough for direction;
it is validated during the external beta, where both sources can be compared.

## Event taxonomy

### Naming

- `domain.object.action`, all lower case, words inside a segment joined with underscores, action in
  the past tense: `intelligence.answer.kept`, `activation.first_value.reached`.
- **Domains:** `onboarding`, `activation`, `library`, `reader`, `task`, `intelligence`, `commerce`,
  `share`, `engagement`, `quality`.
- One event per meaning. Variants are properties, not new names.

### Allowed properties

Properties are enumerations or buckets defined in the tracking plan; free-form strings, numbers
outside buckets and identifiers are rejected by the schema.

| Property | Allowed values |
|---|---|
| `intent` | `chat`, `summarise`, `extract`, `contract`, `edit`, `annotate`, `sign`, `convert`, `organise`, `read`, `scan`, `all_tools`, `skipped` |
| `source` | `files`, `share_extension`, `open_in_place`, `scan`, `sample` |
| `task` | `read_later_page`, `edit_saved`, `scan_searchable`, `sign`, `organise`, `convert`, `annotate` |
| `feature` | `chat`, `summarise`, `extract`, `contract` |
| `tier` | `on_device`, `private_cloud_compute`, `claude` |
| `outcome` | `success`, `not_found`, `failed`, `cancelled` |
| `action` | `copy`, `share`, `export`, `kept_open` |
| `trigger` | `pro_feature`, `settings`, `post_value_card` |
| `plan` | `monthly`, `annual` |
| `format` | `pdf`, `docx`, `xlsx`, `pptx`, `image` |
| `page_bucket` | `1_10`, `11_50`, `51_200`, `201_1000`, `1001_plus` |
| `operation` | `open`, `save`, `ocr`, `export`, `ai`, `purchase` |
| `error_domain` | An enumerated list of the app's own error domains; never system messages or paths |
| Booleans | `in_first_session`, `matches_intent`, `opened_document`, `north_star` |

### Schema versioning

- The tracking plan has a SemVer schema version, sent with every batch.
- Adding an event or an allowed value is a minor change; changing a meaning, renaming or removing is a
  major change. Each event records the version that introduced it.
- The backend accepts the current and previous major versions; older batches are dropped, not
  guessed at.
- Removed events are listed as retired in the plan so their names are never reused.

### MVP event catalogue

| Event | Fired when | Properties | Metric served |
|---|---|---|---|
| `onboarding.flow.started` | The first onboarding screen appears | — | Onboarding completion |
| `onboarding.intent.selected` | An intent is chosen | `intent` | Intent mix |
| `onboarding.page.viewed` | An introduction page comes on screen, forwards or back | `page` | Where the introduction is left |
| `onboarding.flow.skipped` | Skip is tapped | — | Onboarding completion |
| `onboarding.flow.completed` | Onboarding finishes | — | Onboarding completion |
| `activation.first_document.opened` | The first document after install opens (once) | `source` | First document opened |
| `activation.first_value.reached` | The first core task after install completes (once) | `task`, `in_first_session`, `matches_intent` | First value; onboarding intent fulfilled |
| `task.core.completed` | A core task completes | `task`, `page_bucket` | Tasks per active user; feature adoption |
| `intelligence.request.completed` | An intelligence request finishes | `feature`, `tier`, `outcome`, `page_bucket` | AI adoption; tier mix |
| `intelligence.answer.kept` | An answer or summary is kept | `feature`, `action` | Answer kept rate |
| `intelligence.consent.changed` | Cloud-tier consent is granted or revoked | `tier`, `state` (`granted`, `revoked`) | Consent rates (AI governance) |
| `commerce.paywall.viewed` | The paywall appears | `trigger` | Paywall reach |
| `commerce.paywall.closed` | The paywall goes away with no purchase made | `trigger` | Paywall reach against trial starts |
| `commerce.plan.selected` | A different plan is chosen on the paywall | `plan` | Plan mix before purchase |
| `commerce.purchase.started` | The paywall's button is tapped and the App Store's sheet is asked for | `plan` | Paywall to purchase sheet |
| `commerce.purchase.failed` | A purchase could not be made or verified (not a cancellation) | — | Reliability of buying ([operations](operations.md)) |
| `commerce.trial.started` | A free-trial transaction completes on the device | `plan` | Trial start rate (cross-check) |
| `commerce.purchase.completed` | A paid purchase without a trial completes | `plan` | Paid conversion (cross-check) |
| `commerce.purchase.restored` | Restore Purchases brings Pro back | — | Restores (support) |
| `commerce.restore.failed` | Restore Purchases could not be made, or was cancelled | — | Reliability of restoring ([operations](operations.md)) |
| `share.document.exported` | A document is shared or exported | `format` | Shares |
| `engagement.week.recorded` | Once per ISO week, if the app was used | `opened_document`, `north_star` | Weekly active users; north star |
| `quality.operation.failed` | An operation fails | `operation`, `error_domain` | Reliability ([operations](operations.md)) |

The `intelligence.consent.changed` event reports only that a choice changed, never which documents
were involved; it supports the consent reporting in [AI governance](ai-governance.md).

## Consent UX

- **Off by default.** The setting exists only once telemetry ships.
- **Asked once, after first value.** A card appears after the user's first successful task, never
  during the first-run introduction and never next to the paywall or the purchase confirmation. Draft copy: "Help improve PDF Algo Pro. Share
  anonymous daily counts of which features are used. Never your documents, names or anything you
  type." Buttons "Share counts" and "Not now" have equal weight
  ([design system](design-system.md)).
- **Always reversible.** Settings › Privacy › "Share anonymous usage counts", with "What's shared"
  (the last batch in readable form) and "Delete unsent counts". Turning it off stops counting
  immediately and deletes unsent counters. Data already aggregated cannot be traced back to a device,
  so it cannot be deleted per person; the privacy policy says so.
- **No tracking prompt.** Nothing is used for tracking as Apple defines it, so App Tracking
  Transparency does not apply ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)).
- **Separate from AI consent.** Telemetry consent and cloud-AI consent are different screens and
  different settings; one never implies the other ([privacy architecture](privacy-architecture.md)).

## Privacy-label mapping

| Configuration | Label effect |
|---|---|
| Apple-native sources only (launch) | "Data Not Collected": App Analytics and Apple's crash data are collected by Apple, not by us |
| Opt-in telemetry shipped | Usage Data (Product Interaction) and Diagnostics (Performance Data, Other Diagnostic Data), Not Linked to You, purpose Analytics. Disclosure is required even though sharing is optional, because the data does not meet all of Apple's optional-disclosure criteria ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)) |
| App Store Server Notifications | Received by our server from Apple, not transmitted from the app; open question whether Purchase History must be declared once the relay stores subscription state |

The full product mapping, including the AI tiers, is in [App Store strategy](app-store-strategy.md).

## Governance

- **The tracking plan is code.** `tracking-plan.json` in the `Telemetry` package lists every event,
  its purpose, the metric it serves, its properties and allowed values, the version that introduced
  it, and its owner hat. The package generates a typed `TelemetryEvent` API from it.
- **Reviewed in pull requests.** Any change to the plan fills in the telemetry section of the pull
  request template: purpose, metric, properties, privacy review, and privacy-label impact. The
  Privacy hat approves; while there is one maintainer, the checklist is the review, and the `compliance`
  label is applied ([GitHub governance](github-governance.md)).
- **CI invariants** (the `invariants` job; [quality gates](process/quality-gates.md)):
  - events can be sent only through the `Telemetry` package, using generated cases, never string
    literals;
  - feature packages have no networking; only `Intelligence`, `Commerce` and `Telemetry` may reach
    the network ([iOS architecture review](ios-architecture-review.md));
  - the tracking plan's schema rejects string-typed or unbucketed numeric properties;
  - known third-party analytics and crash SDKs are blocked in `Package.resolved`;
  - a plan change without a schema version bump fails.
- **Release checklist.** The privacy label is compared with the tracking plan and the network-capable
  packages before every submission ([process/runbooks/app-store-submission.md](process/runbooks/app-store-submission.md)).
- **Pruning.** Each milestone, events that no longer serve a metric are retired.
- **Impact assessment.** A privacy impact assessment is completed before telemetry first ships
  ([compliance roadmap](compliance-roadmap.md)); the data classes follow
  [data classification](data-classification.md) (telemetry aggregates: internal; subscription-derived
  data and App Store Connect exports: confidential).
- **Threats** to the pipeline (forged batches, re-identification through rare combinations) are in
  the [threat model](threat-model.md).

## Retention

| Data | Where | Kept for |
|---|---|---|
| Unsent counters | The user's device | Until sent, or `Assumption:` 30 days; deleted on opt-out |
| Received batches | `pdf-algo-pro-backend` | Deleted after aggregation, within `Assumption:` 7 days |
| Daily aggregates | Private analytics store | `Assumption:` 13 months, enough for a year-on-year comparison |
| Subscription-derived daily counts | Private analytics store | `Assumption:` 13 months |
| Hashed original transaction identifiers | Relay (entitlements, not analytics) | While the subscription is active, then `Assumption:` 30 days |
| App Store Connect exports | Private storage | `Assumption:` 13 months; Apple's own retention applies to App Store Connect |
| MetricKit reports | The user's device | System-managed; not uploaded in V1 |

Retention periods are validated in the privacy impact assessment and stated in the privacy policy.

## What the data can tell us about switching, paying and staying

| Question | Signals |
|---|---|
| Why do people switch to us? | Source mix and custom product page conversion (which intent brought them), intent mix at onboarding |
| Why do people pay? | Paywall triggers that lead to trials, trial start rate by intent, AI adoption and tier mix among payers (aggregate) |
| Why do people stay? | Day-7 and day-30 retention, renewal and refund rates, answer kept rate, weekly north-star users |

Targets for each are set per milestone in the confidential edition of the business documents, which
is held privately.

## Open questions

- **k threshold and roll-ups**: the value of k and whether weekly roll-ups are needed for French and
  tablet segments early on.
- **Purchase History on the label** once the relay stores subscription state from App Store Server
  Notifications.
- **Opted-in share estimate**: whether the comparison with App Analytics active devices is stable
  enough to scale telemetry counts.
- **Coarse performance buckets** from MetricKit in telemetry: which bands, if any, are worth the label
  impact.
- **Backend timing**: telemetry depends on `pdf-algo-pro-backend`, which is required for the Claude
  tier before general availability ([ADR-0009](adr/0009-tiered-ai-and-consent.md)).
