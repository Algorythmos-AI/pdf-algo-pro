import Foundation

/// The app's public pages on algorythmos.com: privacy policy, terms of use and support.
///
/// About also links to the product page (to share the app), to the company's website, and to the
/// App Store's page for rating the app.
/// The App Store record links to the same pages, and App Review expects the privacy policy to be
/// reachable from inside the app. The paths are a contract with the website: shipped builds keep
/// these links for as long as they are installed, so a path is never renamed, only redirected.
/// `scripts/ci/check_public_links.py` reads the paths from this file and checks that each page, the
/// product page and the website itself answer before a release. The app only hands the address to the system, which opens it in the
/// browser; the app itself makes no request.
public enum AppLinks: String, CaseIterable, Sendable {
  case privacyPolicy = "/pdf-algo-pro/privacy"
  case termsOfUse = "/pdf-algo-pro/terms"
  case support = "/pdf-algo-pro/support"

  /// The website's address.
  public static let site = "https://algorythmos.com"

  /// The product page's path; every page above is under it.
  static let productPath = "/pdf-algo-pro"

  /// The app's identifier on the App Store, from its record in App Store Connect.
  public static let appStoreID = "6817672472"

  /// The App Store's page for rating and reviewing the app, for "Rate PDF Algo Pro" in About.
  ///
  /// It is the App Store's, not the website's, so the release check of public pages leaves it out.
  /// The system opens it in the App Store app only when the row is tapped.
  public static var writeReview: URL {
    // A literal in this file, so the address always parses.
    URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") ?? URL(fileURLWithPath: "/")
  }

  /// The company's website, for "Built by Algorythmos" in About.
  public static var company: URL {
    // A literal in this file, so the address always parses.
    URL(string: site) ?? URL(fileURLWithPath: "/")
  }

  /// The app's own page on the website, for sharing the app: in French for French readers.
  ///
  /// - Parameter languageCode: The language the app is shown in, such as `fr` or `en`.
  /// - Returns: The address to share.
  public static func product(languageCode: String?) -> URL {
    let prefix = languageCode == "fr" ? "/fr-fr" : ""
    return URL(string: site + prefix + productPath) ?? URL(fileURLWithPath: "/")
  }

  /// The page's address for a language.
  ///
  /// French readers get the French page. Every other language gets the short address, which the
  /// website sends on to the English page.
  ///
  /// - Parameter languageCode: The language the app is shown in, such as `fr` or `en`.
  /// - Returns: The address to open in the browser.
  public func url(languageCode: String?) -> URL {
    let prefix = languageCode == "fr" ? "/fr-fr" : ""
    // The parts are literals in this file, so the address always parses.
    return URL(string: Self.site + prefix + rawValue) ?? URL(fileURLWithPath: "/")
  }
}
