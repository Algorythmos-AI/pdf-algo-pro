# Code review guide

How changes to PDF Algo Pro are reviewed: what the author checks before asking, what the reviewer
checks, how quickly reviews happen, how the one maintainer reviews their own work while there is no
second reviewer, how AI and prompt changes and agent-authored pull requests are reviewed, and who
must approve what as roles are assigned. Review protects users, the product's privacy promise and
this public repository; style is left to the formatter.

Owner: Maintainer · Reviewed: each milestone, and whenever a role is assigned to a new person

## What review is for

1. **Correctness**: the change does what the issue asks, and nothing else, on every path.
2. **Safety**: user documents, privacy, security and this public repository are protected.
3. **Maintainability**: the next person understands the change in the context of the ADRs and
   standards ([engineering playbook](engineering-playbook.md)).
4. **Shared understanding**: decisions are visible in the pull request, not only in someone's head.

Formatting, import order and most naming questions are settled by `swift-format`
([Swift style guide](swift-style-guide.md#formatting-with-swift-format)) and are not review topics.

## Author checklist

Before marking a pull request ready for review:

- [ ] One change, linked to its issue; under 400 changed lines of code, or the description explains
      why not ([pull request expectations](engineering-playbook.md#pull-request-expectations)).
- [ ] The title is a Conventional Commit with the right scope; the
      [template](../.github/PULL_REQUEST_TEMPLATE.md) is complete, including how it was tested.
- [ ] I read the diff in GitHub's "Files changed" view, as a reviewer would, and removed debug code,
      stray files and `TODO`s without an issue.
- [ ] Tests cover the new behaviour and fail without the change.
- [ ] UI changes include screenshots (light, dark, largest accessibility size, French) and a
      recording for interactions, using synthetic documents only.
- [ ] Performance-sensitive changes include signpost or metric numbers before and after.
- [ ] Any new data flow is described: what data, which class, where it goes, and the consent that
      covers it.
- [ ] Docs, CHANGELOG `[Unreleased]`, ADRs and [working memory](working-memory.md) are updated
      where state or behaviour changed.
- [ ] All required checks are green, or the failure is explained and being fixed; no check was
      disabled or skipped.

## Reviewer checklist

Work through the sections that the change touches. Every finding is a comment on the pull request,
so the reasoning stays with the code.

### Correctness

- [ ] It meets the acceptance criteria, and only them.
- [ ] Edge cases for documents: empty, one page, 1,000 pages, encrypted, damaged, scanned only,
      forms, annotations from other apps, read-only locations.
- [ ] Edge cases for the environment: offline, iCloud signed out or not downloaded, low storage,
      background and termination during a save, two devices editing the same file.
- [ ] Concurrency: isolation is right, values crossing boundaries are `Sendable`, actor state is
      re-checked after `await`, cancellation is honoured ([coding standards](coding-standards.md#concurrency)).
- [ ] Errors: the package's error type, no swallowed failures, user-facing messages that say what
      to do ([coding standards](coding-standards.md#error-handling)).

### Tests

- [ ] Tests describe behaviour, not implementation; each asserts something that matters.
- [ ] They are deterministic: no sleeps, no network, injected clocks and seeds, synthetic data.
- [ ] The right suites changed: snapshots for UI, golden corpus for document handling, contract
      tests for `PDFEngine`, OCR accuracy for recognition, evaluation cases for AI
      ([testing strategy](testing-strategy.md)).
- [ ] Coverage stays at or above 80% overall and per target, and the covered lines are meaningful
      ([ADR-0014](adr/0014-testing-strategy-and-coverage.md)).

### Accessibility

- [ ] Labels, traits and grouping make sense with VoiceOver; icon-only controls have titles.
- [ ] Layout works at the largest accessibility text size, with Increase Contrast and Reduce Motion.
- [ ] Targets are large enough and state is not shown by colour alone
      ([coding standards](coding-standards.md#accessibility-by-default)).

### Performance

- [ ] No blocking work on the main actor; heavy work is in actors or `@concurrent` functions.
- [ ] Budgeted operations keep their signposts, and the change does not threaten a budget in
      [performance budgets](performance-budgets.md).
- [ ] No large data in observable state; lists are lazy with stable identities.

### Privacy and data flow

- [ ] Nothing new leaves the device; or it does only through a cloud tier the user opted into, and
      the consent text still names the provider and the data ([ADR-0009](adr/0009-tiered-ai-and-consent.md)).
- [ ] Nothing confidential or restricted is logged, cached in a shared location or sent in
      telemetry ([data classification](data-classification.md), [coding standards](coding-standards.md#logging)).
- [ ] The privacy manifest and the App Store privacy label still describe the app
      ([privacy architecture](privacy-architecture.md)).

### Security and the threat model

- [ ] Document input is handled as untrusted: typed errors, bounded work, no active content, links
      confirmed before opening.
- [ ] Deep links, intents and shared URLs only navigate.
- [ ] Prompts keep document text separate from instructions; model output cannot trigger actions.
- [ ] Redaction removes content and is tested as such.
- [ ] New entitlements, permissions, Keychain use or network endpoints are justified, and the
      [threat model](threat-model.md) is updated if a mitigation changed.

### Localisation

- [ ] Every user-facing string is in a String Catalog with a comment, in English and French.
- [ ] No concatenated sentences; plurals use catalog variants; formatters for dates and numbers.
- [ ] Leading and trailing, not left and right; nothing breaks in right-to-left layout.

### Apple-first baseline and non-goals

- [ ] The change uses the platform capability that fits (App Intents, Spotlight, Files, drag and
      drop, keyboard, widgets) where the feature calls for it
      ([ADR-0022](adr/0022-apple-first-capability-baseline.md)).
- [ ] No web views standing in for native screens, no SaaS patterns, no cross-platform toolkit.
- [ ] It is not one of the [non-goals](non-goals.md).
- [ ] Which [founder principles](founder-principles.md) does it touch, and does it honour them?

### Documentation and working memory

- [ ] The CHANGELOG, ADRs, runbooks and indexes are current; a decision that changes course has its
      own ADR or [decision register](decision-register.md) entry.
- [ ] [Working memory](working-memory.md) reflects the new state.

### Public-safety rules

This repository is public ([repository standards](repository-standards.md)). Block the pull request
if the diff, a screenshot, a recording, a fixture or a comment contains any of:

- [ ] Secrets, credentials, certificates or the Apple Team ID.
- [ ] Prices, revenue figures, business targets, or a link to the private companion repository.
- [ ] Apple account facts, company records, billing status or internal organisation details.
- [ ] Personal data, a real document, or a screenshot showing either.
- [ ] Security findings about this or any other repository (those go through
      [private reporting](../.github/SECURITY.md)).
- [ ] Tool-attribution trailers in commits, or an AI-tool name in the README or repository
      description.

## Writing review comments

- Prefix each comment with its weight: **blocking:** (must change before merge), **suggestion:**
  (worth doing, author decides), **question:** (the reviewer needs to understand), **nit:** (minor,
  optional).
- Explain why, with a link to the standard, ADR or documentation it rests on.
- Comment on the code, not the person. Praise what is good; it teaches as much as criticism.
- Resolve every thread before merging; the rulesets require resolved conversations
  ([integration ruleset](../.github/rulesets/integration.json)).

## Review times

`Assumption:` once there is more than one reviewer, these are the targets, in Sydney business days.
Validation: measure time to first response on merged pull requests each milestone and adjust.

| Pull request | First response | Decision (approve or request changes) |
|---|---|---|
| Security fix or `priority:p0` | Same business day | Same business day |
| Release pull request into `main` | Within one business day | Within one business day |
| `size:s` or `size:m` | Within one business day | Within two business days |
| `size:l` | Within one business day, with a time agreed for the full review | As agreed |

An author who is blocked past these times says so on the pull request; a reviewer who cannot meet
them hands the review to someone else and says so.

## Solo-phase self-review protocol

While one maintainer holds every role, the rulesets require no approvals
([github-governance](github-governance.md)), so review is a discipline rather than a gate.

1. **Separate writing from reviewing.** Open the pull request, let CI finish, then review it in
   GitHub's "Files changed" view with the [reviewer checklist](#reviewer-checklist), leaving
   comments for anything to fix. The comments are the record that the review happened.
2. **Record the review.** Add a short "Self-review" note to the description: the checklist sections
   covered and anything deliberately left out.
3. **Wait a day for risky changes.** A change is risky if it touches: privacy or consent, the
   `Intelligence` package or prompts, `Commerce` or entitlements, redaction, file saving or
   migrations, security controls, CI workflows or rulesets, or it is a release pull request. Review
   it again no sooner than the next day, after at least one night away from it, before merging.
4. **The gates are not negotiable.** All required checks pass. The organisation-admin bypass in the
   rulesets is for a documented emergency only, recorded in the
   [decision register](decision-register.md) and [working memory](working-memory.md).
5. **A second opinion is welcome, never a substitute.** An automated review may add findings; each
   is answered on the pull request, and the maintainer's own review still happens.

### Decision: self-review with a wait-a-day rule while there is one maintainer

- **Rationale.** Rulesets requiring an approval would block every merge while there is only one
  person; no review at all would let risky changes through on the day they were written. Reading
  the diff as a reviewer, after a night away for risky changes, recovers much of the benefit of a
  second reader at no cost to flow.
- **Trade-offs.** Risky changes wait at least a day. Self-review still misses what the author
  cannot see.
- **Alternatives considered.** Requiring one approval now (impossible to satisfy); relying on CI
  alone (checks do not see design, privacy intent or product fit); an external reviewer (not
  available, and this repository is public but contributions are by invitation).
- **Risks.** The protocol erodes under deadline pressure. Mitigation: the "Self-review" note is
  part of the Definition of Done, and missing notes are counted at the milestone review.
- **Future scalability impact.** The checklist is the same one a second reviewer uses, so switching
  on required approvals changes who reviews, not how.

## Reviewing AI and prompt changes

Any change to a prompt, a model, a tier's routing, `@Generable` output types, retrieval or consent
text runs the AI evaluation suite before merging ([ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md),
[AI evaluation framework](ai-evaluation-framework.md)). The author attaches the results; the
reviewer checks:

- [ ] The evaluation results are attached for the changed prompt version: each metric against its
      threshold and against the previous version, including citation accuracy, grounding,
      hallucination, the prompt-injection red-team set, latency and cost per tier.
- [ ] No threshold fails, and any drop against the previous version is explained.
- [ ] The prompt identifier and version were bumped, and the prompt changelog has an entry
      ([prompt management](prompt-management.md)).
- [ ] A sample of outputs was read, not only the scores: at least ten cases, including failures.
- [ ] Document text is still separated from instructions; no new tool can act on the user's behalf.
- [ ] What each cloud tier receives is unchanged, or the consent text and the
      [privacy architecture](privacy-architecture.md) are updated with it.
- [ ] Nothing about prompts or models is fetched remotely at run time.
- [ ] Offline and "not available" behaviour still works: the on-device path, the fallback order
      and the messages ([ADR-0021](adr/0021-ai-provider-routing-and-failover.md),
      [model selection](model-selection.md)).
- [ ] A new provider or model family has an ADR and an [AI governance](ai-governance.md) review.

## Reviewing agent-authored pull requests

Coding agents work under [SUPERVISION.md](../.github/SUPERVISION.md). Their pull requests pass the
same gates and checklists as anyone's; these checks come first, because agents fail in
characteristic ways:

- [ ] **The claims are true.** The description matches the diff; the stated tests exist and ran in
      CI.
- [ ] **The APIs exist.** A successful build proves it for code; for documentation, every new link
      is opened and every cited fact is checked against its source.
- [ ] **The tests test something.** Spot-check that a key test fails when the change is reverted;
      reject tests that only assert what the code happens to return.
- [ ] **The scope is the request.** No unrelated edits, drive-by refactors or reformatting.
- [ ] **Nothing protected changed without approval.** CI workflows, rulesets, `AGENTS.md`,
      `SUPERVISION.md`, `CODEOWNERS`, dependencies, entitlements and repository settings change only
      when the maintainer asked for it in the conversation.
- [ ] **No gate was weakened.** No skipped or disabled tests, lowered thresholds, broadened
      exclusions or `swift-format-ignore` without a reason.
- [ ] **Public-safety rules hold**, including no attribution trailers.
- [ ] **Assumptions are labelled** and [working memory](working-memory.md) is updated honestly.

The agent never merges. The person who merges is accountable for the change as if they had
written it.

## Approval thresholds by role

The roles and their activation are defined in [github-governance](github-governance.md) and the
rulesets in [.github/rulesets](../.github/rulesets/main.json); this is how they apply to review.

| Change | Today (one maintainer) | Once the role is held by a second person |
|---|---|---|
| Any pull request into `integration` | 0 approvals; self-review protocol | 1 approval from a maintainer other than the author |
| `Intelligence`, `Commerce`, entitlements, privacy manifest, consent text | 0; wait-a-day rule | Approval from the Security role (code owner) |
| Pull request into `main` (release or hotfix) | 0; wait-a-day rule; release checklist | Approval from the Release role |
| ADRs and architecture changes | 0; wait-a-day rule | Approval from the Architecture role |
| CI workflows, rulesets, `CODEOWNERS`, `AGENTS.md`, `SUPERVISION.md` | 0; wait-a-day rule | Approval from the Maintainer role, and Security for workflows |
| Documentation only | 0 | 1 approval from any maintainer |

In every phase, a push after approval dismisses the approval, and all review threads must be
resolved before merging (both are set in the rulesets).

## Open questions

- Whether the automated second-opinion review in the self-review protocol should run on every pull
  request or only on risky ones, and where its findings are kept.
- Path owners for `CODEOWNERS` when the first roles are assigned ([github-governance](github-governance.md)).
