import Core
import Foundation

/// Document intelligence over tiered models (ADR-0009, ADR-0021).
///
/// The router picks the first available tier in order (on device first), fits the document into
/// that tier's context with retrieval or map-reduce, and returns only grounded, cited results. Cloud
/// tiers are opt-in and join the list only after consent; this build ships the on-device tier.
public struct IntelligenceRouter: DocumentIntelligence {
  private let models: [any LanguageModelDriving]
  private let isHidden: @Sendable () -> Bool

  /// Creates a router over tiers in preference order.
  ///
  /// - Parameter isHidden: Whether the user hid AI features (FR-AI-009); hidden means unavailable.
  public init(models: [any LanguageModelDriving], isHidden: @escaping @Sendable () -> Bool = { false }) {
    self.models = models
    self.isHidden = isHidden
  }

  // MARK: - Availability

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

  public func summarize(_ pages: [PageText]) async throws -> Answer {
    try await summarize(pages, template: PromptCatalog.summarizeChunk)
  }

  public func explainContract(_ pages: [PageText]) async throws -> Answer {
    try await summarize(pages, template: PromptCatalog.explainContract)
  }

  public func answer(_ question: String, from pages: [PageText]) async throws -> Answer {
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let pages = Self.withText(pages)
    guard !pages.isEmpty else { throw IntelligenceError.noText }
    guard !question.isEmpty else { return .notFound(tier: .onDevice) }
    let model = try await activeModel()
    let ranked = Grounding.rank(pages, for: question)
    let candidates = ranked.isEmpty ? pages : ranked + pages.filter { page in !ranked.contains(page) }
    let questionTokens = await model.tokenCount(question)
    let chosen = try await fit(candidates, into: await model.promptBudget() - questionTokens, model: model)
      .sorted { $0.pageIndex < $1.pageIndex }
    let prompt = "\(PromptCatalog.documentBlock(chosen))\n\nQuestion: \(question)"
    let response = try await run { try await model.respond(instructions: PromptCatalog.ask.instructions, prompt: prompt) }
    return Grounding.answer(from: response, pages: chosen, tier: model.tier)
  }

  public func extractFields(from pages: [PageText]) async throws -> Extraction {
    let pages = Self.withText(pages)
    guard !pages.isEmpty else { throw IntelligenceError.noText }
    let model = try await activeModel()
    let chosen = try await fit(pages, into: await model.promptBudget(), model: model)
    let draft = try await run {
      try await model.extract(instructions: PromptCatalog.extract.instructions, prompt: PromptCatalog.documentBlock(chosen))
    }
    let fields = draft.fields.compactMap { field -> ExtractedField? in
      guard let value = field.value else { return nil }
      return ExtractedField(key: field.key, value: value, pageIndex: Grounding.page(containing: value, in: pages))
    }
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
      merged.append(try await run { try await model.respond(instructions: PromptCatalog.summarizeCombine.instructions, prompt: prompt) })
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
