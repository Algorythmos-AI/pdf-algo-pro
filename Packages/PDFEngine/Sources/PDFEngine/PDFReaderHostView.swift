import Core
import PDFKit

#if canImport(UIKit)
  import UIKit

  typealias PlatformColor = UIColor
#else
  import AppKit

  typealias PlatformColor = NSColor
#endif

/// Annotation colours: the user's content, drawn with system colours (design system, annotation colours).
enum AnnotationPalette {
  static let yellow = PlatformColor.systemYellow.withAlphaComponent(0.45)
  static let red = PlatformColor.systemRed
}

/// The PDFKit page view, configured for reading.
///
/// Only `PDFDocumentController` drives it.
@MainActor
final class PDFReaderHostView: PDFView {
  private var pageObserver: (any NSObjectProtocol)?

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
}
