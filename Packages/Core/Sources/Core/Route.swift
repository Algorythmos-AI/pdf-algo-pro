import Foundation

/// A place in the app that navigation can show (ADR-0004).
///
/// Routes are `Codable` so scene state can be restored. The router only navigates; actions always
/// need explicit user intent, so no route performs an action by itself.
public enum Route: Hashable, Codable, Sendable {
  /// A library section.
  case library(LibrarySection)
  /// A document, optionally at a zero-based page index.
  case document(DocumentID, pageIndex: Int?)
  /// The scanner, which the user still starts explicitly.
  case scan
  /// Settings.
  case settings
}

/// Parses `pdfalgopro://` URLs and Spotlight identifiers into routes.
///
/// URLs can come from untrusted sources (a shared link), so parsing is strict and only ever yields
/// a navigation target.
public enum DeepLink {
  /// The app's URL scheme (ADR-0015).
  public static let scheme = "pdfalgopro"

  /// The Staging app's URL scheme, so it installs beside the App Store app without taking its links.
  public static let stagingScheme = "pdfalgopro-staging"

  /// The route for a URL, or `nil` when the URL is not one of ours or is malformed.
  ///
  /// Accepted forms: `pdfalgopro://document/<uuid>?page=<1-based>`, `pdfalgopro://library/<section>`,
  /// `pdfalgopro://scan` and `pdfalgopro://settings`, and the same with the Staging scheme.
  public static func route(for url: URL) -> Route? {
    guard let urlScheme = url.scheme?.lowercased(), urlScheme == scheme || urlScheme == stagingScheme,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let host = components.host?.lowercased()
    else { return nil }
    let path = components.path.split(separator: "/").map(String.init)
    switch host {
    case "document":
      guard path.count == 1, let id = DocumentID(string: path[0]) else { return nil }
      let page = components.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init)
      return .document(id, pageIndex: page.flatMap { $0 >= 1 ? $0 - 1 : nil })
    case "library":
      switch path.first?.lowercased() {
      case nil, "all": return .library(.all)
      case "recents": return .library(.recents)
      case "favorites": return .library(.favorites)
      case "deleted": return .library(.recentlyDeleted)
      default: return nil
      }
    case "scan": return path.isEmpty ? .scan : nil
    case "settings": return path.isEmpty ? .settings : nil
    default: return nil
    }
  }

  /// The URL that opens a document at a page (one-based in the URL, as people count pages).
  public static func url(for id: DocumentID, pageIndex: Int? = nil) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "document"
    components.path = "/\(id)"
    if let pageIndex {
      components.queryItems = [URLQueryItem(name: "page", value: String(pageIndex + 1))]
    }
    return components.url ?? URL(fileURLWithPath: "/")
  }
}
