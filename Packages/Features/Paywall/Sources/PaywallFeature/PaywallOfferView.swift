import Commerce
import DesignSystem
import SwiftUI

/// The offer: what Pro gives, the plans, what is paid and when, and one button.
///
/// The plans and the button stay at the foot of the screen while the rest scrolls, so a price is
/// on screen from the first frame. At accessibility text sizes everything scrolls together, since
/// a fixed foot would leave the words no room.
struct PaywallOfferView: View {
  @Bindable var model: PaywallModel
  let onRestore: () -> Void
  let onRedeem: () -> Void
  let onManage: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if typeSize.isAccessibilitySize {
      ScrollView {
        VStack(spacing: 0) {
          PaywallHeader(trigger: model.trigger, benefits: model.benefits)
          purchasePanel
        }
      }
    } else {
      ScrollView {
        PaywallHeader(trigger: model.trigger, benefits: model.benefits)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        purchasePanel.background(.bar)
      }
    }
  }

  /// The plans, what is paid, the button and the links.
  private var purchasePanel: some View {
    VStack(spacing: Spacing.s150) {
      if model.alreadyHasPro {
        AlreadyProNote()
      }
      switch model.plans {
      case .loading:
        ProgressView {
          Text("Loading plans", bundle: .module)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .accessibilityIdentifier("paywall.loading")
      case .unavailable:
        PlansUnavailable { Task { await model.retry() } }
      case .loaded(let offers):
        PlanPicker(
          offers: offers, selectedID: model.selectedPlanID, saving: model.yearlySaving,
          select: { id in Task { await model.select(id) } })
        if !model.alreadyHasPro, let plan = model.selectedPlan {
          PurchaseTerms(plan: plan)
        }
      }
      action
      PaywallLinks(
        termsOfUse: model.termsOfUse, privacyPolicy: model.privacyPolicy, onRestore: onRestore, onRedeem: onRedeem)
    }
    .padding(.horizontal, Spacing.s200)
    .padding(.top, Spacing.s150)
    .padding(.bottom, Spacing.s100)
    .readableWidth()
  }

  /// The one prominent button: buy the selected plan, or, for someone who has Pro, go on.
  @ViewBuilder private var action: some View {
    if model.alreadyHasPro {
      VStack(spacing: Spacing.s050) {
        Button {
          model.close()
        } label: {
          Text("Continue", bundle: .module)
        }
        .buttonStyle(.primary)
        .accessibilityIdentifier("paywall.continue")
        Button(action: onManage) {
          Text("Manage subscription", bundle: .module).font(.subheadline.weight(.semibold)).minimumTarget()
        }
        .tint(Color.ds.brandTint)
        .accessibilityIdentifier("paywall.manage")
      }
    } else if let plan = model.selectedPlan {
      Button {
        Task { await model.purchase() }
      } label: {
        // The words keep their place while the App Store's sheet is on its way.
        (plan.trial == nil ? Text("Subscribe", bundle: .module) : Text("Start free trial", bundle: .module))
          .opacity(model.isPurchasing ? 0 : 1)
          .overlay { if model.isPurchasing { ProgressView().tint(Color.ds.brandOnFill) } }
      }
      .buttonStyle(.primary)
      .disabled(model.isPurchasing)
      .accessibilityIdentifier("paywall.purchase")
    }
  }
}

/// The two plans, side by side, or one above the other at large text sizes.
struct PlanPicker: View {
  let offers: [PlanOffer]
  let selectedID: String?
  let saving: YearlySaving?
  let select: (String) -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.s150)) : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.s150))
    layout {
      ForEach(offers) { offer in
        PlanCard(
          offer: offer, isSelected: offer.id == selectedID, saving: offer.term == .year ? saving : nil
        ) { select(offer.id) }
      }
    }
    // Room for the badge that sits on the recommended plan's upper edge.
    .padding(.top, Spacing.s100)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("Choose a plan", bundle: .module))
  }
}

/// One plan: its name, what a period costs, and what recommends it.
///
/// Every figure is the App Store's.
struct PlanCard: View {
  let offer: PlanOffer
  let isSelected: Bool
  let saving: YearlySaving?
  let select: () -> Void

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    Button(action: select) {
      VStack(spacing: Spacing.s050) {
        HStack(spacing: Spacing.s050) {
          Text(verbatim: offer.name).font(.subheadline.weight(.semibold))
          Spacer(minLength: 0)
          // Selection is a mark as well as a colour.
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.ds.brandFill : Color.ds.labelSecondary)
            .accessibilityHidden(true)
        }
        Self.price(of: offer)
          .font(.title3.weight(.bold))
          .frame(maxWidth: .infinity, alignment: .leading)
        note
          .font(.footnote)
          .foregroundStyle(Color.ds.labelSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .multilineTextAlignment(.leading)
      .foregroundStyle(Color.ds.labelPrimary)
      .padding(Spacing.s150)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(Color.ds.backgroundGroupedElevated, in: shape)
      .overlay(shape.strokeBorder(isSelected ? Color.ds.brandFill : Color.ds.separator, lineWidth: isSelected ? 2 : 1))
      .overlay(alignment: .top) {
        if saving != nil {
          Text("Best Value", bundle: .module)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.ds.brandOnFill)
            .padding(.horizontal, Spacing.s100)
            .padding(.vertical, 3)
            .background(Color.ds.brandFill, in: Capsule())
            .offset(y: -10)
        }
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("paywall.plan.\(offer.term == .year ? "yearly" : "weekly")")
  }

  /// The line under the price: the trial this account can have, or the annual plan's saving.
  @ViewBuilder private var note: some View {
    if let trial = offer.trial {
      Text("\(PurchaseTerms.length(of: trial)) free", bundle: .module)
    } else if let saving {
      Text("Save \(Self.percent(saving))", bundle: .module)
    } else {
      // Keeps the two cards the same height.
      Text(verbatim: " ").accessibilityHidden(true)
    }
  }

  /// "$X per year" or "$X per week", with the App Store's price.
  static func price(of offer: PlanOffer) -> Text {
    switch offer.term {
    case .year: Text("\(offer.displayPrice) per year", bundle: .module)
    case .week: Text("\(offer.displayPrice) per week", bundle: .module)
    }
  }

  /// The saving as a percentage in the person's locale ("41%", "41 %").
  static func percent(_ saving: YearlySaving) -> String {
    (Double(saving.percent) / 100).formatted(.percent.precision(.fractionLength(0)))
  }
}

/// What is paid and when, for the selected plan, in full: a trial's length, what is due today, the
/// price that follows and how often, that it renews, and how to stop it.
struct PurchaseTerms: View {
  let plan: PlanOffer

  var body: some View {
    VStack(spacing: Spacing.s050) {
      summary
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.ds.labelPrimary)
      Text(
        "Renews automatically until cancelled. Cancel at any time in Settings, under your Apple Account, at least a day before it renews.",
        bundle: .module
      )
      .font(.caption)
      .foregroundStyle(Color.ds.labelSecondary)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(plan.trial == nil ? "paywall.terms" : "paywall.terms.trial")
  }

  @ViewBuilder private var summary: some View {
    if let trial = plan.trial {
      let free = Self.length(of: trial)
      let nothing = plan.formatted(0)
      switch plan.term {
      case .year:
        Text("\(free) free. \(nothing) due today, then \(plan.displayPrice) per year.", bundle: .module)
      case .week:
        Text("\(free) free. \(nothing) due today, then \(plan.displayPrice) per week.", bundle: .module)
      }
    } else {
      PlanCard.price(of: plan)
    }
  }

  /// A trial's length in words, in the person's language: "3 days", "1 week".
  static func length(of trial: TrialOffer) -> String {
    var components = DateComponents()
    switch trial.unit {
    case .day: components.day = trial.length
    case .week: components.weekOfMonth = trial.length
    case .month: components.month = trial.length
    case .year: components.year = trial.length
    }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 1
    return formatter.string(from: components) ?? ""
  }
}

/// Said to someone who opens the offer with Pro already: the truth, and nothing to buy.
struct AlreadyProNote: View {
  var body: some View {
    Label {
      Text("This Apple Account already has Pro.", bundle: .module)
    } icon: {
      Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.ds.brandTint)
    }
    .font(.subheadline.weight(.semibold))
    .frame(maxWidth: .infinity)
    .padding(Spacing.s150)
    .background(
      Color.ds.brandTint.opacity(Opacities.brandGlow), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .accessibilityIdentifier("paywall.alreadyPro")
  }
}

/// Shown in place of the plans when the App Store has not given them: why, and a way to ask again.
struct PlansUnavailable: View {
  let retry: () -> Void

  var body: some View {
    VStack(spacing: Spacing.s100) {
      Text("The plans can’t be loaded", bundle: .module).font(.headline)
      Text("Check your connection and try again.", bundle: .module)
        .font(.subheadline)
        .foregroundStyle(Color.ds.labelSecondary)
      Button(action: retry) {
        Text("Try again", bundle: .module).font(.subheadline.weight(.semibold)).minimumTarget()
      }
      .tint(Color.ds.brandTint)
      .accessibilityIdentifier("paywall.retry")
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier("paywall.unavailable")
  }
}

/// Restore Purchases, Redeem Code, the terms and the privacy policy, as quiet links.
struct PaywallLinks: View {
  let termsOfUse: URL
  let privacyPolicy: URL
  let onRestore: () -> Void
  let onRedeem: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.s200) { links }
      VStack(spacing: 0) {
        HStack(spacing: Spacing.s200) { storeLinks }
        HStack(spacing: Spacing.s200) { policyLinks }
      }
      VStack(spacing: 0) { links }
    }
    .buttonStyle(.plain)
    .font(.caption.weight(.semibold))
    .foregroundStyle(Color.ds.brandTint)
  }

  @ViewBuilder private var links: some View {
    storeLinks
    policyLinks
  }

  @ViewBuilder private var storeLinks: some View {
    Button(action: onRestore) {
      Text("Restore purchases", bundle: .module).minimumTarget()
    }
    .accessibilityIdentifier("paywall.restore")
    Button(action: onRedeem) {
      Text("Redeem a code", bundle: .module).minimumTarget()
    }
    .accessibilityIdentifier("paywall.redeem")
  }

  @ViewBuilder private var policyLinks: some View {
    Link(destination: termsOfUse) {
      Text("Terms", bundle: .module).minimumTarget()
    }
    .accessibilityIdentifier("paywall.termsOfUse")
    Link(destination: privacyPolicy) {
      Text("Privacy", bundle: .module).minimumTarget()
    }
    .accessibilityIdentifier("paywall.privacy")
  }
}
