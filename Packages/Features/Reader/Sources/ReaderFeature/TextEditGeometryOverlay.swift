#if DEBUG
  import PDFEngine
  import SwiftUI
  import UIKit
  import UIKit.UIGestureRecognizerSubclass
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
        // What the field did, in numbers, for the UI tests to read and report.
        Color.clear.frame(width: 1, height: 1)
          .allowsHitTesting(false)
          .accessibilityElement()
          .accessibilityLabel(log.events.summary)
          .accessibilityIdentifier("reader.textEdit.debug")
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
    /// What happened to the field, as counts and caret places only.
    var events = Events()
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

    /// Counts of what happened to the field, and where its caret went, never what it holds.
    struct Events {
      /// Text views made for the field; more than one means the field was made again.
      var made = 0
      /// Times the field was handed the keyboard with the caret put after the last letter.
      var focused = 0
      /// Times the field's text was replaced from the draft.
      var replaced = 0
      /// Touches that reached the text view itself.
      var touches = 0
      /// The caret's place after each change of selection, oldest first, the last few only.
      var carets: [Int] = []
      /// The kind of view the window finds at the start of the field's first line, and the kinds
      /// of the views it sits in, nearest first.
      var hit = "none"
      /// The kind of view the latest touch on the window landed on, and whether that is the field.
      var lastTouch = "none"

      var summary: String {
        "made \(made) focused \(focused) replaced \(replaced) touches \(touches) "
          + "carets \(carets.map(String.init).joined(separator: ",")) hit \(hit) lastTouch \(lastTouch)"
      }
    }

    /// Records a change to the field, where the app was launched to show the editor's geometry.
    static func record(_ change: (inout Events) -> Void) {
      guard isOn else { return }
      change(&shared.events)
      if shared.events.carets.count > 8 { shared.events.carets.removeFirst() }
    }

    /// Records which view the window finds at the start of a text view's first line.
    static func hitTest(_ view: UITextView) {
      guard isOn, let window = view.window else { return }
      let point = view.convert(CGPoint(x: 2, y: 2), to: window)
      guard let found = window.hitTest(point, with: nil) else { return }
      let chain = sequence(first: found, next: \.superview).prefix(4).map { String(describing: type(of: $0)) }
      let entry = (found === view ? "field " : "") + chain.joined(separator: "<")
      if shared.events.hit != entry { record { $0.hit = entry } }
    }

    /// Records the kind of view each touch on the window lands on, while a text view is in it.
    final class TouchProbe: UIGestureRecognizer {
      weak var field: UIView?

      override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
          let name = touch.view.map { String(describing: type(of: $0)) } ?? "none"
          let onField = field.map { touch.view?.isDescendant(of: $0) ?? false } ?? false
          // Where the touch is against the field, in the field's own points and the window's.
          var place = "no field"
          if let field, let window = field.window {
            let inField = touch.location(in: field)
            let frame = field.convert(field.bounds, to: window)
            place =
              "at \(Int(inField.x)),\(Int(inField.y)) in field \(Int(frame.minX)),\(Int(frame.minY)) "
              + "\(Int(frame.width))x\(Int(frame.height)) inside \(field.bounds.contains(inField))"
          }
          TextEditGeometryLog.record { $0.lastTouch = "\(name) onField \(onField) \(place)" }
        }
        state = .failed
      }
    }

    private static func text(_ rect: CGRect) -> String {
      guard !rect.isNull else { return "none" }
      let whole = rect.integral
      return "(\(Int(whole.minX)),\(Int(whole.minY)) \(Int(whole.width))x\(Int(whole.height)))"
    }
  }
#endif
