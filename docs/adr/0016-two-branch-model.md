# ADR-0016: Two-branch model: integration and main

**Status:** accepted (2026-09-28)

**Context.** The organisation's default for app repositories is a single `main` trunk. An iOS app benefits from a separate staging line that feeds internal TestFlight before anything reaches external testers or the App Store.

**Decision.** `integration` is the default branch (staging and internal TestFlight). `main` is production (external TestFlight and the App Store). Work branches squash-merge into `integration`; a release pull request from `integration` to `main` uses a merge commit; `hotfix/*` squash-merge into `main` and are back-merged. A `promotion-guard` check allows only `integration` and `hotfix/*` into `main`. This is a recorded exception to the organisation default, also logged in the organisation decision log.

**Alternatives considered.** `main` only (the org default; no staging line). GitFlow with develop and release branches (more ceremony than a solo-to-small team needs).

**Consequences.** Two protected branches and rulesets; a release pull request per release. Because squash back-merges carry content but not ancestry, the `main` ruleset requires checks to pass on the release pull request's head but not that the head is up to date with `main` (`strict_required_status_checks_policy: false`); the push to `main` re-runs CI on the merged result. The organisation's other product with a staging environment uses the same model.

**Pillars served.** PIL-7

**References.** [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
