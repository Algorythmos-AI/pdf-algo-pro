# Repository standards

The standards this repository meets as a member of the Algorythmos-AI organisation: how it and its
future sibling repositories are named, which files and directories must exist, the README header,
licence and third-party notices, registration in the organisation catalog, what may and may not
appear in a public repository, the settings baseline, and how secrets are handled. Where an
organisation standard applies it is cited by name; where this repository adds a rule, the rule is
stated here.

Owner: Maintainer · Reviewed: quarterly, and when the organisation standards change

## Naming

- **Canonical identifier:** `pdf-algo-pro`, lowercase kebab-case as the organisation naming standard
  requires. The repository is `Algorythmos-AI/pdf-algo-pro` (renamed from `PDF-Algo-Pro`) and is the
  single app repository.
- **Product name:** PDF Algo Pro, publisher Algorythmos Pty Ltd, endorsed as "Built by Algorythmos".
- **Apple identifiers** use reverse-DNS form without hyphens: bundle `com.algorythmos.pdfalgopro`
  (`.staging` for the Staging configuration), App Group `group.com.algorythmos.pdfalgopro`, iCloud
  container `iCloud.com.algorythmos.pdfalgopro`, URL scheme `pdfalgopro://` (ADR-0015).
- **Swift packages** use UpperCamelCase names: `Core`, `PDFEngine`, `DocumentStore`, `Scanning`, `OCR`,
  `Intelligence`, `Search`, `Commerce`, `Telemetry`, `DesignSystem`, `Features/*` (ADR-0002).
- **Branches, pull request titles and tags:** see [branching](process/branching.md).
- **Documents:** kebab-case Markdown under `docs/`; ADRs as `docs/adr/NNNN-slug.md`.

### Reserved satellite repositories

These names are reserved. None exists; each is created only when the case for separating it meets the
criteria below, and the decision is recorded in an ADR (ADR-0019 covers the repository family).

| Repository | Would hold |
|---|---|
| `pdf-algo-pro-ios` | The app, if it ever needs to separate from planning and documentation |
| `pdf-algo-pro-backend` | The relay for cloud AI (`.proxied` authentication, per-user quotas, first-party counters); needed before the Claude tier reaches general availability |
| `pdf-algo-pro-docs` | A published documentation site, if the wiki mirror stops being enough |
| `pdf-algo-pro-design` | Design sources and assets, if they need their own access rules |

Separation criteria:

1. an independent deployment cadence;
2. a different runtime or toolchain;
3. different access or visibility needs;
4. a team ownership boundary.

### The private companion repository

`Algorythmos-AI/pdf-algo-pro-private` holds the confidential material that cannot live in a public
repository: commercial strategy (pricing strategy, revenue model, unit economics, the financial model),
market and customer research, the competitive-moat analysis, analytics targets, the private edition of
the readiness review, and a private decision register. This repository never links to it. Where a
public document has a confidential counterpart, the public edition is redacted and says "confidential
edition held privately".

## Required files and layout

| File | Purpose |
|---|---|
| [`README.md`](../README.md) | What the product is, the header table, how work flows |
| [`LICENSE`](../LICENSE) | Proprietary licence |
| [`NOTICE.md`](../NOTICE.md) | Third-party components and their licences |
| [`CHANGELOG.md`](../CHANGELOG.md) | Keep a Changelog format; source of all release notes |
| [`AGENTS.md`](../AGENTS.md) | Rules for people and coding agents |
| [`CLAUDE.md`](../CLAUDE.md) | One-line import of `AGENTS.md` for agents that read that file name |
| [`.editorconfig`](../.editorconfig), [`.gitignore`](../.gitignore) | Formatting defaults; secrets, signing material, generated projects and real PDFs kept out of git |
| [`.github/CODEOWNERS`](../.github/CODEOWNERS) | Code ownership |
| [`.github/SECURITY.md`](../.github/SECURITY.md), [`SUPPORT.md`](../.github/SUPPORT.md), [`CONTRIBUTING.md`](../.github/CONTRIBUTING.md), [`SUPERVISION.md`](../.github/SUPERVISION.md) | Community health and supervision |
| [`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md), [`.github/ISSUE_TEMPLATE/`](../.github/ISSUE_TEMPLATE/) | Exactly four issue templates (bug, feature, security, research) and a config that disables blank issues |
| [`.github/labels.yml`](../.github/labels.yml), [`milestones.yml`](../.github/milestones.yml), [`dependabot.yml`](../.github/dependabot.yml), [`rulesets/`](../.github/rulesets/) | GitHub configuration as code |
| [`.github/workflows/`](../.github/workflows/) | Exactly five workflows: `ci.yml`, `pr-metadata.yml` (title and description checks), `codeql.yml`, `release.yml`, `dependency-review.yml` |
| [`scripts/gh/`](../scripts/gh/), [`scripts/ci/`](../scripts/ci/) | Repository tooling and CI checks |
| `docs/` | The planning package, process documents, ADRs and runbooks |

The layout when code arrives (directories marked *later* do not exist yet):

```text
pdf-algo-pro/
├── project.yml          XcodeGen spec (later); the .xcodeproj is generated, never committed
├── App/                 thin app target (later)
├── Packages/            local Swift packages (later)
├── Tests/Fixtures/Synthetic/   the only place PDFs may live (later)
├── TestFlight/          WhatToTest.<locale>.txt notes for Xcode Cloud (later)
├── docs/                planning, process, ADRs, runbooks, wiki pages
├── scripts/             gh/ and ci/ tooling
└── .github/             templates, workflows, rulesets, labels, milestones
```

## README header

Every organisation repository opens its README with a one-paragraph plain description and this table
(see [README.md](../README.md)):

| Row | Contains |
|---|---|
| **Status** | The honest current phase (for example "Planning · foundation phase · no app code yet") |
| **Owner** | The owning GitHub team, linked |
| **Runs at** | Where the product runs for users, and whether any service is deployed |
| **Run locally** | The shortest command that runs something, or "nothing to run yet" |
| **Context** | Links to the organisation, governance, agent rules and licence |

The repository description and README name no AI tools (org decision D-015).

## Licence and notices

- The product is proprietary: [LICENSE](../LICENSE) reserves all rights to Algorythmos Pty Ltd.
  Contributions are by invitation ([CONTRIBUTING](../.github/CONTRIBUTING.md)).
- Every third-party component (shipped in the app or used to build it) is added to
  [NOTICE.md](../NOTICE.md) in the same pull request that introduces it, with the ADR that approved it.
  That ADR covers the privacy manifest, telemetry, licence terms and exit plan
  ([AGENTS.md](../AGENTS.md), hard rule 7).
- A licence whose terms conflict with proprietary distribution through the App Store (strong copyleft,
  for example) needs an explicit ADR decision; the default answer is no.
- Test fixtures are synthetic or licence-clean, and their origin is recorded next to them.

## Catalog registration

The repository is registered in the organisation catalog, which lists every product and repository.
Registration is a readiness item ("catalog entry merged"). At a high level the entry records:

- the product and its canonical identifier (`pdf-algo-pro`);
- the repository, its current visibility (public, by org decision D-002) and its intended visibility
  (private);
- the owning team and lifecycle status;
- the data classification, from the organisation's classes: public, internal, confidential, restricted;
- platforms and runtime (iOS and iPadOS apps, no deployed service yet);
- links to the README and documentation, and the reserved satellite names.

The catalog entry contains nothing confidential; confidential facts stay in the private repository.

## Public and private: redaction rules

This repository and its wiki are public. The following never appear in them, in any file, issue,
pull request, commit message or wiki page:

- the Apple Team ID, and any fact about the Apple developer account (which Apple ID holds it, the
  status of agreements, tax or banking);
- company records, and the billing status of any service;
- prices, revenue figures, financial projections and business targets;
- customer data, personal data, and real documents;
- secrets of any kind;
- content copied from private organisation repositories, internals of other Algorythmos repositories,
  and security findings about them.

Public company facts that may appear: Algorythmos Pty Ltd · ACN 701 006 626 · ABN 22 701 006 626 ·
Sydney · [info@algorythmos.com.au](mailto:info@algorythmos.com.au) · <https://algorythmos.com>.

How to refer to things that are not public:

- organisation standards and decisions by name or number only: "org standard (naming)", "org decision
  D-023";
- confidential documents as "confidential edition held privately", never linked;
- readiness blockers by their generic public title, with the specifics held privately.

The secret scan catches credentials; everything else on this list depends on review. The pull request
template's checklist asks the author to confirm it.

## Settings baseline

Repository settings that are not yet code. The Maintainer applies them and records changes in the
organisation's decision log.

| Setting | Value | Why |
|---|---|---|
| Visibility | Public (org decision D-002); intended visibility private | Nothing in the process may depend on the repository staying public |
| Default branch | `integration` | Staging line ([branching](process/branching.md)) |
| Squash merging | On; default message: pull request title and description | Work and hotfix pull requests |
| Merge commits | On | The release pull request |
| Rebase merging | Off | One history model per branch |
| Automatically delete head branches | On | `integration` and `main` are protected by the rulesets' deletion rule, which prevents automatic deletion ([Managing the automatic deletion of branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches)) |
| Issues | On | Work tracking |
| Projects | On | The project board |
| Wiki | On, editing restricted to people with push access | A read-only mirror of `docs/` ([About wikis](https://docs.github.com/en/communities/documenting-your-project-with-wikis/about-wikis)) |
| Discussions | Off | Support goes to email, bugs and ideas to issues |
| Private vulnerability reporting | On | Required by [SECURITY.md](../.github/SECURITY.md) ([Configuring private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository)) |
| Secret scanning and push protection | On | Stops credentials before they land ([About secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)) |
| Dependabot alerts and security updates | On | Version updates come from `dependabot.yml` |
| Code scanning | Advanced set-up through `codeql.yml`; default set-up off | Avoids duplicate analyses |
| Actions | Default workflow token read-only; third-party actions pinned by commit SHA | Every workflow declares its own `permissions` |
| Environment `release` | Deployments from `main` only; holds `WIKI_TOKEN` | Used by `release.yml` |

Open question: whether to manage these settings as code (as the rulesets, labels and milestones already
are) once the organisation has a standard tool for it.

## Secrets

- **Never in git.** `.gitignore` excludes `.env`, `.env.*` (except `.env.example`), `*.p8`, `*.p12`,
  `*.mobileprovision`, `*.cer` and `AuthKey_*.p8`; push protection and the `secrets / Secret scan`
  check stop the rest ([AGENTS.md](../AGENTS.md), hard rule 5).
- **Where secrets live.** Xcode Cloud workflow variables marked Secret; GitHub Actions environment
  secrets (only `WIKI_TOKEN`, in the `release` environment,
  [Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions));
  a gitignored local `.env` on the maintainer's Mac. See [environments](process/environments.md#signing-identity-and-secrets).
- **Never in the app.** No AI provider key ships in the binary; the beta Claude tier uses App Attest and
  the relay holds keys server-side before general availability.
- **Least privilege and expiry.** Tokens are fine-grained where GitHub supports it, scoped to one
  repository, and set to expire.
- **On suspected exposure.** Revoke first, then rotate, then remove from history, then record it as a
  security incident ([incident response](process/runbooks/incident-response.md)).
- **The Apple Team ID** is treated as confidential in this repository and injected at build time.
