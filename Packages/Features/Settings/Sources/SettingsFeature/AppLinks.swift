import Foundation

/// The app's public pages on algorythmos.com: privacy policy, terms of use and support.
///
/// The App Store record links to the same pages, and App Review expects the privacy policy to be
/// reachable from inside the app. The paths are a contract with the website: shipped builds keep
/// these links for as long as they are installed, so a path is never renamed, only redirected.
/// `scripts/ci/check_public_links.py` reads the paths from this file and checks that each page
/// answers before a release. The app only hands the address to the system, which opens it in the
/// browser; the app itself makes no request.
public enum AppLinks: String, CaseIterable, Sendable {
  case privacyPolicy = "/pdf-algo-pro/privacy"
  case termsOfUse = "/pdf-algo-pro/terms"
  case support = "/pdf-algo-pro/support"

  /// The website's address.
  public static let site = "https://algorythmos.com"

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
