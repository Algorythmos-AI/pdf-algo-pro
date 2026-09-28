# PDF Algo Pro

A native PDF reader, editor and scanner for iPhone and iPad, and later Mac, that keeps documents
private and works offline. Document intelligence (summaries, answers with page citations, data
extraction) runs on the device first. Built by Algorythmos.

|                 |                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Status**      | Planning · foundation phase · no app code yet; implementation starts when the readiness gate (`docs/readiness-review.md`) clears |
| **Owner**       | [@Algorythmos-AI/maintainers](https://github.com/orgs/Algorythmos-AI/teams/maintainers)                          |
| **Runs at**     | iPhone and iPad (iOS/iPadOS 27+) via TestFlight and the App Store once released. No deployed service.            |
| **Run locally** | Nothing to run yet. The planning package starts at `docs/README.md`.                                              |
| **Context**     | [Algorythmos-AI](https://github.com/Algorythmos-AI) · [Governance](docs/github-governance.md) · [Agent rules](AGENTS.md) · [Licence](LICENSE) |

---

## What's here

```
pdf-algo-pro/
├── docs/            planning package: product, architecture, ADRs, governance, runbooks
│   └── README.md    start here (30-minute onboarding path)
├── .github/         templates, workflows, rulesets as code, labels and milestones
├── scripts/         repository tooling (rulesets, labels, milestones, backlog, wiki, CI checks)
├── AGENTS.md        rules for people and coding agents working in this repository
└── LICENSE          proprietary
```

## How work flows

- `integration` is the default branch: staging and internal TestFlight builds.
- `main` is production: App Store releases, tagged `vX.Y.Z`.
- Branch from `integration` as `<type>/<description>`, open a pull request with a
  conventional-commit title, and squash-merge when the checks pass.

Details: [branching](docs/process/branching.md) · [quality gates](docs/process/quality-gates.md) ·
[release management](docs/release-management.md) · [contributing](.github/CONTRIBUTING.md).

## Security

Report vulnerabilities privately; see [SECURITY.md](.github/SECURITY.md).

## Licence

Proprietary. Copyright © 2026 Algorythmos Pty Ltd. See [LICENSE](LICENSE).
