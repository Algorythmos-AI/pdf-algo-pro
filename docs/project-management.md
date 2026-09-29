# Project management

How work on PDF Algo Pro is planned and tracked: the project board and its automation, how milestones
map to product phases, the iteration rhythm, the backlog kept as code, triage, work-in-progress limits,
estimation, how epics break down, and the definitions of ready and done. It is sized for one
maintainer today and written so that the same system carries a larger group later.

Owner: Product · Reviewed: each milestone

## Where work lives

| Thing | Home |
|---|---|
| A unit of work | A GitHub issue, from a template ([GitHub governance](github-governance.md#issue-taxonomy)) |
| A phase of the roadmap | A milestone (Foundation, MVP, V1, V1.1, V2) |
| Flow and priority | The project board |
| The planned backlog | [`docs/planning/backlog.yaml`](planning/backlog.yaml), synced to issues |
| Decisions | ADRs in `docs/adr/` and the decision register [`docs/decision-register.md`](decision-register.md) |
| Current state | [`docs/working-memory.md`](working-memory.md) |

## Projects: fields, views and automation

One GitHub project holds the repository's open issues and pull requests
([About Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects)).

| Field | Type | Values |
|---|---|---|
| Status | Single select | Triage, Ready, In progress, In review, Blocked, Done |
| Priority | Single select | P0, P1, P2, P3 (mirrors the `priority:` labels) |
| Pillar | Single select | PIL-1 … PIL-7; an item serving several pillars records the main one here and lists the others in its body |
| Platform | Single select | iPhone, iPad, Mac, Vision Pro |
| Size | Single select | S, M, L, XL (mirrors the `size:` labels) |
| Milestone | Built-in | From the repository milestones |
| Iteration | Iteration | Two-week iterations (see [iterations](#iterations)) |

Views: **Roadmap** (roadmap layout by milestone and iteration), **Board** (by Status, current
milestone), **Triage** (table, Status = Triage). If the API cannot create views, they are made by hand
in the UI ([GitHub governance](github-governance.md#project-board)).

Automation uses GitHub's built-in project workflows
([Using the built-in automations](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations)):

- **Auto-add** new issues and pull requests from this repository.
- **Item added** → Status Triage.
- **Item closed** and **pull request merged** → Status Done (GitHub enables these by default).
- **Auto-archive** Done items after two weeks, so the board shows current work.

Labels and fields overlap on purpose: the `status:`, `priority:` and `size:` labels make an issue's
state visible in plain issue lists and to scripts, and the board's fields drive the views. Triage sets
both; where they disagree, the board field wins and the label is corrected.

## Milestones and phases

| Milestone | Scope (from [`milestones.yml`](../.github/milestones.yml)) | Exit criterion |
|---|---|---|
| Foundation | Planning package, readiness gate, repository and toolchain foundations; no app features | [`docs/readiness-review.md`](readiness-review.md) shows no open Critical blocker |
| MVP | First TestFlight build: read, annotate, fill forms and sign, scan and OCR, on-device document intelligence on iPhone | An internal TestFlight build passes the MVP acceptance criteria in [`docs/prd.md`](prd.md) |
| V1 | First App Store release: editing, organising, subscriptions, EN + FR | Version 1.0.0 approved and released |
| V1.1 | Quality, performance, accessibility and the most requested gaps after launch | The V1.1 scope in [`docs/product/roadmap.md`](product/roadmap.md) shipped |
| V2 | iPad-first experience and Mac; the opt-in Claude tier at general availability | The V2 scope in [`docs/product/roadmap.md`](product/roadmap.md) shipped |

Milestones carry no due dates until the roadmap sets them; a date is added only when the Product hat
commits to it.

## Iterations

Assumption: two-week iterations are the starting cadence, chosen as short enough to adjust often and
long enough to finish a size-L item. After three iterations the Product hat compares planned and
finished items and keeps or changes the length. GitHub iteration fields allow breaks for time away
([About iteration fields](https://docs.github.com/en/issues/planning-and-tracking-with-projects/understanding-fields/about-iteration-fields)).

Each iteration:

1. **Plan** (start): pull `status:ready` items from the current milestone into the iteration, highest
   priority first, within the WIP limit and recent throughput.
2. **Work**: move items across the board; each merged pull request closes its issue.
3. **Review** (end): try the Staging build from TestFlight internal; record what shipped and what slipped
   in [`docs/working-memory.md`](working-memory.md).
4. **Retrospect**: one change to try next iteration, recorded in the same place.

## Backlog as code

The planned backlog is kept in [`docs/planning/backlog.yaml`](planning/backlog.yaml).
Each item has a stable identifier, a milestone, a priority, a size, its pillars and platforms, labels,
and acceptance criteria. The file is changed by pull request like any document, and
`scripts/gh/sync_github.py backlog` creates or updates the matching issues, keyed by the identifier,
so re-running it never duplicates anything; the board's auto-add workflow brings new issues onto the
board. The file's own header is the authority on its fields.

Issues raised directly on GitHub (bugs, ideas from users) do not need a backlog entry; the backlog holds
planned work, the issues hold all work.

## Triage cadence

New issues are triaged weekly and at each iteration planning, following
[GitHub governance](github-governance.md#triage). `priority:p0` items skip the queue; if users are
affected they become incidents ([incident response](process/runbooks/incident-response.md)).

## Work-in-progress limits

- **Solo phase: at most 2 items In progress**: one being built and one waiting (on review, a
  TestFlight build or an outside answer).
- Finish before starting: when the limit is reached, the next action is to unblock or finish, not to
  start.
- An item waiting on something outside the repository moves to Blocked with `status:blocked-external`
  and the reason; it leaves the In progress count but is reviewed at every planning.
- Assumption: with more people the limit becomes 2 per person plus 1 for the group; validated after the
  first iteration with two contributors.

## Estimation

Items are sized with the `size:` labels, which measure relative effort, not time promises:

| Size | Meaning |
|---|---|
| `size:s` | Up to a day |
| `size:m` | A few days |
| `size:l` | About a week or two |
| `size:xl` | Too big: split into an epic before it is Ready |

There are no story points. After three iterations, forecasts use throughput (items finished per
iteration by size) rather than estimates.

## Epics and sub-issues

- An epic is an issue raised with the feature template, type Epic. It states the problem, the
  outcome, the pillars and the milestone.
- It is broken into sub-issues ([Adding sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)),
  each independently mergeable, sized at most `size:l`, with its own acceptance criteria.
- A sub-issue that needs design or research first gets a research sub-issue ahead of it.
- The epic closes when every sub-issue is closed or explicitly moved out of scope; its progress shows
  on the Roadmap view.

## Definition of ready

An item can move to Ready when:

- the problem and the outcome are clear, with acceptance criteria (Given / When / Then where useful);
- its pillars, platforms, priority, size (at most L) and milestone are set;
- dependencies and open questions are known, and none blocks starting;
- UI work has a design to build from;
- the privacy impact is stated: whether any content leaves the device, and under which consent;
- it has been checked against the non-goals ([`docs/non-goals.md`](non-goals.md)).

## Definition of done

An item is done when:

- its pull request is squash-merged into `integration` with every quality gate green
  ([quality gates](process/quality-gates.md)), including line coverage of at least 80% (ADR-0014) once
  code exists;
- tests cover the changed behaviour;
- user-facing strings are in the String Catalog in EN and FR;
- accessibility is checked (VoiceOver, Dynamic Type, contrast) for UI changes;
- the privacy manifest, docs, CHANGELOG `[Unreleased]` and [`docs/working-memory.md`](working-memory.md) are updated where
  they are affected;
- the acceptance criteria are verified on a real device with the Staging build;
- the issue is closed by the pull request.

Shipping to users is tracked separately: an item is *released* when the version containing it reaches
the App Store ([release management](release-management.md)).
