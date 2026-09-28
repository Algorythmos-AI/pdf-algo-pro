import Core
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Where documents are mirrored for system search.
public protocol SpotlightIndexing: Sendable {
  /// Adds or replaces a document.
  func index(_ document: Document, text: String) async
  /// Removes a document.
  func remove(_ id: DocumentID) async
}

/// Indexes titles, tags and text in Core Spotlight, on device, so documents appear in system search
/// (FR-LIB-005). Deleting a document removes it from Spotlight too (FR-LIB-006).
public actor SpotlightIndexer: SpotlightIndexing {
  /// The domain identifier for every document item.
  public static let domain = "com.algorythmos.pdfalgopro.documents"
  /// The most text sent to Spotlight per document.
  public static let textLimit = 20_000

  private let index: CSSearchableIndex

  /// Creates an indexer over a named index, so tests do not touch the default one.
  public init(indexName: String = "documents") {
    index = CSSearchableIndex(name: indexName)
  }

  /// Adds or replaces a document; failures are ignored because Spotlight is a mirror, not a store.
  public func index(_ document: Document, text: String) async {
    guard !document.isDeleted else {
      await remove(document.id)
      return
    }
    try? await index.indexSearchableItems([Self.item(for: document, text: text)])
  }

  /// Removes a document; failures are ignored.
  public func remove(_ id: DocumentID) async {
    try? await index.deleteSearchableItems(withIdentifiers: [id.description])
  }

  /// The Spotlight item for a document.
  ///
  /// The identifier is the document ID, which the app turns back into a route when the user opens the result.
  static func item(for document: Document, text: String) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .pdf)
    attributes.title = document.title
    attributes.displayName = document.title
    attributes.keywords = document.tags
    attributes.textContent = String(text.prefix(textLimit))
    attributes.contentModificationDate = document.modifiedAt
    attributes.pageCount = NSNumber(value: document.pageCount)
    let item = CSSearchableItem(
      uniqueIdentifier: document.id.description, domainIdentifier: domain, attributeSet: attributes)
    item.expirationDate = .distantFuture
    return item
  }
}
