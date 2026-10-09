#if DEBUG && canImport(UIKit)
  import UIKit
  import UIKit.UIGestureRecognizerSubclass
  import os

  /// Records, while a line is picked for editing, which view each touch lands on and what the
  /// page's scrolling and zooming do with it, in Debug builds launched with `-text-edit-touches`.
  ///
  /// It is how a locked page is told apart on a device: a touch that lands outside the page view
  /// never reaches its scroller, and a scroller that begins and is then pulled back is moved by
  /// something else. The log holds view types and gesture states only, never the document's words.
  @MainActor
  final class TextEditTouchLog: NSObject {
    /// Whether the app was launched to record touches while text is edited.
    static let isOn = ProcessInfo.processInfo.arguments.contains("-text-edit-touches")

    private weak var host: UIView?
    private weak var window: UIWindow?
    private let probe = TouchProbe(target: nil, action: nil)
    private var watched: [UIGestureRecognizer] = []
    private var names: [ObjectIdentifier: String] = [:]
    private let logger = Logger(subsystem: "com.algorythmos.pdfalgopro", category: "text-edit.touches")

    init(host: PDFReaderHostView) {
      self.host = host
      super.init()
      // It sees each touch and steps aside: it never recognizes, holds up or cancels anything.
      probe.cancelsTouchesInView = false
      probe.delaysTouchesBegan = false
      probe.delaysTouchesEnded = false
      probe.onTouch = { [weak self] touch in self?.touched(touch) }
      if let window = host.window {
        window.addGestureRecognizer(probe)
        self.window = window
      }
      if let scroller = host.pageScroller {
        watch(scroller.panGestureRecognizer, as: "scroll")
        if let pinch = scroller.pinchGestureRecognizer { watch(pinch, as: "zoom") }
      }
      for (index, recognizer) in (host.gestureRecognizers ?? []).enumerated() {
        watch(recognizer, as: "page \(type(of: recognizer)) \(index)")
      }
      logger.debug("started: scroll enabled \(host.pageScroller?.isScrollEnabled ?? false, privacy: .public)")
    }

    /// Takes the probe and the watchers away; nothing is left behind on the window or the page.
    func stop() {
      window?.removeGestureRecognizer(probe)
      for recognizer in watched { recognizer.removeTarget(self, action: nil) }
      watched = []
      logger.debug("stopped")
    }

    private func watch(_ recognizer: UIGestureRecognizer, as name: String) {
      recognizer.addTarget(self, action: #selector(changed(_:)))
      names[ObjectIdentifier(recognizer)] = name
      watched.append(recognizer)
    }

    @objc private func changed(_ recognizer: UIGestureRecognizer) {
      let name = names[ObjectIdentifier(recognizer)] ?? "?"
      let state = Self.text(recognizer.state)
      logger.debug("gesture \(name, privacy: .public) \(state, privacy: .public)")
    }

    private func touched(_ touch: UITouch) {
      let view = touch.view.map { String(describing: type(of: $0)) } ?? "none"
      let onPage = host.map { touch.view?.isDescendant(of: $0) ?? false } ?? false
      logger.debug("touch on \(view, privacy: .public), inside the page view \(onPage, privacy: .public)")
    }

    private static func text(_ state: UIGestureRecognizer.State) -> String {
      switch state {
      case .possible: "possible"
      case .began: "began"
      case .changed: "changed"
      case .ended: "ended"
      case .cancelled: "cancelled"
      case .failed: "failed"
      @unknown default: "unknown"
      }
    }
  }

  /// Sees each touch on the window as it lands, then steps aside: it never recognizes, so it holds
  /// up and cancels nothing.
  private final class TouchProbe: UIGestureRecognizer {
    var onTouch: ((UITouch) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      for touch in touches { onTouch?(touch) }
      state = .failed
    }
  }
#endif
