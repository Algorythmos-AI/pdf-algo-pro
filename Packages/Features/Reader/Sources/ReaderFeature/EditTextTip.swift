import DesignSystem
import SwiftUI
import TipKit

/// Points at the Edit button, once, so that people find they can change a PDF's text.
///
/// It is shown only when tapping Edit would let the person edit straight away
/// (`ReaderModel.offersEditTip`), and it stops for good the first time Edit is used, when it is
/// closed, or after it has been shown three times. TipKit keeps this on the device; nothing is
/// sent anywhere.
struct EditTextTip: Tip {
  /// Whether the reader is in a state where the tip may show.
  @Parameter
  static var isOffered: Bool = false

  // The words are looked up when the tip is made, on the main actor, where the package's string
  // catalog is reached from; TipKit asks for them from anywhere.
  private let titleText: String
  private let messageText: String

  @MainActor
  init() {
    titleText = String(localized: "Edit this PDF", bundle: .module, comment: "Title of the one-time tip on Edit")
    messageText = String(
      localized: "Tap Edit, then tap any text to change it.", bundle: .module,
      comment: "Message of the one-time tip that points at the Edit button")
  }

  var title: Text { Text(titleText) }

  var message: Text? { Text(messageText) }

  var rules: [Rule] {
    #Rule(Self.$isOffered) { $0 == true }
  }

  var options: [any TipOption] {
    MaxDisplayCount(3)
  }

  /// Retires the tip for good: the person has used Edit.
  ///
  /// Here so that the reader's model need not import TipKit.
  @MainActor
  static func markUsed() {
    isOffered = false
    EditTextTip().invalidate(reason: .actionPerformed)
  }
}

/// The tip, drawn just under the bar, below the buttons.
///
/// It is part of the reader's layout, not a presentation: it cannot hold back a sheet or an
/// alert, and a tap anywhere else goes where it was aimed. The page starts below it, so it covers
/// none of the document; when it goes, the page takes the space back.
///
/// The card is the reader's own, not TipKit's: TipKit's card does not follow the text size the
/// person chose, and its message is too faint (accessibility audit). TipKit decides when the tip
/// shows and remembers that it has been used or closed.
///
/// It has no arrow. A popover tip does not appear on a toolbar button on iOS 26, and a toolbar
/// button does not report where it is to the reader's layout (spike S2), so an arrow could only
/// guess. The card sits under the trailing end of the bar, where the filled Edit button is, and
/// names the button.
struct EditTipCard: View {
  private let tip = EditTextTip()
  @State private var isShown = false

  var body: some View {
    Group {
      // Nothing at all is in the layout, or in what VoiceOver finds, unless the tip is showing.
      if isShown {
        EditTipCardBody(title: tip.title, message: tip.message) { tip.invalidate(reason: .tipClosed) }
          .padding(.horizontal, Spacing.s150)
          .padding(.vertical, Spacing.s050)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .task {
      for await shouldDisplay in tip.shouldDisplayUpdates {
        isShown = shouldDisplay
      }
    }
  }
}

/// How the tip looks: a title, a sentence and a close button, on an opaque card.
///
struct EditTipCardBody: View {
  let title: Text
  let message: Text?
  let close: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.s100) {
      VStack(alignment: .leading, spacing: Spacing.s050) {
        title.font(.headline).foregroundStyle(Color.ds.labelPrimary)
        message?.font(.subheadline).foregroundStyle(Color.ds.labelPrimary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.vertical, Spacing.s100)
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      Button(action: close) {
        Image(systemName: "xmark")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.ds.labelPrimary)
          .frame(width: Sizes.targetMinimum, height: Sizes.targetMinimum)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(Text("Close", bundle: .module))
      .accessibilityIdentifier("reader.editTip.close")
    }
    .padding(.leading, Spacing.s200)
    .padding(.vertical, Spacing.s050)
    .frame(maxWidth: 340, alignment: .leading)
    .background {
      // The shadow belongs to the card's shape alone. Put on the whole card, it would also be
      // drawn behind each word, and the smudge lowers the words' contrast.
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.ds.backgroundGroupedElevated)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ds.separator) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("reader.editTip")
  }
}
