# Founder principles

The principles every PDF Algo Pro decision is judged against. When two options are otherwise
equal, the one that honours more of these wins; when an option breaks one, the decision record
says why. They are written by the founder and apply to everyone who works on the product,
including coding agents.

Owner: Maintainer · Reviewed: yearly, or when a principle is challenged by a real decision

## Mandate

> Build PDF Algo Pro as if it were a strategic product inside a mature technology company expected
> to operate for the next 5-10 years. Generate not only product architecture, but also governance,
> knowledge management, engineering standards, operational processes, security controls, AI
> governance, business planning, GitHub operating models, documentation systems, testing
> frameworks, decision management, platform strategy, product strategy and organisational memory.
> Every recommendation must be evidence-based, traceable, maintainable and designed to support
> future growth from a solo founder to a multi-team engineering organisation.

## Principles

1. **Privacy is the product.** A document stays on the device unless the user chooses otherwise,
   knows where it goes, and can take that choice back. We would rather ship a smaller feature than
   a feature that needs a document's content on our servers.
2. **Apple-first, never web-first.** The app uses native frameworks and platform conventions:
   intents, widgets, Files, Spotlight, keyboard, Pencil, accessibility. No web views standing in for
   native screens, no SaaS patterns, no cross-platform toolkits.
3. **Offline by default.** Reading, editing, scanning, OCR and on-device intelligence work with no
   connection. Cloud features are additions, never requirements.
4. **AI must show its work.** Answers about a document cite the pages they come from. When the
   model is unsure, it says so. The app never presents generated content as the document's own.
5. **Useful before paid.** Users reach real value before any paywall, and the paywall is honest:
   clear price, clear terms, easy to close, easy to cancel. No dark patterns.
6. **Quality over speed.** Performance budgets, accessibility and tests are requirements, not
   polish. We slip a date before we ship a regression.
7. **Evidence over opinion.** Claims cite sources; numbers are sourced or labelled as assumptions
   with a way to test them; decisions are written down with their alternatives.
8. **Small surface, deep quality.** We say no to features that belong to other products (see the
   [non-goals](non-goals.md)) so the core stays excellent.
9. **Built to last.** We choose boring, well-supported technology, write decisions down, and keep
   the product understandable to the next person in 30 minutes.
10. **Honest communication.** Marketing, App Store copy and release notes say only what the product
    does today.

## How the principles are used

- **Design and code review:** the review checklist asks which principles a change touches.
- **Decision records:** an ADR or decision-register entry that trades a principle away names it.
- **Roadmap:** an item that serves no pillar and no principle does not make the roadmap.
