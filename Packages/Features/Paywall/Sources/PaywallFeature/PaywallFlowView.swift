import Commerce
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
  @State private var redeemsCode = false
  private let store: any StoreAccessing

  /// Creates the presentation for a model; `store` is asked when the person restores purchases.
  public init(model: PaywallModel, store: any StoreAccessing) {
    _model = State(initialValue: model)
    self.store = store
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
      VStack(spacing: 0) {
        PaywallHeader(trigger: model.trigger, benefits: model.benefits, saving: saving)
        StoreLinks(
          onRestore: { Task { await model.restore(using: store) } }, onRedeem: { redeemsCode = true })
      }
    }
    // Both plans and the button stay at the foot of the screen while the rest scrolls, and the
    // button says in full what the chosen plan costs and when: StoreKit's words, for the person's
    // storefront and their right to the trial.
    .subscriptionStoreControlStyle(.compactPicker, placement: .bottomBar)
    .subscriptionStoreButtonLabel(.multiline)
    .containerBackground(for: .subscriptionStoreFullHeight) {
      Color.ds.backgroundPrimary.overlay(alignment: .top) { BrandGlow().frame(height: 420) }.ignoresSafeArea()
    }
    .tint(Color.ds.brandFill)
    // The toolbar's Close is the one way out, with one identifier; StoreKit's own would be a second.
    .storeButton(.hidden, for: .cancellation)
    // Restore and Redeem are the app's own quiet links under the header: StoreKit's are two more
    // full-width buttons, which leave the plans no room.
    .storeButton(.hidden, for: .restorePurchases, .redeemCode)
    .storeButton(.visible, for: .policies)
    .subscriptionStorePolicyDestination(url: model.termsOfUse, for: .termsOfService)
    .subscriptionStorePolicyDestination(url: model.privacyPolicy, for: .privacyPolicy)
    .accessibilityIdentifier("paywall.offer")
    .offerCodeRedemption(isPresented: $redeemsCode)
    .alert(Text("Restore purchases", bundle: .module), isPresented: $model.restoreFailed) {
      Button {
      } label: {
        Text("OK", bundle: .module)
      }
    } message: {
      Text(
        "Nothing could be restored. Check that you are signed in to the App Store with the account that bought Pro.",
        bundle: .module)
    }
    .task { saving = await SavingLine.load(model.productIDs) }
  }
}

/// The annual plan's saving, ready to show: the percentage in the person's locale ("41%", "41 %") and the
/// amount in the storefront's currency.
struct SavingLine: Equatable {
  let percent: String
  let amount: String

  /// How long a plan runs before it renews, as far as the saving is concerned.
  enum Term: Equatable {
    case week, year

    /// The term of a subscription period; `nil` for any other length.
    ///
    /// The App Store gives a one-week plan as seven days, and may give a year as twelve months.
    init?(unit: Product.SubscriptionPeriod.Unit, value: Int) {
      switch (unit, value) {
      case (.week, 1), (.day, 7): self = .week
      case (.year, 1), (.month, 12): self = .year
      default: return nil
      }
    }
  }

  /// The saving between the weekly and the annual plan among the products; `nil` when either does not
  /// load or the annual plan saves nothing, and then the offer shows no saving at all.
  static func load(_ productIDs: [String]) async -> SavingLine? {
    guard let products = try? await Product.products(for: productIDs) else { return nil }
    func plan(_ term: Term) -> Product? {
      products.first { product in
        guard let period = product.subscription?.subscriptionPeriod else { return false }
        return Term(unit: period.unit, value: period.value) == term
      }
    }
    guard let weekly = plan(.week), let yearly = plan(.year),
      let saving = YearlySaving(weeklyPrice: weekly.price, yearlyPrice: yearly.price)
    else { return nil }
    let percent = (Double(saving.percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    return SavingLine(percent: percent, amount: saving.amount.formatted(yearly.priceFormatStyle))
  }
}

/// What the offer says above the plans: why it is here, a picture of the app at work, what Pro adds,
/// and what never needs it.
struct PaywallHeader: View {
  let trigger: PaywallTrigger
  let benefits: [PaywallBenefit]
  var saving: SavingLine? = nil
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(spacing: Spacing.s300) {
      VStack(spacing: Spacing.s100) {
        trigger.headline
          .font(.largeTitle.weight(.heavy))
          .foregroundStyle(Color.ds.brandTint)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("paywall.headline.\(trigger.rawValue)")
        trigger.explanation
          .font(.body)
          .foregroundStyle(Color.ds.labelSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      // At the largest text sizes the words need the room; the picture says nothing they do not.
      if !typeSize.isAccessibilitySize {
        DeviceMockup(width: 216) { ScanMockupScreen() }.fadingBottom(height: 236)
      }
      BenefitList(benefits: benefits).cardStyle()
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
        .foregroundStyle(Color.ds.brandOnFill)
        .padding(.horizontal, Spacing.s150)
        .padding(.vertical, Spacing.s050)
        .background(Color.ds.brandFill, in: Capsule())
      Text("Pro Yearly: save \(saving.percent) compared to paying weekly.", bundle: .module)
        .font(.subheadline.bold())
      Text("That’s \(saving.amount) saved per year.", bundle: .module)
        .font(.subheadline)
        .foregroundStyle(Color.ds.labelSecondary)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(Spacing.s200)
    .background(
      Color.ds.brandTint.opacity(Opacities.brandGlow), in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
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

/// Restore Purchases and Redeem Code, as two quiet links under the header.
struct StoreLinks: View {
  let onRestore: () -> Void
  let onRedeem: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.s300) { links }
      VStack(spacing: 0) { links }
    }
    // Plain, with their own colour: inside the store view a button is otherwise drawn filled.
    .buttonStyle(.plain)
    .font(.footnote.weight(.semibold))
    .foregroundStyle(Color.ds.brandTint)
    .padding(.horizontal, Spacing.s300)
    .padding(.bottom, Spacing.s200)
  }

  @ViewBuilder private var links: some View {
    Button(action: onRestore) {
      Text("Restore purchases", bundle: .module).minimumTarget()
    }
    .accessibilityIdentifier("paywall.restore")
    Button(action: onRedeem) {
      Text("Redeem a code", bundle: .module).minimumTarget()
    }
    .accessibilityIdentifier("paywall.redeem")
  }
}
