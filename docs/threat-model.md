# Threat model

The security threats to PDF Algo Pro, its users' documents and the business that ships it,
analysed with STRIDE across every asset and trust boundary: the device, the user's iCloud, Apple
Private Cloud Compute, Anthropic, the future relay, the App Store, and the GitHub and CI supply
chain. Each threat has a likelihood, an impact, its mitigations, the test or gate that verifies them
and the residual risk that is accepted. PRD requirement NFR-SEC-003 makes this register binding:
every mitigation here is traced to a test or gate.

Owner: Security · Reviewed: each milestone, when a trust boundary changes, and after every security incident

## Method

- **STRIDE** classifies each threat as Spoofing, Tampering, Repudiation, Information disclosure,
  Denial of service or Elevation of privilege
  ([Microsoft threat modelling: STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)).
- **Likelihood** (Low, Medium, High) and **impact** (Low, Medium, High, Critical) are qualitative
  judgements by the Security hat, not measured probabilities. They are re-rated at each review
  and whenever a real incident or new public research changes them.
- **Impact scale:** Critical means user content exposed at scale or code execution on devices;
  High means one user's content exposed or significant financial loss; Medium means degraded
  service or limited exposure; Low means inconvenience.
- **Residual risk** is what remains after the mitigations, and is accepted by the named hat.
- Data classes are from [data classification](data-classification.md); flows are from
  [privacy architecture](privacy-architecture.md). The mobile controls follow the OWASP Mobile
  Application Security Verification Standard as a reference checklist
  ([OWASP MASVS](https://mas.owasp.org/MASVS/)).

## Assets

| Asset | Class | Where |
|---|---|---|
| User documents, their text and OCR text | Confidential | Device, user's iCloud Drive |
| Annotations, form values, library metadata | Confidential | Device, user's CloudKit private database |
| Saved signatures, signing identities, document passwords | Restricted | Keychain |
| Content marked for redaction | Restricted | Working copy of the document |
| AI questions, excerpts and answers | Confidential | Device; PCC or Anthropic in transit and under their terms |
| Consent records and AI activity log | Confidential | Device |
| Entitlements and relay quota counters | Confidential | Device (StoreKit); relay (V2) |
| Credentials: relay API key, App Store Connect keys, signing | Restricted | Xcode Cloud, relay secret store |
| Source code, build pipeline, release artefacts | Public or internal | GitHub, Xcode Cloud, App Store Connect |
| Availability and cost of the cloud AI tier | Business | Anthropic workspace, relay |

## Trust boundaries

```
             untrusted input                       Apple services
  PDFs, shared files, URLs,  --TB1-->  +----------------------+ --TB3--> iCloud Drive, CloudKit
  pasted text, deep links              |    User's device     | --TB4--> Private Cloud Compute
                                       |  app | extensions    | --TB7--> App Store, StoreKit
  system surfaces: Spotlight, <--TB2-- |  Keychain | index    |
  widgets, Handoff, clipboard          +----------------------+
                                          |TB5 (beta)     |TB6 (V2)
                                          v               v
                                  Anthropic API <---- relay (pdf-algo-pro-backend)

  Supply chain (TB8): Swift packages and vendor SDK --> GitHub Actions --> Xcode Cloud
                      --> App Store Connect --> users' devices
```

| Boundary | Crosses between | Main concern |
|---|---|---|
| TB1 | Untrusted documents and links, and the app | Parsing, active content, prompt injection |
| TB2 | The app and system surfaces | Content appearing where the user did not expect it |
| TB3 | The device and the user's iCloud | Account compromise, configuration tampering |
| TB4 | The device and Apple PCC | Content leaving the device |
| TB5 | The device and Anthropic (TestFlight beta) | Content leaving the device; no per-user control |
| TB6 | The device, the relay and Anthropic (V2) | Abuse, cost, a new server holding secrets |
| TB7 | The device and the App Store | Entitlement integrity |
| TB8 | Dependencies, CI and distribution | Malicious code reaching every user |

## Threat register

`L` is likelihood and `I` is impact before mitigation; `Residual` is after mitigation.

### TB1: untrusted documents and input

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-01 | E, T | **Parser exploit in a malicious or malformed PDF** (fonts, images, streams). PDF parsing has carried actively exploited code-execution bugs on iOS ([CVE-2021-30860](https://nvd.nist.gov/vuln/detail/CVE-2021-30860)) | Medium | Critical | App sandbox; only `PDFEngine` parses documents; vendor SDK updates within `Assumption:` 14 days of a security release, validated by the dependency cadence in [operations](operations.md); a recent OS floor (iOS 26, [ADR-0023](adr/0023-ios-26-floor-built-with-xcode-27.md)), so system parser patches apply, with the release notes of both supported major versions watched; no `try!` or `as!` in parsing paths; parsing off the main thread with cancellation | Malformed and fuzz corpus in the golden PDF suite never crashes the app (NFR-SEC-002, [testing strategy](testing-strategy.md)); `invariants` gate; SDK version in the release checklist ([release management](release-management.md)) | Medium: zero-days in the SDK or system are outside our control |
| T-02 | E, I | **Active content: JavaScript, launch, form-submit and URI actions** that run code, phone home or reveal that a document was opened. PDFs can carry JavaScript ([JavaScript for Acrobat API Reference](https://opensource.adobe.com/dc-acrobat-sdk-docs/library/jsapiref/index.html)) and features that leak data to a network ([PDF Insecurity: insecure features](https://pdf-insecurity.org/)) | Medium | High | JavaScript disabled in the SDK configuration (decision below); no automatic network access from document content; links open only on tap after showing the full address; form submission not supported; SDK spike confirms these settings exist (C1) | Corpus documents with JavaScript, auto-open actions, remote resources and submit actions; UI test asserts no network request and no execution | Low |
| T-03 | D | **Resource exhaustion:** decompression bombs, very large page counts, deeply nested objects, huge images ([CWE-409](https://cwe.mitre.org/data/definitions/409.html)) | Medium | Medium | Streaming and tiled rendering; per-operation memory and time limits; cancellable work; OCR and indexing in bounded queues that respect thermal state ([ADR-0008](adr/0008-ocr-and-scanning.md)); a document that exceeds limits opens read-only with a message | Very large and bomb documents in the corpus; memory ceilings in [performance budgets](performance-budgets.md) | Low |
| T-04 | T, I | **Prompt injection through document content:** hidden text, images, metadata or fields instruct the model to mislead, exfiltrate or change behaviour ([OWASP LLM01: Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/)) | High | High | Documents are untrusted input (FR-AI-011); instructions separated from excerpts; no action tools, read-only tools only; routing decided by code, never by model output; model output never becomes a route ([AI governance](ai-governance.md)) | Prompt-injection red-team set, with link exfiltration, consent bypass and delimiter spoofing required to pass fully ([AI evaluation framework](ai-evaluation-framework.md), [ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md)) | Medium: injection cannot be eliminated, only contained |
| T-05 | I | **Exfiltration through rendered output:** an injected answer contains a link or text that tempts the user to send content elsewhere | Medium | High | Links in model output are plain text and not tappable; no remote images or previews rendered in answers ([AI governance](ai-governance.md)); extracted values exported as CSV are made inert, so a spreadsheet never runs one as a formula such as `=HYPERLINK(...)` (plan H2, [OWASP CSV injection](https://owasp.org/www-community/attacks/CSV_Injection)) | Red-team exfiltration category; snapshot tests of answer cards; CSV injection vectors in the Core tests | Low |
| T-06 | I | **Fake redaction:** a box drawn over text leaves the text, earlier revisions, metadata or annotations recoverable. Even after removal, surrounding glyph positions can leak redacted names ([Bland et al., Glyph Positions Break PDF Text Redaction](https://arxiv.org/abs/2206.02285)) | High | Critical | True redaction removes text, images, vectors, annotations, form values and metadata under the area (FR-EDIT-005); full rewrite, never an incremental save; the app offers to remove earlier iCloud file versions ([privacy architecture](privacy-architecture.md)); overlays are never labelled "redaction"; option to rasterise a redacted page; AI can suggest regions but the user confirms each ([AI governance](ai-governance.md)) | Redaction suite: search output text, content streams, metadata and all revisions for the removed strings; check no incremental-update sections remain; glyph-position test on the lines next to a redaction | Low to Medium: glyph-width inference on adjacent text unless the page is rasterised |
| T-07 | S | **Signed-PDF spoofing:** a manipulated document displays as validly signed (shadow, incremental-saving and wrapping attacks, [PDF Insecurity: signatures](https://pdf-insecurity.org/)) | Low | High | V1 does not claim to validate signatures; if validation is added, it uses the SDK's validator and shows "modified after signing" states; never shows a green tick for partial coverage | Signature corpus from published attack classes, added before any validation feature ships | Low |
| T-08 | S, T | **Malicious deep links** (`pdfalgopro://`) trigger actions or open unexpected content | Medium | Medium | The router only navigates; actions need explicit user intent ([ADR-0004](adr/0004-navigation-and-multi-window.md)) | Router unit tests with hostile URLs | Low |

### TB2: on-device storage and system surfaces

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-09 | I | **Leakage through logs**: titles, paths or text written to the system log ([CWE-532](https://cwe.mitre.org/data/definitions/532.html)) | Medium | High | Logging rules in [data classification](data-classification.md); `Logger` redacts dynamic strings by default ([Generating log messages](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)); `print` only in debug builds | `invariants` gate (`print`); review checklist ([code review guide](code-review-guide.md)); planned `invariants` rule on `.public` interpolation | Low |
| T-10 | I | **Leakage through crash reports and diagnostics**: content in assertion messages or exported bundles | Low | High | No user content in `fatalError`, `precondition` or error descriptions; crash data reaches us only through Apple from users who share diagnostics ([Acquiring crash reports](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)); the support summary is previewed by the user and excludes names and text (FR-SET-003) | Unit test of the support summary's fields; review checklist | Low |
| T-11 | I | **Spotlight leakage**: document text appears in system search to someone using an unlocked device, or survives deletion | Medium | Medium | Index created with a protection class; items removed on deletion (FR-LIB-006); setting to exclude text; excluded automatically when the app lock is on ([privacy architecture](privacy-architecture.md)) | Index lifecycle tests; app-lock integration test | Low |
| T-12 | I | **Widgets, Lock Screen and app switcher** show titles or pages | Medium | Medium | Widgets marked privacy-sensitive ([privacySensitive(_:)](https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:))); with app lock on, the app switcher snapshot is obscured | Snapshot tests of redacted widgets and the obscured snapshot | Low |
| T-13 | I | **Handoff, clipboard and drag and drop** carry content to other devices or apps | Low | Medium | Handoff carries a document identifier and page only, never publicly indexable ([isEligibleForPublicIndexing](https://developer.apple.com/documentation/foundation/nsuseractivity/iseligibleforpublicindexing)); copy and drag are always user actions | Activity payload unit test | Low |
| T-14 | I, T | **Share extension data exposure**: files left in the shared App Group container, or processed with weaker protection, or sent to a network | Medium | Medium | The extension only copies the file into the App Group container with class C protection; the app imports and deletes the staging copy; no network in extensions; cloud tiers never run in extensions (decision in [privacy architecture](privacy-architecture.md)) | Extension tests: staging directory empty after import; `invariants` networking rule | Low |
| T-15 | I | **Lost or stolen device** | Medium | High | iOS Data Protection (documents class C, restricted data class A or Keychain this-device-only, NFR-SEC-001); optional Face ID or Touch ID app lock (FR-SET-002); Keychain items do not migrate to other devices ([kSecAttrAccessibleWhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)) | Unit tests that read protection attributes | Medium: depends on the user's passcode and on the device being unlocked since restart |
| T-16 | I | **Over-sharing in support reports** | Low | Medium | Summary shown in full before sending; no document names, text or consent history ([privacy architecture](privacy-architecture.md)) | Unit test of summary contents | Low |

### TB3: the user's iCloud and remote configuration

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-17 | S, I | **Compromise of the user's Apple Account** exposes documents in iCloud Drive | Low | High | Outside the app's control; restricted data (signatures, passwords) is not synced by default; the privacy centre explains Advanced Data Protection, which makes iCloud Drive end to end ([iCloud data security overview](https://support.apple.com/en-us/102651)) | Settings copy review | Medium: user-controlled |
| T-18 | T, E | **Remote configuration tampering**: a user or attacker writes to the CloudKit public database, which every user can read and where users can write records they create ([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)) | Low | High | Configuration record types writable only by the developer role; values validated and bounded; a remote value can only switch cloud tiers off, never start a data flow ([engineering playbook](engineering-playbook.md)); last known good cache | CloudKit security-role check and drill in the [kill-switch runbook](process/runbooks/kill-switch.md); flag-parser unit tests | Low |
| T-19 | T, D | **Sync conflicts or identity drift** lose or duplicate edits | Medium | Medium | Coordinated, atomic writes; `NSFileVersion` conflict handling; document-identity spike ([ADR-0005](adr/0005-document-storage-and-identity.md)) | Save-integrity test (NFR-REL-002) | Low |

### TB4 and TB5: AI providers

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-20 | I | **Content sent to a cloud tier without valid consent** (a routing bug or a failover path) | Low | Critical | The router checks a current consent record before every request; failover only moves towards the device ([ADR-0021](adr/0021-ai-provider-routing-and-failover.md)); remote values cannot enable a tier | Router unit tests for every consent and failover state; AI SEV1 definition ([AI governance](ai-governance.md)) | Low |
| T-21 | I | **Retention or breach at Anthropic**: inputs kept up to 30 days by default and flagged content up to two years ([API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)) | Low | High | Opt-in consent that states retention; minimal excerpts, never the file; no server-side tools; zero-data-retention and processing terms before general availability (C4) | Consent text review; contract review in the [compliance roadmap](compliance-roadmap.md) | Medium: a processor breach is outside our control |
| T-22 | I | **Exposure at Private Cloud Compute** | Low | High | Apple's design keeps data only for the request and excludes privileged access ([Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/)); opt-in consent | Consent tests | Low |
| T-23 | T, R | **Generated content taken as the document's own text** (hallucination, or an injected false summary) | Medium | High | Page citations, "not found" states, persistent AI labels, AI-authored annotations marked "PDF Algo Pro AI" ([AI governance](ai-governance.md)) | Citation accuracy and grounding thresholds ([AI evaluation framework](ai-evaluation-framework.md)) | Medium |

### TB5 and TB6: Claude access, the relay and keys

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-24 | D, E | **Relay abuse and cost exhaustion**: scripted clients, heavy users or a bug spend the workspace budget | High | High | App Attest assertions before a relay token is issued ([Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)); entitlement verified from the signed transaction; per-subscriber quotas and token budgets; rate limits; workspace spend limits below the tier cap ([Rate limits](https://platform.claude.com/docs/en/api/rate-limits)); kill switch | Relay load and abuse tests (V2); spend-alert drill in [operations](operations.md); [kill-switch runbook](process/runbooks/kill-switch.md) | Medium |
| T-25 | S | **Beta tokens without identity**: during the App Attest beta, any genuine install can spend the workspace, because tokens carry no end-user identity ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)) | Medium | Medium | Claude tier limited to TestFlight testers; separate workspace with a low spend limit; integration revocable ([AI governance](ai-governance.md)) | Beta readiness checklist | Low |
| T-26 | S, E | **Relay token theft or replay** from a compromised device | Low | Medium | Short-lived tokens bound to the attested key; assertion counters reject replays; quota per subscriber | Relay integration tests with replayed and expired tokens | Low |
| T-27 | I, E | **API key extraction from the app binary** | High if a key shipped | High | No provider key ever ships: App Attest in beta, relay-held key in production ([ADR-0009](adr/0009-tiered-ai-and-consent.md)); the only embedded secret-like value is the PDF SDK licence key, bound to the bundle identifier (C1) | `secrets` job and push protection; release checklist scans the archive's strings for key patterns ([release management](release-management.md)) | Low |
| T-28 | I, T | **Relay compromise** exposes content in transit or the API key | Low | Critical | Content held in memory only; least-privilege deployment; secrets in the host's secret store; dependency and code scanning as for the app; incident plan | Relay security review before V2; [incident response runbook](process/runbooks/incident-response.md) | Medium until the relay has run in production |

### TB7: the App Store and entitlements

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-29 | S, T, E | **Entitlement or subscription bypass**: a patched app on a jailbroken device unlocks Pro, or forged purchase data | Medium | Medium | StoreKit 2 verified transactions on the device ([VerificationResult](https://developer.apple.com/documentation/storekit/verificationresult)); features with a marginal cost (cloud AI) enforced on the server with the App Store Server API ([App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)); no client-side "Pro" flag in storage | StoreKit test sessions in `Commerce` unit tests; relay entitlement tests (V2) | Medium for on-device features (accepted: no marginal cost); Low for cloud features |

### TB8: supply chain

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-30 | T, E | **Compromised SDK or Swift package** ships malicious code to every user ([MITRE ATT&CK T1195.001](https://attack.mitre.org/techniques/T1195/001/)) | Low | Critical | ADR per third-party SDK with privacy manifest, telemetry, licence and exit plan; pinned versions and `Package.resolved` drift gate; binary targets pinned by checksum; vendor SDK confined to `PDFEngine` | `dependency-review` workflow ([About dependency review](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-dependency-review)); `invariants`; ADR review | Medium |
| T-31 | T, I, E | **CI compromise**: a hijacked third-party action exfiltrates secrets or alters builds, as in the 2025 `tj-actions/changed-files` compromise ([CISA](https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-tj-actionschanged-files-cve-2025-30066-and-reviewdogaction)) | Medium | High | Actions pinned to commit SHAs; read-only default token permissions; no signing material in GitHub, signing in Xcode Cloud ([ADR-0013](adr/0013-ci-cd.md), [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)); CodeQL for workflows | `codeql` job; ruleset review ([github governance](github-governance.md)) | Low |
| T-32 | T | **Typosquatting**: a look-alike package or repository URL added by mistake or by a coding agent | Medium | High | New dependencies need an ADR and review; dependency sources limited to named publishers; coding agents follow the same review ([engineering playbook](engineering-playbook.md)) | `dependency-review`; review checklist | Low |
| T-33 | S, E | **Developer account or App Store Connect compromise** leads to a malicious release | Low | Critical | Two-factor authentication on every account; least-privilege roles and scoped keys; human approval for every release; phased release that can be paused ([release management](release-management.md)) | Release checklist; access review each milestone | Low |
| T-34 | I | **Secrets or private material committed to the public repository** | Medium | High | `secrets` job and push protection; Team ID injected at build time ([ADR-0015](adr/0015-identifiers-and-signing.md)); public-safety rules ([repository standards](repository-standards.md)) | `secrets` job; docs review | Low |

### Repudiation

| ID | STRIDE | Threat | L | I | Mitigations | Verified by | Residual |
|---|---|---|---|---|---|---|---|
| T-35 | R | **A user disputes having consented** to a cloud tier | Low | Medium | Versioned, timestamped consent history on the device, visible to the user; consent version sent to the relay (V2) ([privacy architecture](privacy-architecture.md)) | Consent record unit tests | Medium: whether device-local records are sufficient evidence is a legal review item ([compliance roadmap](compliance-roadmap.md)) |

## Gates and tests that verify this register

| Gate or suite | Threats covered | Where defined |
|---|---|---|
| `invariants` (no real PDFs, networking only in three packages, no `print`, no `try!`/`as!`, SDK import boundary, privacy manifest) | T-01, T-09, T-14, T-30 | [Quality gates](process/quality-gates.md) |
| `secrets` job and push protection | T-27, T-34 | [Quality gates](process/quality-gates.md) |
| `dependency-review` and `codeql` | T-30, T-31, T-32 | [ADR-0013](adr/0013-ci-cd.md) |
| Golden PDF corpus: malformed, fuzzed, JavaScript and active-content, bombs, very large | T-01, T-02, T-03 | [Testing strategy](testing-strategy.md) |
| Independent validation of saved files: `pdf-validation` runs qpdf on every corpus file the engine saves (advisory for two weeks) | T-01 | [Testing strategy](testing-strategy.md) |
| Redaction verification suite | T-06 | [Testing strategy](testing-strategy.md) |
| AI evaluation: red-team, citation, grounding sets | T-04, T-05, T-23 | [AI evaluation framework](ai-evaluation-framework.md) |
| Router, consent and flag unit tests | T-08, T-18, T-20, T-35 | [Testing strategy](testing-strategy.md) |
| Snapshot tests (widgets, answer cards, obscured snapshot) | T-05, T-12 | [Testing strategy](testing-strategy.md) |
| Performance and memory budgets | T-03 | [Performance budgets](performance-budgets.md) |
| Release checklist (SDK versions, archive string scan, label check) | T-01, T-27, T-33 | [Release management](release-management.md) |
| Relay security review and abuse tests (V2) | T-24, T-26, T-28 | Relay repository, when created |
| Kill-switch and spend-alert drills | T-18, T-24 | [Kill-switch runbook](process/runbooks/kill-switch.md), [operations](operations.md) |

Tests marked "proposed" or "V2" are added before the feature they protect ships; the release
manager confirms them at the release pull request.

## Residual risk acceptance

The Security hat accepts the residual risks above at each milestone review. Risks rated Medium
residual (T-01, T-04, T-15, T-17, T-21, T-23, T-24, T-28, T-29, T-30, T-35) are re-examined at
every review, and any of them becomes a release blocker if an incident or new research raises it.
Security reports go through private vulnerability reporting or the security mailbox and are handled
under the [incident response runbook](process/runbooks/incident-response.md).

## Decision: disable PDF JavaScript and automatic network actions entirely

**Decision.** PDF Algo Pro never executes JavaScript in PDFs and never lets document content open a
network connection by itself.

**Rationale.** Active content is a large attack surface with little value to the target users;
calculated form fields are the main loss. Blocking it also stops "document opened" tracking beacons,
which would break the privacy promise.

**Trade-offs.** Some interactive forms that rely on scripts (calculated totals, validation) behave
as static forms; the app says so when a document contains scripts.

**Alternatives considered.** Sandboxed script execution with a restricted API (still a large
surface, and depends on the SDK's engine). Asking the user per document (people approve prompts
they do not understand).

**Risks.** Business users with scripted forms may need another app for those forms; tracked through
support requests.

**Future scalability impact.** A narrowly scoped, calculation-only mode could be added for team
editions after a dedicated threat review.

**Pillars served.** PIL-5, PIL-2.

## Decision: enforce entitlements on the server only where there is marginal cost

**Decision.** On-device Pro features rely on StoreKit 2's verified transactions on the device; cloud
AI, which costs money per request, is enforced by the relay.

**Rationale.** A patched app on a jailbroken device can bypass any client check, so client-side
hardening beyond StoreKit's verification buys little; the cost risk sits only where requests cost
money.

**Trade-offs.** Some on-device Pro features can be pirated on modified devices.

**Alternatives considered.** Server verification for every feature (needs a server call on launch,
breaks offline use and adds a data flow). Obfuscation and jailbreak detection (brittle, and
detection itself collects device signals).

**Risks.** Revenue loss from piracy, judged small relative to the privacy and offline cost of the
alternatives; reviewed with App Store Server Notifications data after launch.

**Future scalability impact.** The relay can take on further server-side checks if a future
feature carries marginal cost.

**Pillars served.** PIL-5, PIL-6, PIL-7.

## Open questions

- Whether the chosen PDF SDK can disable JavaScript and every content-initiated network action, and
  whether it performs any network call (licence or telemetry) at all (C1 spike).
- Relay hosting, deployment and secret-store design (V2), including whether it lives in the reserved
  `pdf-algo-pro-backend` repository.
- Whether a rasterise-after-redaction option is on by default for pages with redactions.
- A fuzzing approach for the vendor SDK that fits CI time (continuous fuzzing outside pull requests
  is the likely answer).
