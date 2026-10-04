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
    return await textPage(for: page)?.text ?? EditablePageText(regions: [], kind: .unreadable)
  }

  func textPage(for page: PDFPage) async -> TextPage? {
    let key = ObjectIdentifier(page)
    if let cached = textPages[key], cached.page === page { return cached }
    guard let snapshot = Self.snapshot(of: page) else { return nil }
    var text = await textEditor.text(ofPage: snapshot)
    // The page may have been replaced or removed while its text was being found.
    guard document.index(for: page) != NSNotFound else { return nil }
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
    return found
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
  private func coveredOnly(on page: PDFPage, beside regions: [EditableTextRegion]) -> [EditableTextRegion] {
    guard let lines = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() else { return [] }
    var result: [EditableTextRegion] = []
    for line in lines {
      let bounds = line.bounds(for: page)
      let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, bounds.width > 1, bounds.height > 1 else { continue }
      let core = bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.25)
      guard !regions.contains(where: { $0.bounds.intersects(core) }) else { continue }
      let font = line.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
      result.append(
        EditableTextRegion(
          // Negative, so it can never be mistaken for a region the editor found.
          id: -1 - result.count, text: text, bounds: bounds, angle: 0,
          style: TextStyle(
            fontName: font?.fontName ?? "Helvetica", pointSize: Double(font?.pointSize ?? bounds.height * 0.8),
            isBold: false, isItalic: false, isMonospaced: false, color: .black),
          capability: .visualReplacementOnly(.unsupportedFont)))
    }
    return result
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
    func distance(to rect: CGRect) -> CGFloat {
      hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
    let nearest = regions.filter { distance(to: $0.bounds) <= reach }.min {
      (distance(to: $0.bounds), $0.bounds.width * $0.bounds.height)
        < (distance(to: $1.bounds), $1.bounds.width * $1.bounds.height)
    }
    guard let nearest else { return false }
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
    func all(_ refusal: TextEditRefusal) -> [TextEditOutcome] { edits.map { _ in .refused(refusal) } }
    guard !edits.isEmpty else { return [] }
    guard textEditability != .restricted else { return all(.restricted) }
    guard !isCommittingText, let page = document.page(at: pageIndex) else { return all(.stale) }
    isCommittingText = true
    defer { isCommittingText = false }

    guard let found = await textPage(for: page) else { return all(.pageNotEditable) }
    let generation = structureGeneration
    // The editor is given the regions as it returned them: in the snapshot's own space.
    let translated = edits.map { edit in
      found.found[edit.regionID].map { TextEdit(region: $0, original: edit.original, replacement: edit.replacement) }
        ?? edit
    }
    let result = await textEditor.applying(translated, toPage: found.snapshot)
    let links = await incomingLinkIndex()
    // Everything above awaited. If the document changed meanwhile, the edit is dropped untouched.
    guard generation == structureGeneration, document.index(for: page) != NSNotFound else { return all(.stale) }
    guard let data = result.page else { return result.outcomes }
    guard let source = PDFDocument(data: data), source.pageCount == 1, let replacement = source.page(at: 0) else {
      return all(.notVerified)
    }
    view?.endEditing()
    swap(page, for: replacement, keeping: source, links: links)
    return result.outcomes
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
  public func coverSelectedText(with replacement: String) -> TextEditOutcome {
    guard let selection = selectedTextRegion, let page = document.page(at: selection.pageIndex) else {
      return .refused(.stale)
    }
    guard textEditability != .restricted else { return .refused(.restricted) }
    let region = selection.region
    guard case .visualReplacementOnly = region.capability, region.isUpright else {
      return .refused(.unsupportedDrawing)
    }
    let text = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .refused(.unsupportedCharacters) }

    let size = CGFloat(region.style.pointSize)
    let font = AnnotationPalette.font(size: size, bold: region.style.isBold)
    let width = (text as NSString).size(withAttributes: [.font: font]).width + 8
    let pageBox = page.bounds(for: .cropBox)
    guard region.bounds.minX + width <= pageBox.maxX else { return .tooLong }

    let cover = PDFAnnotation(bounds: region.bounds.insetBy(dx: -1, dy: -1), forType: .square, withProperties: nil)
    let background = Self.backgroundColor(of: page, around: region.bounds)
    cover.color = background
    cover.interiorColor = background
    let border = PDFBorder()
    border.lineWidth = 0
    cover.border = border

    let box = CGRect(
      x: region.bounds.minX - 2, y: region.bounds.minY - 2, width: max(width, region.bounds.width) + 4,
      height: region.bounds.height + 4)
    let label = PDFAnnotation(bounds: box, forType: .freeText, withProperties: nil)
    label.contents = text
    label.font = font
    label.fontColor = Self.platformColor(region.style.color.red, region.style.color.green, region.style.color.blue)
    label.color = .clear
    label.border = border
    add([(cover, page), (label, page)])
    selectedTextRegion = nil
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
