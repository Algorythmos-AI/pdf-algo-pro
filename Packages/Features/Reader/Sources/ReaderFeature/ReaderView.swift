import Core
import DesignSystem
import PDFEngine
import SwiftUI
import UIKit

/// The reader: the page surface, a floating page indicator, and tools in the toolbar.
///
/// Chrome recedes so the document is the interface (design system, principle 2).
public struct ReaderView<Assistant: View>: View {
  @State private var model: ReaderModel
  @State private var password = ""
  @State private var noteText = ""
  @State private var isAddingNote = false
  @State private var pageNumber = ""
  @Environment(\.scenePhase) private var scenePhase
  private let assistant: (ReaderAssistantContext) -> Assistant

  /// Creates the reader; `assistant` builds the assistant sheet, supplied by the app.
  public init(model: ReaderModel, @ViewBuilder assistant: @escaping (ReaderAssistantContext) -> Assistant) {
    _model = State(initialValue: model)
    self.assistant = assistant
  }

  /// The reader.
  public var body: some View {
    content
      .navigationTitle(model.document?.title ?? "")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ReaderToolbar(model: model, isAddingNote: $isAddingNote) }
      .sheet(item: $model.assistantTask) { task in
        assistant(model.assistantContext(for: task))
      }
      .sheet(isPresented: $model.showsOutline) { OutlineSheet(model: model) }
      .sheet(isPresented: $model.showsPages) { PageGridSheet(model: model) }
      .alert(Text("Add a note", bundle: .module), isPresented: $isAddingNote) {
        TextField(text: $noteText) { Text("Note", bundle: .module) }
        Button {
          Task { await model.addNote(noteText) }
          noteText = ""
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
      .task { await model.load() }
      .onChange(of: model.controller?.currentPageIndex) { Task { await model.recordPosition() } }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .background else { return }
        Task { await model.saveBeforeSuspending(keepAlive: Self.beginBackgroundTask) }
      }
      .onDisappear {
        model.speech.stop()
        Task {
          await model.save()
          await model.recordPosition()
        }
      }
  }

  /// Asks iOS for time to finish saving after the app moves to the background.
  ///
  /// Returns the call that ends the request. If the time runs out first, the request is ended then.
  private static func beginBackgroundTask() -> @MainActor () -> Void {
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(withName: "Save document") {
      UIApplication.shared.endBackgroundTask(identifier)
      identifier = .invalid
    }
    return {
      guard identifier != .invalid else { return }
      UIApplication.shared.endBackgroundTask(identifier)
      identifier = .invalid
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
      }
    case .ready:
      if let controller = model.controller {
        PDFReaderView(controller: controller)
          .ignoresSafeArea(edges: .bottom)
          .accessibilityLabel(Text("Document pages", bundle: .module))
          .accessibilityIdentifier("reader.pages")
          .overlay(alignment: .bottom) { indicator }
      }
    }
  }

  private func locked(wrongPassword: Bool) -> some View {
    VStack(spacing: Spacing.s200) {
      Image(systemName: "lock.doc").font(.largeTitle).foregroundStyle(Color.ds.labelSecondary).accessibilityHidden(true)
      Text("This document is password protected", bundle: .module).font(.headline)
      SecureField(text: $password) { Text("Password", bundle: .module) }
        .textFieldStyle(.roundedBorder)
        .submitLabel(.go)
        .onSubmit { model.unlock(password: password) }
        .accessibilityIdentifier("reader.password")
      if wrongPassword {
        Label {
          Text("That password didn't open the document.", bundle: .module)
        } icon: {
          Image(systemName: "xmark.octagon")
        }
        .foregroundStyle(Color.ds.statusError)
        .font(.footnote)
      }
      Button {
        model.unlock(password: password)
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
