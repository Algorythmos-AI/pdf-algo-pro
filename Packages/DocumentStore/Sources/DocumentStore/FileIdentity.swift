import Foundation

/// What tells a file in the library's folder apart from every other file, whatever its name, so a
/// file renamed or moved in the Files app is found again with its entry (#224).
///
/// It has two parts, either of which may be missing:
/// - The document identifier (`URLResourceKey.documentIdentifierKey`). Apple's documentation for the
///   key says it tracks a document across renames and safe saves, persists across restarts, isn't
///   carried by a copy, is unique only within a volume, and isn't given by every volume.
/// - The file number (`FileAttributeKey.systemFileNumber`, the inode), which a rename or a move on the
///   volume keeps, but a save that writes a new file and swaps it in changes. The library records the
///   identity again after each of its own saves, and whenever it finds a file at its recorded name.
///
/// An identity is only ever compared with files in the library's folder, all on one volume, and only
/// for an entry whose file is gone from its name, so the volume isn't part of it.
///
/// `fileResourceIdentifierKey` isn't used: it is only good for comparing files while the app runs,
/// not across restarts. Neither part is carried by a copy, or by a file moved to another volume, such
/// as iCloud Drive: those come back as new documents, as before (iCloud is spike M4, #6). Matching on
/// size and contents isn't used either: two copies of one PDF are two documents, and telling which
/// one was renamed is exactly the guess the library must not make.
struct FileIdentity: Equatable, Sendable {
  /// The system's document identifier, when the volume gives one.
  var document: Int?
  /// The file number on its volume.
  var file: UInt64?

  /// The identity of the file at `url`, or `nil` when the system gives neither part.
  init?(of url: URL) {
    document = (try? url.resourceValues(forKeys: [.documentIdentifierKey]))?.documentIdentifier
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    file = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    guard document != nil || file != nil else { return nil }
  }

  /// An identity as the index stores it, or `nil` when the text isn't one.
  init?(stored: String) {
    var document: Int?
    var file: UInt64?
    for part in stored.split(separator: ";") {
      if part.hasPrefix("d=") { document = Int(part.dropFirst(2)) }
      if part.hasPrefix("f=") { file = UInt64(part.dropFirst(2)) }
    }
    guard document != nil || file != nil else { return nil }
    self.document = document
    self.file = file
  }

  /// The text the index stores, such as `d=42;f=1234`.
  var stored: String {
    [document.map { "d=\($0)" }, file.map { "f=\($0)" }].compactMap(\.self).joined(separator: ";")
  }

  /// Whether both identities are of one file: by the document identifier when both have one, which
  /// survives saves, otherwise by the file number.
  func isSameFile(as other: FileIdentity) -> Bool {
    if let document, let otherDocument = other.document { return document == otherDocument }
    if let file, let otherFile = other.file { return file == otherFile }
    return false
  }
}
