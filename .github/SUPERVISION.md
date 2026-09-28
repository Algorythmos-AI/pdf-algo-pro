# Supervision

How decisions are made, reviewed and overseen in this repository, including work done by coding
agents. Owner: Maintainer. Reviewed: each milestone.

## Decision rights

| Decision | Who decides | Record |
|---|---|---|
| Product scope, pillars, non-goals | Product | [`docs/decision-register.md`](../docs/decision-register.md) |
| Architecture and technology choices | Architecture | ADR in `docs/adr/` |
| Releases to TestFlight external and the App Store | Release | release PR into `main`, tag, CHANGELOG |
| Security exceptions and third-party SDKs | Security | ADR + NOTICE.md entry |
| Data leaving the device, consent, the App Store privacy label and the privacy manifest | Privacy | [`docs/privacy-architecture.md`](../docs/privacy-architecture.md), consent-text version, `PrivacyInfo.xcprivacy` |
| Repository settings, rulesets, visibility | Maintainer | org decision log + `.github/rulesets/` |

These are roles ("hats"). Today one maintainer holds all of them; when people join, the roles are
assigned and the approval thresholds in [github-governance](../docs/github-governance.md) apply.

## Human in the loop

Nothing reaches `integration`, `main`, TestFlight or the App Store without a pull request that a
maintainer merged. Production-facing actions (App Store submission, external TestFlight, changing
repository settings or rulesets, publishing anything outward-facing) always need an explicit human
decision, recorded in the pull request or issue.

## Supervising coding agents

Coding agents may work in this repository under these rules, which extend the organisation's
agent rules:

- **May:** read the repository, create branches, write code and documents, run local checks, open
  pull requests with a conventional-commit title and the PR template filled in.
- **May not, without explicit approval in the conversation:** merge, push to `integration` or
  `main`, change repository settings, rulesets or visibility, create releases or tags, submit to
  TestFlight or the App Store, add a third-party dependency, or write secrets anywhere.
- **Always:** follow [AGENTS.md](../AGENTS.md); cite sources; label assumptions; leave no tool
  attribution in commits or pull requests; stop and ask when a rule and a request conflict.
- **Audit:** every agent change arrives as a pull request with its own description and checks, so
  the history of what an agent did is the pull request history.

## Escalation

Blocked on a decision outside your role: open an issue with the `blocked` label and name the role
that decides. Security concerns go through [SECURITY.md](SECURITY.md), not public issues.
