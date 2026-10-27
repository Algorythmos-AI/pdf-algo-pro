import AccessibilityIDs
import DesignSystem
import PDFEngine
import SwiftUI

/// The bar shown while an annotation is selected (F3): what it is, and what can be done with it.
struct SelectionBar: View {
  let selection: AnnotationSelection
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onDone: () -> Void
  let onMove: (CGSize) -> Void
  let onResize: (CGFloat) -> Void
  let onColor: (AnnotationColor) -> Void
  var onCopy: () -> Void = {}
  var onCut: () -> Void = {}
  var onDuplicate: () -> Void = {}

  /// How far one step of "Move" goes, in points; page space runs up, so up is positive.
  private static let step: CGFloat = 12
  /// The space around the row.
  static let padding = Spacing.s150
  /// The space between the actions: each is at least 44 points wide, so a small gap is enough, and
  /// a wide one left no room for Edit text on a 6.3-inch iPhone in English (#303).
  private static let spacing = Spacing.s050

  /// How the actions sit on the bar, roomiest first (#303).
  ///
  /// Style and Copy go under More first, then Delete. Edit text and Done are never under More.
  nonisolated enum Arrangement: Int, CaseIterable, Equatable, Sendable {
    /// Every action on one row.
    case everything
    /// One row; Style and Copy are under More.
    case styleAndCopyInMore
    /// One row; Style, Copy and Delete are under More.
    case deleteInMore
    /// One row without the title, which gives way before the bar stacks; Style, Copy and Delete are
    /// under More.
    case deleteInMoreNoTitle
    /// Taller, for when no row fits, as at accessibility sizes: the title on its own line, hidden
    /// when even that doesn't fit; Edit text across the bar, its words wrapping between words; More,
    /// with Style, Copy and Delete, and Done below.
    case stacked
  }

  /// An action that can go under More.
  nonisolated enum Action: Hashable, Sendable {
    case style, copy, delete, editText
  }

  /// What is under More in an arrangement.
  ///
  /// Edit text never is.
  nonisolated static func underMore(in arrangement: Arrangement) -> Set<Action> {
    switch arrangement {
    case .everything: []
    case .styleAndCopyInMore: [.style, .copy]
    case .deleteInMore, .deleteInMoreNoTitle, .stacked: [.style, .copy, .delete]
    }
  }

  /// Whether the bar shows the title in an arrangement; `stackedTitleFits` says whether it fits on
  /// its own line in the stacked bar.
  nonisolated static func showsTitle(in arrangement: Arrangement, stackedTitleFits: Bool) -> Bool {
    switch arrangement {
    case .everything, .styleAndCopyInMore, .deleteInMore: true
    case .deleteInMoreNoTitle: false
    case .stacked: stackedTitleFits
    }
  }

  /// A control that can carry the Move actions.
  nonisolated enum MoveActionsCarrier: Equatable, Sendable {
    case title, editText, done
  }

  /// Which control carries the Move actions, for VoiceOver and Switch Control.
  ///
  /// The title when it is shown; otherwise Edit text, which is on the bar in every arrangement, or
  /// Done, which always is, where there is no Edit text (a drawing, shape, stamp or signature). Each
  /// is a stop of its own; the bar, a container, is not (#303).
  nonisolated static func moveActionsCarrier(titleShown: Bool, isTextEditable: Bool) -> MoveActionsCarrier {
    if titleShown { return .title }
    return isTextEditable ? .editText : .done
  }

  /// The arrangement the unseen measure chose; see `measure`.
  @State private var arrangement = Arrangement.everything
  /// Whether the title is on the bar; in the stacked arrangement it is hidden when it doesn't fit.
  @State private var titleShown = true
  @Environment(\.locale) private var locale
  /// The space between the words of Edit text when they wrap, as wide as a space in body text.
  @ScaledMetric(relativeTo: .body) private var wordSpace: CGFloat = 4.5

  var body: some View {
    row(arrangement)
      .background { measure }
      .onPreferenceChange(ArrangementKey.self) { chosen in arrangement = chosen }
      .onPreferenceChange(TitleShownKey.self) { shown in titleShown = shown }
      // Plain labels, so that the only red on this bar is Delete (the app's accent is red too).
      .tint(Color.ds.labelPrimary)
      .padding(Self.padding)
      // A system background, the kind the Delete token keeps 4.5:1 on. The regular material over a white
      // page is mid-grey in dark mode (on an iPhone, 2026-10-26), where Delete was 3.0:1.
      .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityElement(children: .contain)
      // What is selected, also when the title is hidden.
      .accessibilityLabel(kindName)
      .accessibilityIdentifier(AccessibilityID.Reader.Selection.actionBar)
  }

  /// The roomiest arrangement whose row fits on one line, at the text size and in the language in use,
  /// or the stacked one when none does.
  ///
  /// French titles are longer than English ones, and wrapped they broke "Supprimer" in two (#303).
  /// Each arrangement is laid out here unseen and the shown bar follows the one that fits, so the
  /// shown controls stay the same controls when a row's arrangement changes. A row that swapped its
  /// controls for others as the text grew failed the accessibility audit, which changes the text size
  /// and measures at once. The text itself always scales; only where the controls sit changes.
  private var measure: some View {
    ViewThatFits(in: .horizontal) {
      row(.everything).preference(key: ArrangementKey.self, value: .everything)
      row(.styleAndCopyInMore).preference(key: ArrangementKey.self, value: .styleAndCopyInMore)
      row(.deleteInMore).preference(key: ArrangementKey.self, value: .deleteInMore)
      row(.deleteInMoreNoTitle).preference(key: ArrangementKey.self, value: .deleteInMoreNoTitle)
      row(.stacked).preference(key: ArrangementKey.self, value: .stacked)
    }
    .hidden()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  /// The bar in one arrangement.
  ///
  /// In a row, each control keeps its place whatever the arrangement, so it stays the same control
  /// when the arrangement changes.
  @ViewBuilder func row(_ arrangement: Arrangement) -> some View {
    let underMore = Self.underMore(in: arrangement)
    let carrier = Self.moveActionsCarrier(
      titleShown: Self.showsTitle(in: arrangement, stackedTitleFits: titleShown),
      isTextEditable: selection.isTextEditable)
    if arrangement == .stacked {
      VStack(alignment: .leading, spacing: Spacing.s050) {
        // The title, on one line; hidden, rather than cut short, when it doesn't fit.
        ViewThatFits(in: .horizontal) {
          title.preference(key: TitleShownKey.self, value: true)
          Color.clear.frame(width: 0, height: 0).preference(key: TitleShownKey.self, value: false)
        }
        if selection.isTextEditable {
          wrappingEditButton.carryingMoveActions(carrier == .editText, moveActions)
        }
        HStack(spacing: Self.spacing) {
          more(underMore)
          Spacer(minLength: Spacing.s100)
          doneButton.carryingMoveActions(carrier == .done, moveActions)
        }
      }
    } else {
      HStack(spacing: Self.spacing) {
        if Self.showsTitle(in: arrangement, stackedTitleFits: true) { title }
        Spacer(minLength: Spacing.s100)
        if !underMore.contains(.style), hasStyleOrCopy { styleMenu(inMore: false) }
        if !underMore.contains(.copy), selection.isMovable { copyMenu(inMore: false) }
        if !underMore.isEmpty { more(underMore) }
        editButton.carryingMoveActions(carrier == .editText, moveActions)
        if !underMore.contains(.delete) { deleteButton }
        doneButton.carryingMoveActions(carrier == .done, moveActions)
      }
    }
  }

  /// What is selected, by name.
  private var kindName: Text {
    selection.isSignature ? Text("Signature", bundle: .module) : Self.title(for: selection.kind)
  }

  /// What is selected.
  ///
  /// It carries the Move actions, so it gets a full-size target like any control.
  private var title: some View {
    kindName
      .font(.subheadline.weight(.semibold)).minimumTarget()
      // Dragging moves a selection; these do the same without a drag, for VoiceOver and Switch Control.
      .carryingMoveActions(true, moveActions)
  }

  /// Move up, down, left and right, for VoiceOver and Switch Control; nothing when nothing moves.
  @ViewBuilder private var moveActions: some View {
    if selection.isMovable { moveButtons }
  }

  @ViewBuilder private var moveButtons: some View {
    Button {
      onMove(CGSize(width: 0, height: Self.step))
    } label: {
      Text("Move up", bundle: .module)
    }
    Button {
      onMove(CGSize(width: 0, height: -Self.step))
    } label: {
      Text("Move down", bundle: .module)
    }
    Button {
      onMove(CGSize(width: -Self.step, height: 0))
    } label: {
      Text("Move left", bundle: .module)
    }
    Button {
      onMove(CGSize(width: Self.step, height: 0))
    } label: {
      Text("Move right", bundle: .module)
    }
  }

  /// Whether there is Style or Copy to offer.
  private var hasStyleOrCopy: Bool { selection.isMovable || selection.isRecolorable }

  /// The colour and size, on the bar or under More, with the same identifier either way.
  private func styleMenu(inMore: Bool) -> some View {
    Menu {
      styleItems
    } label: {
      if inMore {
        Label {
          Text("Style", bundle: .module)
        } icon: {
          Image(systemName: "paintpalette")
        }
      } else {
        Text("Style", bundle: .module).minimumTarget()
      }
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.style)
  }

  /// Copy, cut and duplicate, on the bar or under More, with the same identifier either way.
  private func copyMenu(inMore: Bool) -> some View {
    Menu {
      copyItems
    } label: {
      if inMore {
        Label {
          Text("Copy", bundle: .module)
        } icon: {
          Image(systemName: "doc.on.doc")
        }
      } else {
        Text("Copy", bundle: .module).minimumTarget()
      }
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.copy)
  }

  /// The colour, and the size of what can be moved.
  @ViewBuilder private var styleItems: some View {
    if selection.isRecolorable {
      Picker(selection: Binding<AnnotationColor?>(get: { nil }, set: { if let color = $0 { onColor(color) } })) {
        ForEach(AnnotationColor.allCases, id: \.self) { color in
          Self.name(of: color).tag(Optional(color))
        }
      } label: {
        Text("Colour", bundle: .module)
      }
      .pickerStyle(.menu)
    }
    if selection.isMovable {
      Button {
        onResize(1.25)
      } label: {
        Label {
          Text("Larger", bundle: .module)
        } icon: {
          Image(systemName: "plus.magnifyingglass")
        }
      }
      .accessibilityIdentifier(AccessibilityID.Reader.Selection.larger)
      Button {
        onResize(0.8)
      } label: {
        Label {
          Text("Smaller", bundle: .module)
        } icon: {
          Image(systemName: "minus.magnifyingglass")
        }
      }
      .accessibilityIdentifier(AccessibilityID.Reader.Selection.smaller)
    }
  }

  @ViewBuilder private var copyItems: some View {
    Button(action: onCopy) {
      Label {
        Text("Copy", bundle: .module)
      } icon: {
        Image(systemName: "doc.on.doc")
      }
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.copyAction)
    Button(action: onCut) {
      Label {
        Text("Cut", bundle: .module)
      } icon: {
        Image(systemName: "scissors")
      }
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.cut)
    Button(action: onDuplicate) {
      Label {
        Text("Duplicate", bundle: .module)
      } icon: {
        Image(systemName: "plus.square.on.square")
      }
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.duplicate)
  }

  /// The actions an arrangement has no room for, in one menu.
  ///
  /// Edit text is never among them.
  private func more(_ underMore: Set<Action>) -> some View {
    Menu {
      if underMore.contains(.style), hasStyleOrCopy { styleMenu(inMore: true) }
      if underMore.contains(.copy), selection.isMovable { copyMenu(inMore: true) }
      if underMore.contains(.delete) {
        Button(role: .destructive, action: onDelete) {
          Label {
            Text("Delete", bundle: .module)
          } icon: {
            Image(systemName: "trash")
          }
        }
        .accessibilityIdentifier(AccessibilityID.Reader.Selection.delete)
      }
    } label: {
      Label {
        Text("More", bundle: .module)
      } icon: {
        Image(systemName: "ellipsis.circle")
      }
      .labelStyle(.iconOnly).minimumTarget()
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.more)
  }

  /// Edit text, the Pro feature, as a button of its own on one row, for text boxes and notes.
  @ViewBuilder private var editButton: some View {
    if selection.isTextEditable {
      Button(action: onEdit) { Text("Edit text", bundle: .module).minimumTarget() }
        .accessibilityIdentifier(AccessibilityID.Reader.Selection.edit)
    }
  }

  /// Edit text across the stacked bar, its words wrapping only between words.
  ///
  /// Each word is a text of its own, laid out whole by `WordFlow`, so no word can be broken or
  /// hyphenated: "Modifier le texte" goes onto as many lines as it needs, a word to a line at most.
  private var wrappingEditButton: some View {
    Button(action: onEdit) {
      WordFlow(spacing: wordSpace) {
        ForEach(Array(Self.editTextWords(locale: locale).enumerated()), id: \.offset) { _, word in
          Text(verbatim: word)
        }
      }
      // Across the bar, so the words have its width to wrap in and the whole width is the target.
      .frame(maxWidth: .infinity, alignment: .leading)
      .minimumTarget()
    }
    .accessibilityLabel(Text("Edit text", bundle: .module))
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.edit)
  }

  /// The words of "Edit text" in a language.
  static func editTextWords(locale: Locale) -> [String] {
    var resource = LocalizedStringResource("Edit text", bundle: .atURL(Bundle.module.bundleURL))
    resource.locale = locale
    return String(localized: resource).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  // systemRed is below 4.5:1 on the material; the token keeps the contrast in every appearance.
  private var deleteButton: some View {
    Button(role: .destructive, action: onDelete) {
      Text("Delete", bundle: .module).foregroundStyle(Color.ds.destructiveText).minimumTarget()
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.delete)
  }

  private var doneButton: some View {
    Button(action: onDone) { Text("Done", bundle: .module).minimumTarget() }
      .accessibilityIdentifier(AccessibilityID.Reader.Selection.done)
  }

  static func name(of color: AnnotationColor) -> Text {
    switch color {
    case .blue: Text("Blue", bundle: .module)
    case .red: Text("Red", bundle: .module)
    case .green: Text("Green", bundle: .module)
    case .yellow: Text("Yellow", bundle: .module)
    case .black: Text("Black", bundle: .module)
    }
  }

  static func title(for kind: AnnotationSelection.Kind) -> Text {
    switch kind {
    case .highlight: Text("Highlight", bundle: .module)
    case .underline: Text("Underline", bundle: .module)
    case .strikeThrough: Text("Strike-through", bundle: .module)
    case .note: Text("Note", bundle: .module)
    case .ink: Text("Drawing", bundle: .module)
    case .rectangle: Text("Rectangle", bundle: .module)
    case .oval: Text("Oval", bundle: .module)
    case .line: Text("Line", bundle: .module)
    case .textBox: Text("Text box", bundle: .module)
    case .stamp: Text("Stamp", bundle: .module)
    case .other: Text("Annotation", bundle: .module)
    }
  }
}

/// The arrangement the unseen measure chose, passed up to the bar.
private nonisolated struct ArrangementKey: PreferenceKey {
  static let defaultValue = SelectionBar.Arrangement.everything

  static func reduce(value: inout SelectionBar.Arrangement, nextValue: () -> SelectionBar.Arrangement) {
    value = nextValue()
  }
}

/// Whether the stacked bar shows its title, passed up to the bar.
private nonisolated struct TitleShownKey: PreferenceKey {
  static let defaultValue = true

  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value && nextValue()
  }
}

/// Words laid out like text, each whole: a line ends between two words, never inside one (#303).
///
/// Each word is given its own width, so a word is never wrapped or hyphenated; a word wider than the
/// line has a line to itself.
struct WordFlow: Layout {
  /// The space between two words on a line.
  var spacing: CGFloat

  /// Which words go on each line, by index, for words of these widths in lines this wide.
  ///
  /// A line breaks only between words.
  nonisolated static func lines(widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
    var lines: [[Int]] = []
    var current: [Int] = []
    var used: CGFloat = 0
    for (index, width) in widths.enumerated() {
      let needed = current.isEmpty ? width : used + spacing + width
      if !current.isEmpty, needed > maxWidth {
        lines.append(current)
        current = [index]
        used = width
      } else {
        current.append(index)
        used = needed
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let lines = Self.lines(widths: sizes.map(\.width), maxWidth: proposal.width ?? .infinity, spacing: spacing)
    var width: CGFloat = 0
    var height: CGFloat = 0
    for line in lines {
      var lineWidth = spacing * CGFloat(max(0, line.count - 1))
      var lineHeight: CGFloat = 0
      for index in line {
        lineWidth += sizes[index].width
        lineHeight = max(lineHeight, sizes[index].height)
      }
      width = max(width, lineWidth)
      height += lineHeight
    }
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    var y = bounds.minY
    for line in Self.lines(widths: sizes.map(\.width), maxWidth: bounds.width, spacing: spacing) {
      var x = bounds.minX
      let height = line.map { sizes[$0].height }.max() ?? 0
      for index in line {
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[index]))
        x += sizes[index].width + spacing
      }
      y += height
    }
  }
}

extension View {
  /// Gives this control the Move actions when it is the one that carries them.
  ///
  /// One view whatever `carries` is, with only the actions conditional: two branches would be two
  /// view types, and SwiftUI would replace the control when the title hides or shows, which is when
  /// the accessibility audit changes the text size and measures (#303).
  fileprivate func carryingMoveActions(_ carries: Bool, _ actions: some View) -> some View {
    accessibilityActions {
      if carries { actions }
    }
  }
}
