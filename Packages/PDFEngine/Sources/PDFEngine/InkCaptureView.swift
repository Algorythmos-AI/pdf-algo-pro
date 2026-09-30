#if canImport(UIKit)
  import UIKit

  /// The drawing layer over the pages (F2a): it collects one stroke at a time from a finger or Apple
  /// Pencil, draws it as it goes, and hands the finished stroke, in its own coordinates, to the page view.
  @MainActor
  final class InkCaptureView: UIView {
    /// Called with each finished stroke.
    var onStroke: (([CGPoint]) -> Void)?
    private var points: [CGPoint] = []
    private let stroke = CAShapeLayer()

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      isMultipleTouchEnabled = false
      stroke.strokeColor = AnnotationPalette.ink.cgColor
      stroke.fillColor = nil
      stroke.lineWidth = PDFDocumentController.inkLineWidth
      stroke.lineCap = .round
      stroke.lineJoin = .round
      layer.addSublayer(stroke)
      isAccessibilityElement = true
      // The engine has no resource bundle, so the label is looked up in the app's string catalog.
      accessibilityLabel = String(localized: "Drawing area", comment: "VoiceOver label for the layer that draws ink")
      accessibilityTraits = .allowsDirectInteraction
      accessibilityIdentifier = "reader.drawing"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("InkCaptureView is made in code")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else { return }
      points = [touch.location(in: self)]
      redraw()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else { return }
      points += (event?.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: self) }
      redraw()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      let finished = points
      points = []
      redraw()
      if finished.count > 1 { onStroke?(finished) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      points = []
      redraw()
    }

    private func redraw() {
      let path = UIBezierPath()
      if let first = points.first {
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
      }
      stroke.path = path.cgPath
    }
  }
#endif
