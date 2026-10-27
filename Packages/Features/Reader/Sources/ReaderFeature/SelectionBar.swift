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

  var body: some View {
    // The longest row that fits on one line. French titles are longer than English ones, and wrapped
    // they broke "Supprimer" in two (#303). Style and Copy become icons first, then go into a More
    // menu; Edit text stays a button of its own for as long as there is room for it, and Delete goes
    // into the menu last.
    ViewThatFits(in: .horizontal) {
      row(iconOnly: false)
      row(iconOnly: true)
      HStack(spacing: Spacing.s150) {
        title
        Spacer(minLength: Spacing.s100)
        editButton
        if hasStyleOrCopy { more(includingEdit: false, includingDelete: false) }
        deleteButton
        doneButton
      }
      HStack(spacing: Spacing.s150) {
        title
        Spacer(minLength: Spacing.s100)
        editButton
        more(includingEdit: false, includingDelete: true)
        doneButton
      }
      HStack(spacing: Spacing.s150) {
        title
        Spacer(minLength: Spacing.s100)
        more(includingEdit: true, includingDelete: true)
        doneButton
      }
    }
    // Plain labels, so that the only red on this bar is Delete (the app's accent is red too).
    .tint(Color.ds.labelPrimary)
    .padding(Spacing.s150)
    // A system background, the kind the Delete token keeps 4.5:1 on. The regular material over a white
    // page is mid-grey in dark mode (on an iPhone, 2026-10-26), where Delete was 3.0:1.
    .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.actionBar)
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

  /// Every action on one line: Style and Copy as words, or as icons where the words don't fit.
  private func row(iconOnly: Bool) -> some View {
    HStack(spacing: Spacing.s150) {
      title
      Spacer(minLength: Spacing.s100)
      if hasStyleOrCopy { styleMenu(iconOnly: iconOnly) }
      if selection.isMovable { copyMenu(iconOnly: iconOnly) }
      editButton
      deleteButton
      doneButton
    }
  }

  /// The colour and size: a word, an icon, or an entry in More, with the same identifier each way.
  private func styleMenu(iconOnly: Bool) -> some View {
    Menu {
      styleItems
    } label: {
      Label {
        Text("Style", bundle: .module)
      } icon: {
        Image(systemName: "paintpalette")
      }
      .labelStyle(SelectionBarLabelStyle(iconOnly: iconOnly)).minimumTarget()
    }
    .accessibilityIdentifier(AccessibilityID.Reader.Selection.style)
  }

  /// Copy, cut and duplicate: a word, an icon, or an entry in More, with the same identifier each way.
  private func copyMenu(iconOnly: Bool) -> some View {
    Menu {
      copyItems
    } label: {
      Label {
        Text("Copy", bundle: .module)
      } icon: {
        Image(systemName: "doc.on.doc")
      }
      .labelStyle(SelectionBarLabelStyle(iconOnly: iconOnly)).minimumTarget()
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

  /// The actions a narrow row has no room for, in one menu.
  private func more(includingEdit: Bool, includingDelete: Bool) -> some View {
    Menu {
      if hasStyleOrCopy { styleMenu(iconOnly: false) }
      if selection.isMovable { copyMenu(iconOnly: false) }
      if includingEdit, selection.isTextEditable {
        Button(action: onEdit) {
          Label {
            Text("Edit text", bundle: .module)
          } icon: {
            Image(systemName: "character.cursor.ibeam")
          }
        }
        .accessibilityIdentifier(AccessibilityID.Reader.Selection.edit)
      }
      if includingDelete {
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

/// A label as its title alone, or as its icon alone with the title kept for VoiceOver.
private struct SelectionBarLabelStyle: LabelStyle {
  let iconOnly: Bool

  func makeBody(configuration: Configuration) -> some View {
    if iconOnly {
      Label(configuration).labelStyle(.iconOnly)
    } else {
      Label(configuration).labelStyle(.titleOnly)
    }
  }
}
