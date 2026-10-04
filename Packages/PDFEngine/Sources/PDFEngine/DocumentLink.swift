import Foundation

/// A link to outside the document, tapped on a page (threat T-02).
///
/// Documents are untrusted, so a link never opens by itself: the reader shows its full address first,
/// and only web, email and phone links can be opened at all. Links within the document are not
/// `DocumentLink`s; PDFKit follows them as usual.
public struct DocumentLink: Equatable, Sendable, Identifiable {
  /// The address the link points to.
  public let url: URL

  /// Creates a link.
  public init(url: URL) {
    self.url = url
  }

  /// A stable identity for presentation.
  public var id: URL { url }

  /// Whether the app will open it: `http`, `https`, `mailto` and `tel` only.
  ///
  /// Files, other apps' schemes, `javascript:` and `data:` links are refused, so a document can't reach
  /// into the device or launch an app.
  public var isOpenable: Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    switch scheme {
    case "http", "https": return url.host?.isEmpty == false
    case "mailto", "tel": return true
    default: return false
    }
  }

  /// The address as shown to the person: in full, so they can see where it goes before opening it.
  public var address: String { url.absoluteString }
}

extension PDFDocumentController {
  /// Holds a tapped link until the person opens it or dismisses it.
  func linkTapped(_ url: URL) {
    // A tap on linked text while editing picks the text; it does not follow the link.
    guard !isEditingText else { return }
    tappedLink = DocumentLink(url: url)
  }

  /// Dismisses the tapped link.
  public func dismissLink() {
    tappedLink = nil
  }
}
