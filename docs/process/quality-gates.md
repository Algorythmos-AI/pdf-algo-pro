# Quality gates

The complete list of checks a change must pass on its way from a pull request to the App Store: what
each gate runs, when it runs, whether it blocks, the threshold it applies, the exact check name GitHub
shows, and what to do when it fails. Gates that exist as workflow jobs today are listed with their
current state; release gates that cannot be automated until app code exists are marked as manual. The
rule that governs all of them: never disable or skip a gate to get green.

Owner: Quality · Reviewed: each milestone, and with any change to a workflow, ruleset or threshold

## How to read this page

- **Blocking** means the change cannot merge (a required check in a ruleset) or the release cannot
  proceed (a release gate). **Warning** means an annotation on the run that never fails it.
- **Triggers**: *PR → integration* (every pull request into `integration`); *PR → main* (the release
  pull request and hotfix pull requests); *push* (after a merge into `integration` or `main`);
  *scheduled* (weekly CodeQL); *release* (the manual `release.yml` run and the manual release checklist).
- **Check name** is the exact name in the workflow file and in the rulesets
  [`integration.json`](../../.github/rulesets/integration.json) and
  [`main.json`](../../.github/rulesets/main.json).

## Pull request gates

| Check name | Workflow → job | Tool | Runs on | Required on `integration` | Required on `main` | Threshold or rule | State today |
|---|---|---|---|---|---|---|---|
| `pr-title` | `ci.yml` → `pr-title` | Shell pattern | Pull requests (opened, edited, synchronised, reopened) | Yes | Yes | Title is a Conventional Commit ([pattern](branching.md#pull-request-titles)) | Active |
| `promotion-guard` | `ci.yml` → `promotion-guard` | Shell | Every pull request; can fail only when the base is `main` | No | Yes | Head is `integration` or `hotfix/*` | Active |
| `secrets / Secret scan` | `ci.yml` → `secrets` (the organisation's shared security workflow, pinned by commit SHA, Semgrep off) | Organisation secret scanner | Pull requests, pushes, merge queue | Yes | Yes | No secret in the change | Active |
| `docs` | `ci.yml` → `docs` | [`scripts/ci/check_docs.py`](../../scripts/ci/check_docs.py) | Pull requests, pushes | Yes | Yes | Relative links resolve; exactly one H1, first; no skipped heading levels; every document indexed once [`docs/README.md`](../README.md) exists | Active |
| `invariants` | `ci.yml` → `invariants` | [`scripts/ci/invariants.py`](../../scripts/ci/invariants.py) | Pull requests, pushes | Yes | Yes | PDFs only under `Tests/Fixtures/Synthetic/`; Swift rules listed below | PDF rule active; Swift rules dormant |
| `changes` | `ci.yml` → `changes` | `git diff` | Pull requests, pushes | No | No | Decides whether `ios` runs | Active |
| `ios` | `ci.yml` → `ios` | Xcode 27, XcodeGen 2.46.0 (checksum-verified), `swift-format`, `xcodebuild`, `.xctestplan`, [`coverage_gate.py`](../../scripts/ci/coverage_gate.py) | When `changes` reports Swift or project input changes | Yes | Yes | Lockfile unchanged; format clean (strict); build with warnings as errors; unit, UI, accessibility-audit and snapshot tests pass; line coverage at least 80% overall and per first-party target (ADR-0014) | Dormant: reports *skipped* |
| `codeql (actions)` | `codeql.yml` → `actions` | CodeQL, `security-extended` queries | Pull requests, pushes, weekly | Not yet | Not yet | Analysis completes; findings appear as code-scanning alerts | Runs, but its upload is rejected while CodeQL default setup is enabled on the repository; becomes required when the repository switches to advanced setup |
| `codeql (swift)` | `codeql.yml` → `swift` | CodeQL, `security-extended`, manual build | When `project.yml` and Swift files exist | No | No | Analysis completes; findings appear as code-scanning alerts | Dormant |
| `dependency-review` | `dependency-review.yml` → `dependency-review` | [Dependency review](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-dependency-review) | Pull requests | Yes | Yes | No newly added dependency with a known vulnerability of high or critical severity (`fail-on-severity: high`) | Active |
| `ai-eval` | `ci.yml` → `ai-eval` (planned) | Apple's Evaluations framework, or the committed on-device result checked against the prompt and schema content hashes ([AI evaluation framework](../ai-evaluation-framework.md#on-device-gate-in-continuous-integration)) | When a new `changes` output, `intelligence`, reports changes under `Packages/Intelligence/` | Once added | Once added | The on-device suite for changed prompts and schemas meets the thresholds in the [AI evaluation framework](../ai-evaluation-framework.md#what-blocks-what) | **Planned**: not in `ci.yml` yet; added in the same pull request as the first `Intelligence` code |

The rulesets add three non-check rules on both branches: changes arrive only by pull request,
review conversations must be resolved before merging, and force pushes and deletion are blocked. On
`main`, checks must pass on the release pull request's head, but the head need not be up to date with
`main` ([keeping `integration` level with `main`](branching.md#keeping-integration-level-with-main)).
Approvals are zero while there is one maintainer
([GitHub governance](../github-governance.md#pull-request-approvals)).

The rulesets in `.github/rulesets/` are the intended configuration. They are applied (by the
maintainer, because rulesets need human approval) after the pull request that introduces them has
merged and every listed check has reported at least once; until then, the table above describes
what the checks do, not what GitHub enforces.

### The `invariants` rules

Always active: no PDF outside `Tests/Fixtures/Synthetic/`, so real documents never enter git.

Active once the first Swift file exists (dormant before then):

- no `try!` and no `as!` outside tests;
- `print(` only inside `#if DEBUG`;
- networking APIs only in the `Intelligence`, `Commerce` and `Telemetry` packages;
- colour literals only in `DesignSystem`;
- the commercial PDF SDK imported only in `PDFEngine`;
- a `PrivacyInfo.xcprivacy` exists and declares every required-reason API category the code uses
  ([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)).

Planned (not in `invariants.py` yet; each is added with the first code it checks):

- **AI tool allow-list:** a `Tool` conformance or a tool passed to a `LanguageModelSession` must be
  on the read-only allow-list, and server-side tools on the Claude model must stay empty
  ([AI governance](../ai-governance.md), [prompt management](../prompt-management.md));
- **`.public` data-class lint:** `privacy: .public` is flagged on any interpolated value, unless it
  is a static identifier, an enumeration case, an error code or a duration, so no document or user
  value reaches a log unredacted ([data classification](../data-classification.md),
  [coding standards](../coding-standards.md)).

### Code-scanning findings

The `codeql (…)` jobs fail when the analysis itself fails. Their findings are reported as
code-scanning alerts on the pull request rather than as a failing job. Until the Security hat enables
[code scanning merge protection](https://docs.github.com/en/code-security/code-scanning/managing-your-code-scanning-configuration/set-code-scanning-merge-protection)
in the rulesets, the rule is procedural: a new alert of high severity or above is fixed, or dismissed
by the Security hat with a written reason, before the pull request merges.

## Push and scheduled runs

- `ci.yml` also runs on every push to `integration` and `main` and in the merge queue, so the branch
  heads are checked after each merge. On a push, `changes` compares against the previous head; if that
  is unavailable it treats every tracked file as changed.
- `codeql.yml` runs weekly (cron `0 19 * * 0`, Sunday 19:00 UTC, Monday morning in Sydney) to pick up
  new queries against unchanged code.
- Dependabot opens grouped GitHub Actions updates monthly against `integration`
  ([`dependabot.yml`](../../.github/dependabot.yml)); they pass the same gates as any other pull request.
- No nightly job exists today. The golden-corpus, OCR and performance suites are candidates for a
  nightly Xcode Cloud workflow once they exist (open question for the Quality hat).

## Dormant gates and the `changes` job

The iOS gates must be required before any Swift exists, or the first code pull request could merge
without them. They are kept dormant, not absent, by a job-level condition:

1. `changes` checks whether the diff touches Swift or project inputs (`*.swift`, `project.yml`,
   `Packages/`, `App/`, `*.xctestplan`, `*.xcprivacy`, `Package.resolved`, or `ci.yml` itself) **and**
   `project.yml` exists.
2. `ios` declares `needs: changes` and `if: needs.changes.outputs.ios == 'true'`, so on a
   documentation-only pull request it is skipped.
3. GitHub reports a job skipped by a condition as successful, and it does not block merging even when
   it is a required check
   ([Using conditions to control job execution](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/using-conditions-to-control-job-execution)).

This is why the repository uses a `changes` job rather than `paths:` filters on the workflow: a
workflow skipped by path filtering leaves its required checks pending and blocks the merge
([Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)).
`codeql.yml` uses the same pattern for `codeql (swift)`, keyed on the presence of `project.yml` and
Swift files. The planned `ai-eval` job will use it too, through a `changes` output named
`intelligence`, added to `ci.yml` together with the first `Intelligence` code.

The cost of this design is that a skipped `ios` looks green. Two safeguards apply: the pattern
includes `ci.yml`, so editing the gate re-runs it; and the first code pull request must show `ios`
actually running and passing (a readiness item: "dormant Swift gates proven on first code PR"). When
the source layout changes, the pattern in `changes` is reviewed in the same pull request.

## Warnings never fail the build

`check_docs.py` prints two kinds of warning as `::warning::` annotations and still exits 0:

- **Evidence scan.** A paragraph containing a percentage or currency amount with no link, citation,
  `Source:`, `Assumption:` label or ADR reference. It flags possible unsourced numbers for the
  reviewer; it cannot judge whether a source is good.
- **Working-memory freshness.** [`docs/working-memory.md`](../working-memory.md) not updated for more than 30 days (once that
  file exists). Time passing never breaks the build.

Run `python3 scripts/ci/check_docs.py --strict-warnings` locally to treat warnings as errors. The
`release` workflow also warns, without failing, when `WIKI_TOKEN` is not set and the wiki cannot be
published.

## Release gates

### Automated in `release.yml` today

The [`release` workflow](../../.github/workflows/release.yml) runs only on `main`, by manual dispatch
after App Store approval. Before it tags anything it checks:

| Gate | Rule |
|---|---|
| Version format | `X.Y.Z` or `X.Y.Z-rc.N` |
| Tag is new | `vX.Y.Z` does not exist yet |
| CHANGELOG section | `CHANGELOG.md` has a `## [X.Y.Z]` heading |
| Marketing version | Once `project.yml` exists, its `MARKETING_VERSION` equals `X.Y.Z` (without any `-rc.N`) |
| Documentation and invariants | `check_docs.py` and `invariants.py` pass on `main` |
| Release notes | The extracted CHANGELOG section is not empty |

### Release-only gates

These run before the App Store submission. Most are manual until the code and test assets exist;
each has a planned automation.

| Gate | Evidence and tool | Threshold | Today | Planned automation | Owner hat |
|---|---|---|---|---|---|
| Performance budgets | XCTest performance tests, `OSSignposter` intervals, [MetricKit](https://developer.apple.com/documentation/metrickit) reports from TestFlight | Budgets in [`docs/performance-budgets.md`](../performance-budgets.md) | Manual | Performance test plan in Xcode Cloud | Quality |
| Golden PDF corpus | Open, render, search, annotate and save round trips over the synthetic corpus | No regression against the recorded baseline | Manual | Test plan over `Tests/Fixtures/Synthetic/` | Quality |
| OCR accuracy | Recognition over the synthetic EN and FR scan corpus | Error-rate thresholds in [`docs/testing-strategy.md`](../testing-strategy.md) | Manual | Test plan with a scored report | Quality |
| AI evaluation suite | Versioned prompts scored against the evaluation set (ADR-0020) | Thresholds in [`docs/ai-evaluation-framework.md`](../ai-evaluation-framework.md) | Manual | Evaluation run attached to the release pull request | AI |
| Version and CHANGELOG consistency | `release.yml` gates above | Exact match | Automated (the marketing-version check activates with `project.yml`) | — | Release |
| TestFlight stability | Crash reports for the Release build in external TestFlight ([Acquiring crash reports](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)) | Crash-free sessions of at least 99.8% over at least 3 days of external testing | Manual | — | Release |
| Store listing | App Store Connect: description, keywords, screenshots, What's New in EN and FR (up to 4000 characters each, [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)), App Privacy answers | Complete and accurate | Manual | — | Release |
| Privacy and support URLs | The URLs entered in App Store Connect open and describe the current app | Reachable and current | Manual | Link check in the release checklist | Release |
| Accessibility | Manual VoiceOver pass over the key flows, plus Dynamic Type at the largest sizes ([Performing accessibility testing](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)); the automated audit already runs inside `ios` | No blocking issue | Manual | — | Design |

Assumption: the stability threshold (99.8% crash-free sessions over at least 3 days) is a starting
value set for this project, not an Apple requirement. How crash-free sessions are counted for a
TestFlight build (the session denominator) is an open question for the Release hat; the threshold is
reviewed after the first three releases against the observed data.

The checklist that collects this evidence is in [release management](../release-management.md#the-release-pull-request).

## When a gate fails

| Check or gate | What to do |
|---|---|
| `pr-title` | Edit the pull request title; the job re-runs on edit. |
| `promotion-guard` | Retarget the pull request to `integration`. If it is an urgent production fix, follow the [hotfix runbook](runbooks/ios-hotfix.md). |
| `secrets / Secret scan` | Treat the secret as leaked, even on a branch: revoke and rotate it first, then remove it from the branch history before anything merges, and tell the Security hat. A false positive is recorded in the pull request and handled through the organisation workflow's allowlist, never by weakening the scan. |
| `docs` | Fix the broken link or heading. A document that does not exist yet is referenced as inline code (`docs/…`), not as a link. |
| `invariants` | Fix the code: handle errors instead of `try!`, use `Logger` instead of `print(`, move networking or colour literals into their package, declare the required-reason API in the privacy manifest. PDFs belong under `Tests/Fixtures/Synthetic/` and must be synthetic. |
| `ios` | Read the failing step. The `Tests.xcresult` bundle is uploaded on failure and kept for 7 days. For coverage, add tests; do not exclude files. If Xcode 27 is missing on the runner, the job fails on purpose: raise it as a toolchain blocker rather than pinning an older Xcode. |
| `codeql (…)` | Fix the finding, or ask the Security hat to dismiss it with a reason. An analysis failure is a CI problem to fix, not to skip. |
| `dependency-review` | Upgrade or replace the dependency. Accepting a known vulnerability needs a Security decision recorded in an ADR. |
| `ai-eval` (planned) | Read the per-sample results, fix the prompt or schema, and re-run the on-device suite. A threshold changes only as the [AI evaluation framework](../ai-evaluation-framework.md) allows. |
| A `release.yml` gate | Fix the cause on `integration` (or through a hotfix), then dispatch the workflow again. |
| A release-only gate | Do not submit. Fix on `integration`, ship a new build through the release pull request, and re-collect the evidence. |

## Never disable or skip a gate

Getting green by weakening a gate is not allowed ([CONTRIBUTING](../../.github/CONTRIBUTING.md)).
That includes:

- removing a check from a ruleset, or adding `continue-on-error`, `if: false` or a narrower `changes`
  pattern to avoid running it;
- lowering a threshold or excluding files from coverage without an ADR (coverage is ADR-0014, CI/CD
  gates are ADR-0013);
- merging a failing pull request through the organisation-admin bypass.

The bypass exists so that the gate machinery itself can be repaired when it is broken; any use is
recorded in an issue. A gate is changed only by a pull request that states why, with the Quality hat's
approval and, for a threshold, an ADR.
