import CoreGraphics

/// Images of pages on their way into a document.
public enum PageImage {
  /// An image brought down so that its longer side is at most `longestSide`, keeping its shape.
  ///
  /// An image already no larger is returned as it is: nothing is ever scaled up. `nil` when Core
  /// Graphics can't draw it.
  public static func scaledDown(_ image: CGImage, toLongestSide longestSide: Int) -> CGImage? {
    let longest = max(image.width, image.height)
    guard longest > longestSide, longestSide > 0 else { return image }
    let scale = Double(longestSide) / Double(longest)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let keepsColors = image.colorSpace.map { $0.model == .rgb && $0.supportsOutput } ?? false
    let hasAlpha: Bool
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
    default: hasAlpha = true
    }
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: keepsColors ? image.colorSpace ?? sRGB : sRGB,
        bitmapInfo: (hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
