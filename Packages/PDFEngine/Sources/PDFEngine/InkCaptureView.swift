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
    /// What the drag draws, so the preview matches what will be added.
    var tool = DrawingTool.pen
    /// Asked where a touch lands, before it becomes a stroke: `false` leaves the touch to the page
    /// view, which moves what is there instead of drawing over it.
    var shouldDraw: ((CGPoint) -> Bool)? {
      didSet { recognizer.canStart = shouldDraw }
    }
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
      guard let first = points.first, let last = points.last else {
        stroke.path = nil
        return
      }
      let box = CGRect(
        x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
      let path: UIBezierPath
      switch tool {
      case .pen:
        path = UIBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
      case .rectangle:
        path = UIBezierPath(rect: box)
      case .oval:
        path = UIBezierPath(ovalIn: box)
      case .arrow:
        path = UIBezierPath()
        path.move(to: first)
        path.addLine(to: last)
        let angle = atan2(last.y - first.y, last.x - first.x)
        for side in [CGFloat.pi * 5 / 6, -CGFloat.pi * 5 / 6] {
          path.move(to: last)
          path.addLine(to: CGPoint(x: last.x + 14 * cos(angle + side), y: last.y + 14 * sin(angle + side)))
        }
      }
      stroke.path = path.cgPath
    }
  }

  /// Recognises one stroke from the first touch: it begins at once, so no ink is lost to a movement
  /// threshold, and fails when a second finger arrives.
  final class InkStrokeRecognizer: UIGestureRecognizer {
    /// The stroke so far, in the view's coordinates.
    private(set) var points: [CGPoint] = []
    /// Whether a stroke may start at a point; when it may not, the recognizer fails at once and
    /// the recognizers that waited for it take the touch.
    var canStart: ((CGPoint) -> Bool)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      guard points.isEmpty, touches.count == 1, let touch = touches.first else {
        state = state == .possible ? .failed : .cancelled
        return
      }
      if let canStart, !canStart(touch.location(in: view)) {
        state = .failed
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
