import Foundation

/// A document-intelligence task the router chooses a tier for (model selection, routing policy by task).
public enum IntelligenceTask: String, CaseIterable, Codable, Sendable {
  /// Summarise a document.
  case summarize
  /// Answer a question with citations (Chat with PDF).
  case ask
  /// Extract structured fields.
  case extract
  /// Explain a contract's key terms (Analyse Contract). Never routed to Claude (PAP-020).
  case explainContract
}

/// A document size band, set by the tokens a request needs, not by page count (model selection).
public enum SizeBand: Int, CaseIterable, Codable, Sendable, Comparable {
  /// Fits the on-device excerpt budget.
  case s
  /// Up to the Private Cloud Compute excerpt budget.
  case m
  /// Up to the Claude per-request cap.
  case l
  /// Larger than any single request.
  case xl

  /// Orders bands from smallest to largest.
  public static func < (lhs: SizeBand, rhs: SizeBand) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension IntelligenceTier {
  /// Whether the tier sends document content off the device, and so needs consent (ADR-0009).
  public var isCloud: Bool { self != .onDevice }

  /// The tiers from most to least private: on device, then Private Cloud Compute, then Claude.
  ///
  /// The router chooses the first qualified tier in this order (AI governance, rule A1).
  public static let routingOrder: [IntelligenceTier] = [.onDevice, .privateCloudCompute, .claude]
}

/// What the user decided about sending document content to one cloud tier, on this device.
///
/// Consent is per provider and per device, is never synced, and is tied to the version of the consent
/// text the user saw (AI governance, consent model).
public struct ConsentState: Hashable, Codable, Sendable {
  /// The user's decision.
  public enum Status: String, CaseIterable, Codable, Sendable {
    /// The consent screen has never been answered.
    case notAsked
    /// The tier may be used automatically when needed.
    case granted
    /// The tier may be used, after a confirmation for each request ("ask before sending").
    case askBeforeSending
    /// The user took the consent back.
    case revoked
  }

  /// The version of the consent text this build shows.
  ///
  /// It rises on a material change: a new provider, a new data category, or changed retention or
  /// training terms. Wording fixes do not change it.
  public static let currentTextVersion = 1

  /// The user's decision.
  public let status: Status
  /// The version of the consent text the decision was made on; `0` when never asked.
  public let textVersion: Int
  /// When the decision was made; `nil` when never asked.
  public let decidedAt: Date?

  /// Creates a consent state.
  public init(status: Status, textVersion: Int, decidedAt: Date?) {
    self.status = status
    self.textVersion = textVersion
    self.decidedAt = decidedAt
  }

  /// The state before the consent screen was ever answered.
  public static let notAsked = ConsentState(status: .notAsked, textVersion: 0, decidedAt: nil)

  /// Whether content may be sent under this consent: it was given, not revoked, and given on exactly
  /// the consent text this build shows.
  ///
  /// A consent for another text version, older or newer, does not count.
  public func permitsSending(currentTextVersion: Int = ConsentState.currentTextVersion) -> Bool {
    (status == .granted || status == .askBeforeSending) && textVersion == currentTextVersion
  }
}

/// Reads the consent on record for a tier; checked before every cloud request.
public protocol ConsentProviding: Sendable {
  /// The consent on record for the tier. The on-device tier needs none and reports `notAsked`.
  func consent(for tier: IntelligenceTier) async -> ConsentState
}

/// Something a request needs from a tier (model selection, step 5).
public enum TierCapability: String, CaseIterable, Codable, Sendable {
  /// Guided generation into a typed result.
  case guidedGeneration
  /// Page images as input.
  case imageInput
  /// The document's language.
  case documentLanguage
}

/// Why a tier was left out of a route, or why no tier could be chosen.
public enum RouteRefusalReason: String, CaseIterable, Codable, Sendable {
  /// The kill switch disabled the provider, the feature or the prompt version (step 1).
  case switchedOff
  /// The document is marked "Keep on device" (step 2).
  case keepOnDevice
  /// The task may never use this tier: Analyse Contract never uses Claude (step 2, PAP-020).
  case taskNotAllowed
  /// The availability check failed, the circuit breaker is open, or the tier is not built (step 3).
  case unavailable
  /// There is no current consent for the cloud tier (step 4).
  case noConsent
  /// The tier lacks a capability the request needs (step 5).
  case notCapable
  /// The request exceeds the tier's token budget, the user's credits or the daily quota (step 6).
  case overBudget
  /// The tier did not pass the evaluation thresholds for this task and size band (step 7).
  case notQualified
}

/// What the router knows about one tier when it decides.
public struct TierFacts: Hashable, Sendable {
  /// Whether the kill switch disabled this provider.
  public var isSwitchedOff: Bool
  /// Whether the availability check passes, including the circuit breaker being closed.
  public var isAvailable: Bool
  /// The consent on record; ignored for the on-device tier.
  public var consent: ConsentState
  /// The consent-text version this build shows for the tier.
  public var currentConsentTextVersion: Int
  /// What the tier can do.
  public var capabilities: Set<TierCapability>
  /// Whether the request fits the tier's token budget and the user's credits or quota.
  public var isWithinBudget: Bool
  /// Whether the tier passed the evaluation thresholds for the request's task and size band.
  public var isQualified: Bool

  /// Creates the facts for a tier.
  ///
  /// The defaults describe a tier that is not built: not available, no consent.
  public init(
    isSwitchedOff: Bool = false, isAvailable: Bool = false, consent: ConsentState = .notAsked,
    currentConsentTextVersion: Int = ConsentState.currentTextVersion,
    capabilities: Set<TierCapability> = Set(TierCapability.allCases), isWithinBudget: Bool = true,
    isQualified: Bool = true
  ) {
    self.isSwitchedOff = isSwitchedOff
    self.isAvailable = isAvailable
    self.consent = consent
    self.currentConsentTextVersion = currentConsentTextVersion
    self.capabilities = capabilities
    self.isWithinBudget = isWithinBudget
    self.isQualified = isQualified
  }
}

/// Everything the routing policy decides from; code gathers it, model output never does.
public struct RoutingInput: Hashable, Sendable {
  /// The task.
  public var task: IntelligenceTask
  /// The size band of the text the request needs; the caller uses it, with the task, to set each
  /// tier's `isQualified`.
  public var sizeBand: SizeBand
  /// Whether the user marked the document "Keep on device".
  public var keepOnDevice: Bool
  /// Whether the kill switch disabled the feature or its prompt version.
  public var isFeatureSwitchedOff: Bool
  /// The capabilities the request needs.
  public var requiredCapabilities: Set<TierCapability>
  /// The facts per tier; a tier without facts is treated as not built, so unavailable.
  public var tiers: [IntelligenceTier: TierFacts]

  /// Creates a routing input.
  public init(
    task: IntelligenceTask, sizeBand: SizeBand, keepOnDevice: Bool = false, isFeatureSwitchedOff: Bool = false,
    requiredCapabilities: Set<TierCapability> = [], tiers: [IntelligenceTier: TierFacts]
  ) {
    self.task = task
    self.sizeBand = sizeBand
    self.keepOnDevice = keepOnDevice
    self.isFeatureSwitchedOff = isFeatureSwitchedOff
    self.requiredCapabilities = requiredCapabilities
    self.tiers = tiers
  }
}

/// The routing policy's decision for one request.
public struct RouteDecision: Hashable, Sendable {
  /// What to do.
  public enum Outcome: Hashable, Sendable {
    /// Answer on a tier.
    ///
    /// - `needsConfirmation`: the user must confirm before content is sent ("ask before sending").
    /// - `isReducedScope`: no tier qualified, so the answer carries a reduced-scope label.
    case use(tier: IntelligenceTier, needsConfirmation: Bool, isReducedScope: Bool)
    /// No tier can answer; the reason says what would enable one.
    case refuse(RouteRefusalReason)
  }

  /// What to do.
  public let outcome: Outcome
  /// Each tier that was not chosen because a step removed it, with the first step's reason.
  public let excluded: [IntelligenceTier: RouteRefusalReason]

  /// Creates a decision.
  public init(outcome: Outcome, excluded: [IntelligenceTier: RouteRefusalReason] = [:]) {
    self.outcome = outcome
    self.excluded = excluded
  }

  /// The chosen tier, or `nil` when the request is refused.
  public var tier: IntelligenceTier? {
    if case .use(let tier, _, _) = outcome { return tier }
    return nil
  }

  /// Whether the user must confirm before the request is sent.
  public var needsConfirmation: Bool {
    if case .use(_, true, _) = outcome { return true }
    return false
  }

  /// Whether the answer must carry a reduced-scope label.
  public var isReducedScope: Bool {
    if case .use(_, _, true) = outcome { return true }
    return false
  }

  /// Why the request is refused, or `nil` when a tier was chosen.
  public var refusal: RouteRefusalReason? {
    if case .refuse(let reason) = outcome { return reason }
    return nil
  }
}
