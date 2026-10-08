#if canImport(UIKit)
  import PDFKit
  import UIKit

  /// Marks the text that can be edited on one page with a faint outline.
  ///
  /// PDFKit keeps the view exactly over its page as the page scrolls and zooms.
  ///
  /// It is a view, never an annotation, so nothing it shows can be saved into the document.
  ///
  /// It draws, and it shields: a touch that lands on it does not reach the form fields and links
  /// of the page underneath, which are not what a tap means while text is being edited. It does not
  /// pick. The page view's own tap recognizer does that (`PDFReaderHostView.pickText(at:)`), and it
  /// sees every tap on a page whether or not PDFKit has given that page an overlay, so picking
  /// never depends on this view being there.
  ///
  /// It adds no accessibility elements of its own: PDFKit already exposes each line of a page's
  /// text to VoiceOver, and does not expose an overlay's elements. Activating one of PDFKit's lines
  /// sends a tap to its middle, which the page view takes and picks the text, so each line is read
  /// once.
  @MainActor
  final class TextRegionOverlayView: UIView {
    weak var host: PDFReaderHostView?
    weak var page: PDFPage?
    private let outlines = CAShapeLayer()
    private var laidOutSize = CGSize.zero

    var regions: [EditableTextRegion] = [] {
      didSet { redraw() }
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      outlines.fillColor = nil
      outlines.lineWidth = 1
      layer.addSublayer(outlines)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
      super.layoutSubviews()
      outlines.frame = bounds
      if bounds.size != laidOutSize { redraw() }
    }

    override func tintColorDidChange() {
      super.tintColorDidChange()
      redraw()
    }

    /// An overlay PDFKit puts back on screen shows what the mode is now, not what it was when the
    /// overlay was last seen.
    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window != nil { host?.textOverlays.refresh(self) }
    }

    /// Where a region is in this view.
    private func frame(of region: EditableTextRegion) -> CGRect? {
      guard let host, let page else { return nil }
      return convert(host.convert(region.bounds, from: page), from: host).insetBy(dx: -2, dy: -1)
    }

    private func redraw() {
      laidOutSize = bounds.size
      let path = UIBezierPath()
      for region in regions {
        guard let frame = frame(of: region), frame.width > 0, frame.height > 0 else { continue }
        path.append(UIBezierPath(roundedRect: frame, cornerRadius: 3))
      }
      outlines.path = path.cgPath
      outlines.strokeColor = tintColor.withAlphaComponent(0.45).cgColor
    }
  }

  /// Gives PDFKit an overlay for each page on screen, and fills it with that page's regions while
  /// text is being edited.
  @MainActor
  final class TextOverlayProvider: NSObject, @MainActor PDFPageOverlayViewProvider {
    weak var host: PDFReaderHostView?
    /// How the page view was showing the document before text editing first zoomed it, to show it
    /// that way again when editing ends.
    var viewBeforeZoom: ViewBeforeZoom?
    /// Keeps the editor's anchor on the picked line, every frame, while text is picked.
    var anchorLink: CADisplayLink?
    /// Every overlay PDFKit was given and still holds.
    ///
    /// Held weakly and never taken out by hand: PDFKit may stop showing an overlay and show the
    /// same one again later, and one that was dropped from this list in between would stay hidden
    /// for good.
    private let overlays = NSHashTable<TextRegionOverlayView>.weakObjects()
    private var isWatching = false
    private var refreshIsPending = false

    /// How many overlays are showing regions; for diagnostics and tests.
    var shownCount: Int { overlays.allObjects.count { !$0.isHidden && $0.window != nil } }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
      let overlay = TextRegionOverlayView()
      overlay.host = host
      overlay.page = page
      overlays.add(overlay)
      refresh(overlay)
      return overlay
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
      guard let overlay = overlayView as? TextRegionOverlayView else { return }
      overlay.page = page
      overlays.add(overlay)
      refresh(overlay)
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {}

    /// Refreshes the overlays whenever what is on screen changes: other pages, or another zoom.
    func watch(_ view: PDFView) {
      guard !isWatching else { return }
      isWatching = true
      // Selector observers end with the object, so there is nothing to take down.
      for name in [Notification.Name.PDFViewVisiblePagesChanged, .PDFViewScaleChanged] {
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: name, object: view)
      }
    }

    /// Many of these arrive during one scroll or pinch; one refresh answers them all.
    @objc private func screenChanged() {
      guard !refreshIsPending, host?.controller?.isEditingText == true else { return }
      refreshIsPending = true
      Task { @MainActor [weak self] in
        self?.refreshIsPending = false
        self?.refreshAll()
      }
    }

    /// Shows or hides every overlay to match the mode.
    func refreshAll() {
      for overlay in overlays.allObjects { refresh(overlay) }
    }

    /// Shows the regions of the overlay's page, once they are found, or hides the overlay.
    func refresh(_ overlay: TextRegionOverlayView) {
      guard let controller = host?.controller, controller.isEditingText, let page = overlay.page,
        let document = host?.document
      else {
        overlay.isHidden = true
        overlay.regions = []
        return
      }
      overlay.isHidden = false
      let pageIndex = document.index(for: page)
      guard pageIndex != NSNotFound else { return }
      Task { @MainActor [weak overlay, weak controller] in
        guard let text = await controller?.pageText(onPage: pageIndex), let overlay, controller?.isEditingText == true,
          overlay.page === page
        else { return }
        if overlay.regions != text.regions { overlay.regions = text.regions }
      }
    }
  }

  extension PDFReaderHostView {
    /// Turns the text-picking overlays on or off.
    func setEditingText(_ isEditing: Bool) {
      // Markup mode stops PDFKit starting its own text selection under the overlays.
      isInMarkupMode = isEditing
      if isEditing { clearSelection() }
      // PDFKit asks for page overlays only in its scrolling layout, not in the paged one, so text
      // is edited in the scrolling layout, on the same page, and the person's layout comes back
      // when they leave.
      if let controller, controller.displayMode == .singlePage {
        let page = currentPage
        apply(isEditing ? .continuous : .singlePage)
        if let page { go(to: page) }
      }
      if !isEditing, let before = textOverlays.viewBeforeZoom {
        textOverlays.viewBeforeZoom = nil
        restore(before)
      }
      textOverlays.refreshAll()
    }

    /// Drops PDFKit's own text selection, which would otherwise point into a page that is gone.
    func clearCurrentSelection() {
      clearSelection()
    }

    /// Shows a page that has just replaced another, where the other was.
    func pageSwapped(to page: PDFPage) {
      // The scrolling layout, which text editing always uses, picks the new page up by itself and
      // keeps its zoom and position (spike S8). Undo can also swap a page while the paged layout
      // is showing, and that layout holds on to the page it had, so it is told.
      if displayMode == .singlePage { go(to: page) }
      textOverlays.refreshAll()
    }

    /// Scrolls the picked text to the upper part of the view, clear of the keyboard, and zooms so
    /// that it is readable and, where the print stays readable, so that the whole line fits the view.
    func bringTextRegionIntoView() {
      guard let selection = controller?.selectedTextRegion, let page = document?.page(at: selection.pageIndex) else {
        return
      }
      let rect = selection.region.bounds
      let current = max(scaleFactor, .leastNonzeroMagnitude)
      // The line's width as it is drawn at a zoom of 1, so a rotated page is measured as it is seen.
      let lineWidth = convert(rect, from: page).width / current
      let usable = bounds.width - layoutMargins.left - layoutMargins.right
      let range = minScaleFactor <= maxScaleFactor ? minScaleFactor...maxScaleFactor : current...current
      let scale = TextEditPlacement.scale(
        pointSize: selection.region.style.pointSize, lineWidth: lineWidth, current: current, range: range,
        width: usable)
      if scale != scaleFactor {
        if textOverlays.viewBeforeZoom == nil { textOverlays.viewBeforeZoom = viewNow() }
        // Setting the zoom turns PDFKit's fitting off; it is turned back on when editing ends.
        scaleFactor = scale
      }
      let box = page.bounds(for: displayBox)
      let zoom = max(scaleFactor, .leastNonzeroMagnitude)
      let top = min(box.maxY, rect.maxY + bounds.height / zoom * TextEditPlacement.lineDepth)
      let left = max(box.minX, rect.minX - layoutMargins.left / zoom)
      go(to: PDFDestination(page: page, at: CGPoint(x: left, y: top)))
      layoutIfNeeded()
      publishTextEditAnchor()
    }

    /// Starts or stops following the picked line, as text is picked or let go of.
    func textRegionSelectionChanged() {
      if controller?.selectedTextRegion == nil {
        textOverlays.anchorLink?.invalidate()
        textOverlays.anchorLink = nil
      } else if textOverlays.anchorLink == nil {
        let link = CADisplayLink(target: TextAnchorTicker(host: self), selector: #selector(TextAnchorTicker.tick))
        link.add(to: .main, forMode: .common)
        textOverlays.anchorLink = link
      }
      publishTextEditAnchor()
    }

    /// Tells the controller where the picked line is on screen now, when that has changed.
    ///
    /// It runs on every frame while text is picked, the way the annotation outline does, so the
    /// editor is never placed from a measurement taken before a zoom, a scroll or a rotation ended.
    func publishTextEditAnchor() {
      guard let controller else { return }
      guard let selection = controller.selectedTextRegion, let page = document?.page(at: selection.pageIndex) else {
        if controller.textEditAnchor != nil { controller.textEditAnchor = nil }
        return
      }
      let anchor = TextEditAnchor(
        selection: selection, lineFrame: convert(selection.region.bounds, from: page), scale: scaleFactor)
      if controller.textEditAnchor != anchor { controller.textEditAnchor = anchor }
    }

    /// The zoom and the place on screen now.
    private func viewNow() -> ViewBeforeZoom {
      let page = currentPage
      let index = page.flatMap { document?.index(for: $0) }
      return ViewBeforeZoom(
        scale: scaleFactor, autoScales: autoScales, pageIndex: index == NSNotFound ? nil : index,
        point: page.map { convert(CGPoint(x: bounds.minX, y: bounds.minY), to: $0) })
    }

    /// Shows the document again as it was before text editing zoomed it.
    ///
    /// The page is found again by its number: an edit replaces the page object.
    private func restore(_ before: ViewBeforeZoom) {
      if before.autoScales {
        autoScales = true
      } else {
        scaleFactor = before.scale
      }
      if let index = before.pageIndex, let point = before.point, let page = document?.page(at: index) {
        go(to: PDFDestination(page: page, at: point))
      }
    }
  }

  /// How the page view showed the document before text editing zoomed it.
  struct ViewBeforeZoom {
    var scale: CGFloat
    var autoScales: Bool
    var pageIndex: Int?
    /// The page point at the top left of the view.
    var point: CGPoint?
  }

  /// Publishes the picked line's place on each screen refresh without keeping the view alive.
  @MainActor
  private final class TextAnchorTicker: NSObject {
    private weak var host: PDFReaderHostView?

    init(host: PDFReaderHostView) {
      self.host = host
    }

    @objc func tick(_ link: CADisplayLink) {
      guard let host else {
        link.invalidate()
        return
      }
      host.publishTextEditAnchor()
    }
  }
#endif
