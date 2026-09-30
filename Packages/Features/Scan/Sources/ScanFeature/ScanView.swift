import Core
import DesignSystem
import Scanning
import SwiftUI
import UniformTypeIdentifiers

/// The scanner sheet: the system document camera where there is one, and images from Files
/// everywhere, so every device can make searchable PDFs.
public struct ScanView: View {
  @State private var model: ScanModel
  @State private var showsCamera = false
  @State private var isChoosingImages = false
  @Environment(\.dismiss) private var dismiss

  /// Creates the sheet for a model.
  public init(model: ScanModel) {
    _model = State(initialValue: model)
  }

  /// The sheet.
  public var body: some View {
    NavigationStack {
      content
        .padding(Spacing.s200)
        .navigationTitle(Text("Scan", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              model.cancel()
              dismiss()
            } label: {
              Text("Cancel", bundle: .module)
            }
          }
        }
        .fullScreenCover(isPresented: $showsCamera) {
          DocumentCameraView { images in
            showsCamera = false
            Task { await model.review(images) }
          } onCancel: {
            showsCamera = false
          }
          .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) {
          result in
          if case .success(let urls) = result { Task { await model.process(files: urls) } }
        }
    }
  }

  /// What the current phase shows; outside the navigation stack so tests can draw every phase.
  @ViewBuilder var content: some View {
    switch model.phase {
    case .ready: ready
    case .reviewing: reviewing
    case .recognizing(let progress): recognizing(progress)
    case .finished: ProgressView()
    case .failed:
      EmptyState(Text("The scan wasn't saved", bundle: .module), systemImage: "exclamationmark.triangle") {
        Text("Text recognition didn't finish. Nothing was added to your library.", bundle: .module)
      } actions: {
        Button {
          model.reset()
        } label: {
          Text("Try again", bundle: .module).minimumTarget()
        }
      }
    }
  }

  private var ready: some View {
    VStack(spacing: Spacing.s300) {
      Image(systemName: "doc.viewfinder").font(.system(.largeTitle)).foregroundStyle(Color.ds.brandTint)
        .accessibilityHidden(true)
      Text(
        "Scanned pages become a searchable PDF. Text is recognised on this device, in English and French.",
        bundle: .module
      )
      .multilineTextAlignment(.center)
      .foregroundStyle(Color.ds.labelSecondary)
      if DocumentCamera.isSupported {
        Button {
          showsCamera = true
        } label: {
          Text("Scan with camera", bundle: .module)
        }
        .buttonStyle(.primary)
        .accessibilityIdentifier("scan.camera")
      } else {
        Text("This device has no document camera. You can make a PDF from photos of pages instead.", bundle: .module)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color.ds.labelSecondary)
          .accessibilityIdentifier("scan.noCamera")
      }
      Button {
        isChoosingImages = true
      } label: {
        Text("Choose images", bundle: .module).minimumTarget()
      }
      .accessibilityIdentifier("scan.images")
      if let notice = model.notice {
        Text(notice)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color.ds.labelSecondary)
          .accessibilityIdentifier("scan.notice")
      }
    }
    .readableWidth()
    .centeredScrolling()
  }

  /// The pages and name, checked before saving (FR-SCAN-006).
  private var reviewing: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.s200) {
        TextField(text: $model.title) { Text("Name", bundle: .module) }
          .textFieldStyle(.roundedBorder)
          .font(.headline)
          .accessibilityLabel(Text("Name", bundle: .module))
          .accessibilityIdentifier("scan.title")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.s200)], spacing: Spacing.s200) {
          ForEach(Array(model.pages.enumerated()), id: \.offset) { index, page in
            Menu {
              Button {
                model.rotatePage(at: index)
              } label: {
                Label {
                  Text("Rotate", bundle: .module)
                } icon: {
                  Image(systemName: "rotate.right")
                }
              }
              if index > 0 {
                Button {
                  model.movePage(at: index, earlier: true)
                } label: {
                  Label {
                    Text("Move earlier", bundle: .module)
                  } icon: {
                    Image(systemName: "arrow.left")
                  }
                }
              }
              if index < model.pages.count - 1 {
                Button {
                  model.movePage(at: index, earlier: false)
                } label: {
                  Label {
                    Text("Move later", bundle: .module)
                  } icon: {
                    Image(systemName: "arrow.right")
                  }
                }
              }
              if model.pages.count > 1 {
                Button(role: .destructive) {
                  model.deletePage(at: index)
                } label: {
                  Label {
                    Text("Delete page", bundle: .module)
                  } icon: {
                    Image(systemName: "trash")
                  }
                }
              }
            } label: {
              VStack(spacing: Spacing.s050) {
                Image(decorative: page, scale: 1).resizable().scaledToFit().frame(height: 140)
                Text("\(index + 1)").font(.caption.monospacedDigit())
              }
            }
            .accessibilityLabel(Text("Page \(index + 1)", bundle: .module))
          }
        }
        Button {
          Task { await model.save() }
        } label: {
          Text("Save", bundle: .module).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .accessibilityIdentifier("scan.save")
        Button {
          model.discardReview()
        } label: {
          Text("Discard", bundle: .module).minimumTarget().frame(maxWidth: .infinity)
        }
      }
      .readableWidth()
    }
  }

  private func recognizing(_ progress: Double) -> some View {
    VStack(spacing: Spacing.s200) {
      ProgressView(value: progress) { Text("Recognising text on this device…", bundle: .module) }
      Button {
        model.cancel()
      } label: {
        Text("Stop", bundle: .module).minimumTarget()
      }
    }
    .readableWidth()
    .centeredScrolling()
  }
}
