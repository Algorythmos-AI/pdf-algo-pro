import Commerce
import DesignSystem
import StoreKit
import SwiftUI

/// The subscription offer, and in the same presentation the confirmation after a purchase.
///
/// The offer is the app's own screen over StoreKit 2 (ADR-0027). Every figure on it, the plans'
/// names, prices and periods and the trial, is the App Store's for the person's storefront and
/// account; the purchase is confirmed in the App Store's own sheet; and who has Pro is read from
/// the App Store's transactions, never from this screen.
public struct PaywallFlowView: View {
  @State private var model: PaywallModel
  @State private var redeemsCode = false
  @State private var managesSubscription = false
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
    .onDisappear { Task { await model.dismissed() } }
  }

  private var offer: some View {
    PaywallOfferView(
      model: model, onRestore: { Task { await model.restore(using: store) } }, onRedeem: { redeemsCode = true },
      onManage: { managesSubscription = true }
    )
    // EXPERIMENT (not for merge): no glow, to learn whether the audit's contrast findings follow it.
    .background(Color.ds.backgroundPrimary)
    .offerCodeRedemption(isPresented: $redeemsCode)
    .manageSubscriptionsSheet(isPresented: $managesSubscription)
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
    .alert(item: $model.notice) { notice in
      switch notice {
      case .pending:
        Alert(
          title: Text("Waiting for approval", bundle: .module),
          message: Text(
            "The purchase will complete when it is approved. Nothing has been charged.", bundle: .module),
          dismissButton: .default(Text("OK", bundle: .module)))
      case .failed:
        Alert(
          title: Text("The purchase didn’t go through", bundle: .module),
          message: Text("Nothing has been charged. You can try again.", bundle: .module),
          dismissButton: .default(Text("OK", bundle: .module)))
      }
    }
  }
}

/// What the offer says above the plans: why it is here, a picture of the app at work, what Pro adds,
/// and what never needs it.
struct PaywallHeader: View {
  let trigger: PaywallTrigger
  let benefits: [PaywallBenefit]
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
        // The primary label, not the secondary: over the brand glow the secondary grey falls below
        // the contrast minimum, which the accessibility audit found on the offer.
        trigger.explanation
          .font(.body)
          .foregroundStyle(Color.ds.labelPrimary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      // At the largest text sizes the words need the room; the picture says nothing they do not.
      if !typeSize.isAccessibilitySize {
        DeviceMockup(width: 216) { ScanMockupScreen() }.fadingBottom(height: 236)
      }
      BenefitList(benefits: benefits).cardStyle()
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
