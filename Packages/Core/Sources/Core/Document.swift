import Foundation

/// A stable identifier for a document in the library.
///
/// Identifiers are types so they cannot be mixed up with other UUIDs or strings.
public struct DocumentID: Hashable, Codable, Sendable, CustomStringConvertible {
  /// The underlying UUID.
  public let rawValue: UUID

  /// Creates a new, unique identifier.
  public init() {
    rawValue = UUID()
  }

  /// Wraps an existing UUID.
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  /// Parses an identifier from its string form, or returns `nil` when the string is not a UUID.
  public init?(string: String) {
    guard let uuid = UUID(uuidString: string) else { return nil }
    rawValue = uuid
  }

  /// The identifier's string form, used in URLs, Spotlight and file names.
  public var description: String { rawValue.uuidString }
}

/// A PDF the user owns, as the library knows it.
///
/// The file is the source of truth; this value is the library's derived index entry for it and can
/// always be rebuilt from the files (ADR-0005, ADR-0006).
public struct Document: Identifiable, Hashable, Codable, Sendable {
  /// The document's stable identifier.
  public let id: DocumentID
  /// The title shown in the library, initially the file name without its extension.
  public var title: String
  /// The file name inside the library folder.
  public var fileName: String
  /// When the document was added to the library.
  public var addedAt: Date
  /// When the document's contents last changed.
  public var modifiedAt: Date
  /// When the document was last opened, or `nil` if never.
  public var lastOpenedAt: Date?
  /// The zero-based index of the page the reader last showed.
  public var lastPageIndex: Int
  /// The number of pages, or zero while unknown (for example a locked document).
  public var pageCount: Int
  /// Whether the user marked the document as a favourite.
  public var isFavorite: Bool
  /// The user's tags, sorted and without duplicates.
  public var tags: [String]
  /// When the document was moved to Recently Deleted, or `nil` if it is in the library.
  public var deletedAt: Date?
  /// Whether the PDF has selectable text (from its author or from on-device recognition).
  public var hasTextLayer: Bool
  /// Whether the PDF needs a password to open.
  public var isEncrypted: Bool

  /// Creates a document value.
  public init(
    id: DocumentID = DocumentID(),
    title: String,
    fileName: String,
    addedAt: Date,
    modifiedAt: Date? = nil,
    lastOpenedAt: Date? = nil,
    lastPageIndex: Int = 0,
    pageCount: Int = 0,
    isFavorite: Bool = false,
    tags: [String] = [],
    deletedAt: Date? = nil,
    hasTextLayer: Bool = false,
    isEncrypted: Bool = false
  ) {
    self.id = id
    self.title = title
    self.fileName = fileName
    self.addedAt = addedAt
    self.modifiedAt = modifiedAt ?? addedAt
    self.lastOpenedAt = lastOpenedAt
    self.lastPageIndex = lastPageIndex
    self.pageCount = pageCount
    self.isFavorite = isFavorite
    self.tags = Document.normalizedTags(tags)
    self.deletedAt = deletedAt
    self.hasTextLayer = hasTextLayer
    self.isEncrypted = isEncrypted
  }

  /// Whether the document is in Recently Deleted.
  public var isDeleted: Bool { deletedAt != nil }

  /// Trims, de-duplicates (ignoring case) and sorts tags, dropping empty ones.
  public static func normalizedTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for tag in tags {
      let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
      result.append(trimmed)
    }
    return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}
