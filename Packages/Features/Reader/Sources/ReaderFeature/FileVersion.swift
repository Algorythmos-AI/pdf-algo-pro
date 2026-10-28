import Foundation

/// One version of a file on disk.
///
/// Saves are atomic and replace the file, so its file number changes; the modification date and size
/// catch in-place writes.
nonisolated struct FileVersion: Equatable, Codable, Sendable {
  let number: Int?
  let modified: Date?
  let size: Int?

  init(_ url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    number = (attributes[.systemFileNumber] as? NSNumber)?.intValue
    modified = attributes[.modificationDate] as? Date
    size = (attributes[.size] as? NSNumber)?.intValue
  }

  /// The version of the file at `url` now; `nil` when it can't be read.
  ///
  /// Every comparison of the file on disk with the version a reader expects reads it here, so what
  /// counts as an unknown version is decided in one place.
  static func current(at url: URL) -> FileVersion? {
    try? FileVersion(url)
  }
}
