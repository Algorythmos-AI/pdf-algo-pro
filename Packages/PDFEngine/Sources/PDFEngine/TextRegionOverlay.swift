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
    /// Keeps the editor's anchor on the picked line, every frame, while text is picked.
    var anchorLink: CADisplayLink?
    /// The right edge of the picked line's page's text, in page space, worked out once per pick.
    var columnMaxX: CGFloat?
    /// The page scroller's inset before the editor made room under the last line; put back when
    /// the text is let go of.
    var insetBeforeEditing: UIEdgeInsets?
    /// Where the page was, and at what zoom, when the text was picked; put back when the text is let
    /// go of, if the page is still where the editor last put it.
    var placeBeforeEditing: (offset: CGPoint, scale: CGFloat)?
    /// Where the editor last scrolled the page to, for itself (to show the line, or to keep it clear
    /// of the keyboard); a page found anywhere else when the text is let go of was moved by the person.
    var offsetSetByEditor: CGPoint?
    /// Where the page was sent as the text was let go of, until the turn ends.
    ///
    /// A page swapped in the same turn, as every finished edit does, is put back there and not where
    /// the page still was.
    var placeBeingRestored: CGPoint?
    #if DEBUG
      /// Records which view touches reach and what the page's gestures do, while text is picked.
      var touchLog: TextEditTouchLog?
    #endif
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
      textOverlays.refreshAll()
    }

    /// Drops PDFKit's own text selection, which would otherwise point into a page that is gone.
    func clearCurrentSelection() {
      clearSelection()
    }

    /// Where the pages are scrolled and zoomed to, read before a page is swapped so that it can be
    /// put back after: where the page is on its way to when the text was just let go of, or where
    /// it is.
    func placeToKeep() -> (offset: CGPoint, scale: CGFloat)? {
      guard let scroller = pageScroller else { return nil }
      return (textOverlays.placeBeingRestored ?? scroller.contentOffset, scaleFactor)
    }

    /// Shows a page that has just replaced another, where the other was.
    ///
    /// - Parameters:
    ///   - page: The page now in the document.
    ///   - place: Where the pages were before the swap (`placeToKeep()`).
    func pageSwapped(to page: PDFPage, keeping place: (offset: CGPoint, scale: CGFloat)?) {
      if displayMode == .singlePage {
        // Undo can swap a page while the paged layout is showing, and that layout holds on to the
        // page it had, so it is told.
        go(to: page)
      } else if let place {
        // The scrolling layout picks the new page up by itself, but not where the pages were: with
        // a page taken out there is less to scroll over, and the view ended at the top of the
        // document after every finished edit and every Undo. So the place is put back, now and once
        // more when PDFKit has laid its pages out again.
        putBack(place)
        Task { @MainActor [weak self] in self?.putBack(place) }
      }
      textOverlays.refreshAll()
    }

    /// Puts the pages back where they were, kept inside what can be scrolled to; never under a finger.
    private func putBack(_ place: (offset: CGPoint, scale: CGFloat)) {
      guard let scroller = pageScroller, !Self.isBeingMoved(scroller) else { return }
      layoutIfNeeded()
      if abs(scaleFactor - place.scale) >= 0.001 { scaleFactor = place.scale }
      let inset = scroller.adjustedContentInset
      let lowest = max(-inset.top, scroller.contentSize.height + inset.bottom - scroller.bounds.height)
      let rightmost = max(-inset.left, scroller.contentSize.width + inset.right - scroller.bounds.width)
      let target = CGPoint(
        x: min(max(place.offset.x, -inset.left), rightmost), y: min(max(place.offset.y, -inset.top), lowest))
      if target != scroller.contentOffset { scroller.setContentOffset(target, animated: false) }
    }

    /// Brings the picked text into view when it is not, at the zoom the person chose.
    ///
    /// The zoom never changes: the page keeps fitting the screen (or the person's own zoom), so no
    /// line of the document is pushed off its edge, and the line is edited where it is, at its own
    /// size, as in Preview. Room above the keyboard is made by scrolling (`scrollPickedText(by:)`).
    func bringTextRegionIntoView() {
      guard let selection = controller?.selectedTextRegion, let page = document?.page(at: selection.pageIndex) else {
        return
      }
      let rect = selection.region.bounds
      #if DEBUG
        if !bounds.contains(convert(rect, from: page)) {
          textOverlays.touchLog?.note("editor brings the line into view")
        }
      #endif
      if !bounds.contains(convert(rect, from: page)), !page.rotation.isMultiple(of: 360) {
        // On a turned page, up the page is not up the screen, and the place worked out below would
        // scroll the wrong way; PDFKit turns the line's box itself.
        go(to: rect, on: page)
        layoutIfNeeded()
        textOverlays.offsetSetByEditor = pageScroller?.contentOffset
      } else if !bounds.contains(convert(rect, from: page)) {
        let box = page.bounds(for: displayBox)
        let zoom = max(scaleFactor, .leastNonzeroMagnitude)
        let top = min(box.maxY, rect.maxY + bounds.height / zoom * TextEditPlacement.lineDepth)
        // Only up and down: the person's place across the page stays where it was.
        let left = min(max(box.minX, convert(bounds.origin, to: page).x), box.maxX)
        go(to: PDFDestination(page: page, at: CGPoint(x: left, y: top)))
        layoutIfNeeded()
        textOverlays.offsetSetByEditor = pageScroller?.contentOffset
      }
      publishTextEditAnchor()
    }

    /// Starts or stops following the picked line, as text is picked or let go of.
    func textRegionSelectionChanged() {
      if let selection = controller?.selectedTextRegion {
        textOverlays.columnMaxX = controller?.textColumnMaxX(onPage: selection.pageIndex)
        if textOverlays.anchorLink == nil {
          let link = CADisplayLink(target: TextAnchorTicker(host: self), selector: #selector(TextAnchorTicker.tick))
          link.add(to: .main, forMode: .common)
          textOverlays.anchorLink = link
        }
        if textOverlays.placeBeforeEditing == nil, let scroller = pageScroller {
          textOverlays.placeBeforeEditing = (scroller.contentOffset, scaleFactor)
        }
        #if DEBUG
          if TextEditTouchLog.isOn, textOverlays.touchLog == nil {
            textOverlays.touchLog = TextEditTouchLog(host: self)
          }
        #endif
      } else {
        stopFollowingPickedText()
        restorePlaceAfterEditing()
      }
      publishTextEditAnchor()
    }

    /// Stops following the picked line on each frame.
    private func stopFollowingPickedText() {
      textOverlays.anchorLink?.invalidate()
      textOverlays.anchorLink = nil
      textOverlays.columnMaxX = nil
      #if DEBUG
        textOverlays.touchLog?.stop()
        textOverlays.touchLog = nil
      #endif
    }

    /// Lets go of a line picked in the document this view showed before another controller's.
    ///
    /// Nothing else would: the old controller no longer reaches this view, so its text is never let
    /// go of here, and the link would go on following a line on a page that is gone, and the room
    /// made under that document's last page would stay under the new one's. The place is not put
    /// back: it was a place in the other document.
    func forgetPickedText() {
      stopFollowingPickedText()
      if let inset = textOverlays.insetBeforeEditing { pageScroller?.contentInset = inset }
      textOverlays.insetBeforeEditing = nil
      textOverlays.placeBeforeEditing = nil
      textOverlays.offsetSetByEditor = nil
    }

    /// Takes away the room the editor made under the last page, and puts the page back where it was
    /// before the text was picked, when only the editor moved it.
    ///
    /// Where the person scrolled or zoomed while editing, the page stays where they took it: putting
    /// it back would throw away where they went. It is only kept inside what can be scrolled to.
    private func restorePlaceAfterEditing() {
      defer {
        textOverlays.insetBeforeEditing = nil
        textOverlays.placeBeforeEditing = nil
        textOverlays.offsetSetByEditor = nil
      }
      guard let scroller = pageScroller else { return }
      if let inset = textOverlays.insetBeforeEditing { scroller.contentInset = inset }
      var target = scroller.contentOffset
      if let before = textOverlays.placeBeforeEditing, let set = textOverlays.offsetSetByEditor,
        abs(scaleFactor - before.scale) < 0.001,
        hypot(scroller.contentOffset.x - set.x, scroller.contentOffset.y - set.y) < 1
      {
        target = before.offset
      }
      let inset = scroller.adjustedContentInset
      let highest = max(-inset.top, scroller.contentSize.height + inset.bottom - scroller.bounds.height)
      target.y = min(max(target.y, -inset.top), highest)
      // A finished edit swaps its page in this same turn, and the pages are then put back where they
      // were: that is here, where the page is being sent, and not where it still is.
      textOverlays.placeBeingRestored = target
      Task { @MainActor [weak self] in self?.textOverlays.placeBeingRestored = nil }
      // Off screen (a page view not in a window) there is nothing to watch move.
      if target != scroller.contentOffset { scroller.setContentOffset(target, animated: window != nil) }
    }

    /// Tells the controller where the picked line is on screen now, when that has changed.
    ///
    /// It runs on every frame while text is picked, the way the annotation outline does, so the
    /// editor stays on its line while the page scrolls, zooms or turns.
    func publishTextEditAnchor() {
      #if DEBUG
        textOverlays.touchLog?.pageMoved()
      #endif
      guard let controller else { return }
      guard let selection = controller.selectedTextRegion, let page = document?.page(at: selection.pageIndex) else {
        if controller.textEditAnchor != nil { controller.textEditAnchor = nil }
        return
      }
      let line = selection.region.bounds
      // The line widened to the right edge of the page's text: as wide as the field may grow.
      let columnRight = max(line.maxX, textOverlays.columnMaxX ?? line.maxX)
      let column = CGRect(x: line.minX, y: line.minY, width: columnRight - line.minX, height: line.height)
      let anchor = TextEditAnchor(
        selection: selection, lineFrame: convert(line, from: page), columnFrame: convert(column, from: page),
        scale: scaleFactor, isPageTurned: !page.rotation.isMultiple(of: 360), viewSize: bounds.size,
        isPageMoving: pageScroller.map { Self.isBeingMoved($0) } ?? false)
      if controller.textEditAnchor != anchor { controller.textEditAnchor = anchor }
    }

    /// Scrolls the page up (or down, for a negative distance) under the picked text, and across by
    /// `across` points, so its editor is clear of the keyboard, as Notes does; the editor stays on its
    /// line.
    ///
    /// Near the end of the document there is nothing left to scroll, so room is made under the last
    /// page, and taken away again when the text is let go of.
    ///
    /// It never moves the page while the person is moving it: a finger on the page, a pinch, or the
    /// glide after a flick. Pulling the page back under their finger is what made the page feel
    /// locked while the editor was open (the owner's report, 2026-10-08).
    ///
    /// Returns whether it scrolled; it does not while the page is moving.
    @discardableResult
    func scrollPickedText(by distance: CGFloat, across: CGFloat = 0, animated: Bool = true) -> Bool {
      guard distance != 0 || across != 0 else { return true }
      guard let scroller = pageScroller, !Self.isBeingMoved(scroller), let before = pickedLineFrame?.minY else {
        return false
      }
      #if DEBUG
        textOverlays.touchLog?.note(
          "editor scrolls the page by \(Int(distance)) across \(Int(across)), animated \(animated)")
      #endif
      let pixel = 1 / max(1, traitCollection.displayScale)
      let move: @MainActor () -> Void = {
        // Scrolling can move the page by more than it was scrolled: PDFKit centres a page shorter
        // than the view, and stops once the room made under it lets it scroll, which lifted the line
        // half a page too far. So the line's move is measured, and what is left is scrolled again.
        // The second pass scrolls a page PDFKit no longer centres, so it moves by what it is asked.
        var moved: CGFloat = 0
        for _ in 0..<2 where abs(distance - moved) >= pixel {
          self.offsetPages(of: scroller, by: distance - moved)
          scroller.layoutIfNeeded()
          self.layoutIfNeeded()
          moved = before - (self.pickedLineFrame?.minY ?? before)
        }
        // Across only when asked: PDFKit places a page narrower than the view itself.
        if across != 0 {
          let inset = scroller.adjustedContentInset
          let rightmost = max(-inset.left, scroller.contentSize.width + inset.right - scroller.bounds.width)
          scroller.contentOffset.x = min(max(-inset.left, scroller.contentOffset.x + across), rightmost)
        }
        // An animation sets the final place at once, so this is where the editor leaves the page.
        self.textOverlays.offsetSetByEditor = scroller.contentOffset
      }
      if animated, !UIAccessibility.isReduceMotionEnabled {
        // The system's own spring, which also says how long it takes.
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: UISpringTimingParameters())
        animator.addAnimations(move)
        animator.startAnimation()
      } else {
        move()
      }
      return true
    }

    /// Whether the person is moving the page: a finger on it, a pinch, a bounce or a glide.
    static func isBeingMoved(_ scroller: UIScrollView) -> Bool {
      scroller.isTracking || scroller.isDragging || scroller.isDecelerating || scroller.isZooming
        || scroller.isZoomBouncing
    }

    /// Moves the pages up under the view by a distance, making room under the last page first when
    /// there is nothing left to scroll.
    private func offsetPages(of scroller: UIScrollView, by distance: CGFloat) {
      let inset = scroller.adjustedContentInset
      let highest = scroller.contentSize.height + inset.bottom - scroller.bounds.height
      let target = max(-inset.top, scroller.contentOffset.y + distance)
      if target > highest {
        if textOverlays.insetBeforeEditing == nil { textOverlays.insetBeforeEditing = scroller.contentInset }
        scroller.contentInset.bottom += target - highest
      }
      scroller.contentOffset.y = target
    }

    /// Where the picked line is on screen, in this view's space.
    private var pickedLineFrame: CGRect? {
      guard let selection = controller?.selectedTextRegion, let page = document?.page(at: selection.pageIndex) else {
        return nil
      }
      return convert(selection.region.bounds, from: page)
    }

    /// PDFKit's own scroller for the pages, the first scroll view inside the page view.
    var pageScroller: UIScrollView? {
      var views: [UIView] = subviews
      while !views.isEmpty {
        let view = views.removeFirst()
        if let scroller = view as? UIScrollView { return scroller }
        views.append(contentsOf: view.subviews)
      }
      return nil
    }
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
      // Off screen there is no line to follow; the link costs nothing until the view is back.
      guard host.window != nil else { return }
      host.publishTextEditAnchor()
    }
  }
#endif
