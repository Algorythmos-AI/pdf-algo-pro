import DesignSystem
import StoreKit
import SwiftUI

/// The subscription offer, and in the same presentation the confirmation after a purchase.
///
/// The plans, their prices, the trial and the renewal terms are StoreKit's own view, so they are
/// right for the person's storefront and for whether they can have the introductory offer. The app
/// writes one comparison of its own, the annual plan's saving, and works it out from StoreKit's
/// prices for the same storefront (ADR-0026, PAP-049).
public struct PaywallFlowView: View {
  @State private var model: PaywallModel
  @State private var saving: SavingLine?

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
      PaywallHeader(trigger: model.trigger, benefits: model.benefits, saving: saving)
    }
    // The toolbar's Close is the one way out, with one identifier; StoreKit's own would be a second.
    .storeButton(.hidden, for: .cancellation)
    .storeButton(.visible, for: .restorePurchases, .redeemCode, .policies)
    .subscriptionStorePolicyDestination(url: model.termsOfUse, for: .termsOfService)
    .subscriptionStorePolicyDestination(url: model.privacyPolicy, for: .privacyPolicy)
    .accessibilityIdentifier("paywall.offer")
    .task { saving = await SavingLine.load(model.productIDs) }
  }
}

/// The annual plan's saving, ready to show: the percentage in the person's locale ("41%", "41 %") and the
/// amount in the storefront's currency.
struct SavingLine: Equatable {
  let percent: String
  let amount: String

  /// The saving between the weekly and the annual plan among the products; `nil` when either does not
  /// load or the annual plan saves nothing, and then the offer shows no saving at all.
  static func load(_ productIDs: [String]) async -> SavingLine? {
    guard let products = try? await Product.products(for: productIDs) else { return nil }
    func plan(_ unit: Product.SubscriptionPeriod.Unit) -> Product? {
      products.first { product in
        guard let period = product.subscription?.subscriptionPeriod else { return false }
        return period.unit == unit && period.value == 1
      }
    }
    guard let weekly = plan(.week), let yearly = plan(.year),
      let saving = YearlySaving(weeklyPrice: weekly.price, yearlyPrice: yearly.price)
    else { return nil }
    let percent = (Double(saving.percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    return SavingLine(percent: percent, amount: saving.amount.formatted(yearly.priceFormatStyle))
  }
}

/// What the offer says above the plans: why it is here, what Pro adds, and what never needs it.
struct PaywallHeader: View {
  let trigger: PaywallTrigger
  let benefits: [PaywallBenefit]
  var saving: SavingLine? = nil

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
      if let saving {
        SavingNote(saving: saving)
      }
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

/// "Best Value" over the annual plan's saving against paying weekly, just above the plans.
struct SavingNote: View {
  let saving: SavingLine

  var body: some View {
    VStack(spacing: Spacing.s100) {
      Text("Best Value", bundle: .module)
        .font(.caption.bold())
        .foregroundStyle(Color.ds.brandTint)
      Text("Pro Yearly: save \(saving.percent) compared to paying weekly.", bundle: .module)
        .font(.subheadline.bold())
      Text("That’s \(saving.amount) saved per year.", bundle: .module)
        .font(.subheadline)
        .foregroundStyle(Color.ds.labelSecondary)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("paywall.saving")
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
