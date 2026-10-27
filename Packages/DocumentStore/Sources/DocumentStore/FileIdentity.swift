import Foundation

/// What tells a file in the library's folder apart from every other file, whatever its name, so a
/// file renamed or moved in the Files app is found again with its entry (#224).
///
/// It has three parts, any of which may be missing:
/// - The document identifier (`URLResourceKey.documentIdentifierKey`). Apple's documentation for the
///   key says it tracks a document across renames and safe saves, persists across restarts, isn't
///   carried by a copy, is unique only within a volume, and isn't given by every volume. The system
///   gives one only to a file marked for tracking (`UF_TRACKED`), so the library marks each of its
///   files when it records the identity (`tracking(_:)`); from then on another app's atomic save keeps
///   it, even while this app isn't running.
/// - The file number (`FileAttributeKey.systemFileNumber`, the inode), which a rename or a move on the
///   volume keeps, but a save that writes a new file and swaps it in changes. It is compared only when
///   one side has no document identifier.
/// - The volume (`URLResourceKey.volumeUUIDStringKey`). Both numbers are only unique on their volume,
///   and the index is backed up, so an identity recorded on another volume (a backup restored to
///   another device) is never taken to be the same file as one here.
///
/// `fileResourceIdentifierKey` isn't used: it is only good for comparing files while the app runs,
/// not across restarts. Neither part is carried by a copy, or by a file moved to another volume, such
/// as iCloud Drive: those come back as new documents, as before (iCloud is spike M4, #6). Matching on
/// size and contents isn't used either: two copies of one PDF are two documents, and telling which
/// one was renamed is exactly the guess the library must not make.
struct FileIdentity: Equatable, Sendable {
  /// The UUID of the file's volume, when the system gives it.
  var volume: String?
  /// The system's document identifier, when the file is tracked and the volume gives one.
  var document: Int?
  /// The file number on its volume.
  var file: UInt64?

  /// `UF_TRACKED` in `<sys/stat.h>`: the file flag that asks the system to keep a document identifier.
  static let trackedFlag: UInt32 = 0x40

  /// The identity of the file at `url`, read as it is now, or `nil` when the system gives no number.
  ///
  /// The file isn't changed: this is for files the library doesn't track yet.
  init?(of url: URL) {
    var url = url
    url.removeAllCachedResourceValues()
    let values = try? url.resourceValues(forKeys: [.documentIdentifierKey, .volumeUUIDStringKey])
    volume = values?.volumeUUIDString
    document = values?.documentIdentifier
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    file = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    guard document != nil || file != nil else { return nil }
  }

  /// Marks the file at `url` for tracking, so the system gives it a document identifier, then reads
  /// its identity; for files the library tracks.
  ///
  /// A file that can't be marked still has its file number.
  static func tracking(_ url: URL) -> FileIdentity? {
    var status = stat()
    if stat(url.path, &status) == 0, status.st_flags & trackedFlag == 0 {
      _ = chflags(url.path, status.st_flags | trackedFlag)
    }
    return FileIdentity(of: url)
  }

  /// An identity as the index stores it, or `nil` when the text isn't one.
  init?(stored: String) {
    var volume: String?
    var document: Int?
    var file: UInt64?
    for part in stored.split(separator: ";") {
      if part.hasPrefix("v=") { volume = String(part.dropFirst(2)) }
      if part.hasPrefix("d=") { document = Int(part.dropFirst(2)) }
      if part.hasPrefix("f=") { file = UInt64(part.dropFirst(2)) }
    }
    guard document != nil || file != nil else { return nil }
    self.volume = volume
    self.document = document
    self.file = file
  }

  /// The text the index stores, such as `v=8D3F…;d=42;f=1234`.
  var stored: String {
    let parts = [volume.map { "v=\($0)" }, document.map { "d=\($0)" }, file.map { "f=\($0)" }]
    return parts.compactMap(\.self).joined(separator: ";")
  }

  /// Whether both identities were read on one volume, as far as they say.
  func isOnSameVolume(as other: FileIdentity) -> Bool {
    guard let volume, let otherVolume = other.volume else { return true }
    return volume == otherVolume
  }

  /// Whether both identities are of one file: never across volumes; by the document identifier when
  /// both have one, which survives saves; otherwise by the file number.
  func isSameFile(as other: FileIdentity) -> Bool {
    guard isOnSameVolume(as: other) else { return false }
    if let document, let otherDocument = other.document { return document == otherDocument }
    if let file, let otherFile = other.file { return file == otherFile }
    return false
  }
}
