import CoreGraphics
import SwiftUI
import UIKit
import VisionKit

/// The system document camera: edge detection, perspective correction and multi-page capture (FR-SCAN-001).
///
/// The camera permission is requested by the system the first time it opens.
public enum DocumentCamera {
  /// Whether this device has a document camera (the simulator does not).
  @MainActor public static var isSupported: Bool { VNDocumentCameraViewController.isSupported }
}

/// The document camera in a SwiftUI adapter (ADR-0003: UIKit stays in adapters).
public struct DocumentCameraView: UIViewControllerRepresentable {
  private let onFinish: ([CGImage]) -> Void
  private let onCancel: () -> Void

  /// Creates the camera; `onFinish` receives the captured pages in order.
  public init(onFinish: @escaping ([CGImage]) -> Void, onCancel: @escaping () -> Void) {
    self.onFinish = onFinish
    self.onCancel = onCancel
  }

  /// Creates the camera controller.
  public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  /// Nothing to update.
  public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

  /// Creates the delegate.
  public func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish, onCancel: onCancel)
  }

  /// Receives the camera's callbacks, which VisionKit delivers on the main thread.
  @MainActor
  public final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    private let onFinish: ([CGImage]) -> Void
    private let onCancel: () -> Void

    init(onFinish: @escaping ([CGImage]) -> Void, onCancel: @escaping () -> Void) {
      self.onFinish = onFinish
      self.onCancel = onCancel
    }

    /// The user saved the scan.
    public func documentCameraViewController(
      _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
    ) {
      let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage }
      onFinish(pages)
    }

    /// The user cancelled.
    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      onCancel()
    }

    /// The camera failed; treated like a cancel, and nothing is saved.
    public func documentCameraViewController(
      _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
    ) {
      onCancel()
    }
  }
}
