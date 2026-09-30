#if canImport(UIKit)
  import UIKit
  import UIKit.UIGestureRecognizerSubclass

  /// The drawing layer over the pages (F2a): it collects one stroke at a time from a finger or Apple
  /// Pencil, draws it as it goes, and hands the finished stroke, in its own coordinates, to the page view.
  ///
  /// Strokes come from a gesture recognizer that every other recognizer must wait for. Raw touch
  /// handling is not enough: the page view's and SwiftUI's recognizers above this layer claim a drag
  /// and cancel its touches part-way.
  @MainActor
  final class InkCaptureView: UIView, UIGestureRecognizerDelegate {
    /// Called with each finished stroke.
    var onStroke: (([CGPoint]) -> Void)?
    private let stroke = CAShapeLayer()
    private let recognizer = InkStrokeRecognizer()

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      stroke.strokeColor = AnnotationPalette.ink.cgColor
      stroke.fillColor = nil
      stroke.lineWidth = PDFDocumentController.inkLineWidth
      stroke.lineCap = .round
      stroke.lineJoin = .round
      layer.addSublayer(stroke)
      recognizer.addTarget(self, action: #selector(strokeChanged(_:)))
      recognizer.delegate = self
      addGestureRecognizer(recognizer)
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

    @objc private func strokeChanged(_ recognizer: InkStrokeRecognizer) {
      switch recognizer.state {
      case .began, .changed:
        redraw(recognizer.points)
      case .ended:
        let points = recognizer.points
        redraw([])
        if points.count > 1 { onStroke?(points) }
      default:
        redraw([])
      }
    }

    /// Every other recognizer waits for the stroke, so none can claim the drag.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    private func redraw(_ points: [CGPoint]) {
      let path = UIBezierPath()
      if let first = points.first {
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
      }
      stroke.path = path.cgPath
    }
  }

  /// Recognises one stroke from the first touch: it begins at once, so no ink is lost to a movement
  /// threshold, and fails when a second finger arrives.
  final class InkStrokeRecognizer: UIGestureRecognizer {
    /// The stroke so far, in the view's coordinates.
    private(set) var points: [CGPoint] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      guard points.isEmpty, touches.count == 1, let touch = touches.first else {
        state = state == .possible ? .failed : .cancelled
        return
      }
      points = [touch.location(in: view)]
      state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
      guard let touch = touches.first else { return }
      points += (event.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: view) }
      state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      if let touch = touches.first { points.append(touch.location(in: view)) }
      state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      state = .cancelled
    }

    override func reset() {
      points = []
    }
  }
#endif
