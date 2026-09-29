# Contributing

Thanks for helping build PDF Algo Pro. This repository is proprietary (see [LICENSE](../LICENSE));
contributions are by invitation. The rules below apply to everyone, people and coding agents alike
(see [AGENTS.md](../AGENTS.md) and [SUPERVISION.md](SUPERVISION.md)).

## Workflow

1. Open or pick an issue. Use the templates; security problems go through [SECURITY.md](SECURITY.md).
2. Branch from `integration`: `feat/…`, `fix/…`, `docs/…`, `chore/…`, `ci/…`, `refactor/…`,
   `perf/…`, `test/…`, with a short kebab-case description (`feat/ocr-language-picker`).
3. Keep each pull request to one change. For code, aim for under 400 changed lines.
4. Title the pull request as a Conventional Commit (`feat(ocr): add French recognition`). Fill in
   the template, including how you tested it.
5. Run `scripts/dev/preflight.sh` before you push: every check a Mac can run, in CI's order.
6. The pull request is squash-merged into `integration` once the required checks pass, the `ios`
   check included: never while a check is red or still running. Releases reach `main` through a
   release pull request; see [release management](../docs/release-management.md).

## Rules

- Don't disable or skip a check to get green. Fix the cause or raise it in the pull request.
- No secrets, credentials, personal data or real documents in the diff. Test documents are synthetic.
- No third-party dependency without an ADR (privacy manifest, telemetry, licence, exit plan).
- Update docs and the CHANGELOG `[Unreleased]` section when behaviour changes for users.
- Commits carry the author's name only: no tool-attribution trailers.

Details: [branching](../docs/process/branching.md) · [quality gates](../docs/process/quality-gates.md) ·
[GitHub governance](../docs/github-governance.md).
