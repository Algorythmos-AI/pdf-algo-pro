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

  /// How a restore ended, from whether the App Store answered.
  static func after(answered: Bool) -> RestoreOutcome {
    answered ? .restored : .failed
  }
}
