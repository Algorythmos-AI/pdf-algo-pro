# AI governance

How PDF Algo Pro uses language models responsibly: the principles its intelligence features follow,
how AI output is labelled, how consent works for each tier, why the model can never act on its own,
how cost is bounded, how the app fails over between providers and works offline, how user content
is protected, and who is accountable. It turns the tiered design in
[ADR-0009](adr/0009-tiered-ai-and-consent.md) and the routing rules in
[ADR-0021](adr/0021-ai-provider-routing-and-failover.md) into operating rules. Quality measurement
lives in the [AI evaluation framework](ai-evaluation-framework.md), prompt handling in
[prompt management](prompt-management.md) and tier choice in [model selection](model-selection.md).

Owner: AI · Reviewed: quarterly, after any AI incident, and before any provider, model or consent change

## Scope

This document governs every feature in pillar PIL-4 AI Document Intelligence and every place where
a language model touches a document:

- **Features:** Chat with PDF (questions with page citations), Summarise Document, Extract Data with
  AI, Analyse Contract, translation of answers and text, OCR assistance with page images, and the App
  Intents that expose them to Siri, Shortcuts and Spotlight.
- **Tiers:** the on-device `SystemLanguageModel`, Apple's `PrivateCloudComputeLanguageModel`
  (Private Cloud Compute, PCC) and Claude through Anthropic's `ClaudeForFoundationModels` package,
  all driven through one `LanguageModelSession` API
  ([What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)).
- **Out of scope:** Vision OCR on its own (deterministic, on device; see
  [ADR-0008](adr/0008-ocr-and-scanning.md)) and system Writing Tools, which Apple operates.

## Principles

Each AI principle applies one or more [founder principles](founder-principles.md). When an AI
decision trades a principle away, the ADR or decision-register entry names it.

| # | AI principle | Founder principle | In practice |
|---|---|---|---|
| A1 | **On device first.** The most private tier that meets the quality bar answers. | 1 Privacy is the product · 3 Offline by default | The router picks the lowest qualified tier ([model selection](model-selection.md)); failover only moves towards the device |
| A2 | **Consent before content leaves the device.** Every cloud tier is opt-in, names the provider and the data, and can be revoked. | 1 Privacy is the product | Consent model below; App Review Guideline 5.1.2(i) |
| A3 | **Show the work.** Answers about a document cite the pages they come from. | 4 AI must show its work | Page-citation chips; uncited claims are not shown as facts |
| A4 | **Say when unsure.** The model reports "not found in this document" rather than guessing. | 4 AI must show its work | Structured output has an explicit "not found" state; refusal correctness is an evaluation metric |
| A5 | **The person decides; the model proposes.** No autonomous actions. | 4 AI must show its work · 6 Quality over speed | Human in the loop, below |
| A6 | **Measured, not assumed.** No prompt or model change ships without passing the evaluation gate. | 6 Quality over speed · 7 Evidence over opinion | [ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md); [AI evaluation framework](ai-evaluation-framework.md) |
| A7 | **Useful without AI.** Every document task works when intelligence is unavailable, declined or switched off. | 3 Offline by default · 5 Useful before paid | Offline matrix, below; AI never gates a core task |
| A8 | **Bounded cost.** Every cloud request has a token budget and a quota before it is sent. | 9 Built to last | Cost control, below |
| A9 | **Explain, never advise.** Features that touch legal, medical or financial documents explain what the document says and never give advice. | 8 Small surface, deep quality · 10 Honest communication | [Non-goals](non-goals.md); the Analyse Contract guardrail below |
| A10 | **Honest labels.** AI output is always identified as AI output, with the tier that produced it. | 10 Honest communication | Disclosure and labelling, below |

These match Apple's generative AI guidance: keep people in control, identify where AI is used,
minimise what is shared with servers, and warn that generated content may contain errors
([Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)).

## Disclosure and labelling of AI output

Apple asks apps to communicate where AI is used and never to let people think AI content was
written by a person; Anthropic requires consumer-facing chat products to disclose that the user is
talking to AI at least at the start of each session
([Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai);
[Anthropic Usage Policy](https://www.anthropic.com/legal/aup)). PDF Algo Pro applies one rule
everywhere: **generated content is never presented as the document's own text.**

| Surface | What the user sees |
|---|---|
| Answer or summary card | A persistent "AI" label with the tier that produced it: "On device", "Private Cloud Compute" or "Claude (Anthropic)" |
| Start of every Chat with PDF conversation | A one-line notice: answers are generated by AI from this document, cite their pages and may contain errors |
| Citations | Tappable page chips after each claim; tapping opens the page with the supporting passage highlighted |
| Unsupported or partial answers | "Not found in this document" or "Partly supported: see pages …"; never a confident answer without a citation |
| Reduced-scope answers (failover, offline, long document on device) | "Answered on device from the most relevant pages" or the equivalent reason |
| AI text inserted into a document (a note, a comment, a filled field) | Only by explicit user action; inserted annotations carry "PDF Algo Pro AI" as the author so they stay identifiable after export |
| Exported or shared summaries | A footer: "AI-generated summary of <document> by PDF Algo Pro. May contain errors; check the cited pages." |
| App Intents (Siri, Shortcuts, Spotlight) | Results say they are AI-generated and name the tier; intents return results and never modify documents |
| Links in model output | Shown as plain text, not tappable, so an instruction hidden in a document cannot plant a link the user follows by reflex |

Labels are part of the design system ([design system](design-system.md)) and are checked in
snapshot tests. Accessibility labels include the tier ("AI answer, on device, cites page 4").

## Consent model

App Review Guideline 5.1.2(i) requires apps to disclose clearly where personal data will be shared
with third parties, including third-party AI, and to obtain explicit permission first
([App Review Guidelines 5.1.2](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing);
clarified in the [13 November 2025 guideline update](https://developer.apple.com/news/?id=ey6d8onl)).
PDF Algo Pro applies the same standard to Apple's own Private Cloud Compute, because founder
principle 1 promises that a document leaves the device only when the user chooses and knows where
it goes.

### Consent per tier

| Tier | What leaves the device | Consent | Default |
|---|---|---|---|
| On device | Nothing | None needed. A first-use explainer states what the feature does, that it runs on the device and that answers may contain errors | Enabled where Apple Intelligence is available and turned on |
| Private Cloud Compute | The question, the instructions, the selected document excerpts (or page images for OCR assistance) and the conversation so far | Explicit opt-in naming Apple Private Cloud Compute | Off until the user opts in; when the router wants PCC it asks "Use Private Cloud Compute for this?" and offers the permanent opt-in there |
| Claude (Anthropic) | The same categories, sent to Anthropic's API: directly with App Attest in the external TestFlight beta; through the relay from general availability | Explicit opt-in naming Anthropic and Claude | Off until the user opts in. After opt-in, "Ask before sending a document to Claude" stays **on** by default; page images always need a per-request confirmation |

Consent is per device and is not synced through iCloud: the data flow starts on that device, and a
device that has never shown the consent screen must not inherit a decision made elsewhere.

### What the consent screen shows

Plain language, one screen per provider, no pre-ticked boxes, "Not now" as prominent as "Allow":

1. **Who:** the provider's name (Apple Private Cloud Compute; Anthropic, maker of Claude).
2. **What is sent:** the question, the relevant pages' text (or the whole document's text for a
   whole-document task), page images when OCR assistance is used, and the conversation so far.
3. **What is not sent:** the PDF file itself, other documents, the user's name, account or contacts,
   and any identifier of the person.
4. **Why:** longer documents and harder questions than the device can handle.
5. **Retention and training**, stated from the provider's own terms (see Data use below):
   for PCC, Apple's statement that prompts are not stored; for Claude, the contracted retention
   terms, including that content flagged by the provider's safety systems can be retained.
6. **How to take it back:** Settings › Intelligence, at any time.
7. A link to the privacy policy and to [privacy architecture](privacy-architecture.md) details.

### Where consent is revoked

- **Settings › Intelligence › Cloud processing:** one switch per provider. Turning a switch off takes
  effect immediately, cancels in-flight requests to that provider and removes it from routing.
- On revocation the app offers to delete cached answers that provider produced (they are stored with
  the library index, [ADR-0006](adr/0006-swiftdata-persistence.md)). It explains honestly that
  content already sent is governed by the provider's retention terms.
- Turning Apple Intelligence off in system Settings disables the on-device and PCC tiers; the app
  reads the framework's availability and reflects it.

### What is logged locally

Nothing below leaves the device; it is not included in telemetry ([ADR-0017](adr/0017-privacy-first-telemetry.md)).

| Record | Contents | Kept |
|---|---|---|
| Consent record | Provider, consent-text version, timestamp of grant and revocation, app version | Until the app is deleted; history kept for the user to see |
| AI activity log (Settings › Intelligence › Activity) | For each cloud request: time, feature, provider, document title, pages sent, tokens in and out, credits used | `Assumption:` 30 days, then deleted; the user can clear it at any time. Validated with beta testers' feedback on usefulness |
| Diagnostics (`Logger`) | Tier, prompt ID and version, error category, latency; never prompt or document text (privacy-redacted) | System log retention ([ADR-0012](adr/0012-on-device-observability.md)) |

### Consent versioning

The consent text carries a version. Adding a provider, adding a data category (for example page
images), or a change in the provider's retention or training terms is a material change: the app
asks again before the next request to that provider. Wording fixes do not re-prompt.

### Decision: per-provider, per-device, revocable consent

**Decision.** Separate opt-in for each cloud provider, on each device, revocable in one place, with
"ask before sending" on by default for Claude and always on for page images.
**Rationale.** Meets Guideline 5.1.2(i) and Apple's guidance to show what is shared with servers;
keeps founder principle 1 literal; gives the user a clear mental model of where a document goes.
**Trade-offs.** More prompts than a single "enable cloud AI" switch; some users will see a
confirmation before long-document answers.
**Alternatives considered.** One global cloud switch (simpler, but hides which company receives
content). Consent synced across devices (convenient, but a new device would send content without
ever showing the disclosure). Consent only for Claude, treating PCC as part of the system (arguable
under the guideline, but weaker than our own promise).
**Risks.** Consent fatigue leading to reflexive taps: mitigated by asking only when the router
actually needs a cloud tier and by making "Not now" equal in weight.
**Future scalability impact.** A new provider adds one consent screen and one switch; enterprise
editions could pre-configure consent through managed settings without changing the model.
**Pillars served.** PIL-4, PIL-5.

## Human in the loop

The model reads; the person acts. This follows Apple's guidance to avoid automating destructive or
hard-to-undo actions and to ask before significant actions
([Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)),
and Apple's acceptable-use requirement not to make decisions without human supervision in high-risk
domains such as legal and finance
([Acceptable use requirements for the Foundation Models framework](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)).

- **No action tools.** The model is given only read-only tools: read pages of the open document,
  search it, Vision's `OCRTool` for text in page images
  ([OCRTool](https://developer.apple.com/documentation/vision/ocrtool)), and Core Spotlight's
  `SpotlightSearchTool` over the app's own on-device index
  ([SpotlightSearchTool](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool);
  configuration in [model selection](model-selection.md)). No tool can edit, save,
  rename, delete, share, send, sign, purchase, open a URL or navigate. Where a task needs no tool,
  the profile sets tool calling to `.disallowed`
  ([GenerationOptions.ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct)).
- **Proposals, not changes.** When a feature produces something that could change a document
  (filling a form from extracted data, suggesting a file name, suggesting redactions), the result is
  shown as a proposal with a preview. Applying it is a user action, registers an undo, and redaction
  always shows the exact regions before anything is removed.
- **Extraction is verified.** Extracted values are shown with their source page and highlighted
  source text; exporting them is a user action.
- **Deep links and intents.** Model output never becomes a `Route`; the deep-link router only
  navigates from user or system intent ([ADR-0004](adr/0004-navigation-and-multi-window.md)). App
  Intents for summarise, ask and extract return results and never modify documents.
- **Escalation to the cloud is visible.** Moving a request from the device to a cloud tier is either
  confirmed by the user or covered by a setting the user turned on; it is never silent.
- **Code enforcement.** The `Intelligence` package exposes no mutating API to model-facing code. A
  planned `invariants` rule rejects any `Tool` conformance that is not on the read-only allow-list
  ([quality gates](process/quality-gates.md#the-invariants-rules)).

## Cost control

Cloud intelligence has a real marginal cost; the on-device tier has none per request. Controls sit
at four layers so that no single failure produces a runaway bill. Prices and plan allowances are
not in this public document; they are held in the confidential pricing and unit-economics
documents (see the public editions of [pricing strategy](pricing-strategy.md) and
[unit economics](unit-economics.md)).

### Per-tier token budgets

Budgets are computed from each model's reported context size at run time, not hard-coded, because
Apple advises adapting to the hardware the app runs on
([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)).

| Tier | Context (sourced) | Per-request budget |
|---|---|---|
| On device | 4,096 tokens per session today, read from `contextSize` ([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)) | Instructions and output schema at most 15%; question and conversation summary at most 10%; document excerpts at most 55%; response reserve at least 20% |
| Private Cloud Compute | 32,000 tokens ([Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)) | Instructions and schema 2,000; question and history 2,000; excerpts 22,000; response and reasoning reserve 6,000 (deeper reasoning uses more of the context window, same source) |
| Claude | 1M tokens for Claude Sonnet 5 and Claude Opus 5.5 ([Models overview](https://platform.claude.com/docs/en/models/overview)) | Input capped at 120,000 tokens per request; output capped at 4,000 tokens for answers and summaries and 8,000 for extraction; a conversation is capped at 300,000 cumulative input tokens before the user is asked to start a new one |

`Assumption:` every percentage and cap in the last column. They are validated during the MVP by
measuring tokens per page on the golden corpus and per-task `usage` counts, and by checking that the
caps do not lower evaluation scores below the release thresholds.

### Pre-checks before a request is sent

| Tier | Pre-check | Source |
|---|---|---|
| On device | Exact count with `tokenCount(for:)` for instructions, prompt and transcript against `contextSize`; the prompt builder trims excerpts until the request fits | [tokenCount(for:)](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/tokencount(for:)); [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels) |
| Private Cloud Compute | `contextSize` is read from the model; no token-count API is documented for PCC, so the on-device count is used as an estimate with a safety margin. `Assumption:` 15% margin, validated against PCC `usage` counts on the evaluation corpus | [PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel) |
| Claude | The package does not expose token counting, and Claude's tokeniser differs from Apple's, so the app estimates conservatively (`Assumption:` 3 characters per token for English and French, validated against `usage`). After general availability the relay counts exactly with Anthropic's token-counting endpoint before forwarding and rejects over-budget requests | [Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models); [Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting) |

After each response, the session's `usage` (input, cached input, output and reasoning tokens) is
recorded against the request's budget and the user's credits
([LanguageModelSession.Usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct)).

### Fair-use AI credits and per-user quotas

- **Credits are the unit.** A credit is a normalised amount of cloud cost: Claude input and output
  tokens are converted using the provider's published per-token rates, so one credit means the same
  cost whatever the task. On-device requests never use credits.
- **Tied to the subscription.** Each plan grants an allowance per billing period
  ([ADR-0011](adr/0011-storekit-2-monetisation.md)); the allowance per plan is set in the
  confidential pricing documents. The app shows the remaining allowance in Settings › Intelligence and
  shows an estimate before any single request that would use a large share of it (`Assumption:`
  more than 5% of the period's allowance).
- **Private Cloud Compute** requests do not use credits. Each person has a daily request limit set by
  Apple, which they can raise by upgrading iCloud+; Apple does not publish the limit's size. The app
  shows Apple's quota states (below, approaching, reached), the reset date when known, and Apple's
  own upgrade suggestion, rather than inventing its own
  ([PrivateCloudComputeLanguageModel.QuotaUsage](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/quotausage-swift.struct);
  [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute);
  [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)).
- **Private Cloud Compute has no cloud cost to the developer only while all three conditions hold:**
  (1) the developer is enrolled in the App Store Small Business Program, (2) the developer has fewer
  than 2 million first-time App Store downloads across its apps, and (3) the
  `com.apple.developer.private-cloud-compute` entitlement has been granted. If a threshold is crossed
  or enrolment ends, Apple notifies the developer, who must migrate to an alternative within
  6 months; Apple publishes no paid option
  ([Private Cloud Compute for developers](https://developer.apple.com/private-cloud-compute/)). The
  consequences are planned for: the PCC tier can be switched off with the kill switch, the router
  then serves on device or through Claude (with consent), and the cost model for that case is kept in
  the confidential unit-economics documents. Whether and when the conditions are met for this app is
  tracked privately (readiness blockers C3 and C4).
- **Enforced at the relay before general availability.** App Attest tokens identify the app, not the
  person, so per-user quotas cannot be enforced with App Attest alone
  ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)).
  The relay in `pdf-algo-pro-backend` verifies the App Store-signed transaction the app presents,
  keys quota counters on a pseudonymous hash of the original transaction identifier (no account, no
  name, no email), debits credits from the response's usage, and refuses requests once the allowance
  is spent. It stores counters only, never prompt or response content
  ([privacy architecture](privacy-architecture.md)).

### Workspace spend caps and alerts

- Separate Anthropic workspaces for development, TestFlight and production, so a test run cannot
  spend production budget. Each workspace has a monthly spend limit and alert thresholds; when a
  limit is reached, requests fail with an error stating that the workspace usage limit was reached
  ([Workspaces](https://platform.claude.com/docs/en/manage-claude/workspaces);
  [Rate limits](https://platform.claude.com/docs/en/api/rate-limits)).
- `Assumption:` alerts at 50%, 80% and 100% of each monthly limit to the mailbox of the AI hat; the
  levels are reviewed after the first full month of TestFlight use.
- After general availability the relay also enforces a soft ceiling below the provider's hard limit,
  so the app fails over gracefully before the hard limit stops every request.
- A reached limit is handled as "provider quota exhausted" (see failover), not as an outage.

### Controls by phase

| Control | TestFlight beta (App Attest) | General availability (relay) |
|---|---|---|
| Per-request token caps | In the app | In the app and the relay |
| Per-user quota and credits | Best effort in the app (tamperable) | Enforced by the relay |
| Workspace spend cap and alerts | Yes | Yes |
| Audience | Limited TestFlight testers | App Store |
| Stop switch | Kill switch; revoking the App Attest integration as a last resort (permanent, needs a new client ID and an app update) | Kill switch; relay configuration |

Revocation behaviour is from
[Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models).

### Decision: layered cost control with a relay before general availability

**Decision.** Token budgets and pre-checks in the app, credits tied to the subscription, per-user
quotas enforced by the relay before general availability, and provider workspace caps as the
backstop.
**Rationale.** Each layer covers a different failure: a long document (budgets), a heavy user
(quotas), a bug or abuse (workspace cap).
**Trade-offs.** The relay is a service to build and operate for a product that otherwise has no
servers; it sees request metadata.
**Alternatives considered.** App Attest only in production (no per-user limits; one user could
exhaust the workspace for everyone). Unlimited cloud AI in the subscription (unbounded cost). Claude
only for a separate paid add-on (more purchase friction; still needs per-user enforcement).
**Risks.** Relay downtime removes the Claude tier (failover covers it); estimate errors before the
relay exists (conservative caps, spend limits).
**Future scalability impact.** The relay is the natural place for team plans, organisation spend
controls and additional providers.
**Pillars served.** PIL-4, PIL-5.

## Provider failover

### Rules

1. **Failover order is Claude, then Private Cloud Compute, then on device**
   ([ADR-0021](adr/0021-ai-provider-routing-and-failover.md)). Failover only moves a request towards
   the device; a PCC failure never sends content to Claude.
2. A tier is used in failover only if the user has consented to it, it is available, and it is not
   switched off by the kill switch.
3. When the fallback tier has a smaller context, the request is rebuilt for that tier's budget
   (fewer, higher-ranked excerpts) and the answer is labelled as reduced in scope.
4. Apple's guidance is to retry on the on-device model when a PCC request fails for lack of network
   ([Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute));
   Anthropic suggests falling back to `SystemLanguageModel` on rate limiting
   ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)).

### Circuit breaker

One breaker per provider on each device; after general availability the relay runs its own breaker
for Claude across all users and tells clients when the provider is down, so devices skip it without
each waiting to trip.

| Parameter | Value |
|---|---|
| Window | The last 20 requests to the provider, or the last 5 minutes, whichever is shorter |
| Trip (closed → open) | 5 consecutive counted failures, or at least 50% counted failures with at least 6 requests in the window |
| Open duration | 60 seconds, doubling after each failed probe, up to 30 minutes |
| Half-open | The next real user request is the probe; success closes the breaker, failure reopens it |
| Time to first token | PCC 10 seconds; Claude 12 seconds |
| Whole request | 60 seconds; 120 seconds for deep-reasoning contract analysis |
| Retry | At most one retry per request, only for transport errors, and only if the user is still waiting; rate-limit responses are not retried inside the window they state |

`Assumption:` every value in this table. Validated by fault-injection tests in the `Intelligence`
package (simulated timeouts, rate limits and outages), by Xcode's simulated PCC quota states, and
by the tier-mix and fallback counters in opt-in telemetry after release; the time-to-first-token
limits are set well above the p95 budgets in [performance budgets](performance-budgets.md).

### Error classification

Error cases come from the framework and the Claude package
([LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror);
[PrivateCloudComputeLanguageModel.Error](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/error);
[Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)).

| Error | Counts towards the breaker | Action |
|---|---|---|
| Transport failure, PCC `networkFailure` or `serviceUnavailable`, `timeout` | Yes | Fail over |
| `rateLimited` (HTTP 429 from Claude) | Yes | Fail over; honour the retry interval |
| PCC `quotaLimitReached` | No: quota state | Mark PCC exhausted until its reset date; show Apple's quota UI; fail over to on device |
| Claude workspace or relay allowance exhausted | No: quota state | Mark Claude exhausted for the period; fail over |
| `contextSizeExceeded` | No | Rebuild the request with a smaller budget on the same tier, once |
| `guardrailViolation`, `refusal` | No | Show the refusal honestly; never retry on another tier to get around a safety refusal |
| `unsupportedLanguageOrLocale`, `unsupportedCapability`, `unsupportedGenerationGuide` | No | Route to a tier that supports it, if consented; otherwise explain |
| Output fails to decode into the expected type | No | Count in the prompt-quality alarm; retry once on the same tier |

Retrying a refused request on another provider would turn one provider's safety decision into a
search for a more permissive one. That defeats the purpose of both providers' safety systems and
runs against Apple's requirement not to circumvent the framework's guardrails
([Acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)).

### Kill switch

A small set of records in the CloudKit **public** database lets the maintainer switch off a
provider, a feature or a prompt version without an app release
([iOS architecture review](ios-architecture-review.md), CloudKit strategy). The public database is
readable by every user of the app even without an iCloud account, and access can be restricted by
role in the CloudKit console
([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)).

The record schema, the target names (`ai.provider.claude`, `ai.provider.pcc`,
`ai.provider.ondevice`, `ai.prompt.<id>`, `feature.<name>`), the fetch policy, the two-step change
and the procedure are owned by the [kill-switch runbook](process/runbooks/kill-switch.md); this
section adds only the AI-specific rules:

- **Security:** the record type is created and written only by the developer role; the app's users
  have read-only access (configured in the CloudKit console and verified in the kill-switch runbook).
- **Off only:** a record can switch a provider, a feature or a prompt version off, or make a prompt
  fall back to its previous bundled version; it never turns on a tier, and consent still gates every
  cloud request. After general availability the relay also enforces the Claude switch on the server
  side.
- **User notices** are the localised strings chosen by the record's `reasonCode` (see
  [user messaging](#user-messaging)); the record carries no free text.
- Failover procedure: [AI provider failover runbook](process/runbooks/ai-provider-failover.md).

### User messaging

Messages are short, specific and non-blocking, following Apple's guidance to describe what happened
and offer a next step
([Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)).
The situations and their EN source texts are kept in one place, the
[AI provider failover runbook](process/runbooks/ai-provider-failover.md#user-facing-messages):
fallback, reduced scope, a tier switched off, the on-device model unavailable, the Private Cloud
Compute daily limit, credits used, and refusals.

### Decision: failover towards the device, with a remote kill switch

**Decision.** Per-provider circuit breakers, failover only towards more private tiers, and a
CloudKit public-database kill switch for providers, features and prompt versions.
**Rationale.** Users keep a working answer path when a provider fails; privacy never gets worse
during an outage; a bad provider, feature or prompt can be stopped in minutes rather than a review
cycle.
**Trade-offs.** Lower-tier answers are less complete; breaker state is per device until the relay
exists.
**Alternatives considered.** Silent fallback with no label (undermines consent and trust, rejected in
ADR-0021). Failover upwards to any available provider (sends content somewhere the user did not
expect). A third-party remote-config service (another data processor).
**Risks.** A mis-set kill-switch record could disable features for everyone: the runbook's two-step
change (CloudKit development environment first, then production) and version-scoped records. Stale
cache on devices that stay offline: cloud tiers are unusable offline anyway.
**Future scalability impact.** The same records and breaker states can drive a status page and
relay-side routing for more providers.
**Pillars served.** PIL-4, PIL-6.

## Offline mode

Intelligence degrades; the app does not. Reading, editing, scanning, OCR, search and signing never
depend on a network or a model ([founder principles](founder-principles.md), principle 3).

### Capability matrix

Columns: **Offline (AI device)** is a device with Apple Intelligence available and no network;
**Offline (other device)** has no Apple Intelligence; **Online + PCC** and **Online + Claude**
assume consent was given. PCC needs a device that supports Apple Intelligence
([PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)),
so a device without it can reach only the Claude tier.

| Capability | Offline (AI device) | Offline (other device) | Online + PCC | Online + Claude |
|---|---|---|---|---|
| Reading, editing, annotating, signing, organising | Full | Full | Full | Full |
| Scan and OCR to searchable PDF (Vision) | Full | Full | Full | Full |
| Keyword search, including OCR text (Core Spotlight) | Full | Full | Full | Full |
| Chat with PDF, citations | Yes: retrieval over the document, a few excerpts per answer | No | Longer excerpts, multi-part questions | Whole-document questions |
| Summarise Document | Yes: short documents in one pass; long documents section by section (slower) | No | Long documents | Very long documents |
| Extract Data with AI | Yes: forms, invoices, receipts, page by page | No | Long documents | Cross-page tables |
| Analyse Contract | Short contracts | No | Long contracts, deeper reasoning | Not offered (see guardrail below) |
| Translate | Text: Translation framework with downloaded languages ([Translation](https://developer.apple.com/documentation/translation)); answers: on-device model in supported languages | Text: Translation framework with downloaded languages | Longer passages | Languages Apple Intelligence does not support |
| OCR assistance with page images | Yes: image input to the on-device model ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)) | No (Vision OCR still works) | Harder pages | With per-request confirmation |
| App Intents (summarise, ask, extract) | Yes, on-device limits | Not offered | As in the app | As in the app |

### Graceful degradation

- **Tell, don't hide.** Unavailable options stay visible with the reason ("Needs a connection",
  "Needs Apple Intelligence", "Turn on Private Cloud Compute in Settings"), so users learn what the
  app can do.
- **Never queue content for later sending.** If a cloud answer is not possible now, the user can
  get an on-device answer now or ask again later; nothing is sent automatically when the network
  returns.
- **Devices and settings without the on-device model.** The on-device model needs a device that
  supports Apple Intelligence (iPhone 15 Pro and later Pro models, the iPhone 16 family and later,
  iPad and Mac with M1 or later, iPad mini with A17 Pro) with Apple Intelligence turned on
  ([Apple Intelligence](https://www.apple.com/apple-intelligence/)). The app reads
  `SystemLanguageModel.availability` and handles each reason
  ([SystemLanguageModel.Availability.UnavailableReason](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason)):
  `deviceNotEligible` (on-device intelligence is not offered; since PCC also needs an eligible device,
  only the Claude tier can answer, from V2, for Pro users with consent),
  `appleIntelligenceNotEnabled` (explain that turning on Apple Intelligence in Settings enables
  private answers) and `modelNotReady` (the model is downloading; the assistant says so and the rest
  of the app stays usable). Offline on an ineligible
  device, intelligence features show why they are unavailable and every other feature works.
- **Thermal and battery limits.** Long on-device jobs respect thermal state and Low Power Mode like
  every other queue ([iOS architecture review](ios-architecture-review.md), background processing);
  in Low Power Mode the app asks before starting a long summary.

## Data use

- **No training on user content.** PDF Algo Pro never uses document content, questions or answers to
  train or tune any model, and never collects them ([ADR-0017](adr/0017-privacy-first-telemetry.md)).
- **Private Cloud Compute.** Apple states that no prompts are stored and that independent researchers
  can verify its privacy claims
  ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)).
- **Claude.** Requests go from the app (or the relay) to Anthropic; Apple is not in the request path
  ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)).
  Anthropic states that retained data is never used for training without the customer's express
  permission, that zero data retention (ZDR) is arranged per organisation, and that even under ZDR
  content flagged by its safety systems may be retained for up to two years
  ([API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)).
- **Required before general availability:** written zero-data-retention terms (or equivalent) and
  data-processing terms for the production workspace. **Status: to negotiate** (readiness blocker
  C4, [readiness review](readiness-review.md)). Until then the Claude tier is TestFlight-only and the
  consent text states the provider's standard terms.
- **Models that cannot meet the terms are excluded.** Anthropic's "Covered Models" require 30-day
  retention and are not available under ZDR (same source); the router never selects them.
- **No server-side tools.** The Claude package can enable web search, web fetch and code execution
  on Anthropic's side ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models));
  PDF Algo Pro never enables them, because they would take document content further than the user
  agreed and code execution is not covered by ZDR
  ([API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)).
- **Minimise what is sent.** Retrieval sends the relevant excerpts, not the file; page images only
  for OCR assistance; the conversation history sent to a cloud model is filtered to what the consent
  covers ([prompt management](prompt-management.md)).
- **Classification.** Document content, questions and answers are user content handled as the most
  sensitive class; relay counters are pseudonymous operational data; evaluation data is synthetic
  and public-safe. The authoritative mapping is in [data classification](data-classification.md);
  threats are analysed in the [threat model](threat-model.md).

## Analyse Contract: not legal advice

Apple's acceptable-use requirements prohibit inaccurate or dangerous outputs and unsupervised
decisions in high-risk domains including legal
([Acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)).
Anthropic classifies legal interpretation and guidance as a high-risk use case that requires
qualified human review and AI disclosure ([Anthropic Usage Policy](https://www.anthropic.com/legal/aup)).
PDF Algo Pro is not a legal adviser ([non-goals](non-goals.md)).

1. **Disclosure everywhere.** The onboarding option, the feature entry point and the top of every
   result say: "Explains what this document says. Not legal advice. For advice about your situation,
   talk to a qualified lawyer."
2. **Describe, never advise.** The output type has fields for parties, dates, term and renewal,
   payment, obligations, termination, liability and indemnity, and "clauses worth asking a lawyer
   about", each with page citations. It has no field for a recommendation, a risk score, whether to
   sign, or whether a clause is enforceable.
3. **Advice-seeking questions** ("Should I sign this?", "Is this legal?") get a fixed response that
   declines to advise and points to the relevant clauses; this is a release-blocking evaluation
   subset.
4. **No jurisdictional conclusions.** The model does not state what the law is in any place.
5. **Tiers.** On device and Private Cloud Compute only. **The Claude tier is not used for Analyse
   Contract** until the Anthropic high-risk requirements have been reviewed against the feature
   (open question below).
6. Other documents in regulated areas (medical letters, financial statements) follow the same
   explain-only rule in Chat with PDF and Summarise.

## Incident handling for AI harms

AI incidents follow the [incident response runbook](process/runbooks/incident-response.md); this
section defines what counts as one and which levers exist.

| Severity | Examples | First lever |
|---|---|---|
| SEV1 | Content sent to a cloud provider without valid consent; a prompt-injection path that exposes content; systematically harmful output | Kill switch for the provider or feature; hotfix |
| SEV2 | Citation accuracy regression in production; provider outage without working failover; spend approaching a workspace limit unexpectedly | Prompt version fallback; provider disable; spend-limit review |
| SEV3 | A single reported harmful, biased or wrong answer | Add to the evaluation sets; fix in the next prompt version |

- **Reports from users.** "Report a problem with this answer" composes a report the user reviews
  before sending; it contains the prompt ID, version, tier and error category, and includes the
  question, answer or document text only if the user adds them.
- **Reporting to providers.** Safety issues not handled by Apple's guardrails are reported through
  Feedback Assistant with the session feedback attachment, generated only on synthetic reproductions
  or with the user's explicit permission
  ([Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)).
  Claude-tier issues go to Anthropic support.
- **Personal information.** If an incident involves personal information, the Privacy hat assesses
  it under the Notifiable Data Breaches scheme where the Privacy Act 1988 applies
  ([OAIC: Notifiable Data Breaches](https://www.oaic.gov.au/privacy/notifiable-data-breaches/about-the-notifiable-data-breaches-scheme);
  [compliance roadmap](compliance-roadmap.md)).
- **After every SEV1 or SEV2:** a written review, a new evaluation case that would have caught it,
  and a decision-register entry if a rule here changes.
- Provider-specific steps: [AI provider failover runbook](process/runbooks/ai-provider-failover.md)
  and [kill-switch runbook](process/runbooks/kill-switch.md).

## Roles and review cadence

Governance is written as roles ("hats") so it scales from one person to many. Today the maintainer
wears every hat; the activation of separate reviewers as people join follows
[GitHub governance](github-governance.md).

| Hat | Accountable for |
|---|---|
| **AI** | This document, the evaluation thresholds, routing policy, prompt approvals, provider relationships and spend limits |
| Privacy | Consent text and versions, data flows, retention terms, breach assessment |
| Security | Prompt-injection defences and red-team set, relay security, kill-switch access |
| Product | Feature scope, disclosure copy, the Analyse Contract guardrail |
| Release | Confirms the evaluation gate passed before a release PR merges into `main` |

| Review | When | Output |
|---|---|---|
| Governance review | Quarterly | Updated document; decision-register entries for rule changes |
| Model and provider re-evaluation | Quarterly; on every iOS release and beta, because the on-device model changes with the operating system ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)); and when a provider announces a deprecation | [Model selection](model-selection.md) update |
| Evaluation thresholds | Each milestone | [AI evaluation framework](ai-evaluation-framework.md) update |
| Incident review | After every SEV1 or SEV2 | Written review, new evaluation cases |
| Consent text | Before any change to providers, data categories or provider terms | New consent version |

## Open questions

- Anthropic's high-risk use-case requirements: does explaining a contract with page citations, with
  no advice, fall within "legal interpretation"? Until answered, Analyse Contract does not use Claude.
- Zero-data-retention and data-processing terms for the production workspace, and whether they
  cover requests made with App Attest tokens as well as through the relay (readiness blocker C4).
- Whether the three Private Cloud Compute conditions (Small Business Program enrolment, the download
  threshold, the entitlement) are met for this app, and from when (tracked privately, readiness
  blockers C3 and C4).
- Whether Apple expects the Guideline 5.1.2(i) consent flow for Private Cloud Compute, or treats it
  as part of Apple Intelligence; the product asks either way.
- The relay's exact entitlement check (signed transaction presented per request, or a short-lived
  relay token) is designed in [privacy architecture](privacy-architecture.md).
