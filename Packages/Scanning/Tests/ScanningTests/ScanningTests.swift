import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import VisionKit

@testable import Scanning

@Suite("Scanning")
struct ScanningTests {
  private func pngFile(width: Int, height: Int) throws -> URL {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  @Test("Chosen images load in order; non-images are skipped; large images are scaled down")
  func loadsImages() throws {
    let small = try pngFile(width: 300, height: 400)
    let large = try pngFile(width: 4000, height: 2000)
    let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).txt")
    try Data("not an image".utf8).write(to: text)
    let images = ImageLoader.images(at: [small, text, large])
    #expect(images.count == 2)
    #expect(images[0].width == 300)
    #expect(max(images[1].width, images[1].height) == 3000)
  }

  // Simulators disagree: the iOS 26.5 simulator reports no document camera on CI runners but reports
  // one on a development Mac. So only the pass-through is checked, not the answer.
  @MainActor
  @Test func theDocumentCameraAsksVisionKitWhetherItIsSupported() {
    #expect(DocumentCamera.isSupported == VNDocumentCameraViewController.isSupported)
    _ = DocumentCameraView(onFinish: { _ in }, onCancel: {}).makeCoordinator()
  }
}
