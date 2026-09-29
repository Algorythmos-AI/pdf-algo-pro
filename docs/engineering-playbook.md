# Engineering playbook

How PDF Algo Pro is engineered: the principles behind the engineering standards, how a change
travels from an issue to the App Store, what "ready" and "done" mean, and the rules for pull
requests, branches, commits, technical debt, feature flags, deprecation and coding agents. This is
the hub for the engineering documents; each topic links to the document that owns the detail. The
standards apply from the first code pull request; until the readiness gate clears there is no
application code ([AGENTS.md](../AGENTS.md), [readiness review](readiness-review.md)).

Owner: Architecture · Reviewed: each milestone

## How would Apple run this repo?

The question is a quality bar, not a claim about Apple's internal processes, which are not public.
We answer it with what Apple and the Swift project publish: the
[Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/), the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/), Swift 6
data-race safety ([Swift 6 migration guide](https://www.swift.org/migration/documentation/migrationguide/)),
Apple's test frameworks ([Swift Testing](https://developer.apple.com/documentation/testing),
[XCTest](https://developer.apple.com/documentation/xctest)) and the tools that ship with Xcode,
applied by people who expect to maintain this code for five to ten years
([founder principles](founder-principles.md)).

### Engineering principles

1. **Platform first.** Use an Apple framework and the platform convention before writing our own or
   adding a dependency ([ADR-0022](adr/0022-apple-first-capability-baseline.md)). A third-party
   dependency needs an ADR.
2. **Privacy by construction.** Data flow is reviewed like code. Document content stays on the
   device unless the user opts in to a named cloud tier ([ADR-0009](adr/0009-tiered-ai-and-consent.md),
   [privacy architecture](privacy-architecture.md)).
3. **Budgets are requirements.** Performance budgets, accessibility and localisation are acceptance
   criteria, not polish ([performance budgets](performance-budgets.md)).
4. **Automate the rule, not the reminder.** When a rule matters, a gate enforces it (`invariants`,
   the coverage gate, `pr-title`, `swift-format --strict`). Rules that cannot yet be automated live
   in review checklists, and move into a gate as soon as they can.
5. **Small, reversible changes.** One change per pull request; `integration` is always releasable;
   unfinished work sits behind a flag.
6. **Decisions are written down.** Architecture in [ADRs](adr/README.md), product and process in the
   [decision register](decision-register.md), current state in [working memory](working-memory.md).
7. **Tests describe behaviour.** Every behaviour change arrives with the test that proves it.
8. **Understandable in 30 minutes.** Code, documents and history are organised so the next person,
   or agent, finds their way without asking.
9. **One path for everyone.** People and coding agents follow the same flow, gates and review.
   Nobody bypasses a gate to get green.

## The engineering standards

| Document | What it owns |
|---|---|
| [Coding standards](coding-standards.md) | Architecture and dependency rules, errors, logging, security, localisation, accessibility, performance, concurrency, dependencies, comments |
| [Swift style guide](swift-style-guide.md) | Swift and SwiftUI idioms, naming, file layout, previews, the `swift-format` configuration |
| [Code review guide](code-review-guide.md) | Author and reviewer checklists, review times, the solo-phase self-review, AI and agent changes, approvals |
| [Testing strategy](testing-strategy.md) | Test pyramid, every suite, OCR accuracy, the golden PDF corpus, coverage, flaky tests, test data |
| [Quality gates](process/quality-gates.md) | Which checks a change passes, and at which stage |
| [Branching](process/branching.md) | The two-branch model and merge rules ([ADR-0016](adr/0016-two-branch-model.md)) |
| [Release management](release-management.md) | Release pull requests, TestFlight, App Store, phased release, hotfixes, tags |
| [GitHub governance](github-governance.md) | Roles, approvals, rulesets, CODEOWNERS |
| [Repository standards](repository-standards.md) | Public-safety rules for this public repository |
| [Changelog strategy](changelog-strategy.md) | How the CHANGELOG feeds release notes |

## How work flows

```
issue ── triage (status:triage → status:ready, milestone, labels)
  └─► branch from integration: <type>/<description>
        └─► pull request: Conventional Commit title, template filled in
              └─► required checks: pr-title · secrets / Secret scan · docs ·
                  invariants · dependency-review · ios
                    └─► review (self-review protocol while there is one maintainer)
                          └─► squash-merge into integration
                                └─► Xcode Cloud Staging build ─► TestFlight internal
                                      └─► release PR integration → main (merge commit,
                                          + promotion-guard, release checklist)
                                            └─► Xcode Cloud Release build ─► TestFlight external
                                                ─► App Store (phased release)
                                                  └─► release.yml: tag vX.Y.Z, GitHub Release,
                                                      docs mirrored to the wiki

hotfix/* from main ─► squash-merge into main ─► back-merge into integration
```

1. **Issue.** Every change starts from an issue created from a template (bug, feature or epic,
   research or spike, non-sensitive security hardening). A docs-only fix of size `size:s` may skip
   the issue if the pull request says why. Vulnerabilities never go in issues
   ([SECURITY.md](../.github/SECURITY.md)).
2. **Triage.** The issue gets a priority (`priority:p0` to `priority:p3`), a size (`size:s` to
   `size:l`; `size:xl` is split into an epic), platform and area labels, and a milestone
   (Foundation, MVP, V1, V1.1, V2). It moves from `status:triage` to `status:ready` when it meets
   the [Definition of Ready](#definition-of-ready) ([project management](project-management.md)).
3. **Branch.** From `integration`, named as in [branches](#branch-names).
4. **Build and check locally.** Generate the project with XcodeGen, build with Xcode 27, format with
   `swift-format`, and run the tests for the packages you touched
   ([Swift style guide](swift-style-guide.md#formatting-with-swift-format)).
5. **Pull request.** Open it early as a draft if you want feedback. The title is a Conventional
   Commit; the [template](../.github/PULL_REQUEST_TEMPLATE.md) is filled in; the issue is linked
   (`Closes #123`).
6. **Gates.** The required checks in the `integration` ruleset must pass: `pr-title`,
   `secrets / Secret scan`, `docs`, `invariants`, `dependency-review` and `ios`
   ([ci.yml](../.github/workflows/ci.yml), [quality gates](process/quality-gates.md)). The CodeQL
   jobs run but are not required checks yet; [GitHub governance](github-governance.md) says when
   each one becomes required. The `ios` job runs only when Swift or project inputs change; a job
   skipped by its condition reports success, so it never blocks a documentation change
   ([GitHub Actions: control jobs with conditions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions)).
7. **Review.** As described in the [code review guide](code-review-guide.md). Review threads must be
   resolved before merging (the rulesets require it).
8. **Squash-merge into `integration`.** Squash is the only merge method the `integration` ruleset
   allows, so each pull request becomes one commit whose subject is the pull request title.
9. **Staging.** Xcode Cloud builds the Staging configuration from `integration` and distributes it
   to internal TestFlight testers ([ADR-0013](adr/0013-ci-cd.md)).
10. **Release pull request.** `integration` into `main`, titled `release: X.Y.Z` (for example `release: 1.2.0`), merged with a merge
    commit. The `promotion-guard` check allows only `integration` or `hotfix/*` into `main`. The
    release checklist lives in [release management](release-management.md).
11. **Production.** Xcode Cloud builds the Release configuration from `main` for external TestFlight
    and the App Store, released in phases.
12. **Tag and publish.** After App Store approval, the Release role runs `release.yml`, which tags
    `vX.Y.Z`, publishes the GitHub Release from the CHANGELOG section and mirrors `docs/` to the wiki.

Hotfixes branch from `main` as `hotfix/<description>`, squash-merge into `main` through the same
gates, and are back-merged into `integration` ([branching](process/branching.md)).

## Definition of Ready

An issue is `status:ready` when:

- [ ] The problem and the outcome are clear, with acceptance criteria (Given / When / Then for
      features).
- [ ] It maps to at least one pillar (PIL-1 to PIL-7) and is not a [non-goal](non-goals.md).
- [ ] Priority, size (at most `size:l`), platform labels and a milestone are set.
- [ ] Dependencies are known and none is blocking (otherwise `blocked` or `status:blocked-external`).
- [ ] UI work has a design covering light and dark appearance, the largest accessibility text size,
      right-to-left layout, and empty, loading and error states ([design system](design-system.md)).
- [ ] New data flows are named, with their data class ([data classification](data-classification.md))
      and whether anything leaves the device.
- [ ] Affected performance budgets are identified ([performance budgets](performance-budgets.md)).
- [ ] The test approach is noted (which suites change; new evaluation cases for AI features).
- [ ] Apple platform capabilities that apply are listed
      ([ADR-0022](adr/0022-apple-first-capability-baseline.md)).

## Definition of Done

A change is done when:

- [ ] The acceptance criteria are met on iPhone in every size class, and iPad layouts are not broken.
- [ ] All required checks pass; nothing was skipped or disabled to get there.
- [ ] Tests cover the new behaviour; line coverage stays at or above 80% overall and per target
      ([ADR-0014](adr/0014-testing-strategy-and-coverage.md)).
- [ ] UI changes have snapshot tests, pass the accessibility audit, and were checked with VoiceOver,
      the largest text size and Increase Contrast.
- [ ] Every new user-facing string is in a String Catalog with a translator comment, in English and
      French. If the French translation is not ready, the feature stays behind a flag and the issue
      stays open.
- [ ] Budgeted operations have signposts and still meet their budgets.
- [ ] The privacy manifest, data classification and threat model are updated when the change
      touches them.
- [ ] The CHANGELOG `[Unreleased]` section, ADRs, runbooks and [working memory](working-memory.md)
      are updated where state or behaviour changed.
- [ ] The pull request was reviewed as the [code review guide](code-review-guide.md) requires and
      squash-merged into `integration`; the issue is closed by the merge.

## Pull request expectations

| Expectation | Detail |
|---|---|
| One change | One purpose per pull request. Refactoring, formatting sweeps and behaviour changes go in separate pull requests. |
| Size | At most 400 changed lines of code (see the decision below). |
| Title | A Conventional Commit, checked by `pr-title` ([commit titles](#commit-and-pull-request-titles)). |
| Description | The template in full: what and why, how it was tested, pillars and platforms, checklist. |
| Evidence for UI | Screenshots before and after, in light and dark, at the largest accessibility text size and in French; a screen recording for any interaction or animation. Use synthetic documents only, and a neutral simulator status bar (`xcrun simctl status_bar booted override --time 9:41`). |
| Tests | Added or updated for every behaviour change; the reason is stated when a change has none (for example, documentation only). |
| Documentation | CHANGELOG `[Unreleased]` for user-visible changes; ADR for an architecture decision; runbook for an operational change. |
| Working memory | [Working memory](working-memory.md) updated when milestone progress, blockers, decisions or next steps change. |
| Performance evidence | `perf:` pull requests show signpost or metric numbers before and after, on the same device. |

### Decision: pull requests of at most 400 changed lines of code

Code pull requests stay under 400 changed lines (additions plus deletions), counting production code,
tests and scripts. Generated files, snapshot reference images, lockfiles, test fixtures and String
Catalog translations do not count. Tests count because reviewers read them too; when tests push a
focused change over the limit, the description says so rather than dropping tests.

- **Rationale.** A SmartBear study of a Cisco team found reviewers should look at no more than 200 to
  400 lines at a time, after which defect detection drops
  ([SmartBear: best practices for peer code review](https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/));
  Google's published practice makes the same point for small changes
  ([Google engineering practices: small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)).
  Small squash commits are also easier to revert and to bisect.
- **Trade-offs.** More pull requests, and features land in slices behind a flag.
- **Alternatives considered.** No limit (large reviews become rubber stamps). A hard CI check on
  line count (blocks legitimate mechanical changes such as renames). A 200-line limit (too tight for
  a SwiftUI screen with its tests and previews).
- **Risks.** Slices that leave half a feature reachable in `integration` (mitigated by flags and the
  Definition of Done); counting games (reviewer judgement wins).
- **Future scalability impact.** The limit keeps review load predictable as reviewers join; a
  size-label check can be automated later if slicing discipline slips.

## Branches and commits

### Branch names

`<type>/<description>`, where the description is short, lowercase kebab-case ASCII, and may start
with the issue number: `feat/ocr-language-picker`, `fix/142-save-conflict`
([contributing](../.github/CONTRIBUTING.md)).

| Prefix | Use |
|---|---|
| `feat/` | New user-visible capability |
| `fix/` | Bug fix |
| `docs/` | Documentation only |
| `chore/` | Maintenance with no behaviour change |
| `ci/` | Workflows, CI scripts, rulesets |
| `refactor/` | Structure change with no behaviour change |
| `perf/` | Performance improvement |
| `test/` | Tests only |
| `hotfix/` | Urgent fix branched from `main` (the only branch besides `integration` allowed into `main`) |

### Commit and pull request titles

Titles follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):
`<type>(<scope>)!: <description>`. The `pr-title` check accepts the types `feat`, `fix`, `docs`,
`chore`, `ci`, `refactor`, `perf`, `test`, `build`, `revert` and `release`, with an optional
lowercase scope ([ci.yml](../.github/workflows/ci.yml)). Write the description in the imperative
("add French recognition"), keep it short enough to read in GitHub's lists, and use `!` only for a
change that breaks a public contract (see [deprecation](#deprecation)). Release pull requests are
titled `release: X.Y.Z`. Commits on a work branch are squashed away, but they still carry the
author's name only and no tool-attribution trailers.

| Scope | Area |
|---|---|
| `app` | App target, scenes, the deep-link router, `AppContainer`, Telemetry |
| `pdf` | `PDFEngine` and the reading, editing, organising and signing features built on it |
| `ocr` | `Scanning` and `OCR` |
| `ai` | `Intelligence`: routing, prompts, consent, evaluation |
| `store` | `Commerce`: StoreKit, paywall, entitlements |
| `ds` | `DesignSystem` |
| `search` | `Search`: Core Spotlight and the on-device index |
| `sync` | `DocumentStore`: files, iCloud Drive, the SwiftData index, CloudKit metadata sync |
| `ci` | Workflows, CI scripts, rulesets |
| `docs` | Documentation |

A change to `Core` uses the scope of the capability that needs it. A sub-area may follow a slash
(`pdf/redaction`, `ai/prompts`). A pull request that spans scopes either picks the main one or
omits the scope. New scopes are added by a pull request to this table.

## Technical debt

Technical debt is a known shortcut whose cost grows over time: a missing abstraction, a skipped
edge case, a workaround for a framework bug, a quarantined test.

- **Record it.** Every piece of debt is an issue labelled `housekeeping` (the organisation's label
  for maintenance work), stating what the shortcut is, what it costs while it stays, what would
  trigger fixing it, and the fix. Code comments point to it: `// TODO(#123): …`. A `TODO` without an
  issue number is not accepted in review.
- **Budget it.** `Assumption:` about one fifth of each milestone's planned capacity, measured in size
  labels, goes to debt. Validation: at each milestone review, compare the debt issues opened and
  closed; raise the share if the open count grows for two milestones in a row, lower it if it
  shrinks to nothing.
- **Escalate it.** Debt that breaks a performance budget, an accessibility requirement, a privacy
  promise or a security control is not debt: it is a bug with a `priority:p1` or higher, fixed
  outside the budget.
- **Review it.** Milestone planning reviews the `housekeeping` backlog with the rest of the work
  ([project management](project-management.md)).

## Feature flags

Flags let unfinished work merge into `integration` safely, and let a feature or a cloud provider be
switched off without a new build.

| Kind | Purpose | Lifetime |
|---|---|---|
| Release flag | Hides work in progress until it is complete, reviewed and translated. Compile time only: it is turned on by changing its compiled default in the build that ships the feature, never remotely | Removed within one milestone of shipping on in an App Store release (`Assumption:` validated by the count of live release flags at each milestone review) |
| Kill switch | Turns off a shipped feature, AI provider or prompt version in production, for example a cloud AI provider ([ADR-0021](adr/0021-ai-provider-routing-and-failover.md)). The record schema, targets, fetch policy and procedure are owned by the [kill-switch runbook](process/runbooks/kill-switch.md) | Permanent; exercised before each release |
| Operational setting | Tightens a limit without a release, for example lowering a per-request page cap for a cloud tier; a remote value can lower the compiled limit, never raise it | Permanent; reviewed yearly |

There are no experiment (A/B test) flags in V1: measuring cohorts needs per-user outcome data that
the telemetry posture does not collect ([ADR-0017](adr/0017-privacy-first-telemetry.md)).

### How flags resolve

1. **Compiled default**, declared with the flag in one typed list in `Core`, with its kind, owner
   hat and removal milestone. Release flags default to off.
2. **Remote value** from a read-only record set in the CloudKit public database, fetched and cached
   as the [kill-switch runbook](process/runbooks/kill-switch.md) describes. The public database is
   readable whether or not the device has an iCloud account
   ([CKContainer.publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)).
   A remote value can only switch shipped behaviour off or tighten a limit.
3. **Local override** in Debug and Staging builds only, from a developer screen that Release builds
   do not contain.

### Rules

- Flags carry values, never behaviour: booleans, enumerations and numbers. No code, no prompts and
  no endpoint URLs arrive remotely. Apps may not download code that changes features
  ([App Review Guidelines 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements)),
  and prompts are versioned, evaluated artefacts ([ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md)).
- A flag never hides a feature from App Review. Anything a flag can switch on in production is
  complete in the submitted build and described in the Notes for Review, because hidden, dormant or
  undocumented features are not allowed
  ([App Review Guidelines 2.3.1](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)).
- Remote values can only turn things **off** (a feature, a cloud tier, a prompt version) or tighten
  a limit; they never turn anything on. Sending data off the device always needs the user's consent
  ([ADR-0009](adr/0009-tiered-ai-and-consent.md)).
- Gradual rollout of a release uses the App Store's phased release, not remote flags
  ([release management](release-management.md#phased-release)).
- Both states of every flag are tested (unit tests with a fake flag provider; snapshots for UI).
- The current flag values appear in the user-exportable diagnostics summary
  ([ADR-0012](adr/0012-on-device-observability.md)).
- A unit test fails when a release flag passes its removal milestone, so expired flags block CI
  instead of lingering.

### Decision: remote flags from the CloudKit public database

- **Rationale.** Apple infrastructure the app already uses, with no server of ours, no user
  identity and no third-party SDK; it works without an iCloud account; the same channel carries the
  AI-provider kill switch the architecture already requires
  ([ios architecture review](ios-architecture-review.md#cloudkit-strategy)).
- **Trade-offs.** No per-user targeting and no percentage rollout (releases roll out through phased
  release instead); record changes are made by hand in the CloudKit Console, in the development
  environment first and then in production, so a change is reviewed as an operational change rather
  than as a pull request ([kill-switch runbook](process/runbooks/kill-switch.md)).
- **Alternatives considered.** A third-party flag service (an SDK and a data processor, against
  [ADR-0017](adr/0017-privacy-first-telemetry.md)); flags served by `pdf-algo-pro-backend` (does not
  exist yet, and would add an identifying request); compile-time flags only (no kill switch without
  a release and App Review).
- **Risks.** A wrong remote value switches something off for everyone (mitigated by the two-step
  change, version-scoped records, the compiled default, last-known-good caching, the "off only" rule,
  and the change record kept as the [kill-switch runbook](process/runbooks/kill-switch.md) requires);
  stale flags accumulate (mitigated by the expiry test).
- **Future scalability impact.** When the relay exists, operational settings that need per-user
  quotas can move there; the typed flag list and resolution order stay the same.

## Deprecation

| What | Policy |
|---|---|
| Package APIs (`public` across our packages) | Prefer changing every caller in the same pull request. When migration spans pull requests, mark the old API `@available(*, deprecated, renamed: …, message: …)` and remove it within the same milestone. |
| Public contracts: App Intents and their parameters, URL scheme routes (`pdfalgopro://`), Spotlight item identifiers, widget and control kinds, Handoff activity types | Treated like a public API because users' Shortcuts, widgets and links depend on them. A change that breaks one uses `!` in the title. Deprecated App Intents stay working for at least two releases (`Assumption:` validated by support requests after each removal) and are hidden from system suggestions with `isDiscoverable = false` ([AppIntent.isDiscoverable](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable)). |
| User-facing features | Removal is a product decision in the [decision register](decision-register.md), announced in the release notes of the release before, with a way to export or keep the user's data. |
| Persisted data: SwiftData schema versions, settings keys, file extended attributes | Never removed while a supported app version could have written them; a settings key is never reused with a new meaning ([ADR-0006](adr/0006-swiftdata-persistence.md)). |
| Minimum OS | Raised only by a new ADR superseding [ADR-0001](adr/0001-platform-floor-and-swift-6.md), decided after WWDC with App Store Connect adoption data. |
| Dependencies and SDK versions | Upgrades follow the vendor's deprecation notices; a removal or major upgrade that changes privacy, telemetry or licence terms needs an ADR update. |
| Documents | Superseded documents are deleted or rewritten, not left stale; ADRs are superseded, never edited ([ADR index](adr/README.md)). |

## Coding agents

Coding agents work in this repository under [SUPERVISION.md](../.github/SUPERVISION.md) and
[AGENTS.md](../AGENTS.md). In short:

- An agent starts where a person would: [AGENTS.md](../AGENTS.md), the documentation index
  ([README](README.md)), [working memory](working-memory.md), then the ADRs and standards for the
  area it is changing.
- It works on a branch and opens a pull request with a Conventional Commit title and the template
  filled in. It never merges, never pushes to `integration` or `main`, and never changes repository
  settings, rulesets, releases, tags or dependencies without explicit approval in the conversation.
- It follows the same size limit, gates and Definition of Done as everyone else, cites sources,
  labels assumptions, and leaves no tool attribution in commits or pull requests.
- It stops and asks when a rule and a request conflict, or when a change reaches outside the
  requested scope (for example, CI workflows, `AGENTS.md` or `SUPERVISION.md`).
- The person who merges an agent's pull request is accountable for it and reviews it with the
  agent checklist in the [code review guide](code-review-guide.md#reviewing-agent-authored-pull-requests).

## Open questions

- Scope names: `store` is used here for `Commerce` and `sync` for `DocumentStore`; `Telemetry`
  changes use `app`. Confirm, or add `telemetry` and `core` scopes.
- Which package owns the CloudKit public-database flag reader. `Core` holds the typed list and the
  provider protocol; the live reader needs CloudKit, which `Core` does not import. Candidates:
  `DocumentStore` (already owns CloudKit) or a new package through an ADR.
- Whether technical debt keeps the organisation's `housekeeping` label or gets a dedicated label in
  [labels.yml](../.github/labels.yml).
