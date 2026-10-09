import Core
import PDFKit

#if canImport(UIKit)
  import UIKit

  typealias PlatformColor = UIColor
  typealias PlatformBezierPath = UIBezierPath
  typealias PlatformFont = UIFont
#else
  import AppKit

  typealias PlatformColor = NSColor
  typealias PlatformBezierPath = NSBezierPath
  typealias PlatformFont = NSFont
#endif

/// Stops PDFKit opening links to outside the document by itself; the controller asks first (T-02).
@MainActor
final class LinkDelegate: NSObject, @MainActor PDFViewDelegate {
  var onLink: ((URL) -> Void)?

  func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
    onLink?(url)
  }
}

/// Annotation colours: the user's content, drawn with system colours (design system, annotation colours).
enum AnnotationPalette {
  static let yellow = highlighter(.systemYellow)

  /// A highlighter's tint of a colour: the colour thinned with white, and opaque.
  ///
  /// A PDF stores a mark's colour without its transparency, so a see-through highlight comes back
  /// from a save darker than it was drawn. An opaque tint looks the same before and after, and the
  /// words still show through because highlights are multiplied onto the page.
  static func highlighter(_ color: PlatformColor) -> PlatformColor {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let parts = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
      parts.count >= 3
    else { return color }
    func thin(_ part: CGFloat) -> CGFloat { 1 - (1 - part) * 0.45 }
    guard let tint = CGColor(colorSpace: space, components: [thin(parts[0]), thin(parts[1]), thin(parts[2]), 1])
    else { return color }
    #if canImport(UIKit)
      return PlatformColor(cgColor: tint)
    #else
      return PlatformColor(cgColor: tint) ?? color
    #endif
  }
  static let red = PlatformColor.systemRed
  static let ink = PlatformColor.systemBlue
  /// Typed text on a page: black, like the frame PDFKit draws around it.
  static let text = PlatformColor.black

  /// The typeface for typed text.
  ///
  /// Helvetica is one of the standard PDF fonts, so every reader draws it; PDFKit replaces the system
  /// font, which a PDF can't name, with a serif face.
  static func font(size: CGFloat, bold: Bool = false) -> PlatformFont {
    PlatformFont(name: bold ? "Helvetica-Bold" : "Helvetica", size: size)
      ?? (bold ? PlatformFont.boldSystemFont(ofSize: size) : PlatformFont.systemFont(ofSize: size))
  }
}

/// The PDFKit page view, configured for reading.
///
/// Only `PDFDocumentController` drives it.
@MainActor
final class PDFReaderHostView: PDFView {
  private var pageObserver: (any NSObjectProtocol)?
  private(set) weak var controller: PDFDocumentController?
  private let linkDelegate = LinkDelegate()
  #if canImport(UIKit)
    /// Marks editable text on each page and takes the taps that pick it (FR-EDIT-001).
    let textOverlays = TextOverlayProvider()
    private var inkCapture: InkCaptureView?
    /// A frame around the selected annotation, so it is plain what Style, Delete or a drag will act on.
    private let selectionOutline = CAShapeLayer()
    private var outlineLink: CADisplayLink?
    /// PDFKit's gesture recognizers that are switched off while an annotation is selected.
    private var silencedGestures: [UIGestureRecognizer] = []
    // PDFView is the delegate of its own recognizers, so the tap gets a delegate of its own.
    private let tapDelegate = SimultaneousGestureDelegate()
    private lazy var transformDelegate = TransformGestureDelegate(host: self)
    private lazy var markupDelegate = MarkupGestureDelegate(host: self)
    /// Where a markup drag started: the page and the point on it.
    private var markupStart: (page: PDFPage, point: CGPoint)?
    /// Where the finger first touched: a drag is only recognised some points later.
    fileprivate var markupTouchDown: CGPoint?
    private var transformStart: AnnotationGeometry?
    private var transformOffset = CGSize.zero
    private var transformScale: CGFloat = 1
    private var hasGestures = false
    private lazy var liftDelegate = LiftGestureDelegate(host: self)
    /// The text being dragged: what it is, where the finger took hold, and its picture.
    private var lift: (selection: TextRegionSelection, origin: CGPoint, picture: UIView)?
  #endif

  /// Binds the view to a document's controller.
  ///
  /// Safe to call again with another controller: a reader that loads its document a second time
  /// makes a new controller, and the view on screen must follow it, or everything the controller
  /// asks of the view (text editing, drawing, going to a page) would go nowhere.
  /// What the zoom limits were last worked out for.
  struct ZoomKey: Equatable {
    var size: CGSize
    var mode: PDFDisplayMode
  }
  private var zoomFittedFor: ZoomKey?

  func configure(for controller: PDFDocumentController) {
    guard self.controller !== controller else { return }
    if let previous = self.controller {
      #if canImport(UIKit)
        if previous.isEditingText { setEditingText(false) }
      #endif
      previous.detach(self)
    }
    #if canImport(UIKit)
      // Also where the last controller is already gone (it is held weakly) with a line picked.
      forgetPickedText()
    #endif
    if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
    #if canImport(UIKit)
      // The provider is asked for a view as each page comes on screen, so it is in place first.
      textOverlays.host = self
      pageOverlayViewProvider = textOverlays
    #endif
    document = controller.document
    autoScales = true
    displayDirection = .vertical
    #if canImport(UIKit)
      isFindInteractionEnabled = true
      pageShadowsEnabled = true
      backgroundColor = .secondarySystemBackground
      // Selection on a page is the system's blue, not the app's red accent: on a document, red is an
      // annotation colour and the colour of Delete. The outlines below and the page overlays inherit it.
      tintColor = .systemBlue
    #endif
    pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: self, queue: .main) {
      [weak self, weak controller] _ in
      MainActor.assumeIsolated {
        guard let page = self?.currentPage else { return }
        controller?.pageChanged(to: page)
      }
    }
    self.controller = controller
    // A tapped web link waits for the person to confirm it instead of opening at once (T-02).
    linkDelegate.onLink = { [weak controller] url in controller?.linkTapped(url) }
    delegate = linkDelegate
    #if canImport(UIKit)
      installGestures()
      textOverlays.watch(self)
    #endif
    controller.attach(self)
    selectionChanged()
    #if canImport(UIKit)
      if controller.isEditingText { setEditingText(true) }
    #endif
  }

  #if canImport(UIKit)
    /// Adds the view's own gesture recognizers, once however often it is bound.
    private func installGestures() {
      guard !hasGestures else { return }
      hasGestures = true
      // Selecting annotations (F3) and picking text to edit (FR-EDIT-001) work alongside PDFKit's
      // own taps: links still open and text selection still clears.
      let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
      tap.cancelsTouchesInView = false
      tap.delegate = tapDelegate
      addGestureRecognizer(tap)
      // Dragging or pinching the selected annotation moves or resizes it (FR-ANN-005); anywhere else,
      // the page scrolls and zooms as usual, because these only begin on the selection.
      let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
      pan.maximumNumberOfTouches = 1
      pan.delegate = transformDelegate
      addGestureRecognizer(pan)
      // With a markup tool in hand, a drag that starts on text marks it (plan B3); a drag that starts
      // anywhere else scrolls as usual.
      let mark = UIPanGestureRecognizer(target: self, action: #selector(marked(_:)))
      mark.maximumNumberOfTouches = 1
      mark.delegate = markupDelegate
      addGestureRecognizer(mark)
      let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
      pinch.delegate = transformDelegate
      addGestureRecognizer(pinch)
      // While text is being edited, pressing on a line and holding lifts it, and the drag that
      // follows moves it (FR-EDIT-009). A quick drag still scrolls and a tap still picks.
      let lift = UILongPressGestureRecognizer(target: self, action: #selector(lifted(_:)))
      lift.minimumPressDuration = 0.35
      lift.delegate = liftDelegate
      addGestureRecognizer(lift)
    }
  #endif

  /// How far past the whole page the reader zooms in.
  ///
  /// `Assumption:` ten times is enough to read 4-point print on a phone; text editing zooms small
  /// print to 15 points on screen and must stay inside this (`bringTextRegionIntoView()`).
  static let largestZoom: CGFloat = 10

  /// Works the zoom limits out again from the size of the view and the page.
  func zoomLimitsChanged() {
    zoomFittedFor = nil
    #if canImport(UIKit)
      setNeedsLayout()
    #else
      needsLayout = true
    #endif
  }

  /// Keeps zooming between the whole page and `largestZoom` times that.
  ///
  /// PDFKit's own smallest zoom is well below the whole page, so a pinch leaves a small page
  /// adrift in the middle of the reader.
  private func limitZoom() {
    guard let controller, controller.limitsZoom, document != nil, bounds.width > 0, bounds.height > 0 else { return }
    let key = ZoomKey(size: bounds.size, mode: displayMode)
    guard zoomFittedFor != key else { return }
    let fit = scaleFactorForSizeToFit
    guard fit > 0, fit.isFinite else { return }
    zoomFittedFor = key
    // Setting a limit turns PDFKit's fitting off, so it is turned back on if it was on.
    let fits = autoScales
    // The upper limit first: a lower limit above the old upper one would be refused.
    maxScaleFactor = fit * Self.largestZoom
    // A hair under the fit, so fitting the page is never itself out of bounds.
    minScaleFactor = fit * 0.999
    if fits, !autoScales { autoScales = true }
  }

  /// Zooms by a factor, inside the limits.
  func zoom(by factor: CGFloat) {
    scaleFactor = min(maxScaleFactor, max(minScaleFactor, scaleFactor * factor))
  }

  #if canImport(UIKit)
    /// A touch inside the field over the picked line goes to the field, so it places the caret and
    /// selects as in any text view; anywhere else, to the page as usual.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      if let field = controller?.fieldOverPage, Self.root(of: field) === Self.root(of: self), !field.isHidden,
        field.isUserInteractionEnabled
      {
        let inField = convert(point, to: field)
        if field.point(inside: inField, with: event), let found = field.hitTest(inField, with: event) {
          return found
        }
      }
      return super.hitTest(point, with: event)
    }

    /// The view at the top of a view's hierarchy: its window, once it is on screen.
    private static func root(of view: UIView) -> UIView {
      sequence(first: view, next: \.superview).reduce(view) { $1 }
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      limitZoom()
    }
  #endif

  func apply(_ mode: ReaderDisplayMode) {
    zoomLimitsChanged()
    switch mode {
    case .continuous:
      displayMode = .singlePageContinuous
      #if canImport(UIKit)
        usePageViewController(false, withViewOptions: nil)
      #endif
    case .singlePage:
      displayMode = .singlePage
      #if canImport(UIKit)
        usePageViewController(true, withViewOptions: nil)
      #endif
    }
  }

  /// The middle of what is on screen, in a page's space, when that page is the one in the middle.
  func visibleCenter(on page: PDFPage) -> CGPoint? {
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    guard self.page(for: center, nearest: true) === page else { return nil }
    return convert(center, to: page)
  }

  func show(_ page: PDFPage) {
    go(to: page)
  }

  func select(_ selection: PDFSelection) {
    setCurrentSelection(selection, animate: true)
    go(to: selection)
  }

  /// Frames the selected annotation, and keeps the frame on it while the page scrolls, zooms or the
  /// annotation moves.
  func selectionChanged() {
    #if canImport(UIKit)
      if controller?.selected == nil {
        outlineLink?.invalidate()
        outlineLink = nil
      } else if outlineLink == nil {
        let link = CADisplayLink(target: OutlineTicker(host: self), selector: #selector(OutlineTicker.tick))
        link.add(to: .main, forMode: .common)
        outlineLink = link
      }
      // While an annotation is selected, touches are for it. PDFKit's own text gestures sit out, or a
      // tap followed at once by a drag selects text and shows the Copy menu instead of moving anything.
      setTextGestures(enabled: controller?.selected == nil)
      updateSelectionOutline()
    #endif
  }

  /// Shows the system find bar (FR-READ-003).
  func presentFind() {
    #if canImport(UIKit)
      findInteraction.presentFindNavigator(showingReplace: false)
    #endif
  }

  /// Ends text entry in a form field, which writes the text into the field.
  func endEditing() {
    #if canImport(UIKit)
      _ = endEditing(true)
    #else
      window?.makeFirstResponder(nil)
    #endif
  }

  func reload() {
    let current = document
    document = nil
    document = current
  }

  /// Shows or removes the drawing layer over the pages.
  func setDrawing(_ isDrawing: Bool, tool: DrawingTool) {
    #if canImport(UIKit)
      inkCapture?.tool = tool
      guard isDrawing != (inkCapture != nil) else { return }
      guard isDrawing else {
        inkCapture?.removeFromSuperview()
        inkCapture = nil
        return
      }
      let capture = InkCaptureView(frame: bounds)
      capture.tool = tool
      capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      capture.onStroke = { [weak self] points in self?.finishStroke(points) }
      capture.shouldDraw = { [weak self] point in self?.takesForMoving(point) != true }
      addSubview(capture)
      inkCapture = capture
    #endif
  }

  /// Hands a stroke drawn in view coordinates to the controller, in the space of the page it started on.
  private func finishStroke(_ points: [CGPoint]) {
    guard let first = points.first, let document, let page = page(for: first, nearest: true) else { return }
    controller?.strokeEnded(points.map { convert($0, to: page) }, onPage: document.index(for: page))
  }

}

#if canImport(UIKit)
  extension PDFReaderHostView {
    /// Switches PDFKit's own gestures, other than scrolling and zooming, off or back on.
    fileprivate func setTextGestures(enabled: Bool) {
      if enabled {
        for recognizer in silencedGestures { recognizer.isEnabled = true }
        silencedGestures = []
        return
      }
      guard silencedGestures.isEmpty else { return }
      var views: [UIView] = [self]
      while let view = views.popLast() {
        views.append(contentsOf: view.subviews)
        for recognizer in view.gestureRecognizers ?? [] where recognizer.isEnabled {
          let isOurs =
            recognizer.delegate === tapDelegate || recognizer.delegate === transformDelegate
            || recognizer.delegate === markupDelegate
          let scrolls =
            (view as? UIScrollView).map {
              $0.panGestureRecognizer === recognizer || $0.pinchGestureRecognizer === recognizer
            }
            ?? false
          if !isOurs && !scrolls {
            recognizer.isEnabled = false
            silencedGestures.append(recognizer)
          }
        }
      }
    }

    fileprivate func updateSelectionOutline() {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      defer { CATransaction.commit() }
      guard let selected = controller?.selected, selected.page.document != nil else {
        selectionOutline.removeFromSuperlayer()
        return
      }
      if selectionOutline.superlayer == nil {
        selectionOutline.fillColor = nil
        selectionOutline.lineWidth = 1.5
        selectionOutline.zPosition = 1
        layer.addSublayer(selectionOutline)
      }
      selectionOutline.strokeColor = tintColor.cgColor
      selectionOutline.frame = bounds
      let frame = convert(selected.annotation.bounds, from: selected.page).insetBy(dx: -4, dy: -4)
      selectionOutline.path = UIBezierPath(roundedRect: frame, cornerRadius: 5).cgPath
    }
  }

  /// Redraws the selection's frame on each screen refresh without keeping the view alive.
  @MainActor
  private final class OutlineTicker: NSObject {
    private weak var host: PDFReaderHostView?

    init(host: PDFReaderHostView) {
      self.host = host
    }

    @objc func tick(_ link: CADisplayLink) {
      guard let host else {
        link.invalidate()
        return
      }
      host.updateSelectionOutline()
    }
  }

  extension PDFReaderHostView {
    /// Selects the annotation under a tap, or clears the selection (F3).
    @objc fileprivate func tapped(_ recognizer: UITapGestureRecognizer) {
      guard let controller, !controller.isDrawing, let document else { return }
      let point = recognizer.location(in: self)
      // While text is being edited, a tap picks text, not an annotation. Picking happens here and
      // nowhere else: this recognizer is on screen for every page, whatever PDFKit does with the
      // overlays that outline the text.
      if controller.isEditingText {
        // Where a page has no overlay to shield it, the tap may also have started a form field.
        endEditing()
        pickText(at: point)
        return
      }
      guard let page = page(for: point, nearest: false) else {
        controller.clearSelection()
        return
      }
      controller.selectAnnotation(at: convert(point, to: page), onPage: document.index(for: page))
    }

    /// The text a press at a point in this view would lift, while text is being edited and none
    /// is picked.
    fileprivate func liftableText(at point: CGPoint) -> TextRegionSelection? {
      guard let controller, controller.isEditingText, controller.selectedTextRegion == nil, let document,
        let page = page(for: point, nearest: false)
      else { return nil }
      let pageIndex = document.index(for: page)
      let reach = 12 / max(scaleFactor, 0.1)
      guard pageIndex != NSNotFound,
        let region = controller.knownTextRegion(at: convert(point, to: page), onPage: pageIndex, reach: reach),
        region.isUpright || region.capability.editsContent
      else { return nil }
      return TextRegionSelection(pageIndex: pageIndex, region: region)
    }

    /// Lifts a line of text under a long press, carries its picture with the finger, and on
    /// letting go asks for the text to be moved there.
    @objc fileprivate func lifted(_ recognizer: UILongPressGestureRecognizer) {
      let point = recognizer.location(in: self)
      switch recognizer.state {
      case .began:
        guard let selection = liftableText(at: point), let page = document?.page(at: selection.pageIndex) else {
          recognizer.state = .cancelled
          return
        }
        let frame = convert(selection.region.bounds, from: page).insetBy(dx: -3, dy: -2)
        // A picture of the line as it is on screen, raised a little, so it is plain what is held.
        let picture = resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero) ?? UIView()
        picture.frame = frame
        picture.layer.borderColor = tintColor.cgColor
        picture.layer.borderWidth = 1.5
        picture.layer.cornerRadius = 3
        picture.layer.shadowColor = UIColor.black.cgColor
        picture.layer.shadowOpacity = 0.25
        picture.layer.shadowRadius = 6
        picture.layer.shadowOffset = CGSize(width: 0, height: 3)
        picture.isUserInteractionEnabled = false
        addSubview(picture)
        lift = (selection, point, picture)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      case .changed:
        guard let lift, let page = document?.page(at: lift.selection.pageIndex) else { return }
        let frame = convert(lift.selection.region.bounds, from: page).insetBy(dx: -3, dy: -2)
        lift.picture.frame = frame.offsetBy(dx: point.x - lift.origin.x, dy: point.y - lift.origin.y)
      case .ended:
        guard let lift, let page = document?.page(at: lift.selection.pageIndex) else { return }
        lift.picture.removeFromSuperview()
        self.lift = nil
        // The drag in page space: the difference between where it ended and where it started.
        let start = convert(lift.origin, to: page)
        let end = convert(point, to: page)
        let offset = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        // A press that did not travel is not a move.
        guard hypot(point.x - lift.origin.x, point.y - lift.origin.y) >= 8 else { return }
        controller?.onTextMoveRequested?(lift.selection, offset)
      default:
        lift?.picture.removeFromSuperview()
        lift = nil
      }
    }

    /// Picks the text nearest a point in this view, for editing.
    func pickText(at point: CGPoint) {
      guard let controller, let document, let page = page(for: point, nearest: true) else { return }
      let pageIndex = document.index(for: page)
      guard pageIndex != NSNotFound else { return }
      // A fingertip's reach, in page points: body text is far smaller than a finger.
      let reach = 22 / max(scaleFactor, 0.1)
      let onPage = convert(point, to: page)
      Task { @MainActor in
        await controller.selectTextRegion(at: onPage, onPage: pageIndex, reach: reach)
      }
    }

    /// Whether a touch, while a shape tool is in hand, is for moving what it lands on.
    ///
    /// A touch on a shape, a stamp or anything else that can be moved selects it, so the drag
    /// that follows moves it; a touch on bare page lets go of any selection and draws. With the
    /// pen every touch draws, because a line may well start on top of another.
    fileprivate func takesForMoving(_ point: CGPoint) -> Bool {
      guard let controller, controller.isDrawing, controller.drawingTool != .pen, let document,
        let page = page(for: point, nearest: false)
      else { return false }
      // A fingertip's reach, in page points.
      let reach = 14 / max(scaleFactor, 0.1)
      return controller.selectForMoving(at: convert(point, to: page), onPage: document.index(for: page), reach: reach)
    }

    /// Whether a gesture starting at a point in this view is on the selected annotation.
    fileprivate func isOnSelection(_ point: CGPoint) -> Bool {
      // While drawing, the drawing layer decides first whether a touch draws; a touch that reaches
      // here is one it left for moving.
      guard let controller, let document, let page = page(for: point, nearest: false) else {
        return false
      }
      return controller.isOnSelection(convert(point, to: page), pageIndex: document.index(for: page))
    }

    @objc fileprivate func panned(_ recognizer: UIPanGestureRecognizer) {
      guard let page = controller?.selected?.page else { return }
      // The drag in page space: the difference between where it is and where it started.
      let origin = convert(CGPoint.zero, to: page)
      let moved = convert(recognizer.translation(in: self), to: page)
      transformOffset = CGSize(width: moved.x - origin.x, height: moved.y - origin.y)
      transform(recognizer.state)
    }

    /// Whether a drag starting at a point in this view marks text: a tool is in hand and the drag
    /// starts on text, or runs sideways across a page.
    ///
    /// Sideways drags are taken even off the text, so that one starting beside a word still marks the
    /// line and never turns into the system's swipe back; up and down still scrolls.
    fileprivate func canMark(at point: CGPoint, sideways: Bool) -> Bool {
      guard let controller, controller.markupTool != nil, !controller.isDrawing,
        !isOnSelection(point), let page = page(for: point, nearest: false)
      else { return false }
      return sideways || page.selectionForWord(at: convert(point, to: page)) != nil
    }

    /// Marks text under a drag: a live preview follows the finger, and lifting it applies the mark.
    @objc fileprivate func marked(_ recognizer: UIPanGestureRecognizer) {
      guard let controller, let tool = controller.markupTool, let document else { return }
      let location = recognizer.location(in: self)
      switch recognizer.state {
      case .began:
        // The drag began a few points after the touch; start from where the finger went down.
        let origin = markupTouchDown ?? location
        guard let page = page(for: origin, nearest: false) else { return }
        markupStart = (page, convert(origin, to: page))
        clearSelection()
        // A drag marks text; it never picks up the mark it started on.
        controller.clearSelection()
        UISelectionFeedbackGenerator().selectionChanged()
        preview(to: location, tool: tool)
      case .changed:
        preview(to: location, tool: tool)
      case .ended:
        highlightedSelections = nil
        if let start = markupStart {
          let marked = controller.markUpText(
            from: start.point, to: convert(location, to: start.page), onPage: document.index(for: start.page))
          if marked { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        controller.clearSelection()
        markupStart = nil
      default:
        highlightedSelections = nil
        markupStart = nil
      }
    }

    private func preview(to location: CGPoint, tool: TextMarkup) {
      guard let start = markupStart, let controller, let document,
        let selection = controller.textSelection(
          from: start.point, to: convert(location, to: start.page), onPage: document.index(for: start.page))
      else {
        highlightedSelections = nil
        return
      }
      selection.color =
        tool == .highlight
        ? PlatformColor.systemYellow.withAlphaComponent(0.45) : AnnotationPalette.red.withAlphaComponent(0.25)
      highlightedSelections = [selection]
    }

    @objc fileprivate func pinched(_ recognizer: UIPinchGestureRecognizer) {
      transformScale = recognizer.scale
      transform(recognizer.state)
    }

    private func transform(_ state: UIGestureRecognizer.State) {
      guard let controller else { return }
      switch state {
      case .began:
        if transformStart == nil {
          transformStart = controller.beginTransform()
        }
      case .changed:
        if let transformStart {
          controller.updateTransform(from: transformStart, offset: transformOffset, scale: transformScale)
        }
      default:
        if let transformStart {
          controller.endTransform(from: transformStart)
        }
        transformStart = nil
        transformOffset = .zero
        transformScale = 1
      }
    }
  }

  /// Lets a long press begin only on a line of text while text is being edited, and holds the
  /// page still while the line is carried.
  @MainActor
  final class LiftGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var host: PDFReaderHostView?

    init(host: PDFReaderHostView) {
      self.host = host
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      MainActor.assumeIsolated {
        guard let host else { return false }
        return host.liftableText(at: gestureRecognizer.location(in: host)) != nil
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // While text is being edited, scrolling and zooming wait to see whether a touch is a press
      // on a line: once a line is lifted the page stays still under it. A drag fails the press
      // within a few points, so scrolling starts as it always did.
      // With a line picked nothing can be lifted (`liftableText(at:)`), so nothing waits: the page
      // scrolls and zooms under the open editor at once, even for a slow drag.
      MainActor.assumeIsolated {
        guard let controller = host?.controller, controller.isEditingText, controller.selectedTextRegion == nil
        else { return false }
        return otherGestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
      }
    }
  }

  /// Lets the move and resize gestures begin only on the selected annotation, and ahead of scrolling there.
  final class TransformGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var host: PDFReaderHostView?

    init(host: PDFReaderHostView) {
      self.host = host
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      MainActor.assumeIsolated {
        guard let host else { return false }
        return host.isOnSelection(gestureRecognizer.location(in: host))
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // A drag and a pinch on the selection work together; nothing else runs alongside them.
      gestureRecognizer.delegate === otherGestureRecognizer.delegate
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // The page's scrolling and zooming wait: on the selection they give way, elsewhere these fail at once.
      otherGestureRecognizer.view is UIScrollView
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      false
    }
  }

  /// Lets the markup drag begin only on text while a tool is in hand, and ahead of scrolling there.
  final class MarkupGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var host: PDFReaderHostView?

    init(host: PDFReaderHostView) {
      self.host = host
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      MainActor.assumeIsolated {
        guard let host, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: host)
        return host.canMark(
          at: host.markupTouchDown ?? pan.location(in: host), sideways: abs(velocity.x) > abs(velocity.y))
      }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      MainActor.assumeIsolated {
        host?.markupTouchDown = touch.location(in: host)
        return true
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // Scrolling and the swipe back wait: they give way to marking, and when this fails they go on.
      // Moving the selected annotation is this view's own gesture and keeps its turn.
      otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.delegate !== self
        && !(otherGestureRecognizer.delegate is TransformGestureDelegate)
    }
  }

  /// Lets a recognizer work alongside the others on the same view.
  final class SimultaneousGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
#endif
