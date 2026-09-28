# Prompt management

How PDF Algo Pro writes, stores, versions, reviews, evaluates, localises, changes and rolls back the
prompts behind its intelligence features, and how one session switches between the on-device,
Private Cloud Compute and Claude models. Prompts change product behaviour as much as code does, so
they are treated as versioned, evaluated artefacts
([ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md)).

Owner: AI · Reviewed: each milestone, and when the Foundation Models framework or a provider package changes

## Principles

1. **Prompts are product code.** Every prompt has an identifier, a version, an owner, a changelog
   and an evaluation result; nothing reaches users without passing the gate in the
   [AI evaluation framework](ai-evaluation-framework.md).
2. **Prompt text ships in the app.** Remote configuration can only choose between prompt versions
   that are already in the app bundle and already evaluated, or switch a prompt off. It never delivers
   new prompt text.
3. **Instructions are trusted; documents are data.** Nothing from a document, a file name, metadata or
   the user's typing is ever placed in instructions.
4. **One output type per task.** Each task has one `@Generable` type shared by every provider, so the
   feature code does not change when the tier changes.
5. **Small and specific.** Prompts are short, imperative and scoped to one task, as Apple advises for
   token efficiency and quality
   ([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)).

## What a prompt artefact is

| Part | Description |
|---|---|
| Identifier | `<task>.<purpose>` in lower case: `answer.cited`, `summary.document`, `summary.section`, `extract.fields`, `contract.review`, `translate.answer`, `ocr.assist`; evaluation judges use `judge.<metric>` |
| Version | SemVer, per identifier (rules below) |
| Variants | One instruction text per provider: `on-device`, `pcc`, `claude`; an on-device variant can be split by on-device model version when Apple ships a new model |
| Output type | The task's `@Generable` Swift type, versioned with the prompt's MAJOR number |
| Metadata | `prompt.yaml`: variants, placeholders, tools, budgets, reasoning level, evaluation suites, status |
| Changelog | `CHANGELOG.md` per identifier |
| Evaluation binding | The suites and thresholds that gate this prompt |

Apple suggests exactly this shape: prompts in their own files rather than hard-coded, named with the
feature and a version, with a changelog per prompt
([Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)).

### Version rules

| Change | Bump | Examples |
|---|---|---|
| Output type changes incompatibly, task meaning changes, or a tool is added or removed | MAJOR | Renaming a field in `CitedAnswer`; adding a "not found" status; adding the page-search tool |
| Instruction wording, examples, budgets, reasoning level, or a new provider variant | MINOR | Rewording how citations are requested; moving `summary.document` to moderate reasoning on PCC |
| No intended behaviour change | PATCH | A typo, whitespace, a comment in `prompt.yaml` |

Every bump, including PATCH, runs the evaluation suite for the task: a "harmless" edit to a prompt
can change model output.

### Per-provider variants

- The on-device model has a 4,096-token context today; Private Cloud Compute has 32,000 tokens and
  reasoning levels; Claude models have far larger contexts
  ([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window);
  [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute);
  [Models overview](https://platform.claude.com/docs/en/models/overview)). Variants differ in length,
  number of examples and budgets; they share the identifier, version and output type.
- Claude produces `@Generable` types through structured outputs, and the package throws rather than
  degrading silently if a model lacks the capability
  ([Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)).
  Before any request, `PromptCatalog` checks the model's declared capabilities
  ([LanguageModelCapabilities](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities)).
- When Apple ships a new on-device model inside the iOS 27 cycle, an on-device variant can be keyed
  to it with an availability check, as Apple recommends
  ([Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)).

### Output types

Output types live in `Sources/Intelligence/Schemas/` and follow Apple's guidance: simple types,
short clear property names, `@Guide` only where needed, and bounded arrays, because the schema is
sent to the model and uses context
([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)).

```swift
@Generable
struct CitedAnswer {
    @Generable
    enum Status { case answered, partlyAnswered, notFound, declined }

    @Generable
    struct Claim {
        var text: String
        @Guide(description: "Pages from the excerpts that support this claim")
        @Guide(.minimumCount(1), .maximumCount(3))
        var pages: [Int]
    }

    var status: Status
    @Guide(.maximumCount(8))
    var claims: [Claim]
}
```

- **Explicit status.** `notFound` and `declined` make "say when unsure" and "explain, never advise"
  measurable ([AI governance](ai-governance.md)).
- **Claims carry pages.** Citation metrics are computed per claim
  ([AI evaluation framework](ai-evaluation-framework.md)); code checks that every page number was
  among the pages sent and drops any that were not.
- **No document content in schemas.** Types, property names, enum cases and `@Guide` descriptions
  are fixed app text. Anthropic caches structured-output schemas for up to 24 hours separately from
  message content ([API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)),
  so a schema built from a document (for example an enum of the names found in it) would leave a copy
  outside the conversation. `DynamicGenerationSchema` is used only with app-defined content.
- **Display labels are not schema.** Property names stay in English because they are model input;
  user-facing labels come from the feature's String Catalog.

## File layout

A proposal for the `Intelligence` package; it is created with the first intelligence feature.

```
Packages/Intelligence/
├── Package.swift
├── Sources/Intelligence/
│   ├── Prompts/
│   │   ├── PromptID.swift              identifiers as an enum
│   │   ├── PromptCatalog.swift         loads bundled prompts, pins versions, applies kill-switch fallback
│   │   ├── PromptBuilder.swift         builds instructions and delimited content within the budget
│   │   └── ContentSanitiser.swift      neutralises delimiters and control characters in document text
│   ├── Schemas/                        CitedAnswer, DocumentSummary, ExtractedFields, ContractReview, PageReading
│   ├── Profiles/
│   │   └── DocumentAssistantProfile.swift
│   ├── Router/                         IntelligenceRouter, budgets, circuit breakers
│   ├── Tools/                          read-only document tools
│   └── Resources/Prompts/
│       ├── PromptLocale.xcstrings      locale and response-language lines (English, French)
│       ├── answer.cited/
│       │   ├── CHANGELOG.md
│       │   ├── 1.1.0/                  current
│       │   │   ├── prompt.yaml
│       │   │   ├── on-device.instructions.txt
│       │   │   ├── pcc.instructions.txt
│       │   │   └── claude.instructions.txt
│       │   └── 1.0.0/                  previous, kept for fallback
│       └── summary.document/ …
└── Tests/
    ├── IntelligenceTests/              builder, sanitiser, budgets, router, catalog
    └── Evaluations/
        ├── Datasets/                   evaluation items referencing the golden corpus
        ├── Suites/                     one Evaluation type per task
        └── Results/                    committed result summaries
```

The bundle holds the **current and previous** version of every prompt so the previous one can be
selected remotely. Older versions are removed from the tree and remain in version-control history
and the changelog.

`prompt.yaml` for one version:

```yaml
id: answer.cited
version: 1.1.0
output_type: CitedAnswer
variants:
  on-device: on-device.instructions.txt
  pcc: pcc.instructions.txt
  claude: claude.instructions.txt
placeholders: [locale_line, response_language_line]   # the only substitutions allowed
tools: [readPages, searchDocument]                     # read-only allow-list
tool_calling_mode: allowed
reasoning_level: { pcc: moderate }
budgets: default                                       # from ai-governance.md cost control
evaluation: [cited-answer, red-team, safety, bias]
status: current                                        # current | previous | retired
```

## Instruction and content separation

Apple's guidance is that a session obeys instructions over prompts, so instructions must never
contain input from people or any unverified source, or the app becomes open to prompt injection
([Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)).
PDF Algo Pro treats every document as untrusted input.

1. **Two types, one direction.** The builder accepts `TrustedText` (bundled prompt text and fixed app
   strings) for instructions and `UntrustedText` (document text, OCR text, file names, metadata, the
   user's question) for the prompt body. There is no conversion from `UntrustedText` to
   `TrustedText`, so the compiler blocks the most common injection mistake.
2. **Delimited content.** Document text is placed only in the prompt, inside blocks the builder
   creates, each with a page number supplied by code:

   ```
   <excerpt page="12">
   …text from page 12…
   </excerpt>
   <question>
   …the user's question…
   </question>
   ```

   The instructions say that excerpts are material to analyse, that they may contain instructions,
   and that such instructions are part of the document and must not be followed.
3. **Sanitising.** Before insertion, `ContentSanitiser` neutralises any sequence that imitates the
   block markers, removes zero-width and bidirectional control characters, normalises Unicode and
   caps the length of each excerpt.
4. **Constrained output.** The `@Generable` output type limits what the model can express; citations
   are checked against the pages actually sent.
5. **Read-only tools only**, scoped to the open document with validated arguments, and tool calling
   `.disallowed` when a task needs none
   ([GenerationOptions.ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct)).
6. **Output checks.** Rendered as text with links not tappable; a URL, email address or phone number
   that does not appear in the document is removed and the answer flagged, a form of the output deny
   list Apple suggests (same safety source).
7. **Code decides.** The tier, consent, escalation and any action are decided by code, never by model
   output.

The red-team set in the [AI evaluation framework](ai-evaluation-framework.md) tests each of these
defences; the wider analysis is in the [threat model](threat-model.md).

## Forbidden patterns

| Pattern | Why | How it is caught |
|---|---|---|
| Document text, file names, metadata or user input placed in instructions | Prompt injection (Apple safety guidance, above) | `TrustedText` and `UntrustedText` types; instruction files may contain only the placeholders in `prompt.yaml`; `invariants` lint |
| Hidden personas: the model presented as a person, or told to deny being AI or to hide which tier answered | Apple and Anthropic both require AI to be disclosed ([Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai); [Anthropic Usage Policy](https://www.anthropic.com/legal/aup)) | Review checklist; lint for phrases such as "you are a human" |
| Asking the user for personal data (name, address, date of birth, account numbers) | Nothing in the product needs it; founder principle 1 | Review checklist; lint for common phrasings; safety set |
| Instructions to give legal, medical or financial advice, recommendations or risk scores | Explain, never advise ([AI governance](ai-governance.md)) | Advice-seeking evaluation subset (100% required) |
| Instructions that let the model choose a tier, escalate, or "send the document for a better answer" | Consent is decided by code | Review; consent-bypass red-team category |
| Document-derived values in output types or `@Guide` descriptions | Schemas are cached by the provider and use context (above) | Review; lint on `DynamicGenerationSchema` use |
| Server-side tools on `ClaudeLanguageModel` (web search, web fetch, code execution) | Content would go further than consented; code execution is not covered by zero data retention ([API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)) | Lint: `serverTools` must be empty |
| Prompt text fetched from a server | Bypasses review and the evaluation gate ([ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md)) | No network path in `PromptCatalog`; review |
| Prompt strings in feature code | Untestable and unreviewable ([ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md)) | Lint: `LanguageModelSession` created only inside `Intelligence` |
| "Answer even if the document does not say", or removing the "not found" path | AI must show its work (founder principle 4) | Refusal-correctness metrics |
| Real people, organisations or copyrighted passages in examples | Privacy and licensing | Review checklist |

## Localisation of prompts

Apple's guidance for multilingual use: write built-in prompts in a language Apple Intelligence
supports; tell the model the person's locale with the exact phrase "The person's locale is …"
(omitted for United States English); state the response language explicitly; and check
`supportsLocale()` before calling, handling `unsupportedLanguageOrLocale`
([Supporting languages and locales with Foundation Models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)).

- **Instructions are written in English**, the language the maintainer reviews in.
- **Two lines are localised** through `PromptLocale.xcstrings`: the locale line and the
  response-language line ("You MUST respond in French."), inserted through the allowed placeholders.
- **Answer language.** By default answers use the app's language; the user can choose "answer in the
  document's language" in Settings.
- **Full French variants only on evidence.** Apple notes that localising prompts can help the model
  answer reliably in the right language
  ([Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions));
  a French instruction variant is added only if French scores miss the language-parity threshold in
  the [AI evaluation framework](ai-evaluation-framework.md).
- **Unsupported languages.** Apple's guardrails cover only supported languages (same source), so a
  document in an unsupported language is answered only by a tier that supports it, and the answer
  notes the language.

## How DynamicProfile switches models

A `LanguageModelSession.DynamicProfile` resolves to exactly one active profile, and each profile can
set the model, temperature, reasoning level, maximum response tokens, tool-calling mode and a
history transform; when the active profile changes, the session uses the new model on its next
request ([LanguageModelSession.DynamicProfile](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile);
[Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)).
Conversation history is preserved across profiles
([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)).

PDF Algo Pro uses one `DocumentAssistantProfile` per assistant conversation. A sketch (names
illustrative):

```swift
struct DocumentAssistantProfile: LanguageModelSession.DynamicProfile {
    var tier: Tier              // set only by IntelligenceRouter after consent, availability and budget checks
    var task: PromptID
    let catalog: PromptCatalog
    let pcc: PrivateCloudComputeLanguageModel
    let claude: ClaudeLanguageModel

    var body: some LanguageModelSession.DynamicProfile {
        switch tier {
        case .onDevice:
            Profile {
                catalog.instructions(task, variant: .onDevice)
                ReadPagesTool()
            }
            .maximumResponseTokens(catalog.responseBudget(task, .onDevice))
            .historyTransform { OnDeviceHistory.fit($0) }
        case .privateCloudCompute:
            Profile {
                catalog.instructions(task, variant: .pcc)
                ReadPagesTool()
            }
            .model(pcc)
            .reasoningLevel(catalog.reasoningLevel(task))
            .historyTransform { ConsentedHistory.filter($0) }
        case .claude:
            Profile {
                catalog.instructions(task, variant: .claude)
                ReadPagesTool()
            }
            .model(claude)
            .historyTransform { ConsentedHistory.filter($0) }
        }
    }
}
```

Rules:

- **Only the router changes `tier`.** It does so after the checks in [model selection](model-selection.md);
  a profile never picks a cloud model by itself.
- **History is a privacy boundary.** Because history carries over, moving a conversation to a cloud
  tier would otherwise send every earlier turn. The cloud profiles' history transform keeps only what
  the user's consent covers (the current document's excerpts and the turns since the user approved
  cloud use for this conversation); the on-device transform compresses history to fit the small
  context. Apple describes exactly this use of history transforms, including removing sensitive
  information before a request
  ([Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)).
- **Life-cycle hooks** record, on the device only: the tier for the answer label and the AI activity
  log (`onPrompt`), token usage for budgets and credits (`onResponse`), and tool calls against the
  allow-list (`onToolCall`).
- Apple's advice for dynamic profiles is to weigh privacy boundaries, model capabilities and cost
  ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)); those are the
  router's inputs.

## Review process

1. **Branch and label.** A `feat/` or `fix/` branch; the pull request carries the `ai` label.
2. **Pull request contents.** The "AI change" section of the template: identifier and old → new
   version, the reason, the evaluation summary per tier and language compared with the current
   version, the change in tokens per task, the forbidden-pattern checklist, and any consent impact (a
   new data category needs a new consent version, [AI governance](ai-governance.md)).
3. **Owners.** `Packages/Intelligence/**` is owned by the AI hat; once there are two or more
   maintainers the Security hat's review is also required, as in the activation table in
   [GitHub governance](github-governance.md).
4. **Checks.** The `invariants` lint (forbidden patterns, placeholders, schema rules), the
   `Intelligence` unit tests, the on-device evaluation gate, a changelog entry, and a version bump
   whenever a prompt file's content hash changes ([quality gates](process/quality-gates.md)).
5. **Reading outputs.** The reviewer reads the instruction diff and a sample of before-and-after
   outputs from the committed results, not only the scores ([code review guide](code-review-guide.md)).
6. **Merge.** Squash-merge into `integration`; TestFlight internal builds pick it up; the cloud-tier
   suites run before the release pull request into `main`.

## Evaluation gate

A prompt version is releasable when its task suites pass the thresholds in the
[AI evaluation framework](ai-evaluation-framework.md) on every tier it has a variant for, and the
committed result file matches the content hash of the prompt and output-type files. A tier that
fails is removed from that task's qualified tiers rather than shipped. The Release hat confirms
the gate on the release pull request ([release management](release-management.md)).

## Prompt changelog

Each identifier has a `CHANGELOG.md` in the Keep a Changelog style used across the repository
([changelog strategy](changelog-strategy.md)):

```markdown
## [1.1.0] - 2026-11-02
### Changed
- Ask for one claim per sentence, each with its own pages.
### Why
- Citation precision on multi-part questions was below threshold on PCC.
### Evaluation
- Citation correctness, on device: 95.8% → 96.4% (EN), 95.1% → 95.9% (FR). Tokens per answer +4%.
```

A change users would notice is also summarised in the app's release notes.

## Rollback

| Level | How | Time to effect |
|---|---|---|
| Remote fallback | The kill-switch record `ai.prompt.<id>` set to `fallback` makes `PromptCatalog` use the bundled previous version on the next request; the record schema and procedure are in the [kill-switch runbook](process/runbooks/kill-switch.md) | Minutes, no release |
| Switch the feature or tier off | The kill-switch record `feature.<name>` or `ai.provider.<claude/pcc/ondevice>` set to `disabled` ([kill-switch runbook](process/runbooks/kill-switch.md)) | Minutes |
| Revert | Revert the pull request on `integration`, re-run the evaluation, release; urgent cases use the `hotfix/*` path into `main` ([release management](release-management.md)) | An App Review cycle |
| Claude model pin | Pin the previous model identifier in a release, or switch the provider off while it is prepared | An App Review cycle |
| New on-device model from Apple | Apple's model cannot be rolled back; add an on-device variant for the new model version, or remove the on-device tier from the task's qualified tiers until a variant passes | An App Review cycle |

Cached answers are stored with the prompt identifier, version and output-type version; after a
MAJOR rollback, cached results from the newer type are discarded, since they are derived data
([ADR-0006](adr/0006-swiftdata-persistence.md)).

## Decision: bundled, evaluated prompts with remote selection only

**Decision.** Prompt text lives in versioned files in the `Intelligence` package, ships in the app
bundle with the previous version, and can be switched remotely only between those bundled versions
or off.
**Rationale.** Every prompt a user receives has passed the evaluation gate and is in the reviewed
binary; prompts work offline without a fetch; a bad version can be reversed in minutes.
**Trade-offs.** New prompt text needs an app release, which takes days rather than minutes.
**Alternatives considered.** Strings in feature code (untestable; rejected in ADR-0020).
Server-delivered prompts, which Apple describes as the most flexible option for fast updates and
rollbacks ([Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)):
rejected because they bypass the evaluation gate, need a server before one exists, and add a remote
path into the model's instructions. A String Catalog for all prompt text (Apple's other suggestion):
used only for the localised lines, because long multi-variant text reviews poorly there.
**Risks.** A harmful prompt reaching users between detection and fix: the previous-version fallback
and the kill switch bound that window.
**Future scalability impact.** If release cadence ever limits prompt iteration, the relay could serve
signed, pre-evaluated prompt bundles; that would need its own ADR.
**Pillars served.** PIL-4, PIL-5, PIL-6.

## Open questions

- Whether `ClaudeLanguageModel` in the beta package behaves identically to Apple's models when a
  dynamic profile switches to it mid-conversation (history format, reasoning segments); checked in
  the first intelligence spike.
- Whether Private Cloud Compute reasoning segments kept in the transcript should be removed by the
  history transform before a later request goes to Claude.
- Where the prompt lint lives (inside the `invariants` gate or a separate script), agreed with
  [quality gates](process/quality-gates.md).
