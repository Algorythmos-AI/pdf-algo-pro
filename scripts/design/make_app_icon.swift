// Generates the interim app icon from the design tokens (a Design-owned icon replaces it later).
//
//   swift scripts/design/make_app_icon.swift
//
// Writes three 1024 x 1024 PNGs into App/PDFAlgoPro/Resources/Assets.xcassets/AppIcon.appiconset:
// - AppIcon.png, the default appearance: opaque RGB with no alpha channel, as App Store Connect
//   requires for the large icon (upload error 90717);
// - AppIcon-Dark.png: the glyph on a transparent background (the system draws the dark background);
// - AppIcon-Tinted.png: a greyscale glyph on a transparent background (the system applies the tint).
// The artwork is a page with text lines and a sparkle, in the brand and intelligence colours.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent()
let iconSet = root.appendingPathComponent("App/PDFAlgoPro/Resources/Assets.xcassets/AppIcon.appiconset")
let size = 1024

// MARK: - Tokens

struct RGBColor {
  let red, green, blue: CGFloat

  init(hex: String) {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt32(digits, radix: 16) ?? 0
    red = CGFloat((value >> 16) & 0xFF) / 255
    green = CGFloat((value >> 8) & 0xFF) / 255
    blue = CGFloat(value & 0xFF) / 255
  }

  func cgColor(alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

  /// Rec. 709 luma, for the tinted (greyscale) variant.
  var grey: CGFloat { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// The appearance values of a colour token, for example `color.brand.tint`.
func token(_ path: String, _ appearance: String) -> RGBColor {
  let data = try! Data(contentsOf: root.appendingPathComponent("design/tokens.json"))
  var node = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  for key in path.split(separator: ".").dropLast() { node = node[String(key)] as! [String: Any] }
  let leaf = node[String(path.split(separator: ".").last!)] as! [String: Any]
  let extensions = leaf["$extensions"] as! [String: Any]
  let appearances = extensions["com.algorythmos.appearances"] as! [String: String]
  return RGBColor(hex: appearances[appearance]!)
}

let brandStrong = token("color.brand.strong", "light")
let brandTint = token("color.brand.tint", "light")
let brandDark = token("color.brand.tint", "dark")
let intelligenceDark = token("color.intelligence.tint", "dark")

// MARK: - Drawing

enum Variant { case standard, dark, tinted }

func draw(_ variant: Variant, in context: CGContext) {
  let canvas = CGRect(x: 0, y: 0, width: size, height: size)
  if variant == .standard {
    // A diagonal gradient from the strong brand colour to the brand tint.
    let colors = [brandStrong.cgColor(), brandTint.cgColor()] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
      gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
  } else {
    context.clear(canvas)
  }

  let pageColor: CGColor
  let lineColor: CGColor
  let sparkleColor: CGColor
  switch variant {
  case .standard:
    pageColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    lineColor = brandTint.cgColor(alpha: 0.35)
    sparkleColor = intelligenceDark.cgColor()
  case .dark:
    pageColor = brandDark.cgColor()
    lineColor = CGColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 0.45)
    sparkleColor = intelligenceDark.cgColor()
  case .tinted:
    pageColor = CGColor(gray: 1, alpha: 1)
    lineColor = CGColor(gray: 0, alpha: 0.35)
    sparkleColor = CGColor(gray: intelligenceDark.grey, alpha: 1)
  }

  // The page, with a folded corner.
  let page = CGRect(x: 292, y: 212, width: 440, height: 600)
  let fold: CGFloat = 120
  let path = CGMutablePath()
  path.move(to: CGPoint(x: page.minX + 36, y: page.minY))
  path.addLine(to: CGPoint(x: page.maxX - 36, y: page.minY))
  path.addQuadCurve(to: CGPoint(x: page.maxX, y: page.minY + 36), control: CGPoint(x: page.maxX, y: page.minY))
  path.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
  path.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
  path.addLine(to: CGPoint(x: page.minX + 36, y: page.maxY))
  path.addQuadCurve(to: CGPoint(x: page.minX, y: page.maxY - 36), control: CGPoint(x: page.minX, y: page.maxY))
  path.addLine(to: CGPoint(x: page.minX, y: page.minY + 36))
  path.addQuadCurve(to: CGPoint(x: page.minX + 36, y: page.minY), control: CGPoint(x: page.minX, y: page.minY))
  path.closeSubpath()
  context.setFillColor(pageColor)
  context.addPath(path)
  context.fillPath()

  // The fold.
  let foldPath = CGMutablePath()
  foldPath.move(to: CGPoint(x: page.maxX, y: page.maxY - fold))
  foldPath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
  foldPath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
  foldPath.closeSubpath()
  context.setFillColor(lineColor)
  context.addPath(foldPath)
  context.fillPath()

  // Text lines.
  context.setFillColor(lineColor)
  for (index, width) in [300.0, 340, 260, 320, 200].enumerated() {
    let y = page.minY + 110 + CGFloat(index) * 72
    context.addPath(
      CGPath(
        roundedRect: CGRect(x: page.minX + 60, y: y, width: CGFloat(width), height: 28), cornerWidth: 14,
        cornerHeight: 14, transform: nil))
    context.fillPath()
  }

  // The sparkle: a four-pointed star over the top-left corner of the page.
  let centre = CGPoint(x: 300, y: 790)
  let outer: CGFloat = 150
  let inner: CGFloat = 38
  let star = CGMutablePath()
  for point in 0..<8 {
    let angle = CGFloat(point) * .pi / 4 + .pi / 2
    let radius = point.isMultiple(of: 2) ? outer : inner
    let vertex = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
    if point == 0 { star.move(to: vertex) } else { star.addLine(to: vertex) }
  }
  star.closeSubpath()
  if variant == .standard {
    // A thin ring in the background colour separates the sparkle from the page.
    context.setStrokeColor(brandStrong.cgColor())
    context.setLineWidth(24)
    context.setLineJoin(.round)
    context.addPath(star)
    context.strokePath()
  }
  context.setFillColor(sparkleColor)
  context.addPath(star)
  context.fillPath()
}

func render(_ variant: Variant, to name: String) {
  let opaque = variant == .standard
  let space = variant == .tinted ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
  let bitmapInfo: UInt32
  if variant == .tinted {
    bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
  } else {
    bitmapInfo = (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
  }
  let context: CGContext
  if variant == .tinted {
    // Grey with alpha is not a supported bitmap context; draw in RGB and convert the pixels to grey.
    context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  } else {
    context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: bitmapInfo)!
  }
  draw(variant, in: context)
  var image = context.makeImage()!
  if variant == .tinted {
    // Convert to greyscale with alpha, pixel by pixel (Rec. 709 luma on premultiplied values).
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let count = size * size
    var grey = [UInt8](repeating: 0, count: count * 2)
    for pixel in 0..<count {
      let r = Double(data[pixel * 4])
      let g = Double(data[pixel * 4 + 1])
      let b = Double(data[pixel * 4 + 2])
      let a = data[pixel * 4 + 3]
      grey[pixel * 2] = UInt8(min(255, (0.2126 * r + 0.7152 * g + 0.0722 * b).rounded()))
      grey[pixel * 2 + 1] = a
    }
    let provider = CGDataProvider(data: Data(grey) as CFData)!
    image = CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 16, bytesPerRow: size * 2,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }
  let url = iconSet.appendingPathComponent(name)
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(name)") }
  print("wrote \(url.path)")
}

render(.standard, to: "AppIcon.png")
render(.dark, to: "AppIcon-Dark.png")
render(.tinted, to: "AppIcon-Tinted.png")

let contents = """
  {
    "images" : [
      { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
      {
        "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
        "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
      },
      {
        "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
        "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
      }
    ],
    "info" : { "author" : "xcode", "version" : 1 }
  }

  """
try! contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
