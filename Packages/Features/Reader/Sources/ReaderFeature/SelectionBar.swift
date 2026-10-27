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

  /// How the actions sit on the bar's one row, roomiest first (#303).
  nonisolated enum Arrangement: Int, CaseIterable, Equatable, Sendable {
    /// Every action is a button of its own.
    case everything
    /// Style and Copy are under More; Edit text, Delete and Done are buttons.
    case styleAndCopyInMore
    /// Style, Copy and Delete are under More; Edit text and Done are buttons.
    case deleteInMore
    /// Everything but Done is under More.
    case allInMore
  }

  /// The arrangement the unseen measure chose; see `measure`.
  @State private var arrangement = Arrangement.everything

  var body: some View {
    row(arrangement)
      .background { measure }
      .onPreferenceChange(ArrangementKey.self) { chosen in arrangement = chosen }
      // Plain labels, so that the only red on this bar is Delete (the app's accent is red too).
      .tint(Color.ds.labelPrimary)
      .padding(Self.padding)
      // A system background, the kind the Delete token keeps 4.5:1 on. The regular material over a white
      // page is mid-grey in dark mode (on an iPhone, 2026-10-26), where Delete was 3.0:1.
      .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(AccessibilityID.Reader.Selection.actionBar)
  }

  /// The roomiest arrangement whose row fits on one line, at the text size and in the language in use.
  ///
  /// French titles are longer than English ones, and wrapped they broke "Supprimer" in two (#303).
  /// Each arrangement is laid out here unseen and the shown row follows the one that fits, so the
  /// shown controls stay the same controls when the arrangement changes. A row that swapped its
  /// controls for others as the text grew failed the accessibility audit, which changes the text size
  /// and measures at once. The text itself always scales; only where the controls sit changes.
  private var measure: some View {
    ViewThatFits(in: .horizontal) {
      row(.everything).preference(key: ArrangementKey.self, value: .everything)
      row(.styleAndCopyInMore).preference(key: ArrangementKey.self, value: .styleAndCopyInMore)
      row(.deleteInMore).preference(key: ArrangementKey.self, value: .deleteInMore)
      row(.allInMore).preference(key: ArrangementKey.self, value: .allInMore)
    }
    .hidden()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  /// The row in one arrangement.
  ///
  /// Each control keeps its place in it whatever the arrangement, so it stays the same control
  /// when the arrangement changes.
  func row(_ arrangement: Arrangement) -> some View {
    HStack(spacing: Self.spacing) {
      title
      Spacer(minLength: Spacing.s100)
      if arrangement == .everything, hasStyleOrCopy { styleMenu(inMore: false) }
      if arrangement == .everything, selection.isMovable { copyMenu(inMore: false) }
      if arrangement != .everything, hasStyleOrCopy || arrangement != .styleAndCopyInMore { more(arrangement) }
      if arrangement != .allInMore { editButton }
      if arrangement == .everything || arrangement == .styleAndCopyInMore { deleteButton }
      doneButton
    }
  }

  /// What is selected.
  ///
  /// It carries the Move actions, so it gets a full-size target like any control.
  private var title: some View {
    (selection.isSignature ? Text("Signature", bundle: .module) : Self.title(for: selection.kind))
      .font(.subheadline.weight(.semibold)).minimumTarget()
      // Dragging moves a selection; these do the same without a drag, for VoiceOver and Switch Control.
      .accessibilityActions {
        if selection.isMovable {
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
      Button {
        onResize(0.8)
      } label: {
        Label {
          Text("Smaller", bundle: .module)
        } icon: {
          Image(systemName: "minus.magnifyingglass")
        }
      }
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

  /// The actions an arrangement has no room for on the row, in one menu.
  private func more(_ arrangement: Arrangement) -> some View {
    Menu {
      if hasStyleOrCopy { styleMenu(inMore: true) }
      if selection.isMovable { copyMenu(inMore: true) }
      if arrangement == .allInMore, selection.isTextEditable {
        Button(action: onEdit) {
          Label {
            Text("Edit text", bundle: .module)
          } icon: {
            Image(systemName: "character.cursor.ibeam")
          }
        }
        .accessibilityIdentifier(AccessibilityID.Reader.Selection.edit)
      }
      if arrangement == .deleteInMore || arrangement == .allInMore {
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

  /// Edit text, the Pro feature, as a button of its own, for text boxes and notes.
  @ViewBuilder private var editButton: some View {
    if selection.isTextEditable {
      Button(action: onEdit) { Text("Edit text", bundle: .module).minimumTarget() }
        .accessibilityIdentifier(AccessibilityID.Reader.Selection.edit)
    }
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
