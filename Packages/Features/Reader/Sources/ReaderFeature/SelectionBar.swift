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

  /// How far one step of "Move" goes, in points; page space runs up, so up is positive.
  private static let step: CGFloat = 12

  var body: some View {
    HStack(spacing: Spacing.s150) {
      // The title carries the Move actions, so it gets a full-size target like any control.
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
      Spacer(minLength: Spacing.s100)
      if selection.isMovable || selection.isRecolorable {
        Menu {
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
        } label: {
          Text("Style", bundle: .module).minimumTarget()
        }
        .accessibilityIdentifier("reader.selection.style")
      }
      if selection.isTextEditable {
        Button(action: onEdit) { Text("Edit text", bundle: .module).minimumTarget() }
          .accessibilityIdentifier("reader.selection.edit")
      }
      // systemRed is below 4.5:1 on the material; the token keeps the contrast in every appearance.
      Button(role: .destructive, action: onDelete) {
        Text("Delete", bundle: .module).foregroundStyle(Color.ds.destructiveText).minimumTarget()
      }
      .accessibilityIdentifier("reader.selection.delete")
      Button(action: onDone) { Text("Done", bundle: .module).minimumTarget() }
        .accessibilityIdentifier("reader.selection.done")
    }
    // Plain labels, so that the only red on this bar is Delete (the app's accent is red too).
    .tint(Color.ds.labelPrimary)
    .padding(Spacing.s150)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("reader.selection.actionBar")
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
