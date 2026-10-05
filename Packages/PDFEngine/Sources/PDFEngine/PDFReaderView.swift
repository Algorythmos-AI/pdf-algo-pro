#if canImport(UIKit)
  import SwiftUI

  /// The reading surface: PDFKit's page view in a SwiftUI adapter (ADR-0003: UIKit stays in adapters).
  ///
  /// Pinch to zoom, text selection, copy and the system find panel come from PDFKit.
  public struct PDFReaderView: UIViewRepresentable {
    private let controller: PDFDocumentController

    /// Creates a reader view for an open document.
    public init(controller: PDFDocumentController) {
      self.controller = controller
    }

    /// Creates the page view.
    public func makeUIView(context: Context) -> some UIView {
      let view = PDFReaderHostView()
      view.configure(for: controller)
      return view
    }

    /// The controller drives the view directly, so the only thing to update is which controller.
    ///
    /// A reader that is shown again loads its document afresh and makes a new controller; the view
    /// on screen follows it.
    public func updateUIView(_ uiView: UIViewType, context: Context) {
      (uiView as? PDFReaderHostView)?.configure(for: controller)
    }
  }
#endif
