# ADR-0020: Prompts as versioned, evaluated artefacts

**Status:** accepted (2026-09-28)

**Context.** Prompt changes change product behaviour as much as code does, and can silently degrade quality or safety.

**Decision.** Prompts live in the `Intelligence` package with an identifier and a SemVer version, per provider where needed, with `@Generable` output types. Any prompt or model change runs the AI evaluation suite (grounding, citation accuracy, hallucination, prompt-injection red team, latency, cost) and must meet its thresholds before merging. Changes are recorded in a prompt changelog and can be rolled back by version.

**Alternatives considered.** Prompts inline in feature code (untestable, unreviewable). Remote prompt configuration without evaluation (fast, but unsafe).

**Consequences.** Slower prompt iteration, in exchange for measurable quality and safe rollback.

**Pillars served.** PIL-4

**References.** [What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
