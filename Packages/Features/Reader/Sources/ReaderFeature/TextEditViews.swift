import Core
import DesignSystem
import PDFEngine
import SwiftUI
import UIKit

/// What the person has typed for the text in hand, shared by the field and the bar.
@MainActor
@Observable
final class TextEditDraft {
  var text = ""
  /// Whether the field sits over the text on the page.
  ///
  /// `nil` while nothing is picked. It is decided once, when the text is picked and the page view
  /// has put it on screen (`ReaderView`), so the field never moves between the page and the bar
  /// while it is typed into.
  var isInPlace: Bool?
  /// Where the bar with Cancel and Done is on screen, in the window's space.
  ///
  /// The bar sits just above the keyboard, so the field over the page stays above the bar and is
  /// never under the keyboard, wherever the keyboard is or however tall it is.
  var barFrame: CGRect?
  /// Whether the field has the keyboard.
  ///
  /// The person can put the keyboard away to look over the page, as in Notes, and tap the field (or
  /// the keyboard button in the bar) to type again; the text in hand stays open either way.
  var isTyping = false
  /// The field on screen, so the bar can hand it the keyboard again.
  @ObservationIgnored weak var field: UITextView?

  /// Puts the keyboard away, keeping the text in hand.
  func hideKeyboard() {
    field?.resignFirstResponder()
  }

  /// Brings the keyboard back to the field, with the caret where it was.
  func showKeyboard() {
    field?.becomeFirstResponder()
  }

  /// Accepts what an input method is still composing, so what is committed is what the person sees.
  ///
  /// With Pinyin, kana or Hangul, the letters typed so far are only a draft until a word is
  /// chosen; Done tapped before that would otherwise put the raw letters ("zhongguo") on the page.
  func finishComposition() {
    guard let field, field.markedTextRange != nil else { return }
    field.unmarkText()
    text = field.text ?? ""
  }
}

/// Finishes the text in hand, from Done in the bar or Return in either field, and says what happened.
enum TextEditCommit {
  /// Commits what was typed, unless this text can be neither changed nor covered, where Done could
  /// only refuse again.
  @MainActor
  static func run(model: ReaderModel, draft: TextEditDraft) {
    guard model.textEditMessage != .cannotEditOrCover, !model.isCommittingTextEdit else { return }
    draft.finishComposition()
    Task {
      guard await model.commitTextEdit(draft.text) else { return }
      // What is announced is what happened: covered text is not changed text.
      let said =
        model.textEditNotice == .coveredInstead
        ? String(
          localized: "Your text covers the old text. The original is still in the file underneath.", bundle: .module)
        : String(localized: "Text changed", bundle: .module)
      UIAccessibility.post(notification: .announcement, argument: said)
    }
  }
}

/// A text field for editing existing text: the document's own font and colour, and none of the
/// keyboard's rewriting, so what is typed is what goes on the page.
///
/// It is as tall as its text at the width it is given, so none of the text is ever out of view:
/// a line longer than the width wraps onto more lines instead of running past the edge. Only where
/// it is given less height than its text, or held to `maximumLines`, does it scroll up and down.
struct TextEditField: UIViewRepresentable {
  @Bindable var draft: TextEditDraft
  /// The font to show the text in, when the field sits over the text on the page.
  var font: UIFont?
  var color: UIColor?
  /// The most lines shown before the field scrolls; `nil` for as many as the space it is given.
  var maximumLines: Int?
  var onSubmit: () -> Void
  /// Called for Escape on a hardware keyboard, which the text view would otherwise keep to itself.
  var onCancel: (() -> Void)?
  /// Whether typing is held, while what was typed is being committed: letters typed then would be
  /// lost when the field closes.
  var isLocked = false
  /// Told where the caret is, in the field's own space, after each change the person types, so the
  /// page can be scrolled to keep it in view; `nil` where the field keeps its caret in view by itself.
  var onCaretMoved: ((CGRect) -> Void)?

  func makeUIView(context: Context) -> TextEditTextView {
    let field = TextEditTextView()
    field.delegate = context.coordinator
    // Smart quotes, dashes and corrections would change what the person typed after they typed it.
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.smartQuotesType = .no
    field.smartDashesType = .no
    field.smartInsertDeleteType = .no
    field.spellCheckingType = .no
    field.returnKeyType = .done
    field.adjustsFontForContentSizeCategory = font == nil
    field.font = resolvedFont
    field.accessibilityIdentifier = "reader.textEdit.field"
    field.accessibilityLabel = String(localized: "Text to change", bundle: .module)
    draft.field = field
    return field
  }

  func updateUIView(_ field: TextEditTextView, context: Context) {
    context.coordinator.parent = self
    field.onEscape = onCancel
    if field.text != draft.text {
      field.text = draft.text
      field.invalidateIntrinsicContentSize()
    }
    if field.font != resolvedFont {
      field.font = resolvedFont
      field.invalidateIntrinsicContentSize()
    }
    field.textColor = color ?? .label
    if !context.coordinator.hasFocused {
      context.coordinator.hasFocused = true
      // After this update, so the field is in a window when it asks for the keyboard.
      Task { @MainActor in
        field.becomeFirstResponder()
        // The caret starts after the last letter, and is shown there.
        field.selectedRange = NSRange(location: (field.text ?? "").utf16.count, length: 0)
        field.revealSelection()
        // VoiceOver goes to the field that just opened, not to whatever it was reading.
        UIAccessibility.post(notification: .layoutChanged, argument: field)
      }
    }
  }

  /// As wide as offered, and as tall as the text at that width: the field is never smaller than
  /// what it holds, except where it is held to fewer lines or less height, where it scrolls.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView field: TextEditTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
    var height = field.fittingHeight(for: width)
    if let maximumLines, let font = field.font {
      height = min(height, ceil(font.lineHeight * CGFloat(maximumLines)))
    }
    if let limit = proposal.height, limit.isFinite { height = min(height, limit) }
    return CGSize(width: width, height: height)
  }

  private var resolvedFont: UIFont { font ?? UIFont.preferredFont(forTextStyle: .body) }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  @MainActor
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: TextEditField
    var hasFocused = false

    init(_ parent: TextEditField) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      changed(textView)
    }

    /// Takes in what the field now holds, keeps the caret in view and reports where it is.
    private func changed(_ textView: UITextView) {
      parent.draft.text = textView.text ?? ""
      // The field grows with its text; the caret stays in view where it is held to a height.
      textView.invalidateIntrinsicContentSize()
      (textView as? TextEditTextView)?.revealSelection()
      // And the page is scrolled to keep it in view, as Notes does, even after the person scrolled
      // the page away. The caret's place inside the field is right already, before the field is
      // laid out again at its new height: the field grows down from its top, which stays where it is.
      if let onCaretMoved = parent.onCaretMoved, let end = textView.selectedTextRange?.end {
        onCaretMoved(textView.caretRect(for: end))
      }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.draft.isTyping = true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      parent.draft.isTyping = false
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      (textView as? TextEditTextView)?.revealSelection()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      // Letters typed while the edit is being made would vanish with the field.
      guard !parent.isLocked else { return false }
      guard text.contains(where: \.isNewline) else { return true }
      // Return is Done: the text is one line on the page, however many it wraps onto here. Only a
      // single line break is Return; several pasted together, or line breaks inside pasted or
      // dictated words, become spaces, so nothing pasted ever finishes the edit by itself.
      if text == "\n" || text == "\r" || text == "\r\n" {
        parent.onSubmit()
        return false
      }
      let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
      if let replaced = textView.textRange(from: range) {
        textView.replace(replaced, withText: flattened.isEmpty ? " " : flattened)
        // Not left to UIKit: a replacement made here must reach the draft, or the next update would
        // put the old text back.
        changed(textView)
      }
      return false
    }
  }
}

/// The text view behind `TextEditField`: the system's own text view, wrapping its text to its
/// width, with nothing around the text so the letters sit where the page's letters are.
///
/// It replaces a text view held to one unbroken line, which showed a long line only as far as the
/// edge of the screen and hid the rest, and the caret with it, behind a sideways scroll (the
/// owner's report, 2026-10-08).
final class TextEditTextView: UITextView {
  private var laidOutSize = CGSize.zero
  /// What Escape on a hardware keyboard does: Cancel, as in the bar.
  var onEscape: (() -> Void)?

  init() {
    super.init(frame: .zero, textContainer: nil)
    backgroundColor = .clear
    textContainerInset = .zero
    textContainer.lineFragmentPadding = 0
    textContainer.widthTracksTextView = true
    isScrollEnabled = true
    alwaysBounceVertical = false
    alwaysBounceHorizontal = false
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  /// How tall all of the text is when it is laid out at a width.
  func fittingHeight(for width: CGFloat) -> CGFloat {
    ceil(sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
  }

  /// Scrolls the caret, or the end of the selection, into view.
  func revealSelection() {
    scrollRangeToVisible(selectedRange)
  }

  /// Escape cancels the text in hand, unless it is ending an input method's composition.
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if markedTextRange == nil, let onEscape, presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
      onEscape()
      return
    }
    super.pressesBegan(presses, with: event)
  }

  /// A new size (a rotation, the keyboard, a wrap onto another line) keeps the caret in view.
  override func layoutSubviews() {
    super.layoutSubviews()
    #if DEBUG
      TextEditGeometryLog.textView(self)
    #endif
    guard bounds.size != laidOutSize else { return }
    laidOutSize = bounds.size
    if isFirstResponder { revealSelection() }
  }
}

extension UITextView {
  /// A text range for a range of the view's text, counted in UTF-16 units.
  fileprivate func textRange(from range: NSRange) -> UITextRange? {
    guard let start = position(from: beginningOfDocument, offset: range.location),
      let end = position(from: start, offset: range.length)
    else { return nil }
    return textRange(from: start, to: end)
  }
}

/// The editor for a piece of existing text, laid over the page.
///
/// For upright text it puts the field on the line itself, in the line's own font at the page's own
/// size, so the text is edited where it is, as in Preview. The page keeps the zoom the person chose
/// and stays free: it can be scrolled and pinched while the field is open, and the field moves with
/// its line. What is typed beyond the line wraps down, to the width of the page's text
/// (`TextEditPlacement`), and the page scrolls under the field to keep it clear of the keyboard, as
/// in Notes.
///
/// The page is moved for the field only when something the person did to the text asks for it: the
/// field opening, the keyboard or the screen changing, or a letter typed. Never because the field
/// moved or grew with the page: an earlier layer made room whenever the field's height changed,
/// which a pinch changes on every frame and a scroll can change by a pixel, and pulled the page back
/// under the person's finger, so it could be neither scrolled nor zoomed away from the line (the
/// owner's report, 2026-10-08).
struct TextEditLayer: View {
  let model: ReaderModel
  let selection: TextRegionSelection
  let draft: TextEditDraft
  /// Where the field is in the layer, as last laid out.
  @State private var fieldFrame: CGRect?
  /// Whether room was made for the field when it first appeared.
  @State private var madeRoomOnOpen = false

  /// The name of the layer's own space, in which the line, the visible area and the field are placed.
  nonisolated static let space = "reader.textEdit.layer"

  /// How far the field's cover reaches past either end of the line, so the old letters' edges are
  /// covered: as far as the outline drawn around each line (`TextRegionOverlayView`).
  nonisolated static let coverOutset: CGFloat = 2

  /// Whether the field can sit on the text: the page view has the text on screen, and the text is
  /// upright on screen, on the page and with the page itself not turned.
  ///
  /// Turned text is edited in the bar, which is always in view. On a turned page a line's frame is
  /// tall and narrow, and a field laid along it would hold a letter or two to a line.
  static func fitsInPlace(_ selection: TextRegionSelection, anchor: TextEditAnchor?) -> Bool {
    guard let anchor, anchor.selection == selection else { return false }
    return selection.region.isUpright && !anchor.isPageTurned
  }

  var body: some View {
    GeometryReader { geometry in
      // Nothing here but the field takes touches: the page under it scrolls and zooms as usual.
      ZStack(alignment: .topLeading) {
        if draft.isInPlace == true, let anchor = model.controller?.textEditAnchor, anchor.selection == selection {
          let visible = Self.visibleArea(in: geometry, below: draft.barFrame)
          TextEditPlacementLayout(line: anchor.lineFrame, column: anchor.columnFrame) {
            field(scale: anchor.scale) { caret in
              // The caret, from the text view's space into the layer's: the text view sits inside
              // the cover, `coverOutset` in from its left edge, at its top. Worked out here, in the
              // layer, rather than through the window, whose space need not match SwiftUI's in a
              // split view.
              guard let fieldFrame else { return }
              reveal(caret.offsetBy(dx: fieldFrame.minX + Self.coverOutset, dy: fieldFrame.minY), in: visible)
            }
            .onGeometryChange(for: CGRect.self) {
              $0.frame(in: .named(Self.space))
            } action: {
              fieldFrame = $0
              if !madeRoomOnOpen {
                madeRoomOnOpen = true
                makeRoom(for: $0, in: visible)
              }
            }
          }
          // The keyboard coming up, the bar growing, or the screen turning: what can be seen got
          // shorter and may now be over the field. Putting the keyboard away moves nothing.
          .onChange(of: visible.maxY) { before, after in
            if after < before, let fieldFrame { makeRoom(for: fieldFrame, in: visible) }
          }
          #if DEBUG
            TextEditGeometryOverlay(line: anchor.lineFrame, visible: visible, scale: anchor.scale)
          #endif
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .coordinateSpace(.named(Self.space))
    }
    .accessibilityElement(children: .contain)
  }

  /// Distances smaller than this are rounding, not a field out of view.
  private static let scrollTolerance: CGFloat = 0.5

  /// Scrolls the page so the whole field is above the bar and the keyboard, or its top where it is
  /// taller than the room there is.
  private func makeRoom(for field: CGRect, in visible: CGRect) {
    let distance = TextEditPlacement.scrollDistance(for: field, in: visible, margin: Spacing.s100)
    if abs(distance) > Self.scrollTolerance { model.controller?.scrollPickedText(by: distance) }
  }

  /// Scrolls the page so the caret is in view, up and down and, on a zoomed page, across.
  private func reveal(_ caret: CGRect, in visible: CGRect) {
    let distance = TextEditPlacement.revealDistance(for: caret, in: visible, margin: Spacing.s100)
    guard abs(distance.dx) > Self.scrollTolerance || abs(distance.dy) > Self.scrollTolerance else { return }
    model.controller?.scrollPickedText(by: distance.dy, across: distance.dx)
  }

  /// The field, and its cover over the old words.
  private func field(scale: CGFloat, onCaretMoved: @escaping (CGRect) -> Void) -> some View {
    TextEditField(
      draft: draft, font: Self.font(for: selection.region, scale: scale),
      color: Self.color(for: selection.region),
      onSubmit: { TextEditCommit.run(model: model, draft: draft) },
      onCancel: { if !model.isCommittingTextEdit { model.cancelTextEdit() } },
      isLocked: model.isCommittingTextEdit,
      onCaretMoved: onCaretMoved
    )
    #if DEBUG
      .modifier(TextEditGeometryOverlay.Measure(role: .textView))
    #endif
    .padding(.horizontal, Self.coverOutset)
    // The field covers the old words while new ones are typed, in a colour the text shows on, and
    // stands a little off the page, so it reads as a field being typed into.
    // The shadow is the cover's own, not the field's: shadowing the field would flatten the text
    // view into one layer, and a tap inside it would no longer move the caret.
    .background {
      Rectangle().fill(Self.isLight(selection.region) ? Color.black : Color.white)
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
    // Drawn only: a touch on the edge of the field reaches the text, not the line around it.
    .overlay { Rectangle().strokeBorder(Color.ds.selection, lineWidth: 1).allowsHitTesting(false) }
    // The caret too: in the app's red it would read as a mistake in the text.
    .tint(Color.ds.selection)
    #if DEBUG
      .modifier(TextEditGeometryOverlay.Measure(role: .editor))
    #endif
  }

  /// The part of the layer that is not under the bars at its top or the bar and keyboard below.
  static func visibleArea(in geometry: GeometryProxy, below bar: CGRect?) -> CGRect {
    let top = geometry.safeAreaInsets.top
    var bottom = geometry.size.height
    if let bar {
      // The bar is outside the layer; both are measured in the window's space.
      bottom = min(bottom, bar.minY - geometry.frame(in: .global).minY)
    }
    return CGRect(x: 0, y: top, width: geometry.size.width, height: max(0, bottom - top))
  }

  /// Whether the region's text is light, so it needs a dark field to be seen while it is typed.
  ///
  /// Decided by which cover, black or white, gives the text more contrast, from the colour's
  /// relative luminance (WCAG 2), not from its sRGB values: a mid grey such as 0.55 read as dark by
  /// the raw values and got a white cover at about 3.4:1.
  static func isLight(_ region: EditableTextRegion) -> Bool {
    let color = region.style.color
    func linear(_ value: Double) -> Double {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let luminance =
      0.2126 * linear(Double(color.red)) + 0.7152 * linear(Double(color.green)) + 0.0722 * linear(Double(color.blue))
    // Contrast against white is 1.05 / (L + 0.05); against black, (L + 0.05) / 0.05.
    return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
  }

  /// The region's own font at its size on screen, or the closest the system has.
  static func font(for region: EditableTextRegion, scale: CGFloat) -> UIFont {
    let size = max(1, region.style.pointSize * scale)
    if let exact = UIFont(name: region.style.fontName, size: size) { return exact }
    var traits: UIFontDescriptor.SymbolicTraits = []
    if region.style.isBold { traits.insert(.traitBold) }
    if region.style.isItalic { traits.insert(.traitItalic) }
    let base =
      UIFont(name: region.style.isMonospaced ? "Courier" : "Helvetica", size: size) ?? .systemFont(ofSize: size)
    return base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: size) } ?? base
  }

  /// The region's own colour.
  ///
  /// A colour read from the person's document, not a design colour.
  static func color(for region: EditableTextRegion) -> UIColor {
    let color = region.style.color
    return UIColor(cgColor: CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
  }
}

/// Puts the editor on its line, after asking it how tall its text is.
///
/// The text is measured first and the place worked out from that, in one layout pass, so the
/// editor is never drawn smaller than its text and then corrected.
struct TextEditPlacementLayout: Layout {
  /// Where the line is, in the layer's space.
  var line: CGRect
  /// The line widened to the right edge of the page's text, in the layer's space.
  var column: CGRect

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let editor = subviews.first else { return }
    // The cover reaches a little past both ends of the text; the place is worked out for the text.
    let outset = TextEditLayer.coverOutset
    let frame = TextEditPlacement.editor(over: line, column: column) { width in
      editor.sizeThatFits(ProposedViewSize(width: width + 2 * outset, height: nil)).height
    }
    editor.place(
      at: CGPoint(x: bounds.minX + frame.minX - outset, y: bounds.minY + frame.minY),
      anchor: .topLeading,
      proposal: ProposedViewSize(width: frame.width + 2 * outset, height: frame.height))
  }
}

/// Cancel and Done for the text in hand, above the keyboard, with anything the person needs to know.
///
/// For text the field cannot sit over (rotated, or tiny on screen) the field is here instead.
struct TextEditBar: View {
  let model: ReaderModel
  let draft: TextEditDraft

  /// The most lines of text the field in the bar shows before it scrolls.
  ///
  /// `Assumption:` four lines keep Cancel and Done and part of the page in view above the keyboard
  /// on the smallest supported iPhone in landscape; checked in the device test plan.
  static let maximumLines = 4

  /// The field is here when the layer found it cannot sit over the text.
  private var showsField: Bool { draft.isInPlace == false }

  /// Whether this text can be neither changed nor covered, so that Done could only refuse again.
  private var isDeadEnd: Bool { model.textEditMessage == .cannotEditOrCover }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s100) {
      if let message = model.textEditMessage {
        TextEditMessageLabel(message: message)
      }
      HStack(spacing: Spacing.s150) {
        Button(role: .cancel) {
          model.cancelTextEdit()
        } label: {
          // Where nothing more can be done with this text, the one button says so.
          if isDeadEnd { Text("Close", bundle: .module) } else { Text("Cancel", bundle: .module) }
        }
        .minimumTarget()
        // While the edit is being made it cannot be called back: Cancel then would close the bar
        // and the page would still change.
        .disabled(model.isCommittingTextEdit)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("reader.textEdit.cancel")
        if showsField {
          TextEditField(
            draft: draft, maximumLines: Self.maximumLines, onSubmit: commit,
            onCancel: { if !model.isCommittingTextEdit { model.cancelTextEdit() } },
            isLocked: model.isCommittingTextEdit)
            .padding(.horizontal, Spacing.s100)
            .frame(minHeight: Sizes.targetMinimum)
            .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
          Spacer(minLength: 0)
          if !isDeadEnd { keyboardButton }
        }
        if model.isCommittingTextEdit {
          ProgressView().accessibilityLabel(Text("Changing the text…", bundle: .module))
        } else if !isDeadEnd {
          Button(action: commit) {
            Text("Done", bundle: .module).bold()
          }
          .minimumTarget()
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("reader.textEdit.done")
        }
      }
      .frame(minHeight: Sizes.targetMinimum)
    }
    .padding(.horizontal, Spacing.s200)
    .padding(.vertical, Spacing.s100)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding(.horizontal, Spacing.s200)
    .padding(.bottom, Spacing.s100)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("reader.textEdit.actionBar")
  }

  /// Puts the keyboard away to look over the page, or brings it back, as the button in Notes does;
  /// the text in hand stays open.
  private var keyboardButton: some View {
    Button {
      if draft.isTyping { draft.hideKeyboard() } else { draft.showKeyboard() }
    } label: {
      if draft.isTyping {
        Label {
          Text("Hide keyboard", bundle: .module)
        } icon: {
          Image(systemName: "keyboard.chevron.compact.down")
        }
      } else {
        Label {
          Text("Show keyboard", bundle: .module)
        } icon: {
          Image(systemName: "keyboard")
        }
      }
    }
    .labelStyle(.iconOnly)
    .minimumTarget()
    .accessibilityIdentifier("reader.textEdit.keyboard")
  }

  private func commit() {
    TextEditCommit.run(model: model, draft: draft)
  }
}

/// One plain sentence about the page or the text in hand: what is so, that nothing was changed
/// where that is true, and what to do next.
struct TextEditMessageLabel: View {
  let message: ReaderModel.TextEditMessage

  var body: some View {
    text.font(.footnote).fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("reader.textEdit.message")
  }

  private var text: Text {
    switch message {
    case .pageIsImage: Text("This PDF contains images rather than editable text.", bundle: .module)
    case .pageNotEditable: Text("This page can’t be edited. Nothing was changed.", bundle: .module)
    case .tooLong: Text("That’s too long to fit here. Try fewer words; nothing was changed.", bundle: .module)
    case .unsupportedCharacters:
      Text("Some of those characters can’t be used here. Nothing was changed.", bundle: .module)
    case .cannotEdit: Text("This text can’t be changed. Nothing was changed.", bundle: .module)
    case .fontMatched: Text("The font will be matched as closely as possible.", bundle: .module)
    case .coversOriginal:
      Text("Your text will cover this text. The original stays in the file underneath.", bundle: .module)
    case .coversOriginalBriefly: Text("Covers the original text.", bundle: .module)
    case .lookingForText: Text("Looking for text on this page…", bundle: .module)
    case .noEditableText: Text("No text on this page can be edited.", bundle: .module)
    case .tookTooLong: Text("This is taking too long. Nothing was changed. Try again.", bundle: .module)
    case .somethingInTheWay: Text("There isn’t room for it there. Nothing was moved.", bundle: .module)
    case .cannotEditOrCover:
      Text("This text can’t be changed or covered here. Nothing was changed.", bundle: .module)
    }
  }
}

/// What the reader says at the bottom of the page while text is being edited and nothing is picked:
/// how to start, or why this page has nothing to edit and what to do instead.
struct TextEditHint: View {
  let model: ReaderModel

  var body: some View {
    Group {
      if model.textEditNotice == .coveredInstead {
        TextEditNoticeCard(model: model)
      } else if let message = model.textEditMessage {
        VStack(spacing: Spacing.s100) {
          TextEditMessageLabel(message: message)
          if message == .pageIsImage, model.canRecognizeText {
            Button {
              Task {
                await model.endTextEditing()
                model.recognizeText()
              }
            } label: {
              Text("Recognise text", bundle: .module)
            }
            .buttonStyle(.bordered)
            .minimumTarget()
            .accessibilityIdentifier("reader.textEdit.recognise")
          }
        }
        .padding(Spacing.s150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      } else if model.showsTextEditStartHint {
        Label {
          Text("Tap text to change it. Hold and drag to move it.", bundle: .module)
        } icon: {
          Image(systemName: "hand.tap")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Spacing.s200)
        .padding(.vertical, Spacing.s100)
        .background(.regularMaterial, in: Capsule())
      }
    }
    .accessibilityIdentifier("reader.textEdit.hint")
  }
}

/// Tells the person that their text was placed over the old text, which is still in the file, and
/// lets them take that back.
///
/// It stays until they act on it: someone changing a name must not go on believing the old name
/// is gone.
struct TextEditNoticeCard: View {
  let model: ReaderModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s100) {
      Text("Your text covers the old text. The original is still in the file underneath.", bundle: .module)
        .font(.subheadline)
        .foregroundStyle(Color.ds.labelPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("reader.textEdit.notice")
      HStack(spacing: Spacing.s150) {
        Button {
          Task { await model.undoCoverInstead() }
        } label: {
          Text("Undo", bundle: .module)
        }
        .accessibilityIdentifier("reader.textEdit.notice.undo")
        Spacer(minLength: 0)
        Button {
          model.dismissTextEditNotice()
        } label: {
          Text("OK", bundle: .module).bold()
        }
        .accessibilityIdentifier("reader.textEdit.notice.ok")
      }
      .frame(minHeight: Sizes.targetMinimum)
    }
    .padding(Spacing.s150)
    .frame(maxWidth: 360)
    // Opaque: it lies over the page's words, and words behind a see-through card lower the
    // contrast of the words on it. The shadow is the shape's alone, not each word's.
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.ds.backgroundGroupedElevated)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ds.separator) }
    .padding(.horizontal, Spacing.s200)
    .accessibilityElement(children: .contain)
  }
}
