# Wiki plan

How the GitHub wiki serves as PDF Algo Pro's institutional memory: what it contains, where its
source lives, how it is published and who keeps it current. The wiki is public, like the
repository, so the same publication rules apply to it.

Owner: Maintainer · Reviewed: each milestone

## Principles

1. **One source of truth.** The wiki is generated from `docs/`. Curated pages live in
   [docs/wiki/](wiki/Home.md); every other document under `docs/` is mirrored as a reference page.
   Edits made in the Wiki tab are overwritten on the next publish.
2. **Summarise and link; never duplicate.** A wiki page explains a topic in a few paragraphs and
   links to the canonical documents. Facts, numbers and decisions live in exactly one document.
3. **Public by definition.** Nothing confidential appears in the wiki: no prices, business targets,
   account or billing facts, or content from private repositories
   ([repository standards](repository-standards.md)).
4. **Written for a newcomer.** Each page answers "what is this and where do I go next" for someone
   in their first week.

## Pages

| Page | Purpose | Canonical sources |
|---|---|---|
| [Home](wiki/Home.md) | Orientation and the start of the 30-minute path | [Docs index](README.md), [working memory](working-memory.md) |
| [Product Vision](wiki/Product-Vision.md) | Why the product exists; pillars; why switch, pay, stay | [Positioning](product-positioning.md), [moat](competitive-moat.md), [PRD](prd.md) |
| [Roadmap](wiki/Roadmap.md) | Phases and platform order | [Roadmap](product/roadmap.md), [backlog](planning/backlog.yaml) |
| [Architecture](wiki/Architecture.md) | The shape of the system | [iOS architecture review](ios-architecture-review.md) |
| [ADRs](wiki/ADRs.md) | How decisions are recorded; key ADRs | [ADR index](adr/README.md), [decision register](decision-register.md) |
| [AI Features](wiki/AI-Features.md) | What intelligence does and where it runs | [AI governance](ai-governance.md), [model selection](model-selection.md) |
| [Security](wiki/Security.md) | Security posture and reporting | [Threat model](threat-model.md), [SECURITY](../.github/SECURITY.md) |
| [Design System](wiki/Design-System.md) | Visual and interaction foundations | [Design system](design-system.md) |
| [API Docs](wiki/API-Docs.md) | Internal interfaces, deep links, the future relay API | [Coding standards](coding-standards.md), [architecture review](ios-architecture-review.md) |
| [Release Notes](wiki/Release-Notes.md) | What shipped in each version | [CHANGELOG](../CHANGELOG.md), [changelog strategy](changelog-strategy.md) |
| [Troubleshooting](wiki/Troubleshooting.md) | Known behaviours and fixes | [Operations](operations.md), runbooks |
| [Contributing](wiki/Contributing.md) | How changes are made | [CONTRIBUTING](../.github/CONTRIBUTING.md), [engineering playbook](engineering-playbook.md) |

The sidebar is [docs/wiki/_Sidebar.md](wiki/_Sidebar.md); the footer is
[docs/wiki/_Footer.md](wiki/_Footer.md).

## Publishing

- **On each release:** the `release.yml` workflow publishes the wiki after tagging, when the
  `WIKI_TOKEN` secret is configured.
- **On demand:** `python3 scripts/gh/publish_wiki.py --out build/wiki` renders locally for review;
  `--push` publishes.
- **Bootstrap (one-time owner action):** GitHub creates the wiki's git repository only after the
  first page is saved in the web interface. After that, the script replaces the whole wiki on each
  publish.

## Keeping it current

- A pull request that changes a canonical document checks whether a wiki page summarises it, and
  updates the summary in the same pull request ([code review guide](code-review-guide.md)).
- The docs gate in CI checks that every curated page is listed in the sidebar and that every link
  resolves ([quality gates](process/quality-gates.md)).
- Each milestone review reads the wiki Home and Product Vision pages against the current state.

## Decision: generate the wiki from the repository

- **Rationale.** Documents reviewed in pull requests stay correct; a separately edited wiki drifts.
  The organisation's research project uses the same pattern.
- **Trade-offs.** The Wiki tab cannot be edited directly; contributors edit `docs/` instead.
- **Alternatives considered.** A hand-edited wiki (drifts, unreviewed); no wiki (the Wiki tab is where
  many newcomers look first); a documentation site (more infrastructure than needed today).
- **Risks.** Publishing credentials: the wiki token is scoped to this repository and stored as a
  secret; publishing is skipped when it is absent.
- **Future scalability impact.** If a documentation site is ever justified, the same `docs/` source
  feeds it (`pdf-algo-pro-docs` is a reserved repository name,
  [repository standards](repository-standards.md)).
