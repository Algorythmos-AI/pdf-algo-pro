#if DEBUG
  import DesignSystem
  import SwiftUI

  // Previews of the reader's parts that need no open document, for the design pass (PAP-070). The
  // reader itself, its toolbar, sheets and editors work on a document controller, so they are
  // checked in the snapshot gallery's UI tests and the owner's walk-through instead
  // (docs/design/design-pass-checklist.md).

  /// Every message the text editor can show, in the order the model declares them.
  private let textEditMessages: [ReaderModel.TextEditMessage] = [
    .pageIsImage, .pageNotEditable, .tooLong, .unsupportedCharacters, .cannotEdit, .fontMatched, .coversOriginal,
    .coversOriginalBriefly, .lookingForText, .noEditableText, .tookTooLong, .somethingInTheWay, .cannotEditOrCover,
  ]

  private func pasteBar(canUndo: Bool = true) -> some View {
    VStack {
      Spacer()
      PasteBar(onPasteHere: {}, onDone: {}, canUndo: canUndo)
        .padding(Spacing.s200)
    }
  }

  /// The tip's card with the tip's own words; the card is drawn without TipKit deciding to show it.
  private func editTip() -> some View {
    let tip = EditTextTip()
    return EditTipCardBody(title: tip.title, message: tip.message, close: {}).padding(Spacing.s200)
  }

  private func messages() -> some View {
    List(textEditMessages, id: \.self) { TextEditMessageLabel(message: $0) }
  }

  #Preview("Paste bar") { pasteBar() }
  #Preview("Paste bar, largest text") { pasteBar().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Paste bar, dark") { pasteBar(canUndo: false).preferredColorScheme(.dark) }
  #Preview("Paste bar, right to left") { pasteBar().environment(\.layoutDirection, .rightToLeft) }

  #Preview("Edit tip") { editTip() }
  #Preview("Edit tip, largest text") { editTip().environment(\.dynamicTypeSize, .accessibility5) }
  #Preview("Edit tip, dark") { editTip().preferredColorScheme(.dark) }

  #Preview("Text editing messages") { messages() }
  #Preview("Text editing messages, largest text") { messages().environment(\.dynamicTypeSize, .accessibility5) }
#endif
