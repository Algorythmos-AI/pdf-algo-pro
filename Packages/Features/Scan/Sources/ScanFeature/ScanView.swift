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
      Group {
        switch model.phase {
        case .ready: ready
        case .recognizing(let progress): recognizing(progress)
        case .finished: ProgressView()
        case .failed:
          ContentUnavailableView {
            Label {
              Text("The scan wasn't saved", bundle: .module)
            } icon: {
              Image(systemName: "exclamationmark.triangle")
            }
          } description: {
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
          Task { await model.process(images) }
        } onCancel: {
          showsCamera = false
        }
        .ignoresSafeArea()
      }
      .fileImporter(isPresented: $isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) {
        result in
        if case .success(let urls) = result { Task { await model.process(ImageLoader.images(at: urls)) } }
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
    }
    .readableWidth()
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
  }
}
