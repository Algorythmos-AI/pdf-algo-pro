import Core
import Foundation

/// Document intelligence over tiered models (ADR-0009, ADR-0021).
///
/// The router picks the first available tier in order (on device first), fits the document into
/// that tier's context with retrieval or map-reduce, and returns only grounded, cited results. Cloud
/// tiers are opt-in and join the list only after consent; this build ships the on-device tier.
public struct IntelligenceRouter: DocumentIntelligence {
  private let models: [any LanguageModelDriving]
  /// How a question's words are compared with a page's when pages are found for it.
  private let wordForms: WordForms
  private let isHidden: @Sendable () -> Bool
  /// Counts each answered request by tier, for the privacy report (FR-SET-005).
  private let activity: (any AIActivityRecording)?

  /// Creates a router over tiers in preference order.
  ///
  /// - Parameters:
  ///   - models: The tiers, most preferred first; the on-device tier leads.
  ///   - isHidden: Whether the user hid AI features (FR-AI-009); hidden means unavailable.
  ///   - activity: Counts answered requests by tier for the privacy report (FR-SET-005).
  ///   - wordForms: How a question's words are compared with a page's when pages are found for it.
  public init(
    models: [any LanguageModelDriving], isHidden: @escaping @Sendable () -> Bool = { false },
    activity: (any AIActivityRecording)? = nil, wordForms: WordForms = .asWritten
  ) {
    self.wordForms = wordForms
    self.models = models
    self.isHidden = isHidden
    self.activity = activity
  }

  // MARK: - Availability

  /// Whether a tier can run now.
  public func availability() async -> IntelligenceAvailability {
    if isHidden() { return .unavailable(.hiddenBySettings) }
    var firstReason: IntelligenceUnavailableReason?
    for model in models {
      switch await model.availability() {
      case .available(let tier): return .available(tier)
      case .unavailable(let reason): firstReason = firstReason ?? reason
      }
    }
    return .unavailable(firstReason ?? .deviceNotEligible)
  }

  private func activeModel() async throws -> any LanguageModelDriving {
    if isHidden() { throw IntelligenceError.unavailable(.hiddenBySettings) }
    for model in models where await model.availability().isAvailable { return model }
    if case .unavailable(let reason) = await availability() { throw IntelligenceError.unavailable(reason) }
    throw IntelligenceError.unavailable(.deviceNotEligible)
  }

  // MARK: - Tasks

  /// Summarises the pages, citing the pages each point draws on.
  public func summarize(_ pages: [PageText]) async throws -> Answer {
    let interval = Signposts.begin("AI.Summary")
    defer { interval.end() }
    return try await summarize(pages, template: PromptCatalog.summarizeChunk)
  }

  /// Explains a contract's key terms in plain language.
  ///
  /// The UI adds the not-legal-advice disclosure.
  public func explainContract(_ pages: [PageText]) async throws -> Answer {
    try await summarize(pages, template: PromptCatalog.explainContract)
  }

  /// Answers a question from the pages, or returns a not-found answer.
  public func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let pages = Self.withText(pages)
    guard !pages.isEmpty else { throw IntelligenceError.noText }
    guard !question.isEmpty else { return .notFound(tier: .onDevice) }
    let model = try await activeModel()
    let chosen: [PageText]
    do {
      let retrieval = Signposts.begin("AI.Retrieve")
      defer { retrieval.end() }
      let ranked = Grounding.rank(pages, for: question, forms: wordForms)
      let candidates = ranked.isEmpty ? pages : ranked + pages.filter { page in !ranked.contains(page) }
      let questionTokens = await model.tokenCount(question)
      chosen = try await fit(candidates, into: await model.promptBudget() - questionTokens, model: model)
        .sorted { $0.pageIndex < $1.pageIndex }
    }
    let prompt = "\(PromptCatalog.documentBlock(chosen))\n\nQuestion: \(question)"
    let response = try await run {
      try await model.respond(instructions: PromptCatalog.ask.instructions, prompt: prompt)
    }
    await activity?.record(model.tier)
    return Grounding.answer(from: response, pages: chosen, tier: model.tier)
  }

  /// The most earlier exchanges a follow-up carries, and their share of the prompt budget (`Assumption:`
  /// 3 and 10%, plan §4.3), so the document keeps most of the room.
  static let followUpExchanges = 3
  static let conversationShare = 0.1

  /// Answers a follow-up question (FR-AI-014).
  ///
  /// Retrieval searches with the new question and the one before it, and puts the pages the last
  /// answer cited first. The earlier exchanges go into the prompt, fenced, as context only; the answer
  /// is grounded against the document pages alone, like any other.
  public func answer(_ question: String, from pages: [PageText], after earlier: [Exchange]) async throws -> Answer {
    let grounded = earlier.filter(\.answer.isGrounded).suffix(Self.followUpExchanges)
    guard let last = grounded.last else { return try await answer(question, from: pages) }
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let pages = Self.withText(pages)
    guard !pages.isEmpty else { throw IntelligenceError.noText }
    guard !question.isEmpty else { return .notFound(tier: .onDevice) }
    let model = try await activeModel()
    let budget = await model.promptBudget()
    var context = Array(grounded)
    var conversation = PromptCatalog.conversationBlock(context)
    while context.count > 1, await model.tokenCount(conversation) > Int(Double(budget) * Self.conversationShare) {
      context.removeFirst()
      conversation = PromptCatalog.conversationBlock(context)
    }
    let chosen: [PageText]
    do {
      let retrieval = Signposts.begin("AI.Retrieve")
      defer { retrieval.end() }
      let cited = Set(last.answer.citations.map(\.pageIndex))
      let ranked = Grounding.rank(pages, for: "\(question) \(last.question)", forms: wordForms)
      let first = pages.filter { cited.contains($0.pageIndex) }
      let candidates =
        first + ranked.filter { !first.contains($0) }
        + pages.filter { page in !first.contains(page) && !ranked.contains(page) }
      let used = await model.tokenCount(question) + model.tokenCount(conversation)
      chosen = try await fit(candidates, into: budget - used, model: model).sorted { $0.pageIndex < $1.pageIndex }
    }
    let prompt = "\(conversation)\n\n\(PromptCatalog.documentBlock(chosen))\n\nQuestion: \(question)"
    let response = try await run {
      try await model.respond(instructions: PromptCatalog.askFollowUp.instructions, prompt: prompt)
    }
    await activity?.record(model.tier)
    return Grounding.answer(from: response, pages: chosen, tier: model.tier)
  }

  /// Extracts structured fields and verifies each value against the text.
  public func extractFields(from pages: [PageText]) async throws -> Extraction {
    let pages = Self.withText(pages)
    guard !pages.isEmpty else { throw IntelligenceError.noText }
    let model = try await activeModel()
    let chosen = try await fit(pages, into: await model.promptBudget(), model: model)
    let draft = try await run {
      try await model.extract(
        instructions: PromptCatalog.extract.instructions, prompt: PromptCatalog.documentBlock(chosen))
    }
    let fields = draft.fields.compactMap { field -> ExtractedField? in
      guard let value = field.value else { return nil }
      return ExtractedField(key: field.key, value: value, pageIndex: Grounding.page(containing: value, in: pages))
    }
    await activity?.record(model.tier)
    return Extraction(fields: fields, tier: model.tier)
  }

  // MARK: - Summaries (map-reduce)

  private func summarize(_ pages: [PageText], template: PromptTemplate) async throws -> Answer {
    let pages = Self.withText(pages)
    guard !pages.isEmpty else { throw IntelligenceError.noText }
    let model = try await activeModel()
    let budget = await model.promptBudget()
    var partials: [String] = []
    for chunk in try await chunks(of: pages, budget: budget, model: model) {
      try Task.checkCancellation()
      let prompt = PromptCatalog.documentBlock(chunk)
      partials.append(try await run { try await model.respond(instructions: template.instructions, prompt: prompt) })
    }
    var combined = partials
    while combined.count > 1 {
      try Task.checkCancellation()
      combined = try await combine(combined, budget: budget, model: model)
    }
    await activity?.record(model.tier)
    return Grounding.answer(from: combined.first ?? "", pages: pages, tier: model.tier)
  }

  /// Merges partial summaries in groups that fit the budget, keeping their citations.
  private func combine(_ partials: [String], budget: Int, model: any LanguageModelDriving) async throws -> [String] {
    var groups: [[String]] = [[]]
    var used = 0
    for partial in partials {
      let cost = await model.tokenCount(partial)
      if used + cost > budget, !(groups.last?.isEmpty ?? true) {
        groups.append([])
        used = 0
      }
      groups[groups.count - 1].append(partial)
      used += cost
    }
    if groups.count == partials.count, partials.count > 1 {
      // Every partial fills the budget on its own: merge pairs so the loop always shrinks.
      groups = stride(from: 0, to: partials.count, by: 2).map { Array(partials[$0..<min($0 + 2, partials.count)]) }
    }
    var merged: [String] = []
    for group in groups {
      guard group.count > 1 else {
        merged.append(contentsOf: group)
        continue
      }
      let prompt = "<document>\n\(group.map(PromptCatalog.sanitize).joined(separator: "\n\n"))\n</document>"
      merged.append(
        try await run {
          try await model.respond(instructions: PromptCatalog.summarizeCombine.instructions, prompt: prompt)
        })
    }
    return merged
  }

  // MARK: - Fitting pages into the context

  /// Consecutive groups of pages that each fit the budget; a page too long on its own is truncated.
  func chunks(of pages: [PageText], budget: Int, model: any LanguageModelDriving) async throws -> [[PageText]] {
    var chunks: [[PageText]] = [[]]
    var used = 0
    for page in pages {
      try Task.checkCancellation()
      let fitted = await truncate(page, to: budget, model: model)
      let cost = await model.tokenCount(fitted.text) + 8
      if used + cost > budget, !(chunks.last?.isEmpty ?? true) {
        chunks.append([])
        used = 0
      }
      chunks[chunks.count - 1].append(fitted)
      used += cost
    }
    return chunks.filter { !$0.isEmpty }
  }

  /// The pages, in the given order, that fit the budget; always at least the first one.
  func fit(_ pages: [PageText], into budget: Int, model: any LanguageModelDriving) async throws -> [PageText] {
    var chosen: [PageText] = []
    var used = 0
    for page in pages {
      try Task.checkCancellation()
      let fitted = chosen.isEmpty ? await truncate(page, to: budget, model: model) : page
      let cost = await model.tokenCount(fitted.text) + 8
      if !chosen.isEmpty, used + cost > budget { break }
      chosen.append(fitted)
      used += cost
    }
    return chosen
  }

  private func truncate(_ page: PageText, to budget: Int, model: any LanguageModelDriving) async -> PageText {
    var text = page.text
    while await model.tokenCount(text) + 8 > budget, text.count > 200 {
      text = String(text.prefix(text.count * 3 / 4))
    }
    return PageText(pageIndex: page.pageIndex, text: text)
  }

  private static func withText(_ pages: [PageText]) -> [PageText] {
    pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  /// Runs a model call, mapping model errors to the errors features show.
  private func run<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as ModelError {
      switch error {
      case .contextTooLarge: throw IntelligenceError.unavailable(.requestTooLarge)
      case .refused: throw IntelligenceError.refused
      case .unavailable(let reason): throw IntelligenceError.unavailable(reason)
      case .failed: throw IntelligenceError.generationFailed
      }
    }
  }
}
