# PDF Algo Pro — rules for people and agents

The Algorythmos-AI organisation's agent rules apply to this repository. This file adds the rules
specific to PDF Algo Pro; where the two differ, the stricter rule wins, except for the one
recorded exception below (branch model).

## Mandate

Build PDF Algo Pro as if it were a strategic product inside a mature technology company expected
to operate for the next 5-10 years. Generate not only product architecture, but also governance,
knowledge management, engineering standards, operational processes, security controls, AI
governance, business planning, GitHub operating models, documentation systems, testing frameworks,
decision management, platform strategy, product strategy and organisational memory. Every
recommendation must be evidence-based, traceable, maintainable and designed to support future
growth from a solo founder to a multi-team engineering organisation.

## Hard rules (never without explicit human approval in chat)

1. **No application code before the readiness gate.** [`docs/readiness-review.md`](docs/readiness-review.md) must show no
   open Critical blocker.
2. **Branch, pull request, squash-merge.** Never push to `integration` or `main`. Work branches
   (`feat/ fix/ docs/ chore/ ci/ refactor/ perf/ test/`) start from `integration`. The release PR
   `integration` → `main` uses a merge commit; `hotfix/*` squash into `main`, then back-merge.
   *Recorded exception:* the org default for apps is `main` only; this repository keeps a staging
   line (`integration`) for internal TestFlight. See ADR-0016 ([`docs/adr/0016-two-branch-model.md`](docs/adr/0016-two-branch-model.md)) and [branching](docs/process/branching.md).
3. **Pull request titles** use Conventional Commits:
   `feat|fix|docs|chore|ci|refactor|perf|test|build|revert|release`, optional `(scope)`.
   Commits are authored by the maintainer and carry no tool-attribution trailers; no AI-tool
   names in the repository description or README.
4. **This repository is public.** Nothing from private repositories, no company records, no Apple
   account details or Team ID, no prices, revenue figures or targets, no customer data. Business
   material lives in the private companion repository; public documents never link to it.
5. **No secrets in git.** The Apple Team ID and every credential are injected at build time.
6. **No real documents in the repository.** Test fixtures are synthetic or licence-clean.
7. **No third-party SDK without an ADR** covering privacy manifest, telemetry, licence and exit plan.
8. **Evidence rule.** Every factual claim cites a source; every number is sourced or labelled
   `Assumption:` with a validation plan.

## Product guardrails

- Apple-first: native frameworks and platform conventions; no web or SaaS patterns.
- Platform priority: iPhone, then iPad, then Mac, then visionOS. visionOS never shapes V1.
- Privacy by default: on-device first; any cloud processing is opt-in, named, and revocable.
- Stay inside the non-goals ([`docs/non-goals.md`](docs/non-goals.md)).

## Where things are

Start at [`docs/README.md`](docs/README.md). Decisions: [`docs/decision-register.md`](docs/decision-register.md) and `docs/adr/`. Current state:
[`docs/working-memory.md`](docs/working-memory.md). How work flows: [GitHub governance](docs/github-governance.md),
[quality gates](docs/process/quality-gates.md), [release management](docs/release-management.md).
