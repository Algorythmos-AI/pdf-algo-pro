import Core
import DesignSystem
import PDFEngine
import SwiftUI
import UIKit

/// The reader: the page surface, a floating page indicator, and tools in the toolbar.
///
/// Chrome recedes so the document is the interface (design system, principle 2).
public struct ReaderView<Assistant: View>: View {
  @State private var newPassword = ""
  @State private var model: ReaderModel
  @State private var password = ""
  @State private var noteText = ""
  @State private var isAddingNote = false
  @State private var isAddingTextBox = false
  @State private var isEditingSelection = false
  @State private var selectionText = ""
  @State private var textBoxText = ""
  @State private var stampText = ""
  @State private var pageNumber = ""
  @State private var textDraft = TextEditDraft()
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.horizontalSizeClass) private var sizeClass
  private let assistant: (ReaderAssistantContext) -> Assistant

  /// Creates the reader; `assistant` builds the assistant sheet, supplied by the app.
  public init(model: ReaderModel, @ViewBuilder assistant: @escaping (ReaderAssistantContext) -> Assistant) {
    _model = State(initialValue: model)
    self.assistant = assistant
  }

  /// Whether the bar leaves out the document's title: where it is narrow and holds the Edit button.
  private var hidesTitle: Bool {
    sizeClass == .compact && model.textEditingAccess != .hidden
  }

  /// Lets the tip that points at Edit show once the page has settled, and takes it away as soon
  /// as the reader is doing anything else.
  private func offerEditTip() async {
    let isLocalAlertUp = isAddingNote || isAddingTextBox || isEditingSelection
    guard model.offersEditTip, !isLocalAlertUp else {
      EditTextTip.isOffered = false
      return
    }
    // The page draws and the push animation ends before anything points at the bar.
    try? await Task.sleep(for: .seconds(1))
    guard !Task.isCancelled, model.offersEditTip, await model.currentPageHasEditableText(), !Task.isCancelled
    else { return }
    EditTextTip.isOffered = true
  }

  /// The reader.
  public var body: some View {
    content
      .navigationTitle(model.document?.title ?? "")
      .navigationBarTitleDisplayMode(.inline)
      // On a narrow bar the word Edit and the title do not both fit, and the bar would squeeze the
      // button to keep the title. The title gives way (PAP-037); it is still the screen's name
      // for VoiceOver and for the back button of whatever is pushed next.
      .toolbar {
        if hidesTitle {
          // An empty item where the title is drawn. (Removing the title from the bar leaves it
          // there on iOS 26.)
          ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        }
      }
      .toolbar { ReaderToolbar(model: model, isAddingNote: $isAddingNote, isAddingTextBox: $isAddingTextBox) }
      .task(id: [model.offersEditTip ? 1 : 0, model.controller?.currentPageIndex ?? -1]) { await offerEditTip() }
      .onDisappear { EditTextTip.isOffered = false }
      .onChange(of: model.textMoves) {
        let said =
          model.textEditNotice == .coveredInstead
          ? String(
            localized: "Your text covers the old text. The original is still in the file underneath.", bundle: .module)
          : String(localized: "Text moved", bundle: .module)
        UIAccessibility.post(notification: .announcement, argument: said)
      }
      .alert(Text("Stamp", bundle: .module), isPresented: $model.isAddingStampText) {
        TextField(text: $stampText) { Text("Initials, Paid, Received…", bundle: .module) }
        Button {
          let text = stampText
          stampText = ""
          Task { await model.addStamp(.text(text)) }
        } label: {
          Text("Add", bundle: .module)
        }
        .disabled(stampText.trimmingCharacters(in: .whitespaces).isEmpty)
        Button(role: .cancel) {
          stampText = ""
        } label: {
          Text("Cancel", bundle: .module)
        }
      }
      .alert(Text("Edit text", bundle: .module), isPresented: $isEditingSelection) {
        TextField(text: $selectionText) { Text("Text", bundle: .module) }
        Button {
          Task { await model.setSelectionText(selectionText) }
        } label: {
          Text("Save", bundle: .module)
        }
        Button(role: .cancel) {
        } label: {
          Text("Cancel", bundle: .module)
        }
      }
      .alert(Text("Add a text box", bundle: .module), isPresented: $isAddingTextBox) {
        TextField(text: $textBoxText) { Text("Text", bundle: .module) }
        Button {
          // The text is taken before the field is cleared: the task runs after this closure returns.
          let text = textBoxText
          textBoxText = ""
          Task { await model.addTextBox(text) }
        } label: {
          Text("Add", bundle: .module)
        }
        Button(role: .cancel) {
          textBoxText = ""
        } label: {
          Text("Cancel", bundle: .module)
        }
      }
      .sheet(item: $model.assistantTask, onDismiss: { model.assistantDismissed() }) { task in
        assistant(model.assistantContext(for: task))
      }
      .sheet(item: $model.sharing) { ShareSheet(file: $0) }
      .sheet(isPresented: $model.showsVersions) { VersionHistorySheet(model: model) }
      .sheet(isPresented: $model.showsSignatures) { SignatureSheet(model: model) }
      .sheet(isPresented: $model.showsOutline, onDismiss: { model.pageSheetDismissed() }) {
        OutlineSheet(model: model)
      }
      .sheet(isPresented: $model.showsAnnotations, onDismiss: { model.pageSheetDismissed() }) {
        AnnotationListSheet(model: model)
      }
      .sheet(isPresented: $model.showsPages, onDismiss: { model.pageSheetDismissed() }) {
        PageGridSheet(model: model)
      }
      .alert(Text("Add a note", bundle: .module), isPresented: $isAddingNote) {
        TextField(text: $noteText) { Text("Note", bundle: .module) }
        Button {
          let text = noteText
          noteText = ""
          Task { await model.addNote(text) }
        } label: {
          Text("Add", bundle: .module)
        }
        Button(role: .cancel) {
        } label: {
          Text("Cancel", bundle: .module)
        }
      }
      .alert(Text("Go to page", bundle: .module), isPresented: $model.showsGoToPage) {
        TextField(text: $pageNumber) { Text("Page number", bundle: .module) }
          .keyboardType(.numberPad)
          .accessibilityIdentifier("reader.goToPage.number")
        Button {
          model.goToPage(pageNumber)
          pageNumber = ""
        } label: {
          Text("Go", bundle: .module)
        }
        Button(role: .cancel) {
          pageNumber = ""
        } label: {
          Text("Cancel", bundle: .module)
        }
      } message: {
        Text("This document has \(model.controller?.pageCount ?? 0) pages.", bundle: .module)
      }
      .alert(Text("Add a password", bundle: .module), isPresented: $model.isAddingPassword) {
        SecureField(text: $newPassword) { Text("Password", bundle: .module) }
          .accessibilityIdentifier("reader.newPassword")
        Button {
          let password = newPassword
          newPassword = ""
          Task { await model.setPassword(password) }
        } label: {
          Text("Add", bundle: .module)
        }
        .disabled(newPassword.isEmpty)
        Button(role: .cancel) {
          newPassword = ""
        } label: {
          Text("Cancel", bundle: .module)
        }
      } message: {
        Text(
          "Anyone opening the document will need this password. Keep it somewhere safe: it can't be recovered.",
          bundle: .module)
      }
      .confirmationDialog(
        Text("Remove the password?", bundle: .module), isPresented: $model.confirmsPasswordRemoval,
        titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          Task { await model.removePassword() }
        } label: {
          Text("Remove password", bundle: .module)
        }
      } message: {
        Text("Anyone with the file will be able to open it, print it and copy from it.", bundle: .module)
      }
      .alert(
        Text(model.notice ?? ""),
        isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
      ) {
        Button {
          model.notice = nil
        } label: {
          Text("OK", bundle: .module)
        }
      }
      .alert(
        Text("Something went wrong", bundle: .module),
        isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
      ) {
        Button {
          model.errorMessage = nil
        } label: {
          Text("OK", bundle: .module)
        }
      } message: {
        Text(model.errorMessage ?? "")
      }
      .confirmationDialog(
        Text("Edit a copy of this signed document?", bundle: .module), isPresented: $model.confirmsEditingSigned,
        titleVisibility: .visible
      ) {
        Button {
          Task { await model.confirmEditingSigned() }
        } label: {
          Text("Edit a copy", bundle: .module)
        }
      } message: {
        Text(
          "This document is digitally signed. Your edits are saved in a copy, and the original keeps its valid signature.",
          bundle: .module)
      }
      .alert(Text("Editing text needs Pro", bundle: .module), isPresented: $model.showsTextEditingLocked) {
        Button {
        } label: {
          Text("OK", bundle: .module)
        }
      } message: {
        Text(
          "Changing the words already in a PDF is one of PDF Algo Pro’s paid features. Reading, searching, marking up, filling in and signing stay free.",
          bundle: .module)
      }
      .modifier(LinkConfirmation(controller: model.controller))
      .task { await model.load() }
      .onChange(of: model.controller?.currentPageIndex) {
        Task {
          await model.recordPosition()
          await model.textEditingPageChanged()
        }
      }
      .onChange(of: model.selectedTextRegion) { _, selection in
        // The editor starts from the text as it is; what to say about it is worked out once.
        textDraft.text = selection?.region.text ?? ""
        textDraft.isInPlace = nil
        if selection != nil { model.textRegionPicked() }
      }
      .onChange(of: scenePhase) { _, phase in
        switch phase {
        case .background:
          Task {
            await model.saveBeforeSuspending(keepAlive: { BackgroundTime.begin("Save document") })
            await model.setWatching(false)
          }
        case .active:
          Task { await model.setWatching(true) }
        default:
          break
        }
      }
      .alert(
        Text("This document changed in another app", bundle: .module), isPresented: $model.hasConflictingChange
      ) {
        Button {
          Task { await model.keepMineAsCopy() }
        } label: {
          Text("Keep mine as a copy", bundle: .module)
        }
        Button(role: .destructive) {
          Task { await model.useOtherVersion() }
        } label: {
          Text("Use the other version", bundle: .module)
        }
      } message: {
        Text(
          "You have changes that aren't saved yet. Keep yours as a new document, or drop them and show the other app's version.",
          bundle: .module)
      }
      .onDisappear {
        model.stopWatching()
        model.speech.stop()
        Task {
          await model.saveBeforeClosing()
          await model.recordPosition()
        }
      }
  }

  @ViewBuilder private var content: some View {
    switch model.phase {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .locked(let wrongPassword):
      locked(wrongPassword: wrongPassword)
    case .failed(let message):
      EmptyState(Text("Can't open this document", bundle: .module), systemImage: "exclamationmark.triangle") {
        Text(message)
      } actions: {
        if model.canRestorePreviousVersion {
          Button {
            Task { await model.restorePreviousVersion() }
          } label: {
            Text("Restore the version before the last save", bundle: .module)
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("reader.restorePrevious")
        }
      }
    case .ready:
      if let controller = model.controller {
        ZStack(alignment: .bottom) {
          PDFReaderView(controller: controller)
            .ignoresSafeArea(edges: .bottom)
            .accessibilityLabel(Text("Document pages", bundle: .module))
            .accessibilityIdentifier("reader.pages")
            .overlay(alignment: .bottom) { indicator }
            .overlay {
              if let selection = model.selectedTextRegion {
                TextEditLayer(model: model, selection: selection, draft: textDraft)
              }
            }
          // Outside the page view, which runs under the keyboard: this sits just above it.
          if model.selectedTextRegion != nil {
            TextEditBar(model: model, draft: textDraft)
          }
        }
        // In the layout, above the page, so the tip covers none of the document's words.
        .safeAreaInset(edge: .top, spacing: 0) { EditTipCard() }
      }
    }
  }

  /// Tries the typed password; the field clears, so a wrong one is typed again from scratch.
  private func tryPassword() {
    model.unlock(password: password)
    password = ""
  }

  private func locked(wrongPassword: Bool) -> some View {
    VStack(spacing: Spacing.s200) {
      Image(systemName: "lock.doc").font(.largeTitle).foregroundStyle(Color.ds.labelSecondary).accessibilityHidden(true)
      Text("This document is password protected", bundle: .module).font(.headline)
      SecureField(text: $password) { Text("Password", bundle: .module) }
        .textFieldStyle(.roundedBorder)
        .submitLabel(.go)
        .onSubmit { tryPassword() }
        .accessibilityIdentifier("reader.password")
      if wrongPassword {
        Label {
          Text("That password didn't open the document.", bundle: .module)
        } icon: {
          // Only the icon is red: the error red is below 4.5:1 for text this small.
          Image(systemName: "xmark.octagon").foregroundStyle(Color.ds.statusError)
        }
        .font(.footnote)
        .accessibilityIdentifier("reader.wrongPassword")
      }
      Button {
        tryPassword()
      } label: {
        Text("Open", bundle: .module)
      }
      .buttonStyle(.primary)
    }
    .padding(Spacing.s300)
    .readableWidth()
  }

  @ViewBuilder private var indicator: some View {
    VStack(spacing: Spacing.s100) {
      if model.isEditingText, model.selectedTextRegion == nil {
        TextEditHint(model: model)
      }
      if let selection = model.selection {
        SelectionBar(
          selection: selection,
          onEdit: {
            selectionText = selection.text ?? ""
            isEditingSelection = true
          },
          onDelete: { Task { await model.deleteSelection() } },
          onDone: { model.clearSelection() },
          onMove: { offset in Task { await model.moveSelection(by: offset) } },
          onResize: { factor in Task { await model.resizeSelection(by: factor) } },
          onColor: { color in Task { await model.setSelectionColor(color) } })
      }
      if model.isDrawing {
        Label {
          // With a shape in hand, what is already on the page can be moved; that is said, or
          // nobody finds it.
          if model.selection != nil {
            Text("Drag it to move it", bundle: .module)
          } else if model.drawingTool == .pen {
            Text("Draw on the page", bundle: .module)
          } else {
            Text("Drag to draw. Drag a shape to move it.", bundle: .module)
          }
        } icon: {
          Image(systemName: "pencil.tip")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Spacing.s200)
        .padding(.vertical, Spacing.s100)
        .background(.regularMaterial, in: Capsule())
        .accessibilityIdentifier("reader.drawingHint")
      }
      if let tool = model.markupTool {
        Label {
          switch tool {
          case .highlight: Text("Drag across text to highlight it", bundle: .module)
          case .underline: Text("Drag across text to underline it", bundle: .module)
          case .strikeThrough: Text("Drag across text to strike it through", bundle: .module)
          }
        } icon: {
          Image(systemName: "hand.draw")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Spacing.s200)
        .padding(.vertical, Spacing.s100)
        .background(.regularMaterial, in: Capsule())
        .accessibilityIdentifier("reader.markupHint")
      }
      if let progress = model.recognitionProgress {
        HStack {
          ProgressView(value: progress) { Text("Recognising text on this device…", bundle: .module) }
          Button {
            model.cancelRecognition()
          } label: {
            Text("Cancel", bundle: .module)
          }
        }
        .padding(Spacing.s150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      Text(model.pageLabel)
        .font(.footnote.monospacedDigit())
        .padding(.horizontal, Spacing.s150)
        .padding(.vertical, Spacing.s050)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel(Text("Page \(model.pageLabel)", bundle: .module))
        .accessibilityIdentifier("reader.pageIndicator")
    }
    .padding(Spacing.s200)
  }

}
