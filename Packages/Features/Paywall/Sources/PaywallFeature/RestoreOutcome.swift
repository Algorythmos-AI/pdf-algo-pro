import Commerce
import SwiftUI

/// How Restore Purchases ended, on the offer and in Settings.
public enum RestoreOutcome: Sendable, Equatable, Identifiable {
  /// The App Store answered and Pro is on.
  case restored
  /// The App Store answered, and this Apple Account has no Pro purchase to bring back.
  case nothingFound
  /// The App Store answered, and the subscription is the person's but paused: it could not take the
  /// last payment and is retrying (#248).
  case paused
  /// The person cancelled the App Store's sign-in.
  case cancelled
  /// The App Store could not be asked, for example without a connection.
  case failed

  /// The outcome's name.
  public var id: Self { self }

  /// How a restore ended, from the App Store's answer and whether Pro is on, or paused, afterwards (#247).
  ///
  /// An answer is not a restore: the App Store also answers for an account with nothing to bring back,
  /// and for one whose Pro is paused in billing retry, which grants no Pro but is not nothing (#248).
  static func after(_ answer: RestoreAnswer, hasPro: Bool, paused: Bool) -> RestoreOutcome {
    switch answer {
    case .synced: hasPro ? .restored : paused ? .paused : .nothingFound
    case .cancelled: .cancelled
    case .failed: .failed
    }
  }

  /// What the person is told; `nil` after a cancellation, which they chose.
  var message: Text? {
    switch self {
    case .restored: Text("Your purchases are restored, and Pro is on.", bundle: .module)
    case .nothingFound:
      Text(
        "This Apple Account has no Pro purchase to restore. If you bought Pro with another account, sign in to the App Store with it and try again.",
        bundle: .module)
    case .paused:
      Text(
        "Pro is paused because the App Store couldn’t take your last payment. Update your payment method in Manage subscription.",
        bundle: .module)
    case .cancelled: nil
    case .failed: Text("The App Store couldn’t be reached. Check your connection and try again.", bundle: .module)
    }
  }
}

extension View {
  /// The alert that says how Restore Purchases ended.
  ///
  /// Nothing is said after a cancellation, nor for an outcome `isTold` leaves to what follows it.
  func restoreAlert(
    _ outcome: Binding<RestoreOutcome?>, isTold: @escaping (RestoreOutcome) -> Bool = { _ in true }
  ) -> some View {
    let isPresented = Binding<Bool>(
      get: {
        guard let shown = outcome.wrappedValue, shown.message != nil else { return false }
        return isTold(shown)
      },
      set: { if !$0 { outcome.wrappedValue = nil } })
    return alert(Text("Restore purchases", bundle: .module), isPresented: isPresented) {
      Button {
      } label: {
        Text("OK", bundle: .module)
      }
    } message: {
      outcome.wrappedValue?.message
    }
  }
}
