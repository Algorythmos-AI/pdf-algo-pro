# Model selection

Which model answers which request in PDF Algo Pro: the routing policy by task, document size,
sensitivity, consent, availability and cost; the criteria each tier is judged on; each provider's
capabilities and limits; the availability checks the app runs; and how the choice is re-evaluated
and extended. It applies [ADR-0009](adr/0009-tiered-ai-and-consent.md) and
[ADR-0021](adr/0021-ai-provider-routing-and-failover.md); consent, cost and failover rules are in
[AI governance](ai-governance.md), and the evidence for each routing choice comes from the
[AI evaluation framework](ai-evaluation-framework.md).

Owner: AI · Reviewed: quarterly, on every iOS release and beta, and when a provider changes its models or terms

## How the router decides

The `IntelligenceRouter` in the `Intelligence` package runs these checks, in order, before every
request. Code decides; model output never influences the route.

1. **Switched off?** Remove any provider, feature or prompt version disabled by the kill switch
   ([AI governance](ai-governance.md)).
2. **Sensitivity.** If the user has marked the document "Keep on device" (a per-document setting),
   remove every cloud tier. Analyse Contract never uses Claude (see the routing table).
3. **Available?** Remove tiers whose availability check fails (device eligibility, Apple Intelligence
   turned on, model downloaded, network, circuit breaker closed).
4. **Consented?** Remove cloud tiers without consent. Where consent says "ask before sending", the
   tier stays but needs a confirmation.
5. **Capable?** Remove tiers that lack a needed capability: guided generation, image input, the
   document's language.
6. **Within budget?** Check the request against the tier's token budget with the pre-checks in
   [AI governance](ai-governance.md), and the user's credits or Apple's daily quota.
7. **Qualified?** Keep only tiers that passed the evaluation thresholds for this task and size band.
8. **Choose the lowest qualified tier:** on device before Private Cloud Compute before Claude. If no
   qualified tier remains, answer on the best remaining tier with a reduced-scope label, or explain
   what would enable a full answer (connect, turn on a cloud tier, try a shorter selection).

Escalating from the device to a cloud tier is confirmed by the user unless they turned on "Use
automatically when needed" for that provider. Failover after an error only moves towards the device
([AI governance](ai-governance.md)).

**Implementation status.** The eight steps are implemented, in this order, by `RoutingPolicy` in the
`Intelligence` package: a pure function from the facts above to a route, a confirmation or a refusal
with its reason. A table test over task, tier, consent state and "Keep on device" proves that every
route to a cloud tier has a granted, current consent. `ConsentStore` keeps the consent records and
`CircuitBreaker` the per-provider breaker. The cloud drivers are not built yet, so the
`IntelligenceRouter` still serves the on-device tier only and does not call the policy.

## Document size bands

Bands are set by the token count of the text a request needs (the whole document for a
whole-document task), measured with the pre-checks, not by page count.

| Band | Text tokens needed | Rough dense pages | Typical documents |
|---|---|---|---|
| S | Fits the on-device excerpt budget: about 2,250 tokens on today's 4,096-token context | 2–3 | Receipts, invoices, letters, one-page forms |
| M | Up to 22,000 tokens (the PCC excerpt budget) | 20–35 | Contracts, statements, short reports |
| L | Up to 120,000 tokens (the Claude per-request cap) | 120–185 | Long reports, manuals, theses |
| XL | More than 120,000 tokens | 185 or more | Very long manuals and compilations |

`Assumption:` a dense page of about 500 words is 650–1,000 tokens. Apple states that an English
token is typically three to four characters
([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window));
Anthropic's pricing guidance of about 0.75 words per token, adjusted for its newer tokeniser's
roughly 30% more tokens, gives a similar figure
([Pricing](https://platform.claude.com/docs/en/about-claude/pricing);
[Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting)). Validated
by counting every document in the golden corpus with `tokenCount(for:)` and with the `usage` of
cloud responses. The budgets behind each band are `Assumption:` values set in
[AI governance](ai-governance.md).

## Routing policy by task

Target policy once every tier has shipped. Tiers switch on by phase: on device only in the MVP,
Private Cloud Compute from V1, Claude from V2 (Pro, opt-in) ([roadmap](product/roadmap.md)). Until a
tier ships, its cells use the next lower qualified tier. Every cell is `Assumption:` until the
evaluation suites have qualified it; the quarterly re-evaluation replaces assumptions with measured
results.

| Task | S | M | L | XL | Claude used for |
|---|---|---|---|---|---|
| **Q&A with citations** (Chat with PDF) | On device | On device with retrieval; PCC for multi-part questions | On device or PCC with retrieval; Claude for whole-document questions ("list every deadline") | Retrieval on any tier; never whole-document | Whole-document and cross-page questions, L |
| **Summarise** | On device, one pass | On device section by section (works offline); PCC in one pass if consented | PCC section by section; Claude in one pass if consented | Section by section on the best consented tier | One-pass summaries of L documents |
| **Extract data** (`@Generable`) | On device | On device page by page, merged in code | PCC by section; Claude for tables that span pages | By section on any qualified tier | Cross-page tables |
| **Analyse Contract** | On device | PCC, moderate reasoning | PCC, deep reasoning, clause by clause | PCC clause by clause | **Never**, until the Anthropic high-risk review is complete ([AI governance](ai-governance.md)) |
| **Translate** | Text: Translation framework; answers: on-device model | Translation framework, paragraph by paragraph | Same | Same | Languages that neither the Translation framework nor Apple Intelligence supports, with consent |
| **OCR assistance with page images** | Vision OCR first; then the on-device model with the page image | Per page, same | Per page, same | Per page, same | Hard pages, with a confirmation for every request that sends images |

Notes:

- **Retrieval first.** Questions use retrieval over page-tagged chunks so each answer cites pages;
  only whole-document tasks send whole documents.
- **Translation framework.** Plain text translation uses Apple's on-device Translation framework,
  which works across devices without Apple Intelligence once languages are downloaded
  ([Translation](https://developer.apple.com/documentation/translation)); the language model is used
  to answer or summarise in another language.
- **OCR stays deterministic.** Vision's `RecognizeDocumentsRequest` is the OCR engine
  ([ADR-0008](adr/0008-ocr-and-scanning.md)); models assist with layout, low-confidence regions and
  questions about figures. Image input is available on the on-device model in iOS 27, and larger
  images use more tokens and time
  ([What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)).
  Apple recommends starting image analysis on the device and moving to PCC when more reasoning or
  context is needed
  ([Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)).

### Modifiers

| Condition | Effect on routing |
|---|---|
| Document marked "Keep on device" | On device only; reduced-scope label when needed |
| Offline | On device only (see the offline matrix in [AI governance](ai-governance.md)) |
| Device not eligible, or Apple Intelligence off | No on-device or PCC tier (PCC also needs an eligible device); no intelligence until V2, then Claude only, for Pro users with consent |
| On-device model downloading | As above until ready; the assistant says so |
| No PCC consent | PCC skipped; the app may ask when the request would benefit |
| PCC daily quota reached | PCC skipped until its reset date; Apple's quota UI shown |
| No Claude consent, or credits used up | Claude skipped |
| Circuit breaker open, or provider switched off | That provider skipped |
| Document language not supported by a tier | That tier skipped for this request |
| Low Power Mode | Long on-device jobs ask before starting |

### Retrieval with Core Spotlight

Library-wide questions ("which of my leases ends this year?") use Core Spotlight's
`SpotlightSearchTool` over the app's own on-device index, which gives fully local retrieval
([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)). Apple says to always
configure the tool with a guide that fits the model's context window to avoid token-overflow errors,
and notes that the default `complete` guide works best with PCC models
([SpotlightSearchTool](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool)).

- **On device:** the `.focused(.documents)` guide, a compact on-device-friendly schema for one
  content domain, with the `.compact` response format for limited context
  ([SpotlightSearchTool.Guide](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/guide);
  [SpotlightSearchTool.FormatLevel](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/formatlevel)),
  and a small result count (`Assumption:` 5 results; validated by the retrieval budget in
  [performance budgets](performance-budgets.md) and by context-overflow counts in the evaluation
  suite).
- **Private Cloud Compute:** the default `complete` guide.
- **Claude:** the same retrieval runs on the device first; only the selected excerpts are sent.
- Per-document questions use the page-tagged chunk index in the `Search` package
  ([ADR-0010](adr/0010-search.md)).

## Criteria matrix

Privacy and offline use are constraints applied first (principles A1 and A2 in
[AI governance](ai-governance.md)); among the tiers that remain, quality must meet the thresholds,
then latency and cost decide.

| Criterion | On device | Private Cloud Compute | Claude |
|---|---|---|---|
| Quality and reasoning | Sized for lightweight tasks; no reasoning mode | Much larger model; light, moderate and deep reasoning | Frontier reasoning; larger context |
| Latency (budgets in [performance budgets](performance-budgets.md)) | No network; first token within the on-device budget | Network round trip; deeper reasoning is slower | Network round trip; varies by model and effort |
| Privacy | Nothing leaves the device | Leaves the device; Apple states prompts are not stored | Leaves the device to Anthropic; retention per contract |
| Cost to us per request | None | None only while the three conditions below hold | Per token, from the Anthropic workspace |
| Offline | Yes | No | No |
| Context size | 4,096 tokens per session | 32,000 tokens | 1M tokens (Sonnet 5, Opus 5.5) |
| Image input | Yes (iOS 27) | Yes | Yes, on all current models |
| Structured output (`@Generable`) | Yes | Yes | Yes, through structured outputs |
| Usage limits | Unlimited | Daily limit per person | Our credits and workspace limits |
| Needs | Apple Intelligence-capable device with Apple Intelligence on | The same, plus the entitlement | Consent; network; relay before general availability |

Sources: the provider sections below.

## Provider capabilities and limits

### On device: `SystemLanguageModel`

| Property | Value | Source |
|---|---|---|
| Context | 4,096 tokens per session, covering instructions, tool definitions, schemas, prompts and responses; read at run time with `contextSize` | [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window) |
| Token counting | `tokenCount(for:)` for instructions, prompts and transcripts (since iOS 26.4) | [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels) |
| Reasoning, usage limits, offline | No reasoning; unlimited use; works offline | [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) |
| Image input | Image attachments in prompts (iOS 27); Vision's `OCRTool` and `BarcodeReaderTool`, not available in Simulator | [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [OCRTool](https://developer.apple.com/documentation/vision/ocrtool) |
| Model version | Changes with the operating system (26.0–26.3, 26.4 and 27.0 so far), so prompts are re-evaluated on every iOS release | [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) |
| Guardrails | Configurable, including a permissive mode for string output about sensitive source material | [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output) |
| Languages | `supportedLanguages` and `supportsLocale(_:)`; guardrails cover supported languages only | [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) |
| Device eligibility | iPhone 15 Pro and later Pro models, the iPhone 16 family and later, iPad and Mac with M1 or later, iPad mini with A17 Pro; Apple Intelligence must be turned on | [Apple Intelligence](https://www.apple.com/apple-intelligence/) |
| Unavailable reasons | `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` | [UnavailableReason](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason) |

### Private Cloud Compute: `PrivateCloudComputeLanguageModel`

| Property | Value | Source |
|---|---|---|
| Context | 32,000 tokens; `contextSize` is read asynchronously | [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [contextSize](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/contextsize) |
| Reasoning | `light`, `moderate`, `deep`; deeper reasoning uses more of the context window and is slower | [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) |
| Usage limit | A daily request limit per person, raised by upgrading iCloud+; the size is not published; `quotaUsage` reports below, approaching or reached, the reset date and an upgrade suggestion | Same; [QuotaUsage](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/quotausage-swift.struct) |
| Cost conditions | No cloud cost only while the developer (1) is enrolled in the App Store Small Business Program, (2) has fewer than 2 million first-time App Store downloads, and (3) has been granted the `com.apple.developer.private-cloud-compute` entitlement. Past the threshold, or on leaving the program, migration to an alternative is due within 6 months; no paid option is published | [Private Cloud Compute for developers](https://developer.apple.com/private-cloud-compute/) |
| Requirements | Network connection; a device and region that support Apple Intelligence; unavailable reasons include `deviceNotEligible` and `systemNotReady` | [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) |
| Errors | `quotaLimitReached`, `networkFailure`, `serviceUnavailable` | [PrivateCloudComputeLanguageModel.Error](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/error) |
| Guardrails | Present, with policies that cannot be configured | [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output) |
| Privacy | No account, authentication or API keys; Apple states prompts are never stored and researchers can verify its claims | [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/) |
| Testing | Xcode scheme options simulate approaching and reaching the quota | [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) |

### Claude: `ClaudeLanguageModel` from `ClaudeForFoundationModels`

| Property | Value | Source |
|---|---|---|
| Status | Beta; APIs may change; conforms to `LanguageModel`, so sessions, streaming, guided generation and tool calling work as with Apple's models | [Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models) |
| Models | Claude Sonnet 5 and Claude Opus 5.5: 1M-token context, 128K maximum output; Claude Haiku 4.5: 200K context, retirement not sooner than 15 October 2026; all current models accept images | [Models overview](https://platform.claude.com/docs/en/models/overview) |
| Authentication | `.appAttest`: short-lived (one-hour) workspace tokens for genuine installs, no end-user identity, physical devices only, revocation permanent. `.proxied`: our relay adds the credential. `.apiKey`: development only | [Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models) |
| Not exposed by the package | Token counting, batch processing, Files API, prompt-caching controls (caching is applied automatically) | Same |
| Error mapping | Context overflow → `contextSizeExceeded`; HTTP 429 → `rateLimited`; timeout → `timeout`; others → `ClaudeError` | Same |
| Server tools | Web search, web fetch, code execution: never enabled ([prompt management](prompt-management.md)) | Same |
| Retention | Zero data retention per organisation by arrangement; "Covered Models" need 30-day retention and are excluded | [API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) |

### Claude model choice

- **Default: Claude Sonnet 5**, which Anthropic describes as the best combination of speed and
  intelligence ([Models overview](https://platform.claude.com/docs/en/models/overview)).
  `Assumption:` it meets the thresholds and the Claude latency budget for every task routed to
  Claude; validated by the cloud-tier suites before the first TestFlight build with Claude.
- **Claude Opus 5.5 only by evidence**, for a task where Sonnet 5 fails a threshold and Opus 5.5
  passes, recorded in the decision register.
- **Excluded:** Covered Models (30-day retention conflicts with the zero-retention requirement) and
  Claude Haiku 4.5 (retirement can come soon after launch).
- **Pinned.** Claude model identifiers are pinned snapshots (same source), and the beta package is
  pinned to an exact version; both change only through the evaluation gate
  ([prompt management](prompt-management.md)).

## Availability checks

| Check | API | Effect |
|---|---|---|
| On-device model | `SystemLanguageModel.default.availability` | Handles `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` as in [AI governance](ai-governance.md) |
| On-device language | `supportsLocale(_:)` | Skip the tier for unsupported languages |
| PCC | `PrivateCloudComputeLanguageModel().availability`, `quotaUsage` | Skip when unavailable or at quota |
| Capabilities | `capabilities.contains(.guidedGeneration)` ([LanguageModelCapabilities](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities)) | Skip models that cannot produce the output type |
| Context | `contextSize` | Sets the budgets for this device and model |
| Network | `NWPathMonitor` ([Network](https://developer.apple.com/documentation/network/nwpathmonitor)) | Offline routing |
| Claude | Consent, credits, circuit breaker, kill switch; relay health after general availability | Skip Claude |

The app uses the framework's availability API rather than device-model lists, as Apple shows
([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)).
Checks run at launch and on returning to the foreground (to decide what the interface offers), and
again before each request.

### Devices without Apple Intelligence

Reading, editing, scanning, OCR, search, signing and Translation-framework translation work fully.
Until V2 these devices get the non-AI tools only: the onboarding AI options stay visible, labelled
with what they need, and lead to the non-AI tools. From V2, intelligence is available to Pro users
through Claude, online and with consent; the options then also lead to the Claude consent screen,
which follows the paywall rule: nothing is shown before first value ([PRD](prd.md), FR-ONB-006).
App Store copy states the Apple Intelligence requirement honestly
([app store strategy](app-store-strategy.md)).

## Quarterly re-evaluation

Every quarter, and also on every iOS release and beta (the on-device model changes with the
operating system), when a provider announces a new model or a deprecation
([Model deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations)), when
the Claude package releases, or when the Private Cloud Compute conditions change:

1. Run every evaluation suite on every tier ([AI evaluation framework](ai-evaluation-framework.md)).
2. Review provider changes: new models, deprecations, retention and data terms, the PCC conditions;
   costs are reviewed in the confidential unit-economics documents.
3. Review field signals: tier mix, answer kept rate, fallback rate
   ([success metrics](success-metrics.md)).
4. Update the qualified tiers and the routing table here; replace assumptions with measurements.
5. Record changes in the [decision register](decision-register.md); a model pin change goes through
   the prompt evaluation gate.

## Adding a new provider

Candidates exist (Apple names Google's Swift package alongside Anthropic's, and open-source
`CoreAILanguageModel` and `MLXLanguageModel` for local models,
[WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)); none is planned.

1. **ADR** covering privacy, retention and training terms, acceptable-use rules, data location,
   availability, the SDK review (privacy manifest, telemetry, licence, exit plan) and cost (held
   privately).
2. **Conformance** to the `LanguageModel` protocol, from the provider's package or our own
   implementation ([LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel)),
   behind the router, pinned to an exact version.
3. **Prompt variants** for each task it will serve ([prompt management](prompt-management.md)).
4. **Full evaluation** on every set; it serves only tasks it qualifies for.
5. **Consent** screen and consent version naming the provider; privacy label and policy updates
   ([privacy architecture](privacy-architecture.md)).
6. **Operations:** kill-switch target, circuit-breaker settings, error mapping, spend limits,
   runbook update ([AI provider failover runbook](process/runbooks/ai-provider-failover.md)).
7. **Staged rollout:** TestFlight first, then an App Store release with phased release. A provider is
   never enabled remotely: remote flags can only turn it off
   ([kill-switch runbook](process/runbooks/kill-switch.md)).
8. **Record** the decision in the [decision register](decision-register.md) and update this document.

## Decision: route to the lowest qualified tier

**Decision.** For each request, use the most private tier that is available, consented, within
budget and has passed the evaluation thresholds for the task and size band.
**Rationale.** Keeps content on the device whenever the device is good enough, makes every cloud
use justified by evidence, and keeps cost proportional to need.
**Trade-offs.** Some answers are on device when a cloud model would be better; routing tables and
evaluation results must be maintained per task and band.
**Alternatives considered.** Always the strongest model (best answers, but breaks privacy by default
and offline use, and cost is unbounded). Letting users pick a model per request (control, but pushes
a technical decision onto every user; the per-provider switches and "Keep on device" give control
without that). Cheapest-first routing (cost optimised, quality and privacy secondary).
**Risks.** A new on-device model with every iOS release can change quality overnight (re-evaluation
on each beta); the PCC conditions can stop holding (kill switch, six-month migration window,
fallback to on device or Claude); the Claude package is beta (pinned, wrapped by the router).
**Future scalability impact.** New providers and on-device models plug in as `LanguageModel`
conformances and join the same qualification process; the relay can later route across providers
on the server side without changing the app's policy.
**Pillars served.** PIL-4, PIL-5, PIL-6.

## Open questions

- Whether the PCC conditions are met for this app, and from when (tracked privately, readiness
  blockers C3 and C4).
- Whether the Claude package's `LanguageModelCapabilities` report image input in a way the router can
  check before sending images.
- Whether Analyse Contract may use Claude under Anthropic's high-risk use-case requirements
  ([AI governance](ai-governance.md)).
- Real tokens-per-page figures for English and French, which set the size bands.
