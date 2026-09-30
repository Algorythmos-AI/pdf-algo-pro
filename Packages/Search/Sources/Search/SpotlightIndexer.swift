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
///
/// The index has a data protection class, so its contents are unreadable while the device is locked
/// after a restart (threat T-11). Document text is left out when the person turns it off in Settings;
/// titles and tags are always indexed.
public actor SpotlightIndexer: SpotlightIndexing {
  /// The domain identifier for every document item.
  public static let domain = "com.algorythmos.pdfalgopro.documents"
  /// The most text sent to Spotlight per document.
  public static let textLimit = 20_000
  /// The index the app uses: created with a protection class (defect D11).
  public static let indexName = "documents-v2"
  /// The index earlier builds used, without a protection class; emptied once by `retireLegacyIndex()`.
  static let legacyIndexName = "documents"

  private let index: CSSearchableIndex
  private let includesText: @Sendable () -> Bool

  /// Creates an indexer over a named index, so tests do not touch the app's.
  ///
  /// - Parameters:
  ///   - indexName: The Spotlight index to write to.
  ///   - includesText: Read on each change: whether document text goes to Spotlight.
  public init(indexName: String = SpotlightIndexer.indexName, includesText: @escaping @Sendable () -> Bool = { true }) {
    #if os(iOS)
      index = CSSearchableIndex(name: indexName, protectionClass: .completeUntilFirstUserAuthentication)
    #else
      index = CSSearchableIndex(name: indexName)
    #endif
    self.includesText = includesText
  }

  /// Empties the unprotected index earlier builds wrote to; the app then reindexes (defect D11).
  public static func retireLegacyIndex() async {
    try? await CSSearchableIndex(name: legacyIndexName).deleteAllSearchableItems()
  }

  /// Adds or replaces a document; failures are ignored because Spotlight is a mirror, not a store.
  public func index(_ document: Document, text: String) async {
    guard !document.isDeleted else {
      await remove(document.id)
      return
    }
    try? await index.indexSearchableItems([Self.item(for: document, text: includesText() ? text : nil)])
  }

  /// Removes a document; failures are ignored.
  public func remove(_ id: DocumentID) async {
    try? await index.deleteSearchableItems(withIdentifiers: [id.description])
  }

  /// The Spotlight item for a document.
  ///
  /// The identifier is the document ID, which the app turns back into a route when the user opens the result.
  static func item(for document: Document, text: String?) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .pdf)
    attributes.title = document.title
    attributes.displayName = document.title
    attributes.keywords = document.tags
    attributes.textContent = text.map { String($0.prefix(textLimit)) }
    attributes.contentModificationDate = document.modifiedAt
    attributes.pageCount = NSNumber(value: document.pageCount)
    let item = CSSearchableItem(
      uniqueIdentifier: document.id.description, domainIdentifier: domain, attributeSet: attributes)
    item.expirationDate = .distantFuture
    return item
  }
}
