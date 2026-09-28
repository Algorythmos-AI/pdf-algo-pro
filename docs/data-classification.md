# Data classification

How PDF Algo Pro applies the organisation's four data classes (public · internal · confidential ·
restricted) to every kind of data the product and its business handle, and the handling rules
that follow from each class: where the data may be stored, which iOS Data Protection class and
encryption it uses, whether it may be shared, what may be logged, how long it is kept and who can
access it. Data flows per feature are in [privacy architecture](privacy-architecture.md); the
threats against each class are in the [threat model](threat-model.md); legal obligations are in the
[compliance roadmap](compliance-roadmap.md).

Owner: Privacy · Reviewed: each milestone, and whenever a new data type, storage location or recipient is added

## How to use this document

- **Every new data flow names its class** in the pull request, as the Definition of Ready checklist
  requires ([engineering playbook](engineering-playbook.md)). A data type not listed here is treated
  as **restricted** until this document is updated.
- **The class is decided by the most sensitive thing the data could contain,** not by what it
  usually contains. A PDF title is usually harmless, but "Divorce settlement draft" is not.
- **Classes apply everywhere the data exists:** on the device, in the user's iCloud, at an AI
  provider, in the relay, in a support mailbox, in git and in CI.
- The organisation defines the class names (organisation standard); the definitions and examples
  below are this product's application of them.

## The four classes

| Class | Meaning for PDF Algo Pro | Harm if disclosed | Typical examples |
|---|---|---|---|
| **Public** | Intended for anyone; published on purpose | None | Published documentation, source code while the repository is public, App Store metadata, remote configuration records, the synthetic test corpus |
| **Internal** | Operational information that is not published but contains no user content and cannot reasonably identify a person | Low: embarrassment or minor operational risk | Aggregated telemetry, crash and performance diagnostics, redacted app logs, CI logs, non-sensitive preferences |
| **Confidential** | All user content and personal information, and business-sensitive information | Significant: privacy harm to a user, or commercial harm to the business | Documents and their text, annotations, OCR text, AI questions and answers, library metadata, purchase data, support correspondence, business planning documents |
| **Restricted** | Data whose disclosure enables impersonation, fraud, account takeover or irreversible loss | Severe | Saved signatures, signing keys and certificates, document passwords, credentials and API keys, unfixed vulnerability details, content the user has marked for redaction |

## Handling rules by class

| Rule | Public | Internal | Confidential | Restricted |
|---|---|---|---|---|
| **Where it may be stored** | Anywhere | The device; App Store Connect; CI; the relay's operational store (after it exists) | User content: only the device, the user's own iCloud, and an AI provider the user consented to. Business-confidential material: only the private companion repository ([ADR-0019](adr/0019-public-private-documentation-split.md)) and the maintainer's managed devices | The Keychain on the device; Xcode Cloud or relay secret stores for credentials; never in git, never in files synced by the app |
| **iOS Data Protection class** (on device) | Not sensitive; default class is acceptable | `NSFileProtectionCompleteUntilFirstUserAuthentication` (class C) | Class C as the minimum, because background indexing and OCR must read documents while the device is locked after first unlock; class A (`NSFileProtectionComplete`) where no background access is needed | Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, or files with `NSFileProtectionComplete` (class A) |
| **Encryption** | TLS in transit | Data Protection at rest; TLS in transit | Data Protection at rest; iCloud encryption in transit and on server, end to end when the user enables Advanced Data Protection; CloudKit encrypted fields for metadata; TLS 1.2 or later to any provider | As confidential, plus Keychain or secret-store encryption; iCloud Keychain (end to end) only if the user turns on signature sync |
| **Sharing** | Anyone | Algorythmos hats and contracted processors, for operating the product | Only by the user's own action (share sheet, export, drag out), or to an AI provider after consent that names the provider and the data. Business-confidential material is never published | Never shared by the app. Never sent to any AI tier, never included in telemetry or diagnostics |
| **Logging** | Allowed | Allowed through `Logger`, with dynamic values private by default | **Never logged.** Logs may contain counts, durations, error categories, prompt identifiers and random local identifiers only | **Never logged,** not even redacted or hashed |
| **Retention** | As long as useful | Per the retention schedule below | Controlled by the user; derived copies deleted with their source | Until the user deletes it; credentials rotated on the schedule in [operations](operations.md) |
| **Who can access** | Anyone | The maintainer, in the hat that needs it | The user. Algorythmos sees user content only when the user sends it (for example a support email). Business-confidential: the maintainer | The user (on device), or the named hat for a credential, with two-factor authentication on every account that holds one |

Sources for the platform mechanisms: Data Protection classes are defined in
[Apple Platform Security: Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web);
the Keychain attribute keeps items on the device and out of migrations to a new device
([kSecAttrAccessibleWhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly));
iCloud encrypts third-party app data in transit and on server, and Advanced Data Protection makes
CloudKit encrypted fields and assets end to end, while Passwords and Keychain are always end to end
([iCloud data security overview](https://support.apple.com/en-us/102651)); `Logger` redacts
interpolated dynamic strings unless marked public
([Generating log messages from your code](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)).

## Data inventory

"Leaves the device" means leaves it by the app's action; files the user shares or exports leave by
the user's action.

### User content

| Data | Class | Lives in | Protection at rest | Leaves the device | Retention | Access |
|---|---|---|---|---|---|---|
| User documents (PDF files) | Confidential | iCloud Drive ubiquity container, or the app's local container when iCloud is off ([ADR-0005](adr/0005-document-storage-and-identity.md), FR-LIB-001) | Class C (NFR-SEC-001) | To the user's iCloud Drive only | Until the user deletes; Recently Deleted for 30 days ([iOS architecture review](ios-architecture-review.md)) | User |
| Document text (text layer, extracted text) | Confidential | Inside the PDF; excerpts in the local search index | Class C | Excerpts to a consented AI tier only | Deleted with the document (FR-LIB-006) | User |
| OCR text | Confidential | Invisible text layer in the PDF; local index | Class C | As document text | As document text | User |
| Camera captures during scanning | Confidential | Temporary directory until the PDF is assembled | Class A | No | Deleted when the scan is saved or cancelled | User |
| Annotations, comments, form field values | Confidential | Inside the PDF as standard annotations and fields (FR-ANN-001) | Class C | With the file only | With the document | User |
| Content marked for redaction, before redaction is applied | **Restricted** | Inside the working copy of the PDF | Class C (the file's class) | Never to an AI tier: marked regions are excluded from AI context | Removed by the redaction itself (FR-EDIT-005) | User |
| Saved ink signatures | **Restricted** | Keychain (FR-EDIT-004) | `WhenUnlockedThisDeviceOnly`; iCloud Keychain only if the user turns on sync | Only through iCloud Keychain, if the user turns it on | Until the user deletes | User |
| Digital signing identities (if the chosen SDK supports certificate signing) | **Restricted** | Keychain | `WhenUnlockedThisDeviceOnly` | Never | Until the user deletes | User |
| Document passwords | **Restricted** | Memory only; Keychain only if the user asks to remember one | `WhenUnlockedThisDeviceOnly` | Never | Session, or until the user removes it | User |
| AI questions, instructions and the excerpts sent with them | Confidential | Memory during the request | n/a | To Private Cloud Compute or Anthropic only after consent ([AI governance](ai-governance.md)) | Not stored by the app; provider retention in [privacy architecture](privacy-architecture.md) | User; provider under its terms |
| AI answers, summaries and extractions (cached) | Confidential | Local library index, not synced | Class C | Only when the user copies, shares or exports | Deleted with the document; cloud-tier answers can be deleted when consent is revoked | User |
| AI activity log (cloud requests: time, feature, provider, document title, pages sent, tokens) | Confidential | App container, not synced | Class C | No | `Assumption:` 30 days, as set in [AI governance](ai-governance.md) | User |

### Library and app data

| Data | Class | Lives in | Protection at rest | Leaves the device | Retention | Access |
|---|---|---|---|---|---|---|
| Library metadata the user authors: folders, tags, favourites, reading position | Confidential (titles and tags can reveal sensitive facts) | SwiftData store synced through the CloudKit private database ([ADR-0006](adr/0006-swiftdata-persistence.md)) | Class C; CloudKit encrypted fields for names and tags | To the user's CloudKit private database, which the developer cannot see ([privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)) | Until the user deletes the item or the app's iCloud data | User |
| Derived data: search index, thumbnails, embeddings, extraction caches | Confidential | Local store and Caches directory; Core Spotlight index with a protection class ([init(name:protectionClass:)](https://developer.apple.com/documentation/corespotlight/cssearchableindex/init(name:protectionclass:))) | Class C | No | Rebuildable; deleted with the source document; excluded from device backup ([Optimizing your app's data for iCloud backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)) | User |
| Preferences (theme, default tools, onboarding intent, AI features shown or hidden) | Internal | `UserDefaults` (app and App Group) | Class C | No | Until changed or the app is deleted | User |
| Consent records (provider, consent-text version, grant and revocation times, app version) | Confidential (integrity matters as much as secrecy) | App container, per device, not synced ([AI governance](ai-governance.md)) | Class C | No | Until the app is deleted; history kept for the user to see | User |
| Remote configuration and kill-switch records | Public | CloudKit public database, readable by every user of the app ([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)); cached on device | Default | Read from Apple only; nothing sent | Last known good value cached | Anyone can read; only the developer role writes |
| On-device diagnostics (MetricKit payloads, error counters) | Internal | App container | Class C | Only inside a support email the user reviews and sends | `Assumption:` 30 days on device, enough for a support case; validated with the first support cases | User; Algorythmos only if sent |
| App logs (`Logger`) | Internal | System log | System-managed | No | System-managed | User and anyone with device log access; hence the logging rules |

### Commerce, operations and support

| Data | Class | Lives in | Protection at rest | Leaves the device | Retention | Access |
|---|---|---|---|---|---|---|
| Purchase and entitlement data (signed transactions, original transaction identifier, product, expiry) | Confidential | Device (StoreKit); after general availability, the relay verifies transactions | Apple-managed on device | To the relay (V2) as a signed transaction; to Apple always | On device: StoreKit-managed. Relay: see the retention schedule | User; relay (hash only) |
| Relay quota counters (hash of the original transaction identifier, credits used in the period) | Confidential (pseudonymous) | Relay store (V2) | Provider encryption at rest | n/a (server side) | Current and previous billing period, `Assumption:` validated in the DPIA ([compliance roadmap](compliance-roadmap.md)) | AI, Security |
| Relay operational logs (request identifier, status, latency, token counts, error class; never content) | Internal | Relay logging (V2) | Provider encryption | n/a | `Assumption:` 30 days, validated in the DPIA | Security |
| Aggregated telemetry (after on-device aggregation, no identifiers) | Internal | Relay store (V2), opt-in only ([ADR-0017](adr/0017-privacy-first-telemetry.md)) | Provider encryption | Yes, only when the user opts in | `Assumption:` 13 months, to allow a year-on-year comparison; confirmed in the DPIA and legal review | Product |
| Crash diagnostics in App Store Connect and Xcode Organizer | Internal | Apple; from users who share diagnostics and from TestFlight testers ([Acquiring crash reports](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)) | Apple-managed | Collected by Apple | Apple-managed | Maintainer |
| Support correspondence and diagnostics bundles users send (FR-SET-003) | Confidential | Company support mailbox | Mail provider encryption | Sent by the user | `Assumption:` deleted 12 months after the case closes; validated in legal review | Maintainer |
| TestFlight tester names and email addresses | Confidential | App Store Connect | Apple-managed | n/a | Removed when a tester leaves the programme | Release |
| App Store Server Notifications V2 (V2, relay) | Confidential | Relay | Provider encryption | n/a | As relay quota counters | AI, Security |

### Engineering and business

| Data | Class | Lives in | Handling |
|---|---|---|---|
| Source code, public documentation, prompt templates | Public while the repository is public (organisation decision D-002); internal if it becomes private | `pdf-algo-pro` repository | Nothing in the repository may be more sensitive than public; the `secrets` job and review enforce it |
| Synthetic golden PDF corpus, OCR corpus, AI evaluation and red-team sets | Public | `Tests/Fixtures/Synthetic/` and the evaluation sets | Synthetic or licence-clean only; the `invariants` gate rejects PDFs anywhere else ([testing strategy](testing-strategy.md)) |
| CI logs and build artefacts | Internal | GitHub Actions, Xcode Cloud | No secrets printed; logs are visible to anyone who can see the public repository's Actions runs, so they are treated as public in practice |
| Business documents: pricing, revenue model, unit economics, financial model, analytics targets, competitive detail | Confidential | Confidential editions only in the private companion repository; redacted editions are public, at the same paths in this repository ([ADR-0019](adr/0019-public-private-documentation-split.md)) | Confidential detail is never copied into a public edition |
| Apple Team ID, Apple account facts, company records | Confidential | Xcode Cloud settings, private records | Injected at build time, never committed ([ADR-0015](adr/0015-identifiers-and-signing.md)) |
| Credentials: Anthropic API keys (relay only), App Store Connect and App Store Server API keys, relay secrets, CloudKit server-to-server keys, GitHub tokens | **Restricted** | Xcode Cloud secret environment variables, the relay's secret store, the maintainer's password manager | Never in git or in the app binary; rotated on schedule and on suspicion; two-factor authentication on every account that holds them |
| PDF SDK licence key | Confidential | Injected at build time; necessarily present in the shipped binary | Bound to the bundle identifier by the vendor (confirmed in the SDK spike, readiness blocker C1); never in git |
| App Attest client identifier for the Claude package | Internal | Shipped in the binary (it identifies the app, not a secret) | Revocable in the provider console ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)) |
| Unfixed vulnerability reports and security findings | **Restricted** | GitHub private vulnerability reporting, the security mailbox | Never in public issues; disclosed only after a fix ([threat model](threat-model.md)) |

## Special rules

1. **User content never reaches Algorythmos systems by default.** The relay (V2) passes AI requests
   through in memory and never writes content to disk or logs; telemetry carries only allow-listed
   aggregates ([ADR-0017](adr/0017-privacy-first-telemetry.md)); support material arrives only when
   the user sends it.
2. **Restricted data never goes to any AI tier,** including the on-device model's context:
   signatures, passwords and redaction-marked regions are removed before a prompt is built
   ([prompt management](prompt-management.md)).
3. **Confidential user content goes to a cloud AI tier only with consent** that names the provider
   and the data (App Review Guideline 5.1.2(i),
   [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/);
   NFR-PRIV-001).
4. **Logging.** Log static messages and numbers. Any interpolated string uses `Logger`'s default
   private redaction; `.public` is allowed only for values in the public or internal class (a prompt
   identifier, an error category). Never interpolate a document title, file name, path, question,
   answer, extracted value or tag. `fatalError`, `precondition` and error descriptions follow the
   same rule, because their text can reach crash reports. Logging personal data is a known weakness
   ([CWE-532: Insertion of Sensitive Information into Log File](https://cwe.mitre.org/data/definitions/532.html)).
5. **Screenshots, bug reports and pull requests** never contain real documents; reproduction uses the
   synthetic corpus.
6. **Derived data follows its source.** Deleting a document deletes its thumbnails, index entries,
   embeddings, extractions and cached answers (FR-LIB-006).
7. **Downgrading a class** (for example aggregating telemetry until it is internal) needs a written
   reason in the pull request and the Privacy hat's review.

## Retention schedule

| Data | Retention | Basis |
|---|---|---|
| Documents in Recently Deleted | 30 days, then permanent deletion | [iOS architecture review](ios-architecture-review.md) |
| Documents deleted from iCloud Drive | iCloud keeps them recoverable for 30 days | [Recover deleted files on iCloud.com](https://support.apple.com/guide/icloud/recover-deleted-files-mmae56ea1ca5/icloud) |
| Derived data and caches | Until the source is deleted; rebuildable at any time | Special rule 6 |
| AI activity log | `Assumption:` 30 days | [AI governance](ai-governance.md) |
| Consent records | Until the app is deleted | [AI governance](ai-governance.md) |
| On-device diagnostics | `Assumption:` 30 days | Table above |
| Relay content | None: never stored | [Privacy architecture](privacy-architecture.md) |
| Relay quota counters | `Assumption:` current and previous billing period | Needed for credits and billing disputes |
| Relay operational logs | `Assumption:` 30 days | Incident investigation |
| Aggregated telemetry | `Assumption:` 13 months | Year-on-year comparison |
| Support correspondence | `Assumption:` 12 months after the case closes | Follow-up and complaints |

Every `Assumption:` in this schedule is confirmed or changed by the data protection impact
assessment and legal review listed in the [compliance roadmap](compliance-roadmap.md).

## Decision: all user content is confidential, with restricted elements

**Decision.** Every document, and everything derived from or written about a document, is
confidential regardless of what it appears to contain. Signatures, signing identities, passwords and
content marked for redaction are restricted.

**Rationale.** The app cannot know what a document contains, and inferring sensitivity by scanning
content would itself be processing of that content. Treating everything as confidential makes the
safe path the default and keeps the rules simple enough to enforce in review and gates.

**Trade-offs.** Useful diagnostics (for example which document failed to open) cannot include a
title or name; support relies on the user attaching a document when they choose to.

**Alternatives considered.** Automatic sensitivity detection (processing content to classify it,
error-prone, and a new privacy risk). Classifying by user-chosen labels (users rarely label).
Treating all documents as restricted (would forbid cloud AI and iCloud sync, which users choose).

**Risks.** Over-broad classes lead to exceptions being argued case by case: exceptions go through
the Privacy hat and the decision register.

**Future scalability impact.** Team or enterprise editions can add organisation-defined labels on
top without weakening this floor.

**Pillars served.** PIL-5 Privacy.

## Decision: Data Protection class C for documents, class A and the Keychain for restricted data

**Decision.** Documents, the library index and derived data use
`NSFileProtectionCompleteUntilFirstUserAuthentication`; restricted data uses the Keychain with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` or class A files; the optional app lock (FR-SET-002)
adds Face ID or Touch ID at the interface.

**Rationale.** Background OCR, indexing and thumbnailing ([ADR-0008](adr/0008-ocr-and-scanning.md),
[ADR-0010](adr/0010-search.md)) must read documents while the device is locked; class A keys are
discarded shortly after the device locks
([Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)).
Restricted items have no background need, so they get the strongest class.

**Trade-offs.** Documents on a device that has been unlocked once since restart are readable by
code running on that device until it restarts; this is the same protection level most document
apps rely on.

**Alternatives considered.** Class A for documents (breaks background work and file-provider
access while locked). Class B, `CompleteUnlessOpen` (designed for files written in the background,
not for reading existing files). An app-specific encryption layer (duplicates Data Protection and
would break Files integration).

**Risks.** A future feature that needs locked-state access to a restricted item: it gets its own
review rather than a weaker default.

**Future scalability impact.** The same classes apply on iPad and visionOS; the Mac uses FileVault
and the login boundary instead, as Apple Platform Security describes (same source).

**Pillars served.** PIL-5, PIL-6.

## Verification

| Rule | Verified by |
|---|---|
| No real documents in git | `invariants` gate: PDFs only under `Tests/Fixtures/Synthetic/` ([quality gates](process/quality-gates.md)) |
| No secrets in git | `secrets` job (organisation reusable secret scan) and push protection |
| Networking only in `Intelligence`, `Commerce`, `Telemetry` | `invariants` gate |
| No `print` outside debug builds | `invariants` gate |
| Protection classes as specified | Unit tests that read the file protection attribute of created files and Keychain item attributes ([testing strategy](testing-strategy.md)) |
| No user content in logs | Code review checklist ([code review guide](code-review-guide.md)); the planned `invariants` rule that flags `.public` on interpolated strings ([quality gates](process/quality-gates.md#the-invariants-rules)) |
| Restricted data excluded from AI context | Unit tests on the prompt builder; red-team cases in the [AI evaluation framework](ai-evaluation-framework.md) |
| Derived data deleted with its source | Library tests for FR-LIB-006 |
| Privacy label matches this inventory | Release checklist (NFR-PRIV-002, [release management](release-management.md)) |

## Open questions

- Whether signature sync through iCloud Keychain is offered at V1 or later, and how the user is told
  what it means.
- Whether the chosen PDF SDK supports certificate-based digital signatures at V1 (readiness blocker
  C1); if not, the signing-identity row is dormant.
- The mail provider and region for the support mailbox, and whether it is recorded as a processor in
  the record of processing ([compliance roadmap](compliance-roadmap.md)).
- Hosting provider and region for the relay (V2), which decide where relay data is stored.
