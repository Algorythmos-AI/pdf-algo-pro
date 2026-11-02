#if DEBUG
  import Commerce
  import Core
  import DesignSystem
  import SwiftUI

  // Previews of the offer, the confirmation after a purchase and the subscription section, for the
  // design pass (PAP-070), with the store's made-up test plans: they say nothing about prices.

  /// Telemetry that keeps nothing.
  private struct PreviewTelemetry: TelemetryRecording {
    func record(_ event: String) async {}
  }

  /// The offer for an account in a given state, or, when `buying`, the confirmation that follows a
  /// purchase.
  private struct PaywallPreview: View {
    @State private var model: PaywallModel
    private let buying: Bool

    init(
      entitlement: Entitlement = .none, trial: TrialOffer? = TrialOffer(length: 3, unit: .day),
      plansLoad: Bool = true, buying: Bool = false
    ) {
      let scripted = ScriptedEntitlements(entitlement)
      let entitlements = EntitlementStore(provider: scripted)
      entitlements.start()
      let offering = FixedStoreOffering(
        plans: plansLoad ? FixedStoreOffering.fixturePlans(trial: trial) : nil,
        onPurchased: { _ in scripted.set(.subscribed) })
      _model = State(
        initialValue: PaywallModel(
          trigger: .onboarding, productIDs: ["yearly", "weekly"],
          benefits: [.unlimitedScans, .unlimitedIntelligence, .textEditing],
          termsOfUse: URL(fileURLWithPath: "/terms"), privacyPolicy: URL(fileURLWithPath: "/privacy"),
          offering: offering, entitlements: entitlements, telemetry: PreviewTelemetry(), onClose: {}))
      self.buying = buying
    }

    var body: some View {
      PaywallFlowView(model: model, store: FixedStoreAccess(isAvailable: true))
        .environment(\.playsDecorativeMotion, false)
        .task {
          guard buying else { return }
          await model.appeared()
          await model.purchase()
        }
    }
  }

  /// The subscription section as Settings shows it.
  private func subscriptionPreview(_ entitlement: Entitlement) -> some View {
    let entitlements = EntitlementStore(provider: FixedEntitlements(entitlement))
    return Form {
      SubscriptionSection(entitlements: entitlements, store: FixedStoreAccess(isAvailable: true), onSeePlans: {})
    }
    .task { await entitlements.refresh() }
  }

  #Preview("Offer") { PaywallPreview() }
  #Preview("Offer, largest text") { PaywallPreview().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Offer, dark") { PaywallPreview().preferredColorScheme(.dark) }
  #Preview("Offer, right to left") { PaywallPreview().environment(\.layoutDirection, .rightToLeft) }

  #Preview("Offer without a trial") { PaywallPreview(trial: nil) }
  #Preview("Offer without a trial, dark") { PaywallPreview(trial: nil).preferredColorScheme(.dark) }

  #Preview("Plans unavailable") { PaywallPreview(plansLoad: false) }
  #Preview("Plans unavailable, largest text") {
    PaywallPreview(plansLoad: false).environment(\.dynamicTypeSize, .accessibility5)
  }

  #Preview("Already Pro") { PaywallPreview(entitlement: .subscribed) }
  #Preview("Already Pro, dark") { PaywallPreview(entitlement: .subscribed).preferredColorScheme(.dark) }

  #Preview("Payment paused") { PaywallPreview(entitlement: .inBillingRetry) }

  #Preview("Welcome to Pro") { PaywallPreview(trial: nil, buying: true) }
  #Preview("Welcome to Pro, largest text") {
    PaywallPreview(trial: nil, buying: true).environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("Welcome to Pro, dark") { PaywallPreview(trial: nil, buying: true).preferredColorScheme(.dark) }

  #Preview("Subscription section, free") { subscriptionPreview(.none) }
  #Preview("Subscription section, Pro") { subscriptionPreview(.subscribed) }
  #Preview("Subscription section, Pro, dark") { subscriptionPreview(.subscribed).preferredColorScheme(.dark) }
#endif
