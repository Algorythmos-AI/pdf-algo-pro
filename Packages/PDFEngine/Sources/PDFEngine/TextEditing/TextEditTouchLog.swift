#if DEBUG && canImport(UIKit)
  import Observation
  import UIKit
  import UIKit.UIGestureRecognizerSubclass
  import os

  /// Records, while a line is picked for editing, which view each touch lands on and what the
  /// page's scrolling and zooming do with it, in Debug builds launched with `-text-edit-touches`.
  ///
  /// It is how a locked page is told apart on a device: a touch that lands outside the page view
  /// never reaches its scroller, and a scroller that begins and is then pulled back is moved by
  /// something else. The log holds view types, gesture states and the page's place only, never the
  /// document's words. Its last lines are also kept in `TextEditTouchTrace`, which the UI tests read
  /// into their failure evidence (issue #188).
  @MainActor
  final class TextEditTouchLog: NSObject {
    /// Whether the app was launched to record touches while text is edited.
    static let isOn = ProcessInfo.processInfo.arguments.contains("-text-edit-touches")

    private weak var host: PDFReaderHostView?
    private weak var window: UIWindow?
    private let probe = TouchProbe(target: nil, action: nil)
    private var watched: [UIGestureRecognizer] = []
    private var names: [ObjectIdentifier: String] = [:]
    /// Where the page was last seen, to note a move no finger made (`pageMoved()`).
    private var lastOffset: CGPoint?
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
      note("started: scroll enabled \(host.pageScroller?.isScrollEnabled ?? false), \(place)")
    }

    /// Logs a line, and keeps it for the UI tests.
    func note(_ line: String) {
      logger.debug("\(line, privacy: .public)")
      TextEditTouchTrace.shared.note(line)
    }

    /// Notes a move of the page that no finger, pinch or glide made, once per frame it happens.
    ///
    /// Called on every frame while text is picked (`publishTextEditAnchor()`): a page the person let
    /// go of that then moves was moved by the app, and this says when and to where.
    func pageMoved() {
      guard let scroller = host?.pageScroller else { return }
      let offset = scroller.contentOffset
      defer { lastOffset = offset }
      guard let last = lastOffset, hypot(offset.x - last.x, offset.y - last.y) >= 1 else { return }
      guard !(scroller.isTracking || scroller.isDragging || scroller.isDecelerating || scroller.isZooming) else {
        return
      }
      note("page moved with no finger on it: y \(Int(last.y)) -> \(place)")
    }

    /// The page's place: its offset, the room above and below it, and how far it can scroll.
    private var place: String {
      guard let scroller = host?.pageScroller else { return "no scroller" }
      let inset = scroller.adjustedContentInset
      let highest = scroller.contentSize.height + inset.bottom - scroller.bounds.height
      return "y \(Int(scroller.contentOffset.y)) (from \(Int(-inset.top)) to \(Int(highest))), "
        + "tracking \(scroller.isTracking) dragging \(scroller.isDragging) decelerating \(scroller.isDecelerating)"
    }

    /// Takes the probe and the watchers away; nothing is left behind on the window or the page.
    func stop() {
      window?.removeGestureRecognizer(probe)
      for recognizer in watched { recognizer.removeTarget(self, action: nil) }
      watched = []
      note("stopped")
    }

    private func watch(_ recognizer: UIGestureRecognizer, as name: String) {
      recognizer.addTarget(self, action: #selector(changed(_:)))
      names[ObjectIdentifier(recognizer)] = name
      watched.append(recognizer)
    }

    @objc private func changed(_ recognizer: UIGestureRecognizer) {
      // Every state but the many "changed" of a moving finger, which say nothing a begin and an end
      // do not.
      guard recognizer.state != .changed else { return }
      let name = names[ObjectIdentifier(recognizer)] ?? "?"
      note("gesture \(name) \(Self.text(recognizer.state)), \(place)")
    }

    private func touched(_ touch: UITouch) {
      let view = touch.view.map { String(describing: type(of: $0)) } ?? "none"
      let onPage = host.map { touch.view?.isDescendant(of: $0) ?? false } ?? false
      let y = touch.window.map { Int(touch.location(in: $0).y) } ?? -1
      note("touch at y \(y) on \(view), inside the page view \(onPage), \(place)")
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

  /// The touch log's last lines, oldest first, each with the seconds since the first, for the UI
  /// tests: a Debug build shows them through `reader.textEdit.touchTrace` (`TextEditGeometryOverlay`),
  /// and `TextEditingUITests` copies them into a failure's evidence, so one failing run says which
  /// gesture took a drag and what moved the page (issue #188).
  @MainActor
  @Observable
  public final class TextEditTouchTrace {
    /// The one trace, which every touch log of the app writes to.
    public static let shared = TextEditTouchTrace()

    /// Whether the app was launched to record touches while text is edited.
    public static var isOn: Bool { TextEditTouchLog.isOn }

    private(set) var lines: [String] = []
    @ObservationIgnored private var start: Date?

    /// The kept lines, on one line.
    public var summary: String { lines.joined(separator: " | ") }

    func note(_ line: String) {
      let now = Date()
      let start = self.start ?? now
      self.start = start
      lines.append(String(format: "%.2f ", now.timeIntervalSince(start)) + line)
      if lines.count > 60 { lines.removeFirst(lines.count - 60) }
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
