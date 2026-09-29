import CoreGraphics
import Foundation
import ImageIO

/// Loads images from files (photos of documents chosen in Files) for scanning without a camera.
public enum ImageLoader {
  /// The images at the URLs, in order, skipping anything that is not an image.
  public static func images(at urls: [URL]) -> [CGImage] {
    urls.compactMap { url in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options =
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 3000,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
      return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
  }
}
