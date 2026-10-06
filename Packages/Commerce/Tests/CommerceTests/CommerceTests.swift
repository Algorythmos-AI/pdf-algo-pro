import CommerceTestSupport
import Foundation
import StoreKit
import Synchronization
import Testing

@testable import Commerce

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 24 * 60 * 60
private let pro: Set<String> = ["pro.monthly", "pro.annual"]

/// One entitlement of every kind. `index(of:)` has no default, so a new case fails to compile here
/// until it is added to the list.
private let everyEntitlement: [Entitlement] = [
  .none, .trial(endsAt: now.addingTimeInterval(7 * day)), .trial(endsAt: now.addingTimeInterval(-day)),
  .subscribed, .inGracePeriod, .inBillingRetry, .expired, .revoked,
]

private func index(of entitlement: Entitlement) -> Int {
  switch entitlement {
  case .none: 0
  case .trial: 1
  case .subscribed: 2
  case .inGracePeriod: 3
  case .inBillingRetry: 4
  case .expired: 5
  case .revoked: 6
  }
}

@Suite("The gate")
struct FeatureGateTests {
  @Test("The list of entitlements has every kind")
  func complete() {
    #expect(Set(everyEntitlement.map(index)) == Set(0...6))
  }

  @Test("A document operation is allowed for every entitlement (FR-STORE-004)")
  func documentsAreNeverLocked() {
    #expect(DocumentOperation.allCases.count == 12)
    for operation in DocumentOperation.allCases {
      for entitlement in everyEntitlement {
        #expect(
          FeatureGate.isAllowed(operation, entitlement: entitlement, now: now),
          "\(operation) with \(entitlement)")
      }
    }
  }

  @Test("A Pro feature is allowed during a running trial, a paid period and the grace period only")
  func proFeatures() {
    #expect(ProFeature.allCases.count == 6)
    let allowed: [Entitlement] = [.trial(endsAt: now.addingTimeInterval(7 * day)), .subscribed, .inGracePeriod]
    for feature in ProFeature.allCases {
      for entitlement in everyEntitlement {
        #expect(
          FeatureGate.isAllowed(feature, entitlement: entitlement, now: now) == allowed.contains(entitlement),
          "\(feature) with \(entitlement)")
      }
    }
  }

  @Test("A trial stops granting Pro at its end date")
  func trialEnd() {
    #expect(Entitlement.trial(endsAt: now.addingTimeInterval(1)).grantsPro(at: now))
    #expect(!Entitlement.trial(endsAt: now).grantsPro(at: now))
  }
}

@Suite("Purchase records map to an entitlement")
struct EntitlementResolutionTests {
  private func resolve(_ records: PurchaseRecord...) -> Entitlement {
    Entitlement.resolve(records: records, productIDs: pro, now: now)
  }

  private let later = now.addingTimeInterval(30 * day)
  private let earlier = now.addingTimeInterval(-day)

  @Test("No record, or one for another product, is no entitlement")
  func none() {
    #expect(resolve() == .none)
    #expect(resolve(PurchaseRecord(productID: "other", expirationDate: later, renewalState: .subscribed)) == .none)
  }

  @Test("An active period is subscribed, or a trial when bought as a free trial")
  func active() {
    #expect(resolve(PurchaseRecord(productID: "pro.monthly", expirationDate: later)) == .subscribed)
    #expect(
      resolve(PurchaseRecord(productID: "pro.monthly", expirationDate: later, renewalState: .subscribed))
        == .subscribed)
    #expect(
      resolve(PurchaseRecord(productID: "pro.annual", expirationDate: later, offer: .freeTrial))
        == .trial(endsAt: later))
    #expect(
      resolve(PurchaseRecord(productID: "pro.annual", expirationDate: later, offer: .paidIntroductory))
        == .subscribed)
    #expect(resolve(PurchaseRecord(productID: "pro.annual", expirationDate: later, offer: .other)) == .subscribed)
    #expect(resolve(PurchaseRecord(productID: "pro.annual", offer: .freeTrial)) == .subscribed)
  }

  @Test("The renewal state decides grace period, billing retry, expiry and revocation")
  func states() {
    let record = PurchaseRecord(productID: "pro.annual", expirationDate: earlier, offer: .freeTrial)
    var graced = record
    graced.renewalState = .inGracePeriod
    var retrying = record
    retrying.renewalState = .inBillingRetry
    var expired = record
    expired.renewalState = .expired
    var revoked = record
    revoked.renewalState = .revoked
    #expect(resolve(graced) == .inGracePeriod)
    #expect(resolve(retrying) == .inBillingRetry)
    #expect(resolve(expired) == .expired)
    #expect(resolve(revoked) == .revoked)
  }

  @Test("Without a renewal state, a period that has ended is expired")
  func endedPeriod() {
    #expect(resolve(PurchaseRecord(productID: "pro.monthly", expirationDate: earlier)) == .expired)
    #expect(resolve(PurchaseRecord(productID: "pro.monthly", expirationDate: now)) == .expired)
  }

  @Test("A revocation date wins over an active state")
  func refund() {
    let record = PurchaseRecord(
      productID: "pro.monthly", expirationDate: later, revocationDate: earlier, renewalState: .subscribed)
    #expect(resolve(record) == .revoked)
  }

  @Test("With several records, the one that gives the most wins")
  func best() {
    let revoked = PurchaseRecord(productID: "pro.monthly", revocationDate: earlier)
    let expired = PurchaseRecord(productID: "pro.monthly", expirationDate: earlier)
    let retrying = PurchaseRecord(productID: "pro.monthly", renewalState: .inBillingRetry)
    let graced = PurchaseRecord(productID: "pro.monthly", renewalState: .inGracePeriod)
    let trial = PurchaseRecord(productID: "pro.annual", expirationDate: later, offer: .freeTrial)
    let subscribed = PurchaseRecord(productID: "pro.annual", expirationDate: later)
    #expect(resolve(revoked, expired) == .expired)
    #expect(resolve(retrying, expired, revoked) == .inBillingRetry)
    #expect(resolve(retrying, graced) == .inGracePeriod)
    #expect(resolve(graced, trial) == .trial(endsAt: later))
    #expect(resolve(trial, subscribed, revoked) == .subscribed)
  }
}

@Suite("StoreKit values map to plain ones")
struct StoreKitMappingTests {
  @Test("Only a free introductory offer is a trial")
  func offers() {
    #expect(PurchaseRecord.Offer(type: .introductory, paymentMode: .freeTrial) == .freeTrial)
    #expect(PurchaseRecord.Offer(type: .introductory, paymentMode: .payAsYouGo) == .paidIntroductory)
    #expect(PurchaseRecord.Offer(type: .introductory, paymentMode: nil) == .paidIntroductory)
    #expect(PurchaseRecord.Offer(type: .promotional, paymentMode: .freeTrial) == .other)
    #expect(PurchaseRecord.Offer(type: .code, paymentMode: nil) == .other)
  }

  @Test("Each renewal state maps, and an unknown one does not")
  func renewalStates() {
    #expect(PurchaseRecord.RenewalState(.subscribed) == .subscribed)
    #expect(PurchaseRecord.RenewalState(.inGracePeriod) == .inGracePeriod)
    #expect(PurchaseRecord.RenewalState(.inBillingRetryPeriod) == .inBillingRetry)
    #expect(PurchaseRecord.RenewalState(.expired) == .expired)
    #expect(PurchaseRecord.RenewalState(.revoked) == .revoked)
    #expect(PurchaseRecord.RenewalState(Product.SubscriptionInfo.RenewalState(rawValue: 99)) == nil)
  }
}

/// A stand-in for an App Store transaction that counts how often it was finished.
private final class FakeTransaction: PurchaseTransaction {
  let productID: String
  let expirationDate: Date?
  let revocationDate: Date?
  let purchaseOffer: PurchaseRecord.Offer?
  private let state: PurchaseRecord.RenewalState?
  private let finishes = Mutex(0)

  init(
    _ productID: String, expirationDate: Date? = nil, revocationDate: Date? = nil,
    offer: PurchaseRecord.Offer? = nil, state: PurchaseRecord.RenewalState? = nil
  ) {
    self.productID = productID
    self.expirationDate = expirationDate
    self.revocationDate = revocationDate
    purchaseOffer = offer
    self.state = state
  }

  var finishCount: Int { finishes.withLock { $0 } }
  func renewalState() async -> PurchaseRecord.RenewalState? { state }
  func finish() async { finishes.withLock { $0 += 1 } }
}

@Suite("Transactions become records")
struct PurchaseTransactionTests {
  private let end = now.addingTimeInterval(30 * day)

  private typealias Result = VerificationResult<FakeTransaction>

  private func results(_ list: [Result]) -> AsyncStream<Result> {
    AsyncStream { continuation in
      for result in list {
        continuation.yield(result)
      }
      continuation.finish()
    }
  }

  @Test("A record carries each field of its transaction")
  func fields() async {
    let transaction = FakeTransaction(
      "pro.annual", expirationDate: end, revocationDate: now, offer: .freeTrial, state: .inGracePeriod)
    let expected = PurchaseRecord(
      productID: "pro.annual", expirationDate: end, revocationDate: now, offer: .freeTrial,
      renewalState: .inGracePeriod)
    #expect(await PurchaseRecord(transaction) == expected)
    #expect(await PurchaseRecord(verified: .verified(transaction)) == expected)
  }

  @Test("A transaction that StoreKit did not verify gives no record")
  func unverified() async {
    let forged = FakeTransaction("pro.annual", expirationDate: end)
    #expect(await PurchaseRecord(verified: .unverified(forged, .invalidSignature)) == nil)
    let records = await PurchaseRecord.verified(
      in: results([.unverified(forged, .invalidSignature), .verified(FakeTransaction("pro.monthly"))]))
    #expect(records == [PurchaseRecord(productID: "pro.monthly")])
  }

  @Test("Each update signals a change, and only a verified one is finished")
  func changes() async {
    let renewed = FakeTransaction("pro.monthly")
    let forged = FakeTransaction("pro.monthly")
    var signals = 0
    for await _ in PurchaseRecord.changes(in: results([.verified(renewed), .unverified(forged, .invalidSignature)])) {
      signals += 1
    }
    #expect(signals == 2)
    #expect(renewed.finishCount == 1 && forged.finishCount == 0)
  }
}

/// Purchase records held in memory. `changes()` hands out one stream, made up front, so a change
/// signalled before the provider starts listening is not lost.
private final class FakeSource: PurchaseRecordSource {
  private let records: Mutex<(active: [PurchaseRecord], latest: [String: PurchaseRecord])>
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init(active: [PurchaseRecord] = [], latest: [PurchaseRecord] = []) {
    records = Mutex((active, Dictionary(uniqueKeysWithValues: latest.map { ($0.productID, $0) })))
    (stream, continuation) = AsyncStream.makeStream(of: Void.self)
  }

  func change(active: [PurchaseRecord]) {
    records.withLock { $0.active = active }
    continuation.yield()
  }

  func finish() { continuation.finish() }

  func activeRecords() async -> [PurchaseRecord] { records.withLock { $0.active } }
  func latestRecord(for productID: String) async -> PurchaseRecord? { records.withLock { $0.latest[productID] } }
  func changes() -> AsyncStream<Void> { stream }
}

@Suite("The StoreKit provider")
struct StoreKitEntitlementsTests {
  private let later = now.addingTimeInterval(30 * day)

  private func provider(_ source: FakeSource) -> StoreKitEntitlements {
    StoreKitEntitlements(productIDs: pro, source: source, now: { now })
  }

  @Test("A current entitlement for a Pro product is used, and other products are ignored")
  func current() async {
    let source = FakeSource(active: [
      PurchaseRecord(productID: "other", expirationDate: later),
      PurchaseRecord(productID: "pro.annual", expirationDate: later, offer: .freeTrial),
    ])
    #expect(await provider(source).currentEntitlement() == .trial(endsAt: later))
  }

  @Test("Without a current entitlement, the latest transaction tells a lapse from no purchase")
  func lapsed() async {
    #expect(await provider(FakeSource()).currentEntitlement() == .none)
    let expired = FakeSource(latest: [PurchaseRecord(productID: "pro.monthly", renewalState: .expired)])
    #expect(await provider(expired).currentEntitlement() == .expired)
    let retrying = FakeSource(
      active: [PurchaseRecord(productID: "other")],
      latest: [PurchaseRecord(productID: "pro.annual", renewalState: .inBillingRetry)])
    #expect(await provider(retrying).currentEntitlement() == .inBillingRetry)
  }

  @Test("The stream gives the entitlement now, then one after each change, and ends with its source")
  func updates() async {
    let source = FakeSource()
    var received: [Entitlement] = []
    let stream = provider(source).entitlementUpdates()
    source.change(active: [PurchaseRecord(productID: "pro.monthly", expirationDate: later)])
    source.finish()
    for await entitlement in stream {
      received.append(entitlement)
    }
    #expect(received.last == .subscribed)
    #expect(received.count == 2)
  }

  @Test("The public initialiser takes the product identifiers")
  func initialiser() {
    _ = StoreKitEntitlements(productIDs: pro)
    _ = StoreKitEntitlements(productIDs: pro, now: { now })
  }
}

@Suite("The trial reminder (FR-STORE-006)")
struct TrialReminderTests {
  private let end = now.addingTimeInterval(7 * day)

  @Test("The reminder is one day before the trial ends, and only a trial has one")
  func date() {
    #expect(TrialReminder.reminderDate(trialEndsAt: end) == now.addingTimeInterval(6 * day))
    #expect(TrialReminder.reminderDate(for: .trial(endsAt: end)) == now.addingTimeInterval(6 * day))
    for entitlement in everyEntitlement where index(of: entitlement) != 1 {
      #expect(TrialReminder.reminderDate(for: entitlement) == nil)
      #expect(TrialReminder.notificationDate(for: entitlement, now: now) == nil)
      #expect(!TrialReminder.isDueAtLaunch(entitlement: entitlement, now: now, lastRemindedTrialEnd: nil))
    }
  }

  @Test("It is due from the reminder date until the trial ends, once per trial")
  func due() {
    let trial = Entitlement.trial(endsAt: end)
    func due(_ offset: TimeInterval, reminded: Date? = nil) -> Bool {
      TrialReminder.isDueAtLaunch(
        entitlement: trial, now: now.addingTimeInterval(offset), lastRemindedTrialEnd: reminded)
    }
    #expect(!due(6 * day - 1))
    #expect(due(6 * day))
    #expect(due(7 * day - 1))
    #expect(!due(7 * day))
    #expect(!due(6 * day, reminded: end))
    #expect(due(6 * day, reminded: end.addingTimeInterval(-30 * day)), "An earlier trial's reminder does not count")
  }

  @Test("A notification is scheduled only while the reminder date is ahead")
  func notification() {
    let trial = Entitlement.trial(endsAt: end)
    #expect(TrialReminder.notificationDate(for: trial, now: now) == now.addingTimeInterval(6 * day))
    #expect(TrialReminder.notificationDate(for: trial, now: now.addingTimeInterval(6 * day)) == nil)
    #expect(TrialReminder.notificationDate(for: .trial(endsAt: now.addingTimeInterval(day / 2)), now: now) == nil)
  }
}

@Suite("The fake provider")
struct FakeEntitlementsTests {
  @Test("It reports what was set, to every stream")
  func fake() async {
    let fake = FakeEntitlements()
    #expect(await fake.currentEntitlement() == .none)
    var first = fake.entitlementUpdates().makeAsyncIterator()
    var second = fake.entitlementUpdates().makeAsyncIterator()
    #expect(await first.next() == Entitlement.none)
    fake.set(.subscribed)
    #expect(await first.next() == .subscribed)
    #expect(await second.next() == Entitlement.none)
    #expect(await second.next() == .subscribed)
    #expect(await fake.currentEntitlement() == .subscribed)
  }
}
