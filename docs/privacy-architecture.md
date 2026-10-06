# Privacy architecture

Where every piece of data in PDF Algo Pro goes, feature by feature: what the data is, where it is
processed, whether it leaves the device and to whom, how long it is kept, and what the user
controls. It also sets the defaults (on device first, every cloud path opt-in), how consent is
recorded, how deletion works, and how the design maps to the privacy manifest and the App Store
privacy label. Data classes come from [data classification](data-classification.md); threats from
the [threat model](threat-model.md); legal obligations from the
[compliance roadmap](compliance-roadmap.md); AI consent and cost rules from
[AI governance](ai-governance.md).

Owner: Privacy · Reviewed: each milestone, and before any change that sends data off the device

## Defaults

1. **On device first.** Reading, editing, scanning, OCR, search and on-device intelligence run on
   the device and work offline (NFR-OFF-001, [founder principles](founder-principles.md) 1 and 3).
2. **No Algorythmos server receives user content by default.** Until the relay exists (V2) there is
   no Algorythmos server in any data path. After it exists, it passes consented AI requests through
   in memory and stores counters only.
3. **Every cloud path that carries content is opt-in, named and revocable:** Private Cloud Compute
   and Claude ([ADR-0009](adr/0009-tiered-ai-and-consent.md), NFR-PRIV-001). Telemetry is opt-in
   too ([ADR-0017](adr/0017-privacy-first-telemetry.md), FR-SET-004), because Apple requires consent
   for collecting usage data "even if such data is considered to be anonymous"
   ([App Review Guidelines 5.1.1(ii)](https://developer.apple.com/app-store/review/guidelines/)).
4. **The user's own iCloud is the only sync channel.** Documents sync through iCloud Drive and
   user-authored library metadata through the CloudKit private database, which the developer cannot
   see ([privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)).
5. **No third-party analytics, advertising or crash SDKs** (NFR-PRIV-003,
   [ADR-0012](adr/0012-on-device-observability.md)). The PDF SDK must pass a telemetry audit with
   all vendor telemetry off ([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)).
6. **Remote configuration can only switch things off.** No remote value can start a data flow
   ([engineering playbook](engineering-playbook.md), feature flags).

## Parties and trust boundaries

```
+------------------------------ The user's device ------------------------------+
|  App: PDFEngine (vendor SDK), Scanning/OCR (Vision), Intelligence (on-device), |
|       library index (SwiftData), Core Spotlight index, consent records         |
|  Extensions: Share, Action, widgets, Quick Look  --  App Group container       |
|  Keychain: saved signatures, remembered passwords                              |
+----+----------+-----------+-------------+-------------+------------+----------+
     |(a)       |(b)        |(c)          |(d)          |(e)         |(h)
     v          v           v             v             v            v
 iCloud Drive  CloudKit    CloudKit      Apple PCC     App Store    Support mailbox
 (documents)   private DB  public DB     (opt-in,      (StoreKit,   (only what the
               (metadata)  (config,      not stored)   crash data)  user sends)
                           read only)
 \___________ Apple, under the user's Apple Account or Apple's terms _________/

     |(f) TestFlight beta only                 |(g) V2 general availability
     v                                         v
 Anthropic Claude API  <------ API key ------  pdf-algo-pro-backend relay
 (App Attest token,                            (attestation, entitlement,
  no user identity)                             quotas, counters only)
```

| Path | Recipient | Carries user content | Consent | Milestone (per [roadmap](product/roadmap.md)) |
|---|---|---|---|---|
| (a) | Apple iCloud Drive, in the user's account | Yes (documents) | The user's iCloud setting for the app | MVP |
| (b) | Apple CloudKit private database, in the user's account | Yes (titles, tags, folders) | The user's iCloud setting | MVP |
| (c) | Apple CloudKit public database | No; the app only reads | None needed | MVP |
| (d) | Apple Private Cloud Compute | Yes (question and excerpts) | Opt-in, per device | V1 |
| (e) | Apple App Store | No document content | Apple's purchase flow; Apple's diagnostics sharing setting | V1 |
| (f) | Anthropic, directly from the app | Yes (question and excerpts) | Opt-in, per device | TestFlight beta only |
| (g) | Relay, then Anthropic | Yes, in transit through the relay | Opt-in, per device | V2 |
| (h) | Algorythmos support mailbox | Only what the user attaches | The user sends the email | MVP |

## Summary of data flows

| Feature | Data | Processed | Leaves the device | Recipient | Retention | User control |
|---|---|---|---|---|---|---|
| Reading | PDF file, rendered tiles, reading position | Device (PDF SDK) | No, except iCloud sync | User's iCloud | Until deleted | Delete; iCloud setting |
| Editing, signing, redaction | Edited file, annotations, signatures (Keychain) | Device | No, except iCloud sync of the file | User's iCloud | Until deleted | Undo; delete; signature management |
| Scanning and OCR | Camera captures, recognised text | Device (VisionKit, Vision) | No | None | Captures deleted after save | Delete scan |
| Search and Spotlight | Titles, tags, document and OCR text in the index | Device (Core Spotlight) | No | None | Deleted with the document | Setting to exclude text from Spotlight |
| System surfaces | Titles, thumbnails, page numbers | Device and Apple's system services | Handoff only, between the user's devices | Apple (Continuity) | Transient | Widget privacy; Handoff setting |
| On-device AI | Question, excerpts, answer | Device (Foundation Models) | No | None | Cached answers deleted with the document | Hide AI features (FR-AI-009) |
| Private Cloud Compute | Question, instructions, excerpts, page images, conversation | Apple PCC | Yes, after consent | Apple | Not stored, per Apple | Consent switch |
| Claude, beta | As PCC | Anthropic | Yes, after consent | Anthropic | Anthropic's terms | Consent switch |
| Claude, V2 | As PCC | Relay (in memory), then Anthropic | Yes, after consent | Algorythmos relay, Anthropic | Relay: none; Anthropic: its terms | Consent switch |
| iCloud Drive and CloudKit sync | Documents; user-authored metadata | Apple | Yes | Apple, in the user's account | Until deleted | iCloud settings; in-app iCloud deletion |
| Remote configuration | None sent | Apple (CloudKit public database) | Request only | Apple | Cached on device | None needed |
| Purchases | Signed transactions | Apple; relay in V2 | To Apple; relay in V2 | Apple; Algorythmos (V2) | Apple; relay counters by period | Apple subscription settings |
| Support diagnostics | Diagnostics summary the user reviews | Device | Only if the user sends it | Algorythmos | `Assumption:` 12 months after the case closes | User chooses to send |
| Opt-in telemetry | Allow-listed daily aggregates | Device, then relay | Yes, only after opt-in | Algorythmos (V2) | `Assumption:` 13 months | Opt-in switch |

The sections below give each flow in detail.

## Data flows by feature

### Reading (PIL-1)

- **Data:** the PDF file, its rendered page tiles, the text layer for selection and read-aloud,
  the reading position and recents.
- **Processed:** on the device by the PDF SDK inside `PDFEngine`; PDFKit only for Quick Look
  thumbnails ([iOS architecture review](ios-architecture-review.md)).
- **Leaves the device:** the file syncs through the user's iCloud Drive if it lives there; the
  reading position syncs as library metadata. Nothing else.
- **Content-initiated network access is blocked:** links, form-submit actions, remote resources and
  scripts inside a PDF never open a connection by themselves; a link opens only when the user taps
  it and confirms the full address ([threat model](threat-model.md)). The SDK's own licence check
  must work offline and its telemetry must be off (a C1 spike criterion).
- **Retention:** the file until the user deletes it; thumbnails in the Caches directory, rebuilt
  on demand.
- **User control:** delete, move, turn off iCloud for the app.

### Editing, signing and redaction (PIL-2)

- **Data:** edits to text and images, annotations, form values, page operations, saved ink
  signatures, document passwords, redaction marks.
- **Processed:** on the device. Office conversion runs on the device if the chosen SDK supports it;
  if not, cloud conversion is a separate opt-in that names its provider (FR-ORG-002) and is not
  built until that consent exists.
- **Signatures** are stored in the Keychain (FR-EDIT-004), on this device only; sync through iCloud
  Keychain, which is end to end encrypted
  ([iCloud data security overview](https://support.apple.com/en-us/102651)), only if the user turns
  it on. They are never sent to any AI tier ([data classification](data-classification.md)).
- **Redaction removes content** (FR-EDIT-005): text, images, vector content, annotations, form
  values, metadata and earlier revisions under the marked area are deleted and the file is
  rewritten in full rather than saved incrementally. Because iCloud keeps earlier file versions,
  after a redaction the app offers to remove other versions of the file
  ([removeOtherVersionsOfItem(at:)](https://developer.apple.com/documentation/foundation/nsfileversion/removeotherversionsofitem(at:)))
  and explains that copies already shared elsewhere are not affected.
- **Protected documents keep their protection** when notes, markup or form entries are saved.
  - **Opened with the user password, or without one:** the user password and the author's
    restrictions stay as they were, under a new owner password that nobody knows. The user password
    never gains the owner's rights. The original owner password no longer applies, because the app
    never had it.
  - **Opened with the owner password:** that password protects the saved file.
  - **Changes the author does not allow** (notes and markup, or form entries) are refused, with an
    explanation, and the file is left as it was.
  - **Adding recognised text** is not offered for encrypted documents, because the searchable copy
    would carry no protection.
- **Leaves the device:** only the saved file, through iCloud Drive.
- **User control:** undo and redo (FR-EDIT-007); signature management in Settings; password
  protection (FR-EDIT-006).

### Scanning and OCR (PIL-3)

- **Data:** camera frames and captured page images; recognised text and structure.
- **Processed:** the system document camera captures pages; Vision's `RecognizeDocumentsRequest`
  recognises text on the device ([ADR-0008](adr/0008-ocr-and-scanning.md)).
- **Leaves the device:** no. The resulting searchable PDF syncs like any document.
- **Retention:** captured images live in a temporary directory with complete protection and are
  deleted when the scan is saved or cancelled; the recognised text is written into the PDF's
  invisible text layer and the local index.
- **User control:** camera permission (system); delete the scan.

### Search, Spotlight and system surfaces (PIL-1, PIL-7)

- **Core Spotlight:** titles, tags and document text (including OCR text) are indexed on the device
  ([ADR-0010](adr/0010-search.md), FR-LIB-005), in an index created with a data protection class
  ([init(name:protectionClass:)](https://developer.apple.com/documentation/corespotlight/cssearchableindex/init(name:protectionclass:))).
  Items are removed when a document is deleted or leaves Recently Deleted (FR-LIB-006). A setting
  excludes document text from system Spotlight, and turning on the app lock (FR-SET-002) excludes
  it automatically.
- **App Intents and Siri:** intents return results to the system; they never modify documents
  ([AI governance](ai-governance.md)). What the system does with a result shown in Siri or Shortcuts
  is governed by Apple's terms.
- **Widgets (V1):** recent titles and thumbnails, read from the App Group container, marked
  privacy-sensitive so they are redacted when the device is locked
  ([privacySensitive(_:)](https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:))).
- **Handoff (V2, FR-READ-007):** the user activity carries a document identifier and page number
  only, never a title or text, and is never eligible for public indexing
  ([isEligibleForPublicIndexing](https://developer.apple.com/documentation/foundation/nsuseractivity/iseligibleforpublicindexing)).
- **Share extension (MVP):** copies the incoming file into the App Group container for the app to
  import, and has no network access.
- **Action extension (V1):** "Summarise with PDF Algo Pro" uses the on-device tier only; cloud
  tiers are offered only inside the app, where the consent screen and activity log live (decision
  below).
- **Leaves the device:** only Handoff activity, through Apple's Continuity between the user's own
  devices.

### On-device intelligence (PIL-4)

- **Data:** the question, instructions, selected excerpts or page images, and the answer.
- **Processed:** Apple's on-device `SystemLanguageModel`
  ([What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)).
- **Leaves the device:** no.
- **Retention:** answers are cached in the local, unsynced part of the library index and deleted
  with the document.
- **User control:** every AI feature can be hidden (FR-AI-009).

### Private Cloud Compute tier (V1, FR-AI-006)

- **Data sent:** the question, instructions, selected excerpts (or page images for OCR
  assistance) and the conversation so far; never the PDF file, other documents, or any identifier
  of the person ([AI governance](ai-governance.md)).
- **Recipient:** Apple. Apple states that no prompts are ever stored and that independent
  researchers can verify this ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)),
  and designs PCC so personal data is used only to fulfil the request and is not retained, including
  through logging ([Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/)).
- **Consent:** opt-in per device, naming Apple Private Cloud Compute; revocable in Settings ›
  Intelligence (FR-SET-001).
- **Retention by the app:** the answer, cached locally as above; one activity-log entry
  (`Assumption:` 30 days, [AI governance](ai-governance.md)).

### Claude tier (FR-AI-007)

Data sent is the same as for Private Cloud Compute. Analyse Contract never uses this tier until the
provider's high-risk requirements are reviewed ([AI governance](ai-governance.md)).

**TestFlight beta (App Attest).** The app proves it is a genuine build through Apple's App Attest;
Anthropic then issues a token that expires after one hour, is scoped to the workspace, and carries
no end-user identity
([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)).

```
device --App Attest--> Anthropic token service --1-hour token--> device
device --question + excerpts (TLS)--> Anthropic Messages API --answer--> device
```

**General availability, V2 (relay).**

```
1. device --App Attest assertion + signed App Store transaction--> relay /token
   relay: verifies the assertion and the transaction signature, checks subscription state,
          derives quota key = keyed hash of the original transaction identifier,
          issues a short-lived relay token bound to the attested key
2. device --relay token + consent version + question + excerpts--> relay /messages
   relay: checks token, kill switch, quota and token budget; forwards in memory
3. relay --server-held API key--> Anthropic Messages API --stream--> relay --> device
4. relay: debits credits from the response's usage counts; writes counters only
```

- **What the relay keeps:** quota counters by quota key, the attested public key and assertion
  counter needed to verify later assertions, and operational logs without content. It never
  writes a question, excerpt or answer to disk or to logs.
- **What Anthropic keeps:** for API customers, inputs and outputs are deleted within 30 days unless
  a zero-data-retention agreement applies, longer retention is needed to enforce its Usage Policy,
  or the law requires it; flagged content can be kept for up to two years
  ([How long do you store my organization's data?](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data);
  [API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)).
  Anthropic acts as a processor for the Claude API (same source), and its data processing addendum
  with Standard Contractual Clauses is incorporated in its Commercial Terms
  ([DPA](https://privacy.claude.com/en/articles/7996862-how-do-i-view-and-sign-your-data-processing-addendum-dpa)).
  A zero-data-retention arrangement is sought before general availability (readiness blocker C4).
- **Network metadata:** the provider and the relay's host see the device's IP address when it
  connects. The relay does not store it; the hosting provider's own logging is configured to drop
  or truncate it (open question: hosting provider).
- **Consent:** opt-in per device naming Anthropic and Claude; "ask before sending" stays on by
  default; page images always need a per-request confirmation ([AI governance](ai-governance.md)).

### iCloud Drive and CloudKit private database

- **Documents** live in the app's iCloud Drive container, visible in Files, encrypted by Apple in
  transit and on server and end to end when the user enables Advanced Data Protection
  ([iCloud data security overview](https://support.apple.com/en-us/102651)). Algorythmos has no
  access. With iCloud off, documents live in the app's local container.
- **User-authored metadata** (folders, tags, favourites, reading position) syncs through the
  CloudKit private database; only the user can access it and it is not visible in the developer
  console ([privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)).
  Names and tags use CloudKit encrypted fields.
- **Derived data does not sync** (search index, OCR caches, embeddings, AI answers, activity log):
  it is rebuilt on each device (decision below).
- **User control:** the iOS iCloud setting for the app; in-app "Delete library data from iCloud";
  deleting files in Files.

### Remote configuration (CloudKit public database)

- **Data:** feature flags, operational settings and kill-switch records, all public-class values.
- **Flow:** the app reads records from Apple's CloudKit public database, which is readable by every
  user of the app with or without an iCloud account
  ([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)).
  No user data is written. Records are writable only by the developer role; the record schema and
  procedure are in the [kill-switch runbook](process/runbooks/kill-switch.md).
- **Retention:** the last known good values are cached on the device.

### Purchases (StoreKit 2)

- **Data:** Apple handles payment; the app receives signed transactions and uses
  `Transaction.currentEntitlements` on the device ([ADR-0011](adr/0011-storekit-2-monetisation.md)).
  StoreKit verifies the signed values automatically, and they can also be verified on a server
  ([VerificationResult](https://developer.apple.com/documentation/storekit/verificationresult)).
- **Before the relay:** nothing about purchases reaches Algorythmos except Apple's own reports in
  App Store Connect.
- **V2:** the relay receives the signed transaction when issuing a relay token and App Store Server
  Notifications V2 for renewals, refunds and expiry
  ([App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications)).
  It keeps the quota key, plan and expiry for the current and previous billing period
  (`Assumption:`, [data classification](data-classification.md)). The app does not set an
  `appAccountToken`, because there are no accounts
  ([appAccountToken](https://developer.apple.com/documentation/storekit/transaction/appaccounttoken)).
- **Losing Pro never locks a user out of their documents** (FR-STORE-004).

### Support diagnostics export (FR-SET-003)

- **Data:** app version and build, OS version, the state of the library's search index, the number of
  documents as a range (such as 11-100, never the exact count), event and error counts, MetricKit crash
  and hang summaries ([MetricKit](https://developer.apple.com/documentation/metrickit)). Never document
  names, paths, text, questions, answers, consent history or disk-space figures. This is what
  `DiagnosticsSummary` builds and what the [privacy policy](https://algorythmos.com/pdf-algo-pro/privacy)
  lists; the three change together.
- **Flow:** the user taps "Report a problem"; the app shows the full summary; the user sends it by
  email if they choose. Nothing is sent automatically.
- **MetricKit summaries** (kind, date, build and the system's short reason, such as the exception
  type or a hang's duration; never call stacks) are kept on the device for 30 days, at most 100, in
  a file excluded from backup. TestFlight and App Store crash reports stay the primary source; they
  reach the team through Apple only when the person shares diagnostics with developers.
- **Retention:** `Assumption:` 12 months after the case closes; deletion on request.

### Opt-in telemetry (V2, FR-SET-004)

- **Off by default.** Settings › Privacy › "Share usage statistics", per device.
- **Data:** allow-listed daily aggregates computed on the device (feature used or not, tier mix,
  error categories, performance buckets); no identifiers, no document content, no free text
  ([ADR-0017](adr/0017-privacy-first-telemetry.md), [analytics strategy](analytics-strategy.md)).
- **Flow:** batches sent through the relay; the relay drops the connection's IP address before
  storage and stores only aggregates.
- **Retention:** `Assumption:` 13 months, confirmed in legal review.
- **User control:** turning it off stops sending and deletes pending local counters. Stored
  aggregates cannot be tied back to a device, so they cannot be deleted per user; the settings text
  says so.

## Consent records

Consent is per provider and per device, is never synced, and is versioned; the rules are in
[AI governance](ai-governance.md). This document adds where the records live and how they are used:

- **Stored** in the app container with class C protection, as an append-only history: purpose
  (PCC, Claude, telemetry), consent-text version, grant and revocation times, app version.
- **Checked before every request** by the `IntelligenceRouter` and the `Telemetry` package; no
  code path sends content or telemetry without a current record.
- **Sent to the relay (V2)** only as the consent-text version in a request header, so the relay can
  refuse requests from builds whose consent text is out of date. This is defence in depth, not
  proof of consent: whether device-local records satisfy the duty to demonstrate consent is a legal
  review item ([compliance roadmap](compliance-roadmap.md)).
- **Deleted** with the app; after reinstalling, every consent is asked again.

## Deletion and retention

| Action | What is deleted | What is not |
|---|---|---|
| Delete a document | It moves to Recently Deleted; its index entries, thumbnails, embeddings, extractions and cached answers are deleted (FR-LIB-006) | Copies the user shared elsewhere |
| Recently Deleted expires (30 days) or is emptied | The file, permanently from the app. A file in iCloud Drive is additionally recoverable from iCloud for 30 days ([Recover deleted files on iCloud.com](https://support.apple.com/guide/icloud/recover-deleted-files-mmae56ea1ca5/icloud)) | — |
| Revoke a cloud AI consent | Future requests stop at once; the app offers to delete cached answers from that provider | Content already sent, which the provider's retention terms govern |
| Turn off telemetry | Pending counters on the device | Stored aggregates (not linkable to the device) |
| Delete the app | The app and its data on the device, including local-only documents, the index, caches, consent records and the activity log ([Delete an app from iPhone](https://support.apple.com/guide/iphone/remove-or-delete-apps-iph248b543ca/ios)) | Documents and metadata in iCloud, which Apple does not delete with the app (same source). Keychain items are treated as possibly surviving: on first launch without an install marker the app clears its own Keychain items |
| "Delete library data from iCloud" (in app) | The app's CloudKit private-database zone | Documents in iCloud Drive, which the user deletes in Files; the iCloud storage settings also let users manage stored data ([Manage your iCloud storage](https://support.apple.com/en-us/108922)) |
| Relay (V2) | Counters expire after the retention period; content is never stored | — |
| Support | Correspondence deleted on request or after the retention period | — |

The app shows a warning before deleting the app would lose local-only documents: when iCloud is
off, Settings says where documents live and how to back them up.

## Privacy manifest

`PrivacyInfo.xcprivacy` records the data the app collects and the required-reason APIs it uses;
apps that use a required-reason API without declaring it are not accepted by App Store Connect
([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files);
[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)).
Reason codes below are from Apple's list
([NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)).

| API category | Our use | Reason codes |
|---|---|---|
| User defaults | Preferences read and written by the app | `CA92.1` |
| User defaults | Preferences shared with widgets and extensions through the App Group | `1C8F.1` |
| File timestamp | Sorting and syncing files in the app and iCloud containers | `C617.1` |
| File timestamp | Documents opened in place through the document picker | `3B52.1` |
| File timestamp | Showing modified dates to the user | `DDA9.1` |
| Disk space | Checking space before a scan, export or conversion | `E174.1` |
| System boot time | Only if code uses `systemUptime` or `mach_absolute_time` for elapsed time | `35F9.1` |

- `NSPrivacyTracking` is false and there are no tracking domains.
- `NSPrivacyCollectedDataTypes` is empty until the release that ships the Claude tier through the
  relay or telemetry (V2), and then matches the label table below.
- Disk space and boot time are never put in the support summary, so the bug-report reasons
  (`7D9E.1`, `3D61.1`) are not needed.
- Each third-party SDK ships its own manifest; the PDF SDK's and the Claude package's manifests are
  reviewed in their ADRs. The snapshot-testing library is test-only and never ships
  ([ADR-0018](adr/0018-snapshot-testing-test-only-dependency.md)).
- The `invariants` gate fails when code uses a required-reason API category the manifest does not
  declare ([quality gates](process/quality-gates.md)).

## App Store privacy label

Apple counts data as collected when it is transmitted off the device in a way that lets the
developer or its third-party partners access it for longer than needed to service the request in
real time; data processed only on the device is not collected; developers do not disclose data
collected by Apple; and data collection that varies because users opt in must still be disclosed
unless every optional-disclosure criterion is met
([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)). The label
therefore describes the app, not a mode: once an opt-in feature that collects data ships, the label
lists it, and the Privacy Choices link explains that it is off by default.

| Release | New off-device flows | Label | Why |
|---|---|---|---|
| MVP (internal TestFlight) | None to Algorythmos | No public label; answers prepared as **Data Not Collected** | — |
| V1 and V1.1 | iCloud, PCC, StoreKit, remote configuration, support email | **Data Not Collected** | On-device processing is not collection; iCloud, PCC, StoreKit and crash reports are Apple's; PCC does not store prompts; support email `Assumption:` meets the optional-disclosure criteria (optional, infrequent, user-initiated each time, sender shown), confirmed before submission |
| V2 | Claude through the relay | User Content: Other User Content, App Functionality; Identifiers: User ID (quota key) and Device ID (attested key), App Functionality, Linked to You; Purchases: Purchase History, App Functionality, Linked to You | Anthropic retains content beyond the request unless a zero-retention agreement applies, and even then may retain flagged content; the relay keeps pseudonymous identifiers for quotas |
| V2 | Opt-in telemetry | Usage Data: Product Interaction; Diagnostics: Performance Data and Other Diagnostic Data; Analytics; Not Linked to You | Aggregates without identifiers, kept for months |

Whether Other User Content sent to Anthropic is "linked" (the relay strips identifiers, but document
text can itself identify people) is confirmed with legal review before V2; the conservative answer
is used until then. The label and this table are compared at every release (NFR-PRIV-002,
[release management](release-management.md)); the product-page strategy is in
[App Store strategy](app-store-strategy.md).

## Decision: derived data stays on each device

**Decision.** Only user-authored metadata syncs through the CloudKit private database. The search
index, OCR caches, embeddings, AI answers and the AI activity log are stored in a separate, local
SwiftData configuration and rebuilt on each device.

**Rationale.** Minimises what leaves the device (principle 1); derived data is rebuildable by
definition ([ADR-0006](adr/0006-swiftdata-persistence.md)); cloud-tier answers stay on the device
where the consent was given, so revoking consent on one device cannot leave copies synced to
another.

**Trade-offs.** Each device re-indexes and re-OCRs imported documents; AI answers are not shared
across devices.

**Alternatives considered.** Sync everything (simpler model, more data in iCloud, consent leakage
across devices). Sync OCR text only (saves battery, but OCR text is written into the PDF's text
layer anyway, so it already travels with the file).

**Risks.** Battery and time for the first index on a new device: background processing on external
power ([iOS architecture review](ios-architecture-review.md)).

**Future scalability impact.** Library-wide questions (FR-AI-008) run over a local index on each
device; the split configuration is recorded in ADR-0006's implementation.

**Pillars served.** PIL-5, PIL-6.

## Decision: the relay issues short-lived tokens after attestation and entitlement checks

**Decision.** The relay verifies an App Attest assertion and a signed App Store transaction at a
token endpoint, then issues a short-lived relay token (`Assumption:` 15 minutes, validated against
token-endpoint load and user experience in the beta) bound to the attested key. Quotas key on a
keyed hash of the original transaction identifier. No accounts.

**Rationale.** App Attest proves the app is genuine but carries no user identity, so it cannot
enforce per-user quotas on its own
([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models));
the signed transaction proves an entitlement without an account
([App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)); App Attest
lets a server confirm requests come from legitimate instances of the app
([Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)).
A short-lived token avoids re-verifying on every request and limits the value of a stolen token.

**Trade-offs.** The relay stores two pseudonymous identifiers (the quota key and the attested key),
which changes the privacy label. A token endpoint adds latency to the first request of a session.

**Alternatives considered.** Sending the signed transaction with every request (heavier, and a
leaked transaction is replayable until expiry). Sign in with Apple accounts (introduces accounts,
more personal data and the in-app account-deletion duty of Guideline 5.1.1(v)). App Attest only
(no per-user limits; one user could exhaust the workspace).

**Risks.** Devices that cannot use App Attest (no Secure Enclave) get no Claude tier; family-shared
subscriptions share one quota key (accepted, documented in the paywall text).

**Future scalability impact.** The same token can carry team or organisation plans and route to
more providers.

**Pillars served.** PIL-4, PIL-5.

## Decision: extensions use the on-device tier only

**Decision.** Code running in an extension (the Share and Action extensions, widgets, and App
Intents that run outside the app) never sends content to a cloud tier. Cloud tiers run only in the
app.

**Rationale.** Consent screens, the activity log and "ask before sending" confirmations live in the
app; an extension invoked from another app's context is the wrong place to make a data-sharing
decision. App Attest is also unavailable to most extension types, including share extensions
([Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)).

**Trade-offs.** Long documents summarised from the Action extension get an on-device, reduced-scope
answer with an "Open in PDF Algo Pro for more" action.

**Alternatives considered.** Cloud tiers in extensions after consent was given in the app (possible,
but hides the confirmation step inside another app's interface).

**Risks.** Users may expect parity; the reduced-scope label explains it.

**Future scalability impact.** Can be revisited per extension type with a consent design review.

**Pillars served.** PIL-5, PIL-7.

## Verification

| Property | Test or gate |
|---|---|
| No networking outside `Intelligence`, `Commerce`, `Telemetry` | `invariants` gate ([quality gates](process/quality-gates.md)) |
| No cloud request without a current consent record | Router unit tests with fake providers ([testing strategy](testing-strategy.md)) |
| Remote values can only disable cloud tiers | Flag-provider unit tests |
| Handoff and widget payloads carry no content | Unit tests on activity payloads; snapshot tests of redacted widgets |
| Derived data deleted with its source | Library tests for FR-LIB-006 |
| Redaction removes content and earlier versions | Redaction suite in the golden corpus ([threat model](threat-model.md)) |
| Relay stores no content | Relay integration test that inspects storage and logs after a request (V2) |
| Privacy manifest matches API use | `invariants` gate |
| Label matches behaviour | Release checklist (NFR-PRIV-002) |

## Open questions

- Hosting provider and region for the relay, and whether its edge logs IP addresses (decides an
  APP 8 and GDPR transfer question in the [compliance roadmap](compliance-roadmap.md)).
- Zero-data-retention terms with Anthropic, and whether they also cover App Attest requests
  (readiness blocker C4; shared with [AI governance](ai-governance.md)).
- Whether the V2 label marks Other User Content as linked (legal review).
- Whether signature sync through iCloud Keychain is offered at V1.
- Whether the chosen PDF SDK can guarantee no network access from document content (C1 spike).
