#if DEBUG
  import PDFEngine
  import SwiftUI
  import UIKit
  import os

  /// Shows where the text editor's parts are, over the page, in Debug builds launched with
  /// `-text-edit-geometry`, and logs the numbers behind them.
  ///
  /// - Red: the picked line, where the page draws it.
  /// - Green: the editor, with the cover over the old words.
  /// - Blue: the text view inside it.
  /// - Purple: the text as the text view lays it out (drawn by `TextEditGeometryLog`).
  /// - Yellow: what can be seen, above the bar and the keyboard.
  ///
  /// The log holds numbers only, never the document's words, like `TextEditingDiagnostics`.
  struct TextEditGeometryOverlay: View {
    let line: CGRect
    let visible: CGRect
    let scale: CGFloat

    /// Which part of the editor a frame is of.
    enum Role {
      case editor
      case textView
    }

    /// Reports a view's frame in the layer's space.
    struct Measure: ViewModifier {
      let role: Role

      func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) {
          $0.frame(in: .named(TextEditLayer.space))
        } action: { frame in
          switch role {
          case .editor: TextEditGeometryLog.shared.editor = frame
          case .textView: TextEditGeometryLog.shared.textView = frame
          }
        }
      }
    }

    var body: some View {
      if TextEditGeometryLog.isOn {
        let log = TextEditGeometryLog.shared
        ZStack(alignment: .topLeading) {
          outline(visible, .yellow)
          outline(line, .red)
          if let editor = log.editor { outline(editor, .green) }
          if let textView = log.textView { outline(textView, .blue) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: [line, visible, log.editor ?? .null, log.textView ?? .null], initial: true) {
          log.layer(line: line, visible: visible, scale: scale)
        }
        // The room request's last steps, read by the UI tests into their failure messages, so a
        // field left out of view says why (`TextEditingUITests`).
        Color.clear.frame(width: 1, height: 1)
          .accessibilityElement()
          .accessibilityLabel(Text(verbatim: log.roomSummary))
          .accessibilityIdentifier("reader.textEdit.roomTrace")
      }
    }

    private func outline(_ rect: CGRect, _ color: Color) -> some View {
      Rectangle().stroke(color, lineWidth: 1).frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }
  }

  /// The editor's measurements, for `TextEditGeometryOverlay` and the log.
  @MainActor
  @Observable
  final class TextEditGeometryLog {
    static let shared = TextEditGeometryLog()

    /// Whether the app was launched to show the editor's geometry.
    static let isOn = ProcessInfo.processInfo.arguments.contains("-text-edit-geometry")

    var editor: CGRect?
    var textView: CGRect?
    /// The room request's last steps, oldest first, each with how many times in a row it was taken.
    private(set) var roomTrace: [(step: String, count: Int)] = []
    @ObservationIgnored private var lastLayer = ""
    @ObservationIgnored private var lastTextView = ""
    private let logger = Logger(
      subsystem: "com.algorythmos.pdfalgopro", category: "text-edit.geometry")

    /// Logs where the line, the visible area and the editor are, when that changes.
    func layer(line: CGRect, visible: CGRect, scale: CGFloat) {
      let editor = editor ?? .null
      let clipped = editor.isNull ? false : !visible.contains(editor.integral.insetBy(dx: 1, dy: 1))
      let entry =
        "line \(Self.text(line)) visible \(Self.text(visible)) editor \(Self.text(editor)) "
        + "textView \(Self.text(textView ?? .null)) scale \(scale) outsideVisible \(clipped)"
      guard entry != lastLayer else { return }
      lastLayer = entry
      logger.debug("layer \(entry, privacy: .public)")
    }

    /// The room request's last steps, on one line.
    var roomSummary: String {
      roomTrace.map { $0.count > 1 ? "\($0.step) x\($0.count)" : $0.step }.joined(separator: "; ")
    }

    /// Notes a step of the room request (`TextEditLayer`), the same step taken again in a row once.
    func room(_ step: String) {
      guard Self.isOn else { return }
      if let last = roomTrace.last, last.step == step {
        roomTrace[roomTrace.count - 1].count += 1
        return
      }
      roomTrace.append((step, 1))
      if roomTrace.count > 24 { roomTrace.removeFirst(roomTrace.count - 24) }
      logger.debug("room \(step, privacy: .public)")
    }

    /// Notes what the room request decided, with the numbers it decided from.
    func room(
      _ step: TextEditRoomRequest.Step, request: TextEditRoomRequest, anchor: TextEditAnchor, field: CGRect?,
      visible: CGRect, _ controller: PDFDocumentController
    ) {
      guard Self.isOn else { return }
      let size = controller.pageViewSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "none"
      let place = "line \(Self.text(anchor.lineFrame)) field \(Self.text(field ?? .null)) visible \(Self.text(visible))"
      switch step {
      case .wait(.notMeasured):
        room("wait notMeasured at \(Int(anchor.viewSize.width))x\(Int(anchor.viewSize.height)), view \(size)")
      case .wait(.notLaidOut):
        room("wait notLaidOut \(place)")
      case .wait(let reason):
        room("wait \(reason.rawValue)")
      case .scroll(let distance):
        room("scroll \(Int(distance.rounded())) \(place)")
      case .confirm:
        room("inView \(place)")
      case .done:
        let why = controller.isPageTouched ? "touched" : "scrolls \(request.scrolls) checks \(request.checks)"
        room("done \(why) \(place)")
      }
    }

    /// Logs the text view's own sizes and caret, and outlines its laid-out text in purple.
    static func textView(_ view: UITextView) {
      guard isOn else { return }
      let used = view.textLayoutManager?.usageBoundsForTextContainer ?? .null
      let caret = view.selectedTextRange.map { view.caretRect(for: $0.end) } ?? .null
      let entry =
        "frame \(text(view.frame)) contentSize \(view.contentSize.width)x\(view.contentSize.height) "
        + "container \(view.textContainer.size.width)x\(view.textContainer.size.height) used \(text(used)) "
        + "offset \(view.contentOffset.x),\(view.contentOffset.y) caret \(text(caret)) "
        + "caretVisible \(caret.isNull ? false : view.bounds.contains(caret.insetBy(dx: 0, dy: 1)))"
      outlineText(used, in: view)
      guard entry != shared.lastTextView else { return }
      shared.lastTextView = entry
      shared.logger.debug("textView \(entry, privacy: .public)")
    }

    private static func outlineText(_ used: CGRect, in view: UITextView) {
      let name = "textEditGeometry.used"
      let shape =
        view.layer.sublayers?.first { $0.name == name } as? CAShapeLayer
        ?? {
          let shape = CAShapeLayer()
          shape.name = name
          shape.fillColor = nil
          shape.strokeColor = UIColor.systemPurple.cgColor
          shape.lineWidth = 1
          view.layer.addSublayer(shape)
          return shape
        }()
      let inset = view.textContainerInset
      shape.path = used.isNull ? nil : UIBezierPath(rect: used.offsetBy(dx: inset.left, dy: inset.top)).cgPath
    }

    static func text(_ rect: CGRect) -> String {
      guard !rect.isNull else { return "none" }
      let whole = rect.integral
      return "(\(Int(whole.minX)),\(Int(whole.minY)) \(Int(whole.width))x\(Int(whole.height)))"
    }
  }
#endif
