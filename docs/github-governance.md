# GitHub governance

How PDF Algo Pro uses GitHub as its operating system: where work is proposed, planned, reviewed,
gated, released and remembered, and which of those rules live as code in this repository. It covers
roles, branch protection, code ownership, approvals, versioning, labels, milestones, the project board,
the issue taxonomy, triage and supervision. It is written for one maintainer today and for a
multi-team organisation later; each rule says what changes as people join.

Owner: Maintainer · Reviewed: each milestone, and whenever a ruleset, template or label file changes

## Principles

- **As code where GitHub allows it.** Rulesets, labels, milestones, issue and pull request templates,
  workflows and code ownership are files in `.github/`, changed by pull request and applied by scripts.
  Settings that cannot be code are listed in [repository standards](repository-standards.md#settings-baseline).
- **A human merges.** Nothing reaches `integration`, `main`, TestFlight or the App Store without a pull
  request merged by a maintainer ([SUPERVISION.md](../.github/SUPERVISION.md)).
- **Roles, not people.** Decisions belong to roles ("hats"). Today the maintainer wears every hat; the
  thresholds below switch on as the hats are handed to different people.

## Roles (hats)

| Hat | Decides | Future team |
|---|---|---|
| Maintainer | Repository settings, rulesets, visibility, access | — |
| Product | Scope, pillars, non-goals, priorities, milestones | — |
| Architecture | Architecture and technology choices (ADRs) | `ios-platform` |
| Release | Release trains, release pull requests, TestFlight and App Store submission | `release` |
| Security | Security exceptions, third-party SDKs, vulnerability handling | `security` |
| Quality | Quality gates and thresholds, test strategy | `qa` |
| Design | Design system, UX flows, accessibility sign-off | `design` |
| AI | AI tiers, providers, prompts and evaluations | `ai` |
| PDF engine | PDF SDK boundary, rendering, editing, OCR pipeline | `pdf-engine` |
| Operations | Incidents, kill switch, runbooks | — |

The decision-rights table in [SUPERVISION.md](../.github/SUPERVISION.md) is the authoritative list of
who decides what; this table adds the hats used by the process documents.

## Branching and releases

- `integration` is the default branch and the staging line; `main` is production. Work branches
  squash-merge into `integration`; the release pull request merges `integration` into `main` with a
  merge commit; hotfixes squash into `main` and are back-merged. This departs from the organisation
  default of `main` only, as recorded in ADR-0016 and org decision D-023.
- Details: [branching](process/branching.md) · [environments](process/environments.md) ·
  [quality gates](process/quality-gates.md) · [release management](release-management.md) ·
  [changelog strategy](changelog-strategy.md) · [project management](project-management.md).

## Protected branches: rulesets as code

Branch and tag protection is defined in [`.github/rulesets/`](../.github/rulesets/) using GitHub
repository rulesets ([About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets),
[Available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)).

| File | Ruleset name | Applies to | Rules |
|---|---|---|---|
| [`integration.json`](../.github/rulesets/integration.json) | `protect-integration` | `refs/heads/integration` | No deletion; no force push; pull request required with 0 approvals, stale approvals dismissed, conversations resolved, **squash only**; required checks `pr-title`, `secrets / Secret scan`, `docs`, `invariants`, `dependency-review`, `codeql (actions)`, `ios`; not strict about being up to date |
| [`main.json`](../.github/rulesets/main.json) | `protect-main` | `refs/heads/main` | As above, but **merge or squash** allowed, the same checks plus `promotion-guard`, and **strict**: the pull request must be up to date with `main` |
| [`tags.json`](../.github/rulesets/tags.json) | `protect-release-tags` | `refs/tags/v*` | No deletion, no update, no force push. Creation is allowed, so the release workflow can tag |

All three list the organisation-admin role as a bypass actor. The bypass is for repairing the gate
machinery, never for merging a change that fails a gate ([quality gates](process/quality-gates.md#never-disable-or-skip-a-gate)).

### Applying rulesets

[`scripts/gh/apply_rulesets.sh`](../scripts/gh/apply_rulesets.sh) creates each ruleset, or updates the
live one of the same name by merging the file into it with
[`merge_ruleset.py`](../scripts/gh/merge_ruleset.py), so settings GitHub added later and the file does
not mention are kept rather than reset to weaker defaults.

1. **Apply only after every required check has reported at least once** on a pull request. A required
   check that never reports leaves pull requests waiting, and a check can be selected as required only
   if it has completed successfully in the repository in the past seven days
   ([Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)).
   The dormant `ios` job counts: it reports as skipped on every pull request.
2. **Dry run first**, read the diff, then apply:

   ```sh
   REPO=Algorythmos-AI/pdf-algo-pro bash scripts/gh/apply_rulesets.sh --dry-run
   REPO=Algorythmos-AI/pdf-algo-pro bash scripts/gh/apply_rulesets.sh
   ```

3. Verify in **Settings → Rules → Rulesets**, and open a test pull request to see the required checks.

Applying or changing rulesets needs admin rights and is a Maintainer decision, made only with explicit
human approval ([SUPERVISION.md](../.github/SUPERVISION.md)). A change to a ruleset file is reviewed like
code; the file and the live ruleset must never disagree for longer than it takes to apply.

`codeql (swift)` is not a required check yet. It becomes one in the pull request after it first runs on
Swift code.

## Code owners

Today [`CODEOWNERS`](../.github/CODEOWNERS) assigns every file to `@Algorythmos-AI/maintainers`, and the
rulesets do not require code-owner review while there is one maintainer. GitHub uses the last matching
pattern in the file for each path
([About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)).

As hats are handed over, path owners are added in this order of paths (later lines win):

| Paths | Owner team |
|---|---|
| `*` | `maintainers` |
| `/App/`, `/project.yml`, `/Packages/Core/`, `/Packages/DocumentStore/`, `/Packages/Search/`, `/Packages/Features/` | `ios-platform` |
| `/Packages/PDFEngine/`, `/Packages/Scanning/`, `/Packages/OCR/` | `pdf-engine` |
| `/Packages/Intelligence/` | `ai` and `security` |
| `/Packages/DesignSystem/` | `design` |
| `/Tests/`, `*.xctestplan`, `/scripts/ci/` | `qa` |
| `/Packages/Commerce/`, `/Packages/Telemetry/`, `*.entitlements`, `PrivacyInfo.xcprivacy`, `/.github/workflows/`, `/.github/rulesets/`, `/.github/SECURITY.md` | `security` |
| `/CHANGELOG.md`, `/.github/workflows/release.yml`, `/docs/release-management.md`, `/docs/changelog-strategy.md`, `/docs/process/` | `release` |

Open question: the final GitHub team slugs (for example whether they carry a product prefix) follow the
organisation naming standard and are decided when the first team is created.

## Pull request approvals

Approvals switch on by changing the rulesets as the number of people grows. Each step is a pull request
to `.github/rulesets/` plus `CODEOWNERS`, applied with the script above.

| Stage | Trigger | Approvals into `integration` | Approvals into `main` | Extra reviewers |
|---|---|---|---|---|
| Solo (today) | One maintainer | 0 | 0 | None; the maintainer merges after the checks pass |
| Two or more maintainers | A second person with write access | 1, code-owner review on | 1, code-owner review on | — |
| Security owner assigned | The Security hat is held by someone who is not the author | — | — | Security approval for `Intelligence`, `Commerce` and entitlements, through `CODEOWNERS` |
| Release manager assigned | The Release hat is held separately | — | Release manager approval on every pull request into `main` | The Release hat also becomes a required reviewer of the `release` environment ([Managing environments](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment)) |

An author never approves their own pull request; stale approvals are dismissed on new pushes (already on).

## Versions, build numbers and tags

- **Marketing version:** SemVer `MAJOR.MINOR.PATCH` in `project.yml` (`MARKETING_VERSION`,
  shown to users as the app version) ([Semantic Versioning](https://semver.org/spec/v2.0.0.html)).
  MAJOR for a change users must adapt to (a document or library format change, a raised minimum OS),
  MINOR for new capabilities, PATCH for fixes.
- **Build number:** `CI_BUILD_NUMBER`, set by Xcode Cloud for every build and never edited by hand
  ([Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)).
- **Tags:** `vX.Y.Z` on `main`, created by the release workflow after App Store approval; `vX.Y.Z-rc.N`
  is published as a GitHub pre-release. Tags are immutable under the tag ruleset.

Details: [release management](release-management.md#versions-and-build-numbers).

## Labels

Labels come from two files and one script:

- the organisation's shared set: `security`, `breaking-change`, `blocked`, `ai`, `devops`,
  `dependencies`, `migration`, `i18n`, `compliance`, `housekeeping`;
- this repository's [`labels.yml`](../.github/labels.yml), which **extends** that set and never
  redefines an organisation label.

| Group | Labels |
|---|---|
| Work type (GitHub defaults) | `bug`, `enhancement`, `documentation` |
| Platform | `ios`, `ipad`, `macos`, `visionos` |
| Product area | `pdf`, `ocr`, `performance`, `accessibility`, `design`, `release` (plus the organisation's `ai`, `security`, `i18n`) |
| Priority | `priority:p0` (blocks a release or harms users), `priority:p1` (current milestone), `priority:p2` (next milestone), `priority:p3` (nice to have) |
| Size | `size:s` (up to a day), `size:m` (a few days), `size:l` (a week or two), `size:xl` (too big: split into an epic) |
| Status | `status:triage`, `status:ready`, `status:in-progress`, `status:blocked-external` |

[`scripts/gh/sync_github.py`](../scripts/gh/sync_github.py) applies the organisation set first, then the
product set; it stops if a product label redefines an organisation label, and it never deletes a label:

```sh
uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py labels           # dry run
uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py labels --apply
```

## Milestones

Milestones map to roadmap phases (`docs/product/roadmap.md`) and are defined in
[`milestones.yml`](../.github/milestones.yml): **Foundation**, **MVP**, **V1**, **V1.1**, **V2**.
Apply them with `sync_github.py milestones` (dry run first, then `--apply`). Every issue that is
`status:ready` has a milestone. What each phase contains is described in
[project management](project-management.md#milestones-and-phases).

## Project board

One GitHub project (Projects) holds every open issue and pull request of the repository
([About Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects)).

| Field | Values |
|---|---|
| Status | Triage, Ready, In progress, In review, Blocked, Done |
| Priority | P0, P1, P2, P3 |
| Pillar | PIL-1 Document Reading, PIL-2 Document Editing, PIL-3 OCR & Scanning, PIL-4 AI Document Intelligence, PIL-5 Privacy, PIL-6 Offline Capability, PIL-7 Native Apple Experience |
| Platform | iPhone, iPad, Mac, Vision Pro |
| Size | S, M, L, XL |
| Milestone | Built-in field from the repository milestones |

Views:

- **Roadmap:** roadmap layout grouped by milestone, showing epics and their dates.
- **Board:** board layout by Status, filtered to the current milestone.
- **Triage:** table of items with Status = Triage, sorted by creation date.

The Projects API manages projects, fields and items
([Using the API to manage Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects));
if it cannot create or configure views, the three views are created by hand in the project's UI and
listed here as done. Automation and iterations are described in
[project management](project-management.md#projects-fields-views-and-automation).

## Issue taxonomy

Blank issues are disabled ([`config.yml`](../.github/ISSUE_TEMPLATE/config.yml)); every issue starts from a
template, which applies its labels.

| Kind | Template | Labels applied | Notes |
|---|---|---|---|
| Bug | [`bug.yml`](../.github/ISSUE_TEMPLATE/bug.yml) | `bug`, `status:triage` | Functional, accessibility, performance, AI answer quality or crash. No real documents or personal data. |
| Feature | [`feature.yml`](../.github/ISSUE_TEMPLATE/feature.yml), type Feature | `enhancement`, `status:triage` | States the problem, the outcome, pillars and platforms, and the guardrails check. |
| Epic | [`feature.yml`](../.github/ISSUE_TEMPLATE/feature.yml), type Epic | `enhancement`, `status:triage` | Decomposed into sub-issues ([Adding sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)); there is no `epic` label. |
| Research or spike | [`research.yml`](../.github/ISSUE_TEMPLATE/research.yml) | `status:triage` | One question, the decision it informs, a method and a time box. The outcome goes to the decision register or an ADR. |
| Security hardening | [`security.yml`](../.github/ISSUE_TEMPLATE/security.yml) | `security`, `status:triage` | Non-sensitive hardening only. Vulnerabilities go to private reporting ([SECURITY.md](../.github/SECURITY.md)). |

Documentation work uses the feature template and gets the `documentation` label at triage.

## Triage

A weekly triage (Assumption: weekly suits a solo maintainer; revisit when more than one person triages)
takes every `status:triage` item through these steps:

1. Check the template is complete; ask the reporter for what is missing.
2. Move anything containing a vulnerability, personal data or document content out of public view: edit
   it out and move the report to a private security advisory.
3. Close duplicates and non-goals (`docs/non-goals.md`) with a short reason.
4. Add platform and area labels, a priority, a size (split `size:xl` into an epic), a milestone and the
   Pillar field.
5. Replace `status:triage` with `status:ready`, or `blocked` / `status:blocked-external` with the reason.

| Commitment | Target | Source |
|---|---|---|
| Acknowledge a vulnerability report | Within five business days | [SECURITY.md](../.github/SECURITY.md) (organisation default) |
| Reply to support email | Within two business days | [SUPPORT.md](../.github/SUPPORT.md) |
| Triage a new issue | Within one week | Assumption: follows from the weekly cadence |
| Start work on a `priority:p0` item | Immediately; it becomes an incident if users are affected | [Incident response](process/runbooks/incident-response.md) |

## Supervision

[SUPERVISION.md](../.github/SUPERVISION.md) sets out decision rights, keeps a human in the loop for every
production-facing action, and lists what coding agents may and may not do: they may branch, write and
open pull requests; they may not merge, push to `integration` or `main`, change settings or rulesets,
create releases or tags, submit builds, add dependencies or write secrets without explicit approval.
Every agent change arrives as a pull request, so the pull request history is the audit trail.

## Why there is no FUNDING.yml

`FUNDING.yml` adds a Sponsor button that invites people to fund a repository
([Displaying a sponsor button](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository)).
PDF Algo Pro is a proprietary commercial product, contributions are by invitation, and the repository
is public only by organisation decision. A Sponsor button would misdescribe the project, and the
organisation's rule is to introduce a standard file only when it is justified. The file is omitted on
purpose; this section is the record of that choice.
