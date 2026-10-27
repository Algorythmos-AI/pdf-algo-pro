import Commerce
import SwiftUI

/// How Restore Purchases ended, on the offer and in Settings.
public enum RestoreOutcome: Sendable, Equatable, Identifiable {
  /// The App Store answered and Pro is on.
  case restored
  /// The App Store answered, and this Apple Account has no Pro purchase to bring back.
  case nothingFound
  /// The person cancelled the App Store's sign-in.
  case cancelled
  /// The App Store could not be asked, for example without a connection.
  case failed

  /// The outcome's name.
  public var id: Self { self }

  /// How a restore ended, from the App Store's answer and whether Pro is on afterwards (#247).
  ///
  /// An answer is not a restore: the App Store also answers for an account with nothing to bring back.
  static func after(_ answer: RestoreAnswer, hasPro: Bool) -> RestoreOutcome {
    switch answer {
    case .synced: hasPro ? .restored : .nothingFound
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
