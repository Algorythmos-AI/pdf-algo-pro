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
  /// `nil` until the page has settled and the layer has measured where the text is. The layer
  /// decides once, and the bar follows.
  var isInPlace: Bool?
}

/// A plain text field for editing existing text: the document's own font and colour, and none of
/// the keyboard's rewriting, so what is typed is what goes on the page.
struct TextEditField: UIViewRepresentable {
  @Bindable var draft: TextEditDraft
  /// The font to show the text in, when the field sits over the text on the page.
  var font: UIFont?
  var color: UIColor?
  var onSubmit: () -> Void

  func makeUIView(context: Context) -> SingleLineTextView {
    let field = SingleLineTextView()
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
    field.accessibilityIdentifier = "reader.textEdit.field"
    field.accessibilityLabel = String(localized: "Text to change", bundle: .module)
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  func updateUIView(_ field: SingleLineTextView, context: Context) {
    context.coordinator.parent = self
    if field.text != draft.text { field.show(draft.text) }
    field.font = font ?? UIFont.preferredFont(forTextStyle: .body)
    field.textColor = color ?? .label
    field.setNeedsLayout()
    if !context.coordinator.hasFocused {
      context.coordinator.hasFocused = true
      // After this update, so the field is in a window when it asks for the keyboard.
      Task { @MainActor in field.becomeFirstResponder() }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  @MainActor
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: TextEditField
    var hasFocused = false

    init(_ parent: TextEditField) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.draft.text = textView.text ?? ""
      // Typing does not go through `text`, so the scrolling area is fitted here, and the caret is
      // kept in view at the end of a line that has grown.
      (textView as? SingleLineTextView)?.fitLine()
      textView.scrollRangeToVisible(textView.selectedRange)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      guard text.contains(where: \.isNewline) else { return true }
      // Return is Done. A line that is pasted in with line breaks is one line here: the breaks
      // become spaces.
      if text.allSatisfy(\.isNewline) {
        parent.onSubmit()
      } else if let replaced = textView.textRange(from: range) {
        textView.replace(replaced, withText: text.split(whereSeparator: \.isNewline).joined(separator: " "))
      }
      return false
    }
  }
}

/// One line of text to type into, which scrolls sideways under a finger when it is longer than
/// the field.
///
/// A text field shows a long line only around its caret, and cannot be swiped: a line of small
/// print, zoomed in to be read, is several screens wide, and its start could not be got back to
/// (the owner's reports, 2026-10-07). This is a text view kept to one line, so it scrolls like any
/// scrolling text and still follows the caret.
final class SingleLineTextView: UITextView {
  init() {
    // The text system is put together here, not left to the view: left to itself the view makes
    // a container as wide as it is, and the line would be cut off at the field's edge.
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    // The line is as long as its words; the view is a window onto it.
    let container = NSTextContainer(
      size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = false
    container.heightTracksTextView = false
    container.lineFragmentPadding = 0
    container.maximumNumberOfLines = 1
    container.lineBreakMode = .byClipping
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    super.init(frame: .zero, textContainer: container)
    backgroundColor = .clear
    textContainerInset = .zero
    isScrollEnabled = true
    alwaysBounceHorizontal = true
    alwaysBounceVertical = false
    showsHorizontalScrollIndicator = false
    showsVerticalScrollIndicator = false
    isDirectionalLockEnabled = true
    contentInsetAdjustmentBehavior = .never
    isBuilt = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  /// False while the text view is still being put together, when its text container is not there yet.
  private var isBuilt = false

  /// How wide the line of text is, laid out.
  var lineWidth: CGFloat {
    keepLineUnbroken()
    layoutManager.ensureLayout(for: textContainer)
    return ceil(layoutManager.usedRect(for: textContainer).width)
  }

  /// Puts the container back to "as wide as the words".
  ///
  /// A scrolling text view sets its container to its own width whenever it lays out, whatever the
  /// container was told, so this is said again each time.
  private func keepLineUnbroken() {
    if textContainer.widthTracksTextView { textContainer.widthTracksTextView = false }
    if textContainer.size.width < 100_000 {
      textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    fitLine()
  }

  /// Shows a line of text, and fits the scrolling area to it.
  func show(_ line: String) {
    text = line
    fitLine()
  }

  /// Sizes the scrolling area to the one line of text, and centres the line in the field's height.
  ///
  /// Called on every layout and every change to the text, because the text view does not always
  /// lay itself out again when its text changes.
  func fitLine() {
    guard isBuilt else { return }
    keepLineUnbroken()
    layoutManager.ensureLayout(for: textContainer)
    let used = layoutManager.usedRect(for: textContainer)
    // The line sits in the middle of the field's height, as a text field's does.
    let top = max(0, (bounds.height - used.height) / 2)
    if abs(textContainerInset.top - top) > 0.5 {
      textContainerInset = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
    }
    let size = scrollSize
    if super.contentSize != size { super.contentSize = size }
    if contentOffset.y != 0 { contentOffset.y = 0 }
  }

  /// Wide enough to scroll to either end, with room for the caret after the last letter; never
  /// tall enough to scroll up and down.
  private var scrollSize: CGSize {
    CGSize(width: max(bounds.width, lineWidth + 6), height: bounds.height)
  }

  /// The text view works out its own scrolling size whenever the text changes, from a line as wide
  /// as itself; whatever it asks for, it gets the size of the one unbroken line.
  override var contentSize: CGSize {
    get { super.contentSize }
    set { super.contentSize = isBuilt ? scrollSize : newValue }
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
/// It takes every touch, so the page stays still while the text is being changed, and for upright
/// text it puts the field exactly over the line, in the line's own font, so the text is edited
/// where it is.
struct TextEditLayer: View {
  let model: ReaderModel
  let selection: TextRegionSelection
  let draft: TextEditDraft
  @State private var frame: CGRect?
  @State private var height: CGFloat = 0

  /// The share of the reader's height, from the top, that stays clear of the keyboard and the
  /// editor's bar while text is being typed.
  ///
  /// Assumption: the keyboard with its bar takes a little over half of an iPhone's height; checked
  /// in the device test plan.
  static let clearShare = 0.45

  /// Whether the field can sit over the text: upright, big enough on screen to read, and where it
  /// can be seen while it is typed into.
  ///
  /// Text that the page could not scroll clear of the keyboard is edited in the bar instead, which
  /// is always in view.
  static func fitsInPlace(_ selection: TextRegionSelection, frame: CGRect?, within height: CGFloat? = nil) -> Bool {
    guard let frame, selection.region.isUpright else { return false }
    if let height, frame.maxY > height * clearShare { return false }
    return frame.height >= 12 && frame.minX >= 0 && frame.minY >= 0
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        // Nearly clear, so it is hit-tested: touches stop here while the editor is open.
        Color.black.opacity(0.001)
        if let frame, draft.isInPlace == true {
          let scale = model.controller?.selectedTextRegionScale ?? 1
          TextEditField(
            draft: draft, font: Self.font(for: selection.region, scale: scale),
            color: Self.color(for: selection.region),
            onSubmit: { Task { await model.commitTextEdit(draft.text) } }
          )
          .padding(.horizontal, 2)
          .frame(width: Self.fieldSpan(over: frame, in: geometry.size.width).width, height: frame.height)
          // The field covers the old words while new ones are typed, in a colour the text shows on.
          .background(Self.isLight(selection.region) ? Color.black : Color.white)
          .overlay(alignment: .bottom) { Rectangle().fill(Color.ds.selection).frame(height: 1.5) }
          // The caret too: in the app's red it would read as a mistake in the text.
          .tint(Color.ds.selection)
          .offset(x: Self.fieldSpan(over: frame, in: geometry.size.width).x, y: frame.minY)
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      height = $0
    }
    .task(id: selection) {
      // The page has just scrolled the text clear of the keyboard; read where it ended up.
      try? await Task.sleep(for: .milliseconds(80))
      let measured = model.controller?.selectedTextRegionFrame
      frame = measured
      draft.isInPlace = Self.fitsInPlace(selection, frame: measured, within: height > 0 ? height : nil)
    }
    .accessibilityElement(children: .contain)
  }

  /// The narrowest the field is, so there is always room to see a few words being typed.
  static let minimumFieldWidth: CGFloat = 140

  /// Where the field starts and how wide it is: from the start of the text to the edge of the
  /// reader, and never past it.
  ///
  /// A small line is zoomed in to be read, and may then be wider than the screen. A field as wide
  /// as the line ran off the screen with the end of the sentence in it, where the caret could not
  /// be seen or reached (the owner's report, 2026-10-07). Kept on screen, the field scrolls its
  /// own text as the caret moves, as any text field does.
  static func fieldSpan(over frame: CGRect, in width: CGFloat) -> (x: CGFloat, width: CGFloat) {
    // Right to the edge: a strip of page left beside the field shows the old words there.
    let edge = width
    let span = min(max(minimumFieldWidth, edge - (frame.minX - 2)), max(0, edge - Spacing.s100))
    // Text that starts close to the right edge: the field keeps its width and starts further left.
    let x = max(Spacing.s100, min(frame.minX - 2, edge - span))
    return (x, span)
  }

  /// Whether the region's text is light, so it needs a dark field to be seen while it is typed.
  static func isLight(_ region: EditableTextRegion) -> Bool {
    let color = region.style.color
    return 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue > 0.6
  }

  /// The region's own font at its size on screen, or the closest the system has.
  static func font(for region: EditableTextRegion, scale: CGFloat) -> UIFont {
    let size = max(8, region.style.pointSize * scale)
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

/// Cancel and Done for the text in hand, above the keyboard, with anything the person needs to know.
///
/// For text the field cannot sit over (rotated, or tiny on screen) the field is here instead.
struct TextEditBar: View {
  let model: ReaderModel
  let draft: TextEditDraft

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
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("reader.textEdit.cancel")
        if showsField {
          TextEditField(draft: draft, onSubmit: commit)
            .padding(.horizontal, Spacing.s100)
            .frame(minHeight: Sizes.targetMinimum)
            .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
          Spacer(minLength: 0)
        }
        if model.isCommittingTextEdit {
          ProgressView().accessibilityLabel(Text("Changing the text…", bundle: .module))
        } else if !isDeadEnd {
          Button(action: commit) {
            Text("Done", bundle: .module).bold()
          }
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

  private func commit() {
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
