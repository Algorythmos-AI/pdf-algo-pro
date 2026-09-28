import SwiftUI
import UIKit

/// An sRGB colour value from the token file.
public struct RGB: Hashable, Sendable {
  /// Red, 0 to 1.
  public let red: Double
  /// Green, 0 to 1.
  public let green: Double
  /// Blue, 0 to 1.
  public let blue: Double

  /// Creates a colour value.
  public init(_ red: Double, _ green: Double, _ blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Relative luminance, as WCAG 2.2 defines it.
  public var luminance: Double {
    func channel(_ value: Double) -> Double {
      value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
  }

  /// The WCAG contrast ratio between two colours, from 1 to 21.
  public static func contrast(_ first: RGB, _ second: RGB) -> Double {
    let (lighter, darker) = first.luminance >= second.luminance ? (first, second) : (second, first)
    return (lighter.luminance + 0.05) / (darker.luminance + 0.05)
  }
}

/// Builds colours that resolve per appearance: light, dark, and each with Increase Contrast.
public enum DynamicColor {
  /// The appearance a colour resolves in.
  public enum Appearance: CaseIterable, Sendable {
    /// Light mode.
    case light
    /// Dark mode.
    case dark
    /// Light mode with Increase Contrast.
    case lightHighContrast
    /// Dark mode with Increase Contrast.
    case darkHighContrast

    /// The trait collection for this appearance.
    public var traits: UITraitCollection {
      UITraitCollection { traits in
        traits.userInterfaceStyle = self == .dark || self == .darkHighContrast ? .dark : .light
        traits.accessibilityContrast = self == .lightHighContrast || self == .darkHighContrast ? .high : .normal
      }
    }
  }

  /// Picks the value for an appearance.
  public static func value(
    for traits: UITraitCollection, light: RGB, dark: RGB, lightHighContrast: RGB, darkHighContrast: RGB
  ) -> RGB {
    let isDark = traits.userInterfaceStyle == .dark
    let isHigh = traits.accessibilityContrast == .high
    switch (isDark, isHigh) {
    case (false, false): return light
    case (true, false): return dark
    case (false, true): return lightHighContrast
    case (true, true): return darkHighContrast
    }
  }

  /// A colour with a value for each appearance.
  public static func make(light: RGB, dark: RGB, lightHighContrast: RGB, darkHighContrast: RGB) -> Color {
    Color(
      uiColor: uiColor(
        light: light, dark: dark, lightHighContrast: lightHighContrast, darkHighContrast: darkHighContrast))
  }

  /// The UIKit form of `make`, used by tests to resolve each appearance.
  public static func uiColor(light: RGB, dark: RGB, lightHighContrast: RGB, darkHighContrast: RGB) -> UIColor {
    UIColor { traits in
      let rgb = value(
        for: traits, light: light, dark: dark, lightHighContrast: lightHighContrast, darkHighContrast: darkHighContrast)
      return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
  }

  /// A system colour by its token name.
  public static func system(_ name: SystemColorName) -> Color {
    Color(uiColor: name.uiColor)
  }
}

/// The system colours semantic tokens resolve to; the HIG asks apps to keep their meaning.
public enum SystemColorName: String, CaseIterable, Sendable {
  /// `systemBackground`.
  case systemBackground
  /// `secondarySystemBackground`.
  case secondarySystemBackground
  /// `systemGroupedBackground`.
  case systemGroupedBackground
  /// `secondarySystemGroupedBackground`.
  case secondarySystemGroupedBackground
  /// `label`.
  case label
  /// `secondaryLabel`.
  case secondaryLabel
  /// `tertiaryLabel`.
  case tertiaryLabel
  /// `separator`.
  case separator
  /// `systemFill`.
  case systemFill
  /// `secondarySystemFill`.
  case secondarySystemFill
  /// `tertiarySystemFill`.
  case tertiarySystemFill
  /// `systemGreen`.
  case systemGreen
  /// `systemOrange`.
  case systemOrange
  /// `systemRed`.
  case systemRed
  /// `link`.
  case link

  /// The UIKit system colour.
  public var uiColor: UIColor {
    switch self {
    case .systemBackground: .systemBackground
    case .secondarySystemBackground: .secondarySystemBackground
    case .systemGroupedBackground: .systemGroupedBackground
    case .secondarySystemGroupedBackground: .secondarySystemGroupedBackground
    case .label: .label
    case .secondaryLabel: .secondaryLabel
    case .tertiaryLabel: .tertiaryLabel
    case .separator: .separator
    case .systemFill: .systemFill
    case .secondarySystemFill: .secondarySystemFill
    case .tertiarySystemFill: .tertiarySystemFill
    case .systemGreen: .systemGreen
    case .systemOrange: .systemOrange
    case .systemRed: .systemRed
    case .link: .link
    }
  }
}

extension Color {
  /// The design system's colour tokens: `Color.ds.brandTint`.
  public static let ds = DesignColors()
}
