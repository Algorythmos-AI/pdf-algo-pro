import Foundation
import Testing

@testable import Core

@Suite("Routing value types")
struct RoutingValueTests {
  @Test("Only the on-device tier keeps content on the device, and it leads the routing order")
  func tiers() {
    #expect(IntelligenceTier.allCases.filter(\.isCloud) == [.privateCloudCompute, .claude])
    #expect(IntelligenceTier.routingOrder == [.onDevice, .privateCloudCompute, .claude])
    #expect(SizeBand.allCases.sorted() == [.s, .m, .l, .xl])
  }

  @Test("A consent permits sending only when given, not revoked, and on the current consent text")
  func consent() throws {
    let current = ConsentState.currentTextVersion
    for status in ConsentState.Status.allCases {
      let given = status == .granted || status == .askBeforeSending
      #expect(ConsentState(status: status, textVersion: current, decidedAt: .now).permitsSending() == given)
      #expect(!ConsentState(status: status, textVersion: current - 1, decidedAt: .now).permitsSending())
      #expect(!ConsentState(status: status, textVersion: current + 1, decidedAt: .now).permitsSending())
    }
    #expect(!ConsentState.notAsked.permitsSending())
    let state = ConsentState(status: .askBeforeSending, textVersion: 3, decidedAt: Date(timeIntervalSince1970: 60))
    #expect(try JSONDecoder().decode(ConsentState.self, from: JSONEncoder().encode(state)) == state)
  }

  @Test("A tier without stated facts is not built: unavailable and without consent")
  func defaultFacts() {
    let facts = TierFacts()
    #expect(!facts.isAvailable)
    #expect(facts.consent == .notAsked)
    let refused = RouteDecision(outcome: .refuse(.noConsent))
    #expect(refused.tier == nil)
    #expect(refused.refusal == .noConsent)
    let used = RouteDecision(outcome: .use(tier: .claude, needsConfirmation: true, isReducedScope: true))
    #expect(used.tier == .claude)
    #expect(used.needsConfirmation)
    #expect(used.isReducedScope)
    #expect(used.refusal == nil)
  }
}
