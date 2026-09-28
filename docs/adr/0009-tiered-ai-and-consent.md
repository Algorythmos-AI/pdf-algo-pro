# ADR-0009: Tiered AI with on-device first and consent for every cloud tier

**Status:** accepted (2026-09-28)

**Context.** Document intelligence is the product's differentiator; privacy and offline use are its promise. iOS 27's Foundation Models framework offers one session API across on-device, Private Cloud Compute and third-party models.

**Decision.** An `IntelligenceRouter` over `LanguageModelSession` uses, in order: the on-device `SystemLanguageModel`; Apple's `PrivateCloudComputeLanguageModel`; Claude through Anthropic's `ClaudeForFoundationModels` package. Cloud tiers are opt-in, with consent naming the provider and the data, revocable in Settings (Guideline 5.1.2(i)). Tiers ship by phase: on device in the MVP, Private Cloud Compute from V1, Claude from V2 (Pro only). During the Claude tier's TestFlight beta it authenticates with App Attest; a proxied relay (`pdf-algo-pro-backend`) is required before that tier reaches general availability, because App Attest tokens carry no user identity. Answers cite pages; documents are untrusted input; the model cannot trigger actions.

**Alternatives considered.** Cloud-first AI (breaks the privacy and offline pillars). Provider API keys in the app (extractable). Our own inference servers (cost and liability).

**Consequences.** Small on-device context needs chunking and retrieval. A relay service must exist before GA (readiness blocker C4). Cost controls and evaluation gates are mandatory (ADR-0020, ADR-0021).

**Pillars served.** PIL-4, PIL-5, PIL-6

**References.** [What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/) · [Claude for Apple Foundation Models](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
