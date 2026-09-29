import Foundation

/// A section of the library sidebar.
public enum LibrarySection: Hashable, Codable, Sendable {
  /// Every document that is not deleted.
  case all
  /// Documents opened recently, newest first.
  case recents
  /// Documents marked as favourites.
  case favorites
  /// Documents carrying a tag.
  case tag(String)
  /// Documents deleted in the last 30 days.
  case recentlyDeleted

  /// The fixed sections, in sidebar order; tag sections follow them.
  public static let fixed: [LibrarySection] = [.all, .recents, .favorites, .recentlyDeleted]

  /// Whether a document belongs in this section.
  public func contains(_ document: Document) -> Bool {
    switch self {
    case .all: !document.isDeleted
    case .recents: !document.isDeleted && document.lastOpenedAt != nil
    case .favorites: !document.isDeleted && document.isFavorite
    case .tag(let tag): !document.isDeleted && document.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    case .recentlyDeleted: document.isDeleted
    }
  }
}

/// How the library orders documents.
public enum LibrarySort: String, CaseIterable, Codable, Sendable {
  /// Most recently opened first; never-opened documents follow, newest added first.
  case recentlyOpened
  /// Alphabetical by title, as Finder sorts names.
  case title
  /// Most recently added first.
  case dateAdded

  /// Sorts documents in this order.
  public func sorted(_ documents: [Document]) -> [Document] {
    switch self {
    case .recentlyOpened:
      documents.sorted { lhs, rhs in
        switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
        case (let left?, let right?): left > right
        case (.some, .none): true
        case (.none, .some): false
        case (.none, .none): lhs.addedAt > rhs.addedAt
        }
      }
    case .title:
      documents.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    case .dateAdded:
      documents.sorted { $0.addedAt > $1.addedAt }
    }
  }
}
