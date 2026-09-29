import Core
import DesignSystem
import PDFEngine
import SwiftUI

/// The reader: the page surface, a floating page indicator, and tools in the toolbar.
///
/// Chrome recedes so the document is the interface (design system, principle 2).
public struct ReaderView<Assistant: View>: View {
  @State private var model: ReaderModel
  @State private var password = ""
  @State private var noteText = ""
  @State private var isAddingNote = false
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
      .toolbar { toolbar }
      .sheet(item: $model.assistantTask) { task in
        assistant(model.assistantContext(for: task))
      }
      .sheet(isPresented: $model.showsOutline) { outline }
      .sheet(isPresented: $model.showsPages) { pageGrid }
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
      .onDisappear {
        model.speech.stop()
        Task {
          await model.save()
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

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      if model.phase == .ready {
        if model.showsIntelligence {
          Menu {
            Button {
              model.assistantTask = .summarize
            } label: {
              Label {
                Text("Summarise", bundle: .module)
              } icon: {
                Image(systemName: "text.append")
              }
            }
            Button {
              model.assistantTask = .ask
            } label: {
              Label {
                Text("Ask a question", bundle: .module)
              } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right")
              }
            }
            Button {
              model.assistantTask = .extract
            } label: {
              Label {
                Text("Extract data", bundle: .module)
              } icon: {
                Image(systemName: "tablecells")
              }
            }
            Button {
              model.assistantTask = .explainContract
            } label: {
              Label {
                Text("Explain contract", bundle: .module)
              } icon: {
                Image(systemName: "doc.text.magnifyingglass")
              }
            }
          } label: {
            Label {
              Text("Ask", bundle: .module)
            } icon: {
              Image(systemName: "sparkles")
            }
          }
          .accessibilityIdentifier("reader.ask")
        }
        Menu {
          ForEach(TextMarkup.allCases, id: \.self) { markup in
            Button {
              Task { await model.markUpSelection(markup) }
            } label: {
              Self.label(for: markup)
            }
          }
          Button {
            isAddingNote = true
          } label: {
            Label {
              Text("Add note", bundle: .module)
            } icon: {
              Image(systemName: "note.text.badge.plus")
            }
          }
          Button {
            Task { await model.undo() }
          } label: {
            Label {
              Text("Undo", bundle: .module)
            } icon: {
              Image(systemName: "arrow.uturn.backward")
            }
          }
        } label: {
          Label {
            Text("Markup", bundle: .module)
          } icon: {
            Image(systemName: "highlighter")
          }
        }
        .accessibilityIdentifier("reader.markup")
        Menu {
          Button {
            model.showsPages = true
          } label: {
            Label {
              Text("Pages", bundle: .module)
            } icon: {
              Image(systemName: "square.grid.2x2")
            }
          }
          Button {
            model.showsOutline = true
          } label: {
            Label {
              Text("Contents", bundle: .module)
            } icon: {
              Image(systemName: "list.bullet.indent")
            }
          }
          Picker(
            selection: Binding(get: { model.controller?.displayMode ?? .continuous }, set: { model.setDisplayMode($0) })
          ) {
            Text("Continuous", bundle: .module).tag(ReaderDisplayMode.continuous)
            Text("Single page", bundle: .module).tag(ReaderDisplayMode.singlePage)
          } label: {
            Text("Layout", bundle: .module)
          }
          Button {
            model.toggleReadAloud()
          } label: {
            Label {
              model.speech.isSpeaking ? Text("Stop reading", bundle: .module) : Text("Read aloud", bundle: .module)
            } icon: {
              Image(systemName: model.speech.isSpeaking ? "stop.circle" : "speaker.wave.2")
            }
          }
          if model.canRecognizeText {
            Button {
              model.recognizeText()
            } label: {
              Label {
                Text("Recognise text", bundle: .module)
              } icon: {
                Image(systemName: "text.viewfinder")
              }
            }
          }
        } label: {
          Label {
            Text("More", bundle: .module)
          } icon: {
            Image(systemName: "ellipsis.circle")
          }
        }
        .accessibilityIdentifier("reader.more")
      }
    }
  }

  private var outline: some View {
    NavigationStack {
      Group {
        let items = model.controller?.outline ?? []
        if items.isEmpty {
          EmptyState(Text("No table of contents", bundle: .module), systemImage: "list.bullet.indent") {
            Text("This document doesn't include one. Use Pages to jump to a page.", bundle: .module)
          }
        } else {
          List(items) { item in
            Button {
              model.controller?.goTo(pageIndex: item.pageIndex)
              model.showsOutline = false
            } label: {
              HStack {
                Text(item.title).padding(.leading, CGFloat(item.depth) * Spacing.s200)
                Spacer()
                Text("\(item.pageIndex + 1)").foregroundStyle(Color.ds.labelSecondary).monospacedDigit()
              }
            }
          }
        }
      }
      .navigationTitle(Text("Contents", bundle: .module))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            model.showsOutline = false
          } label: {
            Text("Done", bundle: .module)
          }
        }
      }
    }
  }

  private var pageGrid: some View {
    NavigationStack {
      PageGrid(model: model)
        .navigationTitle(Text("Pages", bundle: .module))
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              model.showsPages = false
            } label: {
              Text("Done", bundle: .module)
            }
          }
        }
    }
  }

  static func label(for markup: TextMarkup) -> Label<Text, Image> {
    switch markup {
    case .highlight:
      Label {
        Text("Highlight", bundle: .module)
      } icon: {
        Image(systemName: "highlighter")
      }
    case .underline:
      Label {
        Text("Underline", bundle: .module)
      } icon: {
        Image(systemName: "underline")
      }
    case .strikeThrough:
      Label {
        Text("Strike through", bundle: .module)
      } icon: {
        Image(systemName: "strikethrough")
      }
    }
  }
}

/// A grid of page thumbnails; tapping one jumps to it (FR-READ-002).
struct PageGrid: View {
  let model: ReaderModel
  private let thumbnails = ThumbnailCache()

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.s200)], spacing: Spacing.s200) {
        ForEach(0..<(model.controller?.pageCount ?? 0), id: \.self) { pageIndex in
          Button {
            model.controller?.goTo(pageIndex: pageIndex)
            model.showsPages = false
          } label: {
            PageThumbnail(
              pageIndex: pageIndex, url: model.fileURL, version: model.document?.modifiedAt ?? .distantPast,
              cache: thumbnails,
              isCurrent: model.controller?.currentPageIndex == pageIndex)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Page \(pageIndex + 1)", bundle: .module))
        }
      }
      .padding(Spacing.s200)
    }
  }
}

private struct PageThumbnail: View {
  let pageIndex: Int
  let url: URL?
  let version: Date
  let cache: ThumbnailCache
  let isCurrent: Bool
  @State private var image: CGImage?

  var body: some View {
    VStack(spacing: Spacing.s050) {
      Group {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
          Color.ds.backgroundSecondary
        }
      }
      .frame(height: 128)
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isCurrent ? Color.ds.brandTint : .clear, lineWidth: 2))
      Text("\(pageIndex + 1)").font(.caption.monospacedDigit())
    }
    .task(id: url) {
      guard let url else { return }
      image = await cache.thumbnail(for: url, pageIndex: pageIndex, version: version, maximumPixelSize: 256)
    }
  }
}
