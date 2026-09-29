# ADR-0022: Apple-first capability baseline

**Status:** accepted (2026-09-28)

**Context.** Most competitors ship cross-platform or web-derived apps. PDF Algo Pro's native experience is part of its moat, so platform integration is a requirement, not a nice-to-have.

**Decision.** Every feature is designed against the baseline: App Intents, widgets, Control Center controls, Share and Action extensions, Files integration, Core Spotlight, Apple Intelligence, Dynamic Type, VoiceOver, keyboard shortcuts and menus, drag and drop, multi-window on iPad, Handoff, Quick Look and PencilKit. The milestone for each capability is in the architecture review; the design review checklist asks which apply. No web or SaaS interaction patterns.

**Alternatives considered.** Adding platform features after launch (they rarely arrive, and the product feels generic).

**Consequences.** More work per feature, but compounding product quality and discoverability across the system.

**Pillars served.** PIL-7

**References.** [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) · [App Intents](https://developer.apple.com/documentation/appintents)
