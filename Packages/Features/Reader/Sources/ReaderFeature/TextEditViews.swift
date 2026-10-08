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
    return field
  }

  func updateUIView(_ field: TextEditTextView, context: Context) {
    context.coordinator.parent = self
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
      parent.draft.text = textView.text ?? ""
      // The field grows with its text; the caret stays in view where it is held to a height.
      textView.invalidateIntrinsicContentSize()
      (textView as? TextEditTextView)?.revealSelection()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      (textView as? TextEditTextView)?.revealSelection()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      guard text.contains(where: \.isNewline) else { return true }
      // Return is Done: the text is one line on the page, however many it wraps onto here. A line
      // that is pasted in with line breaks is one line here: the breaks become spaces.
      if text.allSatisfy(\.isNewline) {
        parent.onSubmit()
      } else if let replaced = textView.textRange(from: range) {
        textView.replace(replaced, withText: text.split(whereSeparator: \.isNewline).joined(separator: " "))
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
/// It takes every touch, so the page stays still while the text is being changed, and for upright
/// text it puts the field over the line, in the line's own font, so the text is edited where it
/// is. The field is placed from what it holds (`TextEditPlacement`): it starts where the line
/// starts, is as tall as its text, wraps a line wider than the screen, and stays above the bar
/// and the keyboard.
struct TextEditLayer: View {
  let model: ReaderModel
  let selection: TextRegionSelection
  let draft: TextEditDraft

  /// The name of the layer's own space, in which the line, the visible area and the field are placed.
  static let space = "reader.textEdit.layer"

  /// How far the field's cover reaches past the start of the line, so the old letters' edges are
  /// covered: as far as the outline drawn around each line (`TextRegionOverlayView`).
  static let coverOutset: CGFloat = 2

  /// Whether the field can sit over the text: the page view has the text on screen, the text is
  /// upright, and it is big enough on screen to type over.
  ///
  /// Other text is edited in the bar, which is always in view.
  static func fitsInPlace(_ selection: TextRegionSelection, anchor: TextEditAnchor?) -> Bool {
    guard let anchor, anchor.selection == selection, selection.region.isUpright else { return false }
    return anchor.lineFrame.height >= TextEditPlacement.minimumInPlaceHeight
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        // Nearly clear, so it is hit-tested: touches stop here while the editor is open.
        Color.black.opacity(0.001)
        if draft.isInPlace == true, let anchor = model.controller?.textEditAnchor, anchor.selection == selection {
          let visible = Self.visibleArea(in: geometry, below: draft.barFrame)
          TextEditPlacementLayout(line: anchor.lineFrame, visible: visible, margin: Spacing.s100) {
            field(scale: anchor.scale)
          }
          #if DEBUG
            TextEditGeometryOverlay(line: anchor.lineFrame, visible: visible, scale: anchor.scale)
          #endif
        }
      }
      .coordinateSpace(.named(Self.space))
    }
    .accessibilityElement(children: .contain)
  }

  /// The field, its cover over the old words, and the line under it.
  private func field(scale: CGFloat) -> some View {
    TextEditField(
      draft: draft, font: Self.font(for: selection.region, scale: scale),
      color: Self.color(for: selection.region),
      onSubmit: { Task { await model.commitTextEdit(draft.text) } }
    )
    #if DEBUG
      .modifier(TextEditGeometryOverlay.Measure(role: .textView))
    #endif
    .padding(.leading, Self.coverOutset)
    // The text keeps clear of the screen's edge; the cover runs to it.
    .padding(.trailing, Spacing.s100)
    // The field covers the old words while new ones are typed, in a colour the text shows on.
    .background(Self.isLight(selection.region) ? Color.black : Color.white)
    .overlay(alignment: .bottom) { Rectangle().fill(Color.ds.selection).frame(height: 1.5) }
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

/// Puts the editor where `TextEditPlacement` says, after asking it how tall its text is.
///
/// The text is measured first and the place worked out from that, in one layout pass, so the
/// editor is never drawn smaller than its text and then corrected.
struct TextEditPlacementLayout: Layout {
  /// Where the line is, in the layer's space.
  var line: CGRect
  /// The part of the layer that can be seen.
  var visible: CGRect
  /// The space kept clear at the visible area's edges.
  var margin: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let editor = subviews.first else { return }
    let outset = TextEditLayer.coverOutset
    // The editor's cover starts a little before the text; the place is worked out for the text.
    let placed = TextEditPlacement.editor(over: line, in: visible, margin: margin) { width in
      editor.sizeThatFits(ProposedViewSize(width: width + outset, height: nil)).height
    }
    editor.place(
      at: CGPoint(x: bounds.minX + placed.frame.minX - outset, y: bounds.minY + placed.frame.minY),
      anchor: .topLeading,
      proposal: ProposedViewSize(width: placed.frame.width + outset, height: placed.frame.height))
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
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("reader.textEdit.cancel")
        if showsField {
          TextEditField(draft: draft, maximumLines: Self.maximumLines, onSubmit: commit)
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
