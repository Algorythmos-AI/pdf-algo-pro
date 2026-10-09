import Core
import CoreGraphics
import Foundation
import PDFKit

/// Existing text the person picked to edit: the page it is on, and the region.
public struct TextRegionSelection: Hashable, Sendable {
  /// The zero-based page.
  public let pageIndex: Int
  /// The text.
  public let region: EditableTextRegion

  /// Creates a selection.
  public init(pageIndex: Int, region: EditableTextRegion) {
    self.pageIndex = pageIndex
    self.region = region
  }
}

/// The text found on one page, kept while the page object stays in the document unchanged.
struct TextPage {
  /// Tells one finding of a page's text from a later one of the same page.
  var id = UUID()
  /// The page itself, held so its identity cannot be reused by another page.
  let page: PDFPage
  /// The page as the one-page PDF the regions were found in; edits are applied to the same bytes.
  let snapshot: Data
  /// The page's text, with the regions' boxes in the live page's space.
  let text: EditablePageText
  /// The regions as the editor returned them, in the snapshot's space, by identifier.
  let found: [Int: EditableTextRegion]
}

/// Editing existing text (FR-EDIT-001, ADR-0025).
///
/// An edit never touches the document until it is proven. The page being edited is copied into a
/// one-page PDF in memory, the editor changes and proves that copy, and only then is the new page
/// swapped in for the old one. The ordinary save and the ordinary undo manager do the rest: a swap
/// is undone by swapping the old page object back.
extension PDFDocumentController {
  // MARK: - What may be edited

  /// Whether the document's existing text may be edited.
  ///
  /// A protected document needs both permissions: changing its content, and adding to it, because
  /// an edit is saved together with whatever markup is on the page.
  public var textEditability: TextEditability {
    if isLocked || !document.allowsDocumentChanges || !document.allowsCommenting { return .restricted }
    return digitalSignature.isSigned ? .signed : .editable
  }

  /// Whether the words of a page were changed since the last save, by an edit or by undoing one.
  public var hasUnsavedTextEdits: Bool { !contentEditedPages.isEmpty }

  /// Turns text editing mode on or off.
  ///
  /// While it is on, taps on a page pick text instead of annotations, and drawing is off.
  public func setEditingText(_ isEditing: Bool) {
    guard isEditing != isEditingText else { return }
    if isEditing {
      if isDrawing { setDrawing(false) }
      clearSelection()
      view?.endEditing()
      prepareIncomingLinks()
    }
    isEditingText = isEditing
    selectedTextRegion = nil
    #if canImport(UIKit)
      view?.setEditingText(isEditing)
    #endif
  }

  /// The existing text of a page: its regions, and whether the page has text at all.
  ///
  /// Found once per page and kept until the page's content changes. Only the page asked for is
  /// read, so a long document costs no more than a short one.
  public func pageText(onPage pageIndex: Int) async -> EditablePageText {
    guard !isLocked, let page = document.page(at: pageIndex) else {
      return EditablePageText(regions: [], kind: .unreadable)
    }
    switch await findText(of: page) {
    case .found(let found): return found.text
    case .unreadable: return EditablePageText(regions: [], kind: .unreadable)
    case .tookTooLong: return EditablePageText(regions: [], kind: .tookTooLong)
    }
  }

  /// What looking for a page's text came to.
  enum TextSearch {
    case found(TextPage)
    case unreadable
    case tookTooLong
  }

  func textPage(for page: PDFPage) async -> TextPage? {
    if case .found(let found) = await findText(of: page) { found } else { nil }
  }

  /// Finds a page's text, once however many ask at the same time.
  ///
  /// The outlines, a tap and the reader's message can all ask about the same page within a moment
  /// of each other; they share one search.
  func findText(of page: PDFPage) async -> TextSearch {
    let key = ObjectIdentifier(page)
    if let cached = textPages[key], cached.page === page { return .found(cached) }
    let work: Task<Bool, Never>
    if let running = textSearches[key], running.page === page {
      work = running.work
    } else {
      // The task says only whether time ran out: what was found is kept in `textPages`, because a
      // page object cannot be handed between tasks.
      work = Task {
        if case .tookTooLong = await searchText(of: page) { true } else { false }
      }
      textSearches[key] = (page, work)
    }
    let tookTooLong = await work.value
    if textSearches[key]?.work == work { textSearches[key] = nil }
    if let cached = textPages[key], cached.page === page { return .found(cached) }
    return tookTooLong ? .tookTooLong : .unreadable
  }

  private func searchText(of page: PDFPage) async -> TextSearch {
    let key = ObjectIdentifier(page)
    let started = ContinuousClock.now
    guard let snapshot = Self.snapshot(of: page) else {
      noteSearch(.unreadable, regions: [], since: started)
      return .unreadable
    }
    let editor = textEditor
    guard var text = await Self.within(textFindLimit, { await editor.text(ofPage: snapshot) }) else {
      // Nothing is kept, so the next look at this page tries again.
      noteSearch(.timedOut, regions: [], since: started)
      return .tookTooLong
    }
    // The page may have been replaced or removed while its text was being found.
    guard document.index(for: page) != NSNotFound else { return .unreadable }
    let original = Dictionary(text.regions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    // PDFKit writes a page with its box moved to the origin, so the snapshot's space is the live
    // page's space shifted by the box's origin (usually zero).
    let origin = page.bounds(for: .mediaBox).origin
    var regions = text.regions.map { region in
      EditableTextRegion(
        id: region.id, text: region.text, bounds: region.bounds.offsetBy(dx: origin.x, dy: origin.y),
        angle: region.angle, style: region.style, capability: region.capability)
    }
    if text.kind == .text { regions += coveredOnly(on: page, beside: regions) }
    text = EditablePageText(regions: regions, kind: text.kind)
    if textPages.count >= 16 { textPages.removeAll() }
    let found = TextPage(page: page, snapshot: snapshot, text: text, found: original)
    textPages[key] = found
    let kind: TextEditingDiagnostics.PageKind =
      switch text.kind {
      case .text: .text
      case .image: .image
      case .unreadable: .unreadable
      case .tookTooLong: .timedOut
      }
    noteSearch(kind, regions: regions, since: started)
    rehearse(found)
    return .found(found)
  }

  // MARK: - Rehearsal

  /// What trying an edit out on a page showed.
  struct Rehearsal: Sendable {
    var proven = 0
    var unproven = 0
    var failure: TextEditProofFailure?

    /// Whether the page's text cannot be edited in place: every line tried failed.
    var isUnprovable: Bool { unproven > 0 && proven == 0 }
  }

  /// Starts trying an edit out on a page whose text was just found, in the background.
  ///
  /// The page's lines are already outlined and can be picked; this does not hold them back. If no
  /// line can be edited and proven, every line of the page is then marked cover-only, usually
  /// well before anyone has tapped one, so the editor says so before the person types. A tap that
  /// comes sooner is still finished by covering (`ReaderModel.commitTextEdit`).
  private func rehearse(_ found: TextPage) {
    let key = ObjectIdentifier(found.page)
    // The regions as the editor returned them: in the snapshot's own space.
    let editable = found.found.values.filter(\.capability.editsContent).sorted { $0.id < $1.id }
    guard found.text.kind == .text, !editable.isEmpty else { return }
    let editor = textEditor
    let snapshot = found.snapshot
    let limit = textEditLimit
    textRehearsals[key]?.cancel()
    textRehearsals[key] = Task { [weak self] in
      let rehearsal =
        await Self.within(limit) { await Self.rehearse(editable, onPage: snapshot, with: editor) } ?? Rehearsal()
      // The page may have been edited, replaced or found afresh meanwhile; this is about the page
      // as it was.
      guard let self, let current = self.textPages[key], current.page === found.page, current.id == found.id
      else { return }
      self.textEditingDiagnostics.rehearsalProven = rehearsal.proven
      self.textEditingDiagnostics.rehearsalUnproven = rehearsal.unproven
      if let failure = rehearsal.failure { self.note(failure, in: &self.textEditingDiagnostics) }
      if rehearsal.isUnprovable, let pageIndex = Optional(self.document.index(for: found.page)), pageIndex != NSNotFound
      {
        self.markTextCoverOnly(onPage: pageIndex)
      }
      self.publishDiagnostics()
    }
  }

  /// Waits for the rehearsal of a page to finish, if one is running.
  func finishTextRehearsal(onPage pageIndex: Int) async {
    guard let page = document.page(at: pageIndex) else { return }
    await textRehearsals[ObjectIdentifier(page)]?.value
  }

  /// Tries an edit out on one line of a page, and on two more, spread down the page, only if that
  /// one could not be edited; the results are thrown away.
  ///
  /// A line that is too long in a matched font says nothing about the page and is not counted.
  private static func rehearse(
    _ editable: [EditableTextRegion], onPage snapshot: Data, with editor: any PDFTextEditing
  ) async -> Rehearsal {
    var rehearsal = Rehearsal()
    for index in [editable.count / 2, 0, editable.count - 1] {
      if Task.isCancelled || rehearsal.proven > 0 { break }
      let result = await editor.rehearsing(editable[index], onPage: snapshot)
      switch result.outcomes.first {
      case .edited: rehearsal.proven += 1
      case .refused(let refusal) where refusal.meansNotEditableInPlace:
        rehearsal.unproven += 1
        rehearsal.failure = rehearsal.failure ?? result.proofFailure
      default: break
      }
    }
    return rehearsal
  }

  /// Marks every line of a page as cover-only, after an edit to it could not be made or proven.
  ///
  /// The next line picked then says so before the person types.
  public func markTextCoverOnly(onPage pageIndex: Int) {
    guard let page = document.page(at: pageIndex), let found = textPages[ObjectIdentifier(page)],
      found.page === page
    else { return }
    let regions = found.text.regions.map { region in
      EditableTextRegion(
        id: region.id, text: region.text, bounds: region.bounds, angle: region.angle, style: region.style,
        capability: region.capability.editsContent ? .visualReplacementOnly(.notVerified) : region.capability)
    }
    textPages[ObjectIdentifier(page)] = TextPage(
      id: found.id, page: page, snapshot: found.snapshot,
      text: EditablePageText(regions: regions, kind: found.text.kind), found: found.found)
    var counts = textEditingDiagnostics
    counts.direct = 0
    counts.limited = 0
    counts.coverOnly = [:]
    for region in regions {
      if case .visualReplacementOnly(let reason) = region.capability {
        counts.coverOnly[reason.rawValue, default: 0] += 1
      }
    }
    textEditingDiagnostics = counts
    #if canImport(UIKit)
      view?.textOverlays.refreshAll()
    #endif
  }

  // MARK: - Time limits

  /// Runs work, giving up on it after a limit.
  ///
  /// Swift cannot stop work that is running, so the work is cancelled, which the native editor
  /// checks for as it goes, and whatever it returns afterwards is thrown away: only the first of
  /// "finished" and "time is up" is ever seen by the caller.
  ///
  /// - Returns: What the work returned, or `nil` when the limit passed first.
  static func within<Value: Sendable>(
    _ limit: Duration, _ work: @escaping @Sendable () async -> Value
  ) async -> Value? {
    let (results, first) = AsyncStream<Value?>.makeStream(bufferingPolicy: .bufferingOldest(1))
    let job = Task { first.yield(await work()) }
    let timer = Task {
      try? await Task.sleep(for: limit)
      if !Task.isCancelled { first.yield(nil) }
    }
    var winner: Value?
    for await result in results {
      winner = result
      break
    }
    job.cancel()
    timer.cancel()
    first.finish()
    return winner
  }

  // MARK: - Diagnostics

  private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
    let elapsed = ContinuousClock.now - start
    return Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
  }

  private func noteSearch(
    _ kind: TextEditingDiagnostics.PageKind, regions: [EditableTextRegion], since start: ContinuousClock.Instant
  ) {
    var record = TextEditingDiagnostics(pageKind: kind)
    for region in regions {
      switch region.capability {
      case .direct: record.direct += 1
      case .limited: record.limited += 1
      case .visualReplacementOnly(let reason): record.coverOnly[reason.rawValue, default: 0] += 1
      }
    }
    record.findMilliseconds = Self.milliseconds(since: start)
    // A page is looked at again straight after an edit; what is known about the edit and the taps
    // stays.
    record.taps = textEditingDiagnostics.taps
    record.picks = textEditingDiagnostics.picks
    record.lastEdit = textEditingDiagnostics.lastEdit
    record.editMilliseconds = textEditingDiagnostics.editMilliseconds
    record.proofCheck = textEditingDiagnostics.proofCheck
    record.proofMeasured = textEditingDiagnostics.proofMeasured
    record.proofExpected = textEditingDiagnostics.proofExpected
    record.made = textEditingDiagnostics.made
    record.covered = textEditingDiagnostics.covered
    record.refusals = textEditingDiagnostics.refusals
    textEditingDiagnostics = record
    publishDiagnostics()
  }

  private func note(_ failure: TextEditProofFailure, in record: inout TextEditingDiagnostics) {
    record.proofCheck = failure.check.rawValue
    record.proofMeasured = failure.measured
    record.proofExpected = failure.expected
  }

  private func noteEdit(_ outcome: TextEditOutcome?, since start: ContinuousClock.Instant) {
    switch outcome {
    case .edited:
      textEditingDiagnostics.lastEdit = .edited
      textEditingDiagnostics.made += 1
    case .tooLong:
      textEditingDiagnostics.lastEdit = .tooLong
      textEditingDiagnostics.refusals += 1
    case .refused(let reason):
      textEditingDiagnostics.lastEdit = .refused(reason.rawValue)
      textEditingDiagnostics.refusals += 1
    case nil: return
    }
    textEditingDiagnostics.editMilliseconds = Self.milliseconds(since: start)
    publishDiagnostics()
  }

  /// Fills in what only the page view knows, and hands the record on.
  func publishDiagnostics() {
    textEditingDiagnostics.viewIsBound = view != nil
    #if canImport(UIKit)
      textEditingDiagnostics.outlinedPages = view?.textOverlays.shownCount ?? 0
    #endif
    onTextEditingDiagnostics?(textEditingDiagnostics)
  }

  /// A page on its own as a one-page PDF, without its annotations: what the editor works on.
  ///
  /// It exists only in memory. For a protected document that matters: the copy is not encrypted.
  static func snapshot(of page: PDFPage) -> Data? {
    guard let copy = page.copy() as? PDFPage else { return nil }
    for annotation in copy.annotations { copy.removeAnnotation(annotation) }
    let single = PDFDocument()
    single.insert(copy, at: 0)
    return single.dataRepresentation()
  }

  /// Lines PDFKit can read that the editor found no region for: text in a font or form it cannot
  /// edit.
  ///
  /// They can only be covered and replaced.
  ///
  /// The lines are built here from where PDFKit says each character is, not taken from PDFKit's
  /// own idea of a line: for text laid out in frames or tables, PDFKit can return one "line" that
  /// spans a whole block, which outlined half the page as one piece of text and left the real
  /// lines in it with no outline at all (a tester's report, 2026-10-06).
  private func coveredOnly(on page: PDFPage, beside regions: [EditableTextRegion]) -> [EditableTextRegion] {
    var result: [EditableTextRegion] = []
    for line in Self.readLines(on: page) {
      let bounds = line.bounds
      let core = bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.25)
      guard !regions.contains(where: { $0.bounds.intersects(core) }) else { continue }
      let font =
        page.selection(for: line.range)?.attributedString?.attribute(.font, at: 0, effectiveRange: nil)
        as? PlatformFont
      result.append(
        EditableTextRegion(
          // Negative, so it can never be mistaken for a region the editor found.
          id: -1 - result.count, text: line.text, bounds: bounds, angle: 0,
          style: TextStyle(
            fontName: font?.fontName ?? "Helvetica", pointSize: Double(font?.pointSize ?? bounds.height * 0.8),
            isBold: false, isItalic: false, isMonospaced: false, color: .black),
          capability: .visualReplacementOnly(.unsupportedFont)))
    }
    return result
  }

  /// A line of a page's text as PDFKit reads it: its characters, and the box around them.
  struct ReadLine {
    var range: NSRange
    var text: String
    var bounds: CGRect
  }

  /// The most characters of an oversized "line" that are looked at one by one.
  static let readLineCharacterLimit = 4000

  /// A page's lines of text as PDFKit reads them, each no bigger than a line.
  ///
  /// PDFKit's own lines are used where they are line-sized. One that is far taller than its
  /// letters is a block (text in a frame or a table cell), and is taken apart character by
  /// character: a character joins the line being built when it sits on about the same baseline,
  /// close after the last one; otherwise it starts a new line.
  static func readLines(on page: PDFPage) -> [ReadLine] {
    guard let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() else { return [] }
    var lines: [ReadLine] = []
    for selection in selections {
      let bounds = selection.bounds(for: page)
      let text = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, bounds.width > 1, bounds.height > 1, selection.numberOfTextRanges(on: page) > 0 else {
        continue
      }
      let font = selection.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
      let size = font?.pointSize ?? 12
      if bounds.height <= 2.5 * size, !text.contains("\n") {
        lines.append(ReadLine(range: selection.range(at: 0, on: page), text: text, bounds: bounds))
      } else {
        for index in 0..<selection.numberOfTextRanges(on: page) {
          lines += split(selection.range(at: index, on: page), on: page)
        }
      }
    }
    return lines
  }

  /// Takes a stretch of a page's text apart into lines, by where each character is.
  static func split(_ range: NSRange, on page: PDFPage) -> [ReadLine] {
    guard let string = page.string as NSString?, range.location != NSNotFound,
      range.location + range.length <= string.length
    else { return [] }
    var lines: [ReadLine] = []
    var current: ReadLine?
    var last = CGRect.null
    func close() {
      if let line = current {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, line.bounds.width > 1, line.bounds.height > 1 {
          lines.append(ReadLine(range: line.range, text: text, bounds: line.bounds))
        }
      }
      current = nil
      last = .null
    }
    for index in range.location..<range.location + min(range.length, readLineCharacterLimit) {
      let one = NSRange(location: index, length: 1)
      let character = string.substring(with: one)
      if character == "\n" || character == "\r" {
        close()
        continue
      }
      if character.trimmingCharacters(in: .whitespaces).isEmpty {
        // A space belongs to the line it follows; it never starts one or moves the line's edge.
        if var line = current {
          line.text += character
          line.range.length = index - line.range.location + 1
          current = line
        }
        continue
      }
      // A one-character selection, because PDFKit's per-character boxes are empty for some
      // characters.
      guard let box = page.selection(for: one)?.bounds(for: page), box.width > 0, box.height > 0.5,
        box.width.isFinite, box.height.isFinite
      else { continue }
      let height = max(box.height, 1)
      let sameBaseline = !last.isNull && abs(box.midY - last.midY) < 0.5 * max(height, last.height)
      let follows = !last.isNull && box.minX >= last.minX - height && box.minX - last.maxX < 2.5 * height
      if sameBaseline, follows, var line = current {
        line.text += character
        line.range.length = index - line.range.location + 1
        line.bounds = line.bounds.union(box)
        current = line
      } else {
        close()
        current = ReadLine(range: one, text: character, bounds: box)
      }
      last = box
    }
    close()
    return lines
  }

  // MARK: - Picking text

  /// Picks the text nearest a point.
  ///
  /// Body text is far smaller than a fingertip, so the nearest region within `reach` points wins,
  /// not only one directly under the point. While text is already picked, nothing changes: the
  /// editor that is open must be finished or cancelled first.
  ///
  /// - Returns: Whether text was picked.
  @discardableResult
  public func selectTextRegion(at point: CGPoint, onPage pageIndex: Int, reach: CGFloat) async -> Bool {
    guard isEditingText, selectedTextRegion == nil, !isCommittingText else { return false }
    let regions = await pageText(onPage: pageIndex).regions
    guard isEditingText, selectedTextRegion == nil else { return false }
    textEditingDiagnostics.taps += 1
    defer { publishDiagnostics() }
    func distance(to rect: CGRect) -> CGFloat {
      hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
    let nearest = regions.filter { distance(to: $0.bounds) <= reach }.min {
      (distance(to: $0.bounds), $0.bounds.width * $0.bounds.height)
        < (distance(to: $1.bounds), $1.bounds.width * $1.bounds.height)
    }
    guard let nearest else { return false }
    textEditingDiagnostics.picks += 1
    selectedTextRegion = TextRegionSelection(pageIndex: pageIndex, region: nearest)
    #if canImport(UIKit)
      view?.bringTextRegionIntoView()
    #endif
    return true
  }

  /// Picks a region directly, as assistive technology and tests do.
  public func selectTextRegion(_ region: EditableTextRegion, onPage pageIndex: Int) {
    guard isEditingText, selectedTextRegion == nil, !isCommittingText else { return }
    selectedTextRegion = TextRegionSelection(pageIndex: pageIndex, region: region)
    #if canImport(UIKit)
      view?.bringTextRegionIntoView()
    #endif
  }

  /// The right edge of a page's text, in page space, from the text already found on it; `nil`
  /// before the page's text is found.
  ///
  /// The editor for a line may grow to it, so typed words wrap where the page's own lines end.
  func textColumnMaxX(onPage pageIndex: Int) -> CGFloat? {
    guard let page = document.page(at: pageIndex), let found = textPages[ObjectIdentifier(page)], found.page === page
    else { return nil }
    return found.text.regions.filter(\.isUpright).map(\.bounds.maxX).max()
  }

  #if canImport(UIKit)
    /// Scrolls the page under the picked text by a distance in screen points: up for a positive
    /// distance, down for a negative one, and across by `across` (to the left for a positive one).
    ///
    /// The editor stays on its line and moves with it. Nothing moves while the person is moving the
    /// page themselves.
    ///
    /// Returns whether it scrolled.
    @discardableResult
    public func scrollPickedText(by distance: CGFloat, across: CGFloat = 0) -> Bool {
      guard selectedTextRegion != nil, let view else { return false }
      return view.scrollPickedText(by: distance, across: across)
    }

    /// Whether a finger is on the page, dragging or pinching it.
    public var isPageTouched: Bool {
      guard let scroller = view?.pageScroller else { return false }
      return scroller.isTracking || scroller.isZooming
    }

    /// The page view's size now, to tell a line measured before the view last changed size
    /// (`TextEditAnchor.isMeasured(at:)`); `nil` while no page view shows the document.
    public var pageViewSize: CGSize? { view?.bounds.size }
  #endif

  /// Lets go of the picked text without changing it.
  public func clearTextRegionSelection() {
    selectedTextRegion = nil
  }

  // MARK: - Editing

  /// Replaces the picked text.
  ///
  /// Returns what happened; anything but `.edited` changed nothing.
  ///
  /// Text that can only be covered is not covered here: the caller asks for that explicitly with
  /// `coverSelectedText(with:)`, so covering is never mistaken for editing.
  public func replaceSelectedText(with replacement: String) async -> TextEditOutcome {
    guard let selection = selectedTextRegion else { return .refused(.stale) }
    let edit = TextEdit(region: selection.region, replacement: replacement)
    let outcome = await applyTextEdits([edit], onPage: selection.pageIndex).first ?? .refused(.stale)
    if outcome.isEdited { selectedTextRegion = nil }
    return outcome
  }

  // MARK: - Moving text

  /// The text at a point, if the page's text has been found; for lifting it under a finger.
  ///
  /// Nothing is looked for here: a page whose text is not yet known has nothing to lift.
  public func knownTextRegion(at point: CGPoint, onPage pageIndex: Int, reach: CGFloat) -> EditableTextRegion? {
    guard isEditingText, let page = document.page(at: pageIndex), let found = textPages[ObjectIdentifier(page)],
      found.page === page
    else { return nil }
    func distance(to rect: CGRect) -> CGFloat {
      hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
    return found.text.regions.filter { distance(to: $0.bounds) <= reach }.min {
      (distance(to: $0.bounds), $0.bounds.width * $0.bounds.height)
        < (distance(to: $1.bounds), $1.bounds.width * $1.bounds.height)
    }
  }

  /// A move kept on the page: the offset is shortened so the text's box stays inside the page.
  public func offset(_ offset: CGVector, keeping region: EditableTextRegion, onPage pageIndex: Int) -> CGVector {
    guard let page = document.page(at: pageIndex) else { return .zero }
    let box = page.bounds(for: .cropBox).insetBy(dx: 2, dy: 2)
    let bounds = region.bounds
    let dx = min(max(offset.dx, box.minX - bounds.minX), box.maxX - bounds.maxX)
    let dy = min(max(offset.dy, box.minY - bounds.minY), box.maxY - bounds.maxY)
    return CGVector(dx: dx, dy: dy)
  }

  /// Moves a line of text, keeping its words.
  ///
  /// The text is erased where it was and drawn where it is put, and proven like any edit; undo
  /// puts it back. Returns what happened; anything but `.edited` changed nothing. Text that can
  /// only be covered is not moved here: the caller asks for that with
  /// `cover(_:with:insteadOfEditing:movedBy:)`.
  ///
  /// Nothing is picked for this, so no editor opens: the text is moved as it is.
  public func moveText(_ selection: TextRegionSelection, by offset: CGVector) async -> TextEditOutcome {
    guard isEditingText, selectedTextRegion == nil else { return .refused(.stale) }
    let kept = self.offset(offset, keeping: selection.region, onPage: selection.pageIndex)
    let edit = TextEdit(region: selection.region, replacement: selection.region.text, offset: kept)
    return await applyTextEdits([edit], onPage: selection.pageIndex).first ?? .refused(.stale)
  }

  /// Applies edits to one page as a single undo step, all or nothing.
  ///
  /// This is also the entry point for anything that proposes edits, such as a future writing
  /// assistant: it hands over values and never touches the file.
  ///
  /// - Parameters:
  ///   - edits: Changes to regions of the page, as `pageText(onPage:)` returned them.
  ///   - pageIndex: The zero-based page.
  /// - Returns: What happened to each edit. Unless every edit was made, nothing changed.
  public func applyTextEdits(_ edits: [TextEdit], onPage pageIndex: Int) async -> [TextEditOutcome] {
    let started = ContinuousClock.now
    let outcomes = await makeTextEdits(edits, onPage: pageIndex)
    noteEdit(outcomes.first { !$0.isEdited } ?? outcomes.first, since: started)
    return outcomes
  }

  private func makeTextEdits(_ edits: [TextEdit], onPage pageIndex: Int) async -> [TextEditOutcome] {
    func all(_ refusal: TextEditRefusal) -> [TextEditOutcome] { edits.map { _ in .refused(refusal) } }
    guard !edits.isEmpty else { return [] }
    guard textEditability != .restricted else { return all(.restricted) }
    guard !isCommittingText, let page = document.page(at: pageIndex) else { return all(.stale) }
    isCommittingText = true
    defer { isCommittingText = false }

    let found: TextPage
    switch await findText(of: page) {
    case .found(let text): found = text
    case .unreadable: return all(.pageNotEditable)
    case .tookTooLong: return all(.timedOut)
    }
    let generation = structureGeneration
    // The editor is given the regions as it returned them: in the snapshot's own space.
    let translated = edits.map { edit in
      found.found[edit.regionID].map {
        TextEdit(region: $0, original: edit.original, replacement: edit.replacement, offset: edit.offset)
      }
        ?? edit
    }
    let editor = textEditor
    let snapshot = found.snapshot
    // The page is swapped only below, on the path where the editor answered in time. An answer
    // that comes after the limit is never seen here, so it can never reach the document.
    guard let result = await Self.within(textEditLimit, { await editor.applying(translated, toPage: snapshot) })
    else { return all(.timedOut) }
    if let failure = result.proofFailure { note(failure, in: &textEditingDiagnostics) }
    let links = await incomingLinkIndex()
    // Everything above awaited. If the document changed meanwhile, the edit is dropped untouched.
    guard generation == structureGeneration, document.index(for: page) != NSNotFound else { return all(.stale) }
    guard let data = result.page else { return result.outcomes }
    guard let source = PDFDocument(data: data), source.pageCount == 1, let replacement = source.page(at: 0) else {
      return all(.notVerified)
    }
    view?.endEditing()
    swap(page, for: replacement, keeping: source, links: links)
    limitUndoMemory(adding: found.snapshot.count + data.count)
    return result.outcomes
  }

  /// The most bytes of replaced pages the undo history may hold.
  ///
  /// Assumption: 64 MB is far more than a session of edits to ordinary pages needs and small
  /// beside the memory an app is allowed; validated on the oldest supported iPhone in the device
  /// test plan.
  static let undoMemoryLimit = 64_000_000

  /// Keeps the undo history's memory bounded: each text edit keeps the page it replaced.
  ///
  /// The undo manager cannot drop one entry, so when the estimate passes the limit the history is
  /// shortened to its newest half, oldest steps first, and stays at that length.
  func limitUndoMemory(adding bytes: Int) {
    textUndoBytes += bytes
    guard textUndoBytes > Self.undoMemoryLimit else { return }
    let current = undoManager.levelsOfUndo == 0 ? 64 : undoManager.levelsOfUndo
    undoManager.levelsOfUndo = max(4, current / 2)
    textUndoBytes /= 2
  }

  // MARK: - Swapping a page

  /// Puts `new` where `old` is, as one undoable step.
  ///
  /// The annotations and form fields move across as the same objects, so nothing that refers to
  /// them goes stale, and every bookmark and link that pointed at the old page points at the new
  /// one. Undo calls this again with the pages the other way round.
  ///
  /// - Parameters:
  ///   - old: The page to take out; it must be in the document.
  ///   - new: The page to put in its place.
  ///   - source: The document `new` came from, kept alive for as long as the page can come back.
  ///   - links: Which links point at which page.
  func swap(_ old: PDFPage, for new: PDFPage, keeping source: PDFDocument?, links: [ObjectIdentifier: [PDFAnnotation]])
  {
    let index = document.index(for: old)
    guard index != NSNotFound else { return }
    clearSelection()
    selectedTextRegion = nil
    #if canImport(UIKit)
      view?.clearCurrentSelection()
    #endif

    // The two pages show the same content, each from its own box's origin. PDFKit moves a page's
    // box to the origin when it writes it, so everything placed on the page moves by the difference.
    let from = old.bounds(for: .mediaBox).origin
    let to = new.bounds(for: .mediaBox).origin
    let shift = CGVector(dx: to.x - from.x, dy: to.y - from.y)
    new.rotation = old.rotation
    for box in [PDFDisplayBox.cropBox, .bleedBox, .trimBox, .artBox] {
      let wanted = old.bounds(for: box).offsetBy(dx: shift.dx, dy: shift.dy)
      if new.bounds(for: box) != wanted { new.setBounds(wanted, for: box) }
    }
    // The new page goes into the document before anything is moved onto it. A form field moved to
    // a page that is not in a document yet loses its name when the page is inserted.
    document.removePage(at: index)
    document.insert(new, at: index)
    let fields = old.annotations.map { (widget: $0, name: $0.fieldName) }
    // A pop-up travels with the note it belongs to.
    for annotation in old.annotations where annotation.type != "Popup" {
      old.removeAnnotation(annotation)
      if shift != .zero { annotation.bounds = annotation.bounds.offsetBy(dx: shift.dx, dy: shift.dy) }
      new.addAnnotation(annotation)
    }
    for annotation in old.annotations { old.removeAnnotation(annotation) }
    for field in fields where field.widget.fieldName != field.name { field.widget.fieldName = field.name }
    repoint(from: old, to: new, shift: shift, links: links)

    textPages[ObjectIdentifier(old)] = nil
    contentEditedPages.removeAll { $0 === old }
    contentEditedPages.append(new)
    structureGeneration += 1
    hasUnsavedChanges = true
    #if canImport(UIKit)
      view?.pageSwapped(to: new)
    #endif
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated {
        // `source` is captured so the page that may come back keeps its document.
        controller.swap(new, for: old, keeping: source, links: controller.incomingLinks ?? [:])
      }
    }
  }

  private func repoint(
    from old: PDFPage, to new: PDFPage, shift: CGVector, links: [ObjectIdentifier: [PDFAnnotation]]
  ) {
    func moved(_ destination: PDFDestination) -> PDFDestination {
      // A destination with no particular point keeps having none.
      let point = destination.point
      let known = point.x != kPDFDestinationUnspecifiedValue && point.y != kPDFDestinationUnspecifiedValue
      let result = PDFDestination(
        page: new, at: known ? CGPoint(x: point.x + shift.dx, y: point.y + shift.dy) : point)
      result.zoom = destination.zoom
      return result
    }
    func walk(_ item: PDFOutline, depth: Int) {
      guard depth < TextEditingLimits.depth else { return }
      if let destination = item.destination, destination.page === old { item.destination = moved(destination) }
      for child in 0..<item.numberOfChildren {
        if let next = item.child(at: child) { walk(next, depth: depth + 1) }
      }
    }
    if let root = document.outlineRoot { walk(root, depth: 0) }
    let pointing = links[ObjectIdentifier(old)] ?? []
    for link in pointing {
      if let destination = link.destination, destination.page === old { link.destination = moved(destination) }
      if let action = link.action as? PDFActionGoTo, action.destination.page === old {
        link.action = PDFActionGoTo(destination: moved(action.destination))
      }
    }
    if !pointing.isEmpty {
      var index = incomingLinks ?? [:]
      index[ObjectIdentifier(old)] = nil
      index[ObjectIdentifier(new), default: []] += pointing
      incomingLinks = index
    }
  }

  // MARK: - Links into pages

  /// Starts finding which links point at which page, a few pages at a time so the page view stays
  /// responsive.
  ///
  /// Walking every page's annotations takes most of a second for a 500-page document (spike S6), so
  /// it is done once, not per edit.
  func prepareIncomingLinks() {
    guard incomingLinks == nil, linkIndexing == nil else { return }
    linkIndexing = Task { @MainActor [weak self] in
      var index: [ObjectIdentifier: [PDFAnnotation]] = [:]
      var pageIndex = 0
      while let self, pageIndex < self.document.pageCount {
        if let page = self.document.page(at: pageIndex) {
          for annotation in page.annotations {
            let target = annotation.destination?.page ?? (annotation.action as? PDFActionGoTo)?.destination.page
            if let target { index[ObjectIdentifier(target), default: []].append(annotation) }
          }
        }
        pageIndex += 1
        if pageIndex.isMultiple(of: 20) { await Task.yield() }
      }
      self?.incomingLinks = index
      self?.linkIndexing = nil
    }
  }

  private func incomingLinkIndex() async -> [ObjectIdentifier: [PDFAnnotation]] {
    if let incomingLinks { return incomingLinks }
    prepareIncomingLinks()
    await linkIndexing?.value
    return incomingLinks ?? [:]
  }

  // MARK: - Covering text that cannot be edited

  /// Covers the picked text and places new text over it.
  ///
  /// Returns what happened.
  ///
  /// This is not editing: the original text stays in the file, and is still what search, copy and
  /// read aloud find. It is two ordinary annotations (a filled rectangle and a text box), added as
  /// one undo step, and the outcome says `.visualReplacement` so it is never counted as an edit.
  /// It is offered only for text whose capability is `.visualReplacementOnly`.
  ///
  /// - Parameters:
  ///   - replacement: The new text.
  ///   - insteadOfEditing: Whether this finishes an edit that could not be made or proven in the
  ///     page's content. Text the engine marked as editable may then be covered too.
  /// - Returns: What happened; anything but `.edited(.visualReplacement)` changed nothing.
  public func coverSelectedText(with replacement: String, insteadOfEditing: Bool = false) -> TextEditOutcome {
    guard let selection = selectedTextRegion else { return .refused(.stale) }
    return cover(selection, with: replacement, insteadOfEditing: insteadOfEditing)
  }

  /// Covers a piece of text and places new text over it, or elsewhere on its page.
  ///
  /// See `coverSelectedText(with:insteadOfEditing:)`, which does this for the picked text.
  ///
  /// - Parameters:
  ///   - selection: The text to cover.
  ///   - replacement: The new text.
  ///   - insteadOfEditing: Whether this finishes an edit that could not be made or proven in the
  ///     page's content. Text the engine marked as editable may then be covered too.
  ///   - offset: How far from the old text the new text is placed, in page points; the cover stays
  ///     over the old text.
  /// - Returns: What happened; anything but `.edited(.visualReplacement)` changed nothing.
  public func cover(
    _ selection: TextRegionSelection, with replacement: String, insteadOfEditing: Bool = false,
    movedBy offset: CGVector = .zero
  ) -> TextEditOutcome {
    guard let page = document.page(at: selection.pageIndex) else { return .refused(.stale) }
    guard textEditability != .restricted else { return .refused(.restricted) }
    let region = selection.region
    guard insteadOfEditing || !region.capability.editsContent, region.isUpright else {
      return .refused(.unsupportedDrawing)
    }
    let text = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .refused(.unsupportedCharacters) }

    let size = CGFloat(region.style.pointSize)
    let font = AnnotationPalette.font(size: size, bold: region.style.isBold)
    let width = (text as NSString).size(withAttributes: [.font: font]).width + 8
    let pageBox = page.bounds(for: .cropBox)
    guard region.bounds.minX + offset.dx + width <= pageBox.maxX else { return .tooLong }

    let cover = PDFAnnotation(bounds: region.bounds.insetBy(dx: -1, dy: -1), forType: .square, withProperties: nil)
    let background = Self.backgroundColor(of: page, around: region.bounds)
    cover.color = background
    cover.interiorColor = background
    let border = PDFBorder()
    border.lineWidth = 0
    cover.border = border

    let box = CGRect(
      x: region.bounds.minX - 2, y: region.bounds.minY - 2, width: max(width, region.bounds.width) + 4,
      height: region.bounds.height + 4
    ).offsetBy(dx: offset.dx, dy: offset.dy)
    let label = PDFAnnotation(bounds: box, forType: .freeText, withProperties: nil)
    label.contents = text
    label.font = font
    label.fontColor = Self.platformColor(region.style.color.red, region.style.color.green, region.style.color.blue)
    label.color = .clear
    label.border = border
    add([(cover, page), (label, page)])
    selectedTextRegion = nil
    textEditingDiagnostics.covered += 1
    publishDiagnostics()
    return .edited(.visualReplacement)
  }

  /// The colour behind a piece of text: the commonest colour of the page just around it.
  private static func backgroundColor(of page: PDFPage, around rect: CGRect) -> PlatformColor {
    let area = rect.insetBy(dx: -2, dy: -2)
    let width = 24
    let height = 8
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return .white }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: CGFloat(width) / area.width, y: CGFloat(height) / area.height)
    context.translateBy(x: -area.minX, y: -area.minY)
    page.draw(with: .mediaBox, to: context)
    guard let image = context.makeImage(), let data = image.dataProvider?.data as Data? else { return .white }
    let pixels = [UInt8](data)
    var counts: [Int: Int] = [:]
    for row in 0..<height {
      for column in 0..<width {
        let offset = row * image.bytesPerRow + column * 4
        guard offset + 2 < pixels.count else { continue }
        counts[Int(pixels[offset]) << 16 | Int(pixels[offset + 1]) << 8 | Int(pixels[offset + 2]), default: 0] += 1
      }
    }
    guard let commonest = counts.max(by: { $0.value < $1.value })?.key else { return .white }
    return platformColor(
      Double(commonest >> 16 & 0xFF) / 255, Double(commonest >> 8 & 0xFF) / 255, Double(commonest & 0xFF) / 255)
  }

  /// A platform colour from sRGB components.
  ///
  /// These are colours read from the person's document, not design colours.
  private static func platformColor(_ red: Double, _ green: Double, _ blue: Double) -> PlatformColor {
    let color = CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    #if canImport(UIKit)
      return PlatformColor(cgColor: color)
    #else
      return PlatformColor(cgColor: color) ?? .black
    #endif
  }

  // MARK: - Saving

  /// Whether the pages whose content was edited read the same in a staged file as they do here.
  ///
  /// The proof before a swap checks the edited page on its own. This checks what PDFKit actually
  /// wrote, before it replaces the document.
  func contentEdits(areIntactIn staged: PDFDocument) -> Bool {
    for page in contentEditedPages {
      let index = document.index(for: page)
      guard index != NSNotFound else { continue }
      guard let written = staged.page(at: index),
        EditProof.squeezed(written.string ?? "") == EditProof.squeezed(page.string ?? "")
      else { return false }
    }
    return true
  }
}
