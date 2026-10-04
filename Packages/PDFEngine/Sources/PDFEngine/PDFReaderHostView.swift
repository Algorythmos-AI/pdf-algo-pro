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
  static let yellow = PlatformColor.systemYellow.withAlphaComponent(0.45)
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
    // PDFView is the delegate of its own recognizers, so the tap gets a delegate of its own.
    private let tapDelegate = SimultaneousGestureDelegate()
    private lazy var transformDelegate = TransformGestureDelegate(host: self)
    private lazy var markupDelegate = MarkupGestureDelegate(host: self)
    /// Where a markup drag started: the page and the point on it.
    private var markupStart: (page: PDFPage, point: CGPoint)?
    private var transformStart: AnnotationGeometry?
    private var transformOffset = CGSize.zero
    private var transformScale: CGFloat = 1
  #endif

  func configure(for controller: PDFDocumentController) {
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
      // Selecting annotations (F3) works alongside PDFKit's own taps: links still open and text
      // selection still clears.
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
    #endif
    controller.attach(self)
  }

  func apply(_ mode: ReaderDisplayMode) {
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
    /// Selects the annotation under a tap, or clears the selection (F3).
    @objc fileprivate func tapped(_ recognizer: UITapGestureRecognizer) {
      // While text is being edited, taps pick text (through the page overlays), not annotations.
      guard let controller, !controller.isDrawing, !controller.isEditingText, let document else { return }
      let point = recognizer.location(in: self)
      guard let page = page(for: point, nearest: false) else {
        controller.clearSelection()
        return
      }
      controller.selectAnnotation(at: convert(point, to: page), onPage: document.index(for: page))
    }

    /// Whether a gesture starting at a point in this view is on the selected annotation.
    fileprivate func isOnSelection(_ point: CGPoint) -> Bool {
      guard let controller, !controller.isDrawing, let document, let page = page(for: point, nearest: false) else {
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

    /// Whether a drag starting at a point in this view would mark text: a tool is in hand and there
    /// is text under the finger.
    fileprivate func canMark(at point: CGPoint) -> Bool {
      guard let controller, controller.markupTool != nil, !controller.isDrawing,
        let page = page(for: point, nearest: false)
      else { return false }
      return page.selectionForWord(at: convert(point, to: page)) != nil
    }

    /// Marks text under a drag: a live preview follows the finger, and lifting it applies the mark.
    @objc fileprivate func marked(_ recognizer: UIPanGestureRecognizer) {
      guard let controller, let tool = controller.markupTool, let document else { return }
      let location = recognizer.location(in: self)
      switch recognizer.state {
      case .began:
        // The drag began a few points after the touch; start from where the finger went down.
        let translation = recognizer.translation(in: self)
        let origin = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        guard let page = page(for: origin, nearest: false) else { return }
        markupStart = (page, convert(origin, to: page))
        clearSelection()
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
      selection.color = tool == .highlight ? AnnotationPalette.yellow : AnnotationPalette.red.withAlphaComponent(0.25)
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
        let location = pan.location(in: host)
        let translation = pan.translation(in: host)
        return host.canMark(at: CGPoint(x: location.x - translation.x, y: location.y - translation.y))
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // Scrolling waits: on text it gives way to marking, elsewhere this fails at once and it scrolls.
      otherGestureRecognizer.view is UIScrollView
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
