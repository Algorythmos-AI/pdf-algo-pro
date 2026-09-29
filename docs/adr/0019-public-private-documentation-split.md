# ADR-0019: Public and private documentation, and the repository family

**Status:** accepted (2026-09-28)

**Context.** This repository is public for now (free CI minutes), but business planning includes prices, costs, targets and competitive detail that must not be public.

**Decision.** `pdf-algo-pro` is the canonical product identifier and the single app repository. Business-sensitive documents exist here as redacted public editions at the same paths as their confidential editions in the private repository `pdf-algo-pro-private`; public documents never link to it. Satellite repositories (`pdf-algo-pro-ios`, `-backend`, `-docs`, `-design`) are reserved and created only when a separation criterion is met: independent deploy cadence, a different runtime or toolchain, different access or visibility needs, or a team ownership boundary.

**Alternatives considered.** Everything public (discloses strategy). Making this repository private now (loses free macOS CI minutes). Many repositories from the start (drift and overhead for a solo maintainer).

**Consequences.** Two documents to keep in step for each business topic. Clear rules on what may never appear publicly (see repository standards).

**Pillars served.** PIL-5
