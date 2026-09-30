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

/// Annotation colours: the user's content, drawn with system colours (design system, annotation colours).
enum AnnotationPalette {
  static let yellow = PlatformColor.systemYellow.withAlphaComponent(0.45)
  static let red = PlatformColor.systemRed
  static let ink = PlatformColor.systemBlue
}

/// The PDFKit page view, configured for reading.
///
/// Only `PDFDocumentController` drives it.
@MainActor
final class PDFReaderHostView: PDFView {
  private var pageObserver: (any NSObjectProtocol)?
  private weak var controller: PDFDocumentController?
  #if canImport(UIKit)
    private var inkCapture: InkCaptureView?
    // PDFView is the delegate of its own recognizers, so the tap gets a delegate of its own.
    private let tapDelegate = SimultaneousGestureDelegate()
  #endif

  func configure(for controller: PDFDocumentController) {
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
    #if canImport(UIKit)
      // Selecting annotations (F3) works alongside PDFKit's own taps: links still open and text
      // selection still clears.
      let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
      tap.cancelsTouchesInView = false
      tap.delegate = tapDelegate
      addGestureRecognizer(tap)
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
      guard let controller, !controller.isDrawing, let document else { return }
      let point = recognizer.location(in: self)
      guard let page = page(for: point, nearest: false) else {
        controller.clearSelection()
        return
      }
      controller.selectAnnotation(at: convert(point, to: page), onPage: document.index(for: page))
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
