import DesignSystem
import StoreKit
import SwiftUI

/// The subscription offer, and in the same presentation the confirmation after a purchase.
///
/// The plans, their prices, the trial and the renewal terms are StoreKit's own view, so they are
/// right for the person's storefront and for whether they can have the introductory offer. Nothing
/// the app writes states a price, a period or a trial (ADR-0026).
public struct PaywallFlowView: View {
  @State private var model: PaywallModel

  /// Creates the presentation for a model.
  public init(model: PaywallModel) {
    _model = State(initialValue: model)
  }

  /// The offer, or the confirmation.
  public var body: some View {
    NavigationStack {
      Group {
        switch model.phase {
        case .offer: offer
        case .welcome: WelcomeProView(model: model)
        }
      }
      .toolbar {
        if model.phase == .offer {
          // On screen from the first frame, and one tap closes: the offer is never a condition of
          // using the app (FR-ONB-004).
          ToolbarItem(placement: .cancellationAction) {
            Button {
              model.close()
            } label: {
              Text("Close", bundle: .module)
            }
            .accessibilityIdentifier("paywall.close")
          }
        }
      }
    }
    .task { await model.appeared() }
    .onChange(of: model.grantsPro) { Task { await model.entitlementChanged() } }
  }

  private var offer: some View {
    SubscriptionStoreView(productIDs: model.productIDs) {
      PaywallHeader(trigger: model.trigger, benefits: model.benefits)
    }
    // The toolbar's Close is the one way out, with one identifier; StoreKit's own would be a second.
    .storeButton(.hidden, for: .cancellation)
    .storeButton(.visible, for: .restorePurchases, .redeemCode, .policies)
    .subscriptionStorePolicyDestination(url: model.termsOfUse, for: .termsOfService)
    .subscriptionStorePolicyDestination(url: model.privacyPolicy, for: .privacyPolicy)
    .accessibilityIdentifier("paywall.offer")
  }
}

/// What the offer says above the plans: why it is here, what Pro adds, and what never needs it.
struct PaywallHeader: View {
  let trigger: PaywallTrigger
  let benefits: [PaywallBenefit]

  var body: some View {
    VStack(spacing: Spacing.s300) {
      AppMark(side: 64)
      VStack(spacing: Spacing.s100) {
        trigger.headline
          .font(.title.bold())
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("paywall.headline.\(trigger.rawValue)")
        trigger.explanation
          .font(.body)
          .foregroundStyle(Color.ds.labelSecondary)
          .multilineTextAlignment(.center)
      }
      BenefitList(benefits: benefits)
      Label {
        Text(
          "Your documents are always yours: opening, reading, signing, sharing and exporting never need Pro.",
          bundle: .module)
      } icon: {
        Image(systemName: "lock.open")
      }
      .font(.footnote)
      .foregroundStyle(Color.ds.labelSecondary)
    }
    .padding(Spacing.s300)
    .readableWidth()
  }
}

/// What Pro adds, one row each.
struct BenefitList: View {
  let benefits: [PaywallBenefit]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s200) {
      ForEach(benefits) { benefit in
        HStack(alignment: .top, spacing: Spacing.s150) {
          IconTile(systemName: benefit.symbol)
          VStack(alignment: .leading, spacing: Spacing.s050) {
            benefit.title.font(.headline)
            benefit.detail.font(.subheadline).foregroundStyle(Color.ds.labelSecondary)
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.benefit.\(benefit.rawValue)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
