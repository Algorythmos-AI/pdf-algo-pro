import Core
import Foundation
import PDFKit

extension PDFDocumentController {
  /// Writes the document atomically with coordinated access; a failed save leaves the file unchanged (NFR-REL-002).
  ///
  /// An encrypted document stays encrypted, with the same restrictions (see `protectionOptions()`).
  /// A text edit whose page does not read in the written file as it does here is put back, and the
  /// rest is saved; `textEditsPutBack` then says which pages (issue #232).
  ///
  /// - Parameters:
  ///   - url: The document's file.
  ///   - previous: Where to keep the file as it was before this save (FR-EDIT-008, first step), replacing
  ///     any version kept there before; `nil` keeps none. On APFS the copy is a clone, so it takes no
  ///     space until the files differ. A save that keeps one is a save of a document already on disk:
  ///     if its file is gone, renamed or moved meanwhile, nothing is written, rather than a new file
  ///     at the old name beside the moved one (#224).
  ///   - isUnchanged: Whether the file is still the version the caller expects, asked with write
  ///     access coordinated, straight before the file is replaced; `nil` asks nothing.
  ///   - written: Told the file's URL with write access still coordinated, straight after it was
  ///     replaced, so the caller can note the version it wrote before anyone else can write.
  /// - Throws: `PDFEngineError.restricted` when the document's author does not allow the change;
  ///   `PDFEngineError.insufficientSpace` when the device is too full to save safely;
  ///   `PDFEngineError.changedOnDisk` when `isUnchanged` says the file changed, which is left as it is;
  ///   `PDFEngineError.saveFailed` when writing fails, or when the earlier version can't be kept.
  public func save(
    to url: URL, keepingPreviousAt previous: URL? = nil, onlyIf isUnchanged: ((URL) -> Bool)? = nil,
    written: ((URL) -> Void)? = nil
  ) throws {
    textEditsPutBack = []
    let interval = Signposts.begin("Document.Save")
    defer { interval.end() }
    let options = try protectionOptions()
    let fileManager = FileManager.default
    // The new file is about the size of the old one, so check for that much before writing anything.
    let currentSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let available = Self.availableCapacity?(url) ?? Self.volumeAvailableCapacity(besides: url)
    guard Self.hasRoom(toWrite: currentSize, available: available) else { throw PDFEngineError.insufficientSpace }
    let hook = Self.saveFault
    func fault(_ step: SaveStep) throws { try hook?(step, url) }
    do { try fault(.started) } catch { throw Self.saveError(for: error) }
    // Staged beside the document, on the same volume, so replacing it is a rename, not a copy.
    let folder =
      (try? fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true))
      ?? fileManager.temporaryDirectory
    let staging = folder.appendingPathComponent("save-\(UUID().uuidString).pdf")
    defer {
      try? fileManager.removeItem(at: staging)
      if folder != fileManager.temporaryDirectory { try? fileManager.removeItem(at: folder) }
    }
    document.repairAttributesIfNeeded()
    var check = try stage(to: staging, options: options, fault: fault)
    // Pages whose text was edited must read in the written file as they do here (FR-EDIT-001). An
    // edit that does not is put back and the rest written again, so it cannot block every save
    // after it (issue #232).
    if !contentEditedPages.isEmpty, !editsAreIntact(in: check, options: options) {
      textEditsPutBack = putBackTextEdits(notIntactIn: check)
      guard !textEditsPutBack.isEmpty else { throw PDFEngineError.saveFailed }
      try? fileManager.removeItem(at: staging)
      check = try stage(to: staging, options: options, fault: fault)
      guard editsAreIntact(in: check, options: options) else { throw PDFEngineError.saveFailed }
    }
    // The outline and the links to pages must read back as they are here: PDFKit on iOS 27 leaves them
    // out, and they are put back (#307).
    _ = try mendStructure(in: check, at: staging, options: options)
    do { try fault(.validated) } catch { throw Self.saveError(for: error) }
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staging.path)
    var coordinationError: NSError?
    var writeError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) {
      target in
      let fileManager = FileManager.default
      do {
        try fault(.coordinated)
        let exists = fileManager.fileExists(atPath: target.path)
        if previous != nil, !exists { throw CocoaError(.fileNoSuchFile) }
        // Another app's write while this save was staged is not replaced (#257).
        if let isUnchanged, exists, !isUnchanged(target) { throw PDFEngineError.changedOnDisk }
        if let previous, exists {
          if fileManager.fileExists(atPath: previous.path) { try fileManager.removeItem(at: previous) }
          try fileManager.copyItem(at: target, to: previous)
        }
        try fault(.keptPrevious)
        if exists {
          _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } else {
          try fileManager.moveItem(at: staging, to: target)
        }
        written?(target)
        try fault(.replaced)
      } catch {
        writeError = error
      }
    }
    if let writeError {
      if writeError as? PDFEngineError == .changedOnDisk { throw PDFEngineError.changedOnDisk }
      throw Self.saveError(for: writeError)
    }
    guard coordinationError == nil else { throw PDFEngineError.saveFailed }
    switch pendingProtection {
    case .set(let newPassword):
      wasEncrypted = true
      password = newPassword
    case .remove:
      wasEncrypted = false
      password = nil
    case nil:
      break
    }
    pendingProtection = nil
    hasUnsavedChanges = false
    contentEditedPages = []
    // What was just written is what a later edit that cannot be kept goes back to.
    textEditOriginals = [:]
    recordFormValues()
  }

  /// Writes the document to `staging` and reads it back.
  ///
  /// PDFKit keeps an encrypted document encrypted whatever the options, so a document whose
  /// password is being (or was) removed is written as a fresh copy of its pages. PDFKit maps the
  /// staged file rather than reading it into memory, so this stays cheap for large files.
  private func stage(
    to staging: URL, options: [PDFDocumentWriteOption: Any], fault: (SaveStep) throws -> Void
  ) throws -> PDFDocument {
    let source = pendingProtection == .remove || (document.isEncrypted && !wasEncrypted) ? unencryptedCopy() : document
    guard source.write(to: staging, withOptions: options) else { throw PDFEngineError.saveFailed }
    do { try fault(.staged) } catch { throw Self.saveError(for: error) }
    guard let check = PDFDocument(url: staging), check.isLocked || check.pageCount == source.pageCount else {
      throw PDFEngineError.saveFailed
    }
    return check
  }

  /// Whether the edited pages read in the staged file as they do here, once it is unlocked.
  private func editsAreIntact(in check: PDFDocument, options: [PDFDocumentWriteOption: Any]) -> Bool {
    if check.isLocked, let key = options[.userPasswordOption] as? String ?? password {
      check.unlock(withPassword: key)
    }
    return check.isLocked || contentEdits(areIntactIn: check)
  }

  /// The steps of a save, for the fault-injection tests of the Trust suite (plan §4.1).
  enum SaveStep: CaseIterable, Sendable {
    /// The free space was checked; nothing is written yet.
    case started
    /// The new file is written to the staging folder.
    case staged
    /// The staged file reopened with the same number of pages.
    case validated
    /// Write access to the document is coordinated; the document and the kept version are untouched.
    case coordinated
    /// The version before the save is kept (when asked for).
    case keptPrevious
    /// The staged file replaced the document.
    case replaced
  }

  #if DEBUG
    /// Tests set this to fail a save at a chosen step of the document at the given URL (each test
    /// matches its own file, so suites running beside it are not affected); nil in normal runs, and
    /// absent from release builds.
    static var saveFault: (@Sendable (SaveStep, URL) throws -> Void)?
    /// Tests set this to report the free space beside a document (`nil` from it: the volume's own).
    static var availableCapacity: (@Sendable (URL) -> Int64?)?
  #else
    static var saveFault: (@Sendable (SaveStep, URL) throws -> Void)? { nil }
    static var availableCapacity: (@Sendable (URL) -> Int64?)? { nil }
  #endif

  /// What a save counts as saved, taken before saving to a copy, so that the changes count as unsaved
  /// again if the copy is not kept (#223).
  public struct UnsavedChanges {
    fileprivate let hasUnsavedChanges: Bool
    fileprivate let contentEditedPages: [PDFPage]
    fileprivate let formValues: [(widget: PDFAnnotation, value: FormValue)]
    fileprivate let pendingProtection: ProtectionChange?
    fileprivate let wasEncrypted: Bool
    fileprivate let password: String?
    fileprivate let textEditOriginals: [ObjectIdentifier: PDFPage]
  }

  /// The changes as they stand, to take before `save(to:)` writes a copy.
  public var unsavedChanges: UnsavedChanges {
    UnsavedChanges(
      hasUnsavedChanges: hasUnsavedChanges, contentEditedPages: contentEditedPages, formValues: formValues,
      pendingProtection: pendingProtection, wasEncrypted: wasEncrypted, password: password,
      textEditOriginals: textEditOriginals)
  }

  /// Counts `changes` as unsaved again, after `save(to:)` wrote a copy that then was not kept (#223).
  ///
  /// Changes made since stay unsaved too. The document's own file still has the protection it had,
  /// and a password change asked for since waits its turn.
  public func countAsUnsaved(_ changes: UnsavedChanges) {
    hasUnsavedChanges = hasUnsavedChanges || changes.hasUnsavedChanges
    contentEditedPages =
      changes.contentEditedPages + contentEditedPages.filter { !changes.contentEditedPages.contains($0) }
    formValues = changes.formValues
    wasEncrypted = changes.wasEncrypted
    password = changes.password
    if pendingProtection == nil { pendingProtection = changes.pendingProtection }
    // An edit made before the copy can still be put back to the page as the document file has it (#232).
    textEditOriginals.merge(changes.textEditOriginals) { since, _ in since }
  }

  /// The free space for important use on the volume holding `url`, or `nil` when it can't be read.
  static func volumeAvailableCapacity(besides url: URL) -> Int64? {
    try? url.deletingLastPathComponent()
      .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
  }

  /// The engine's error for a failure while saving: a full disk is reported as such, so the person is
  /// told to free space rather than that the save failed; anything else is `saveFailed`.
  static func saveError(for error: any Error) -> PDFEngineError {
    let nsError = error as NSError
    let outOfSpace =
      (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
      || (nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(ENOSPC) || nsError.code == Int(EDQUOT)))
    if outOfSpace { return .insufficientSpace }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== nsError {
      return saveError(for: underlying)
    }
    return .saveFailed
  }

  // MARK: - Passwords (FR-EDIT-006)

  /// A document with copies of this one's pages (and their annotations), its metadata and its outline,
  /// but no encryption.
  ///
  /// Links between pages are pointed at the copies, as the outline is: a copied link still names this
  /// document's page, and was written as a link to the first page (#235).
  func unencryptedCopy() -> PDFDocument {
    let copy = PDFDocument()
    var duplicates: [Int: PDFPage] = [:]
    var targets = LinkTargets(in: document)
    for index in 0..<document.pageCount {
      guard let page = document.page(at: index), let duplicate = page.copy() as? PDFPage else { continue }
      // Only the copy's own annotations: pointing one this document shares would break its link here.
      let shared = Set(page.annotations.map { ObjectIdentifier($0) })
      for annotation in duplicate.annotations where !shared.contains(ObjectIdentifier(annotation)) {
        targets.note(annotation)
      }
      copy.insert(duplicate, at: copy.pageCount)
      duplicates[index] = duplicate
    }
    copy.documentAttributes = document.documentAttributes
    if let outline = document.outlineRoot {
      copy.outlineRoot = Self.copyOutline(outline, noting: &targets)
    }
    targets.point { duplicates[$0] }
    return copy
  }

  /// A copy of an outline entry and its children, each going where the original goes.
  ///
  /// A destination or go-to action is noted in `targets`, to be pointed at the copied page with its
  /// zoom; any other action, a web address say, is copied as it is (#341).
  private static func copyOutline(_ item: PDFOutline, noting targets: inout LinkTargets) -> PDFOutline {
    let copy = PDFOutline()
    copy.label = item.label
    copy.isOpen = item.isOpen
    // An entry read from a file can carry its destination both as such and as a go-to action; setting
    // the action afterwards would clear the destination.
    if let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination {
      copy.destination = destination
      targets.note(copy)
    } else {
      copy.action = item.action?.copy() as? PDFAction
    }
    for index in 0..<item.numberOfChildren {
      guard let child = item.child(at: index) else { continue }
      copy.insertChild(copyOutline(child, noting: &targets), at: copy.numberOfChildren)
    }
    return copy
  }

  /// A password change, applied by the next save.
  enum ProtectionChange: Equatable {
    /// Protect the document with this password, which opens it and grants every permission.
    case set(String)
    /// Remove the password and every restriction.
    case remove
  }

  /// Whether a password protects the document, counting a change waiting for the next save.
  public var isPasswordProtected: Bool {
    switch pendingProtection {
    case .set: true
    case .remove: false
    case nil: wasEncrypted
    }
  }

  /// Whether the password can be removed: the document is protected, and was opened with its owner
  /// password (a password that only opens it can't lift the author's protection).
  public var canRemovePassword: Bool {
    wasEncrypted && !isLocked && document.permissionsStatus == .owner
  }

  /// Protects the document with a password when it is next saved.
  ///
  /// An empty password does nothing.
  ///
  /// - Returns: `false` when the password is empty, or the document's author restricted it and it
  ///   wasn't opened with the owner password.
  @discardableResult
  public func setPassword(_ newPassword: String) -> Bool {
    guard !newPassword.isEmpty, !isLocked, !wasEncrypted || document.permissionsStatus == .owner else { return false }
    pendingProtection = .set(newPassword)
    hasUnsavedChanges = true
    return true
  }

  /// Removes the password and every restriction when the document is next saved.
  ///
  /// - Returns: `false` when the document has no password, or wasn't opened with its owner password.
  @discardableResult
  public func removePassword() -> Bool {
    guard wasEncrypted, !isLocked, document.permissionsStatus == .owner else { return false }
    pendingProtection = .remove
    hasUnsavedChanges = true
    return true
  }

  /// Room kept free beyond the new file, so a save never fills the device (`Assumption:` 50 MB).
  static let spareSpace: Int64 = 50_000_000

  /// Whether a file of `byteCount` bytes can be written safely with `available` bytes free.
  ///
  /// The new file is staged next to the old one until it replaces it, and the kept earlier version holds
  /// the old one's space after that, so the new file must fit whole, with room to spare.
  /// When the free space can't be read, the save goes ahead and the write itself reports a full disk.
  static func hasRoom(toWrite byteCount: Int, available: Int64?) -> Bool {
    guard let available else { return true }
    return available >= Int64(byteCount) + spareSpace
  }

  /// Whether the document's author allows notes and markup; always true for unencrypted documents.
  public var allowsAnnotating: Bool { document.allowsCommenting }

  /// Whether the document's author allows printing; always true for unencrypted documents.
  public var allowsPrinting: Bool { document.allowsPrinting }

  /// The write options that keep an encrypted document's protection (defect D9).
  ///
  /// - Opened with the owner password: that password keeps protecting it and opens it.
  /// - Opened with the user password, or with none: the user password and the author's restrictions
  ///   stay as they were, under a new owner password nobody knows. The user password never grants
  ///   more than it did, and the original owner password, which this app never had, no longer applies.
  ///
  /// - Throws: `PDFEngineError.restricted` when the author does not allow the unsaved changes.
  func protectionOptions() throws -> [PDFDocumentWriteOption: Any] {
    switch pendingProtection {
    case .set(let newPassword):
      return [.userPasswordOption: newPassword, .ownerPasswordOption: newPassword]
    case .remove:
      guard document.permissionsStatus == .owner else { throw PDFEngineError.restricted }
      return [:]
    case nil:
      break
    }
    guard wasEncrypted else { return [:] }
    if hasUnsavedChanges && !document.allowsCommenting || hasChangedFormValues && !document.allowsFormFieldEntry {
      throw PDFEngineError.restricted
    }
    if document.permissionsStatus == .owner, let password {
      return [.userPasswordOption: password, .ownerPasswordOption: password]
    }
    var options: [PDFDocumentWriteOption: Any] = [
      .ownerPasswordOption: UUID().uuidString + UUID().uuidString,
      .accessPermissionsOption: document.accessPermissions.rawValue,
    ]
    if let password { options[.userPasswordOption] = password }
    return options
  }
}
