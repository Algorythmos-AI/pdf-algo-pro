// Generates the app icon (version 2, approved by the owner on 2026-10-01) from the design tokens.
//
//   swift scripts/design/make_app_icon.swift
//
// Writes three 1024 x 1024 PNGs into each of two icon sets in App/PDFAlgoPro/Resources/Assets.xcassets,
// AppIcon.appiconset (Debug and Release) and AppIcon-Staging.appiconset (Staging, with a beta badge):
// - the default appearance: opaque RGB with no alpha channel, as App Store Connect requires for the
//   large icon (upload error 90717);
// - the dark appearance: the glyph on a transparent background (the system draws the dark background);
// - the tinted appearance: a greyscale glyph on a transparent background (the system applies the tint).
// It also writes an Icon Composer document beside the catalog for each set (AppIcon.icon and
// AppIcon-Staging.icon): the same artwork in layers, which iOS 26 renders with Liquid Glass. The build
// uses the document; the PNGs are what the document is checked against and what older tools read.
// The artwork is a large page carrying a "PDF" mark drawn as paths (no font) and the intelligence
// sparkle, on a crimson-to-violet field. Coordinates have their origin at the bottom left, y up.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent()
let catalog = root.appendingPathComponent("App/PDFAlgoPro/Resources/Assets.xcassets")
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

let brandTint = token("color.brand.tint", "light")
let intelligenceDark = token("color.intelligence.tint", "dark")
let gradientStart = token("color.icon.gradientStart", "light")
let gradientMid = token("color.icon.gradientMid", "light")
let foldTint = token("color.icon.fold", "light")
let stagingBadge = token("color.icon.stagingBadge", "light")
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// MARK: - Shapes

enum Variant { case standard, dark, tinted }

let page = CGRect(x: 200, y: 110, width: 624, height: 804)
let fold: CGFloat = 190

/// The page outline, with the top-right corner cut off for the fold.
func pagePath() -> CGPath {
  let radius: CGFloat = 56
  let path = CGMutablePath()
  path.move(to: CGPoint(x: page.minX + radius, y: page.minY))
  path.addLine(to: CGPoint(x: page.maxX - radius, y: page.minY))
  path.addQuadCurve(to: CGPoint(x: page.maxX, y: page.minY + radius), control: CGPoint(x: page.maxX, y: page.minY))
  path.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
  path.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
  path.addLine(to: CGPoint(x: page.minX + radius, y: page.maxY))
  path.addQuadCurve(to: CGPoint(x: page.minX, y: page.maxY - radius), control: CGPoint(x: page.minX, y: page.maxY))
  path.addLine(to: CGPoint(x: page.minX, y: page.minY + radius))
  path.addQuadCurve(to: CGPoint(x: page.minX + radius, y: page.minY), control: CGPoint(x: page.minX, y: page.minY))
  path.closeSubpath()
  return path
}

func foldPath() -> CGPath {
  let path = CGMutablePath()
  path.move(to: CGPoint(x: page.maxX, y: page.maxY - fold))
  path.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
  path.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
  path.closeSubpath()
  return path
}

/// The letters P, D and F as centre lines to stroke with `markStem`, so the mark needs no font.
let markStem: CGFloat = 64
func pdfMark() -> CGPath {
  let bottom: CGFloat = 330
  let top: CGFloat = 580
  let half = markStem / 2
  let bar = top - half - 96  // the bottom of the P's bowl and the F's middle bar
  let path = CGMutablePath()

  // P: 140 wide.
  var x: CGFloat = 277
  path.move(to: CGPoint(x: x + half, y: bottom))
  path.addLine(to: CGPoint(x: x + half, y: top - half))
  path.addLine(to: CGPoint(x: x + 140 - half - 48, y: top - half))
  path.addArc(
    center: CGPoint(x: x + 140 - half - 48, y: top - half - 48), radius: 48, startAngle: .pi / 2,
    endAngle: -.pi / 2, clockwise: true)
  path.addLine(to: CGPoint(x: x + half, y: bar))

  // D: 160 wide.
  x += 140 + 22
  let bowl = (top - bottom - markStem) / 2
  path.move(to: CGPoint(x: x + half, y: bottom + half))
  path.addLine(to: CGPoint(x: x + half, y: top - half))
  path.addLine(to: CGPoint(x: x + 160 - half - bowl, y: top - half))
  path.addArc(
    center: CGPoint(x: x + 160 - half - bowl, y: bottom + half + bowl), radius: bowl, startAngle: .pi / 2,
    endAngle: -.pi / 2, clockwise: true)
  path.closeSubpath()

  // F: 125 wide.
  x += 160 + 22
  path.move(to: CGPoint(x: x + half, y: bottom))
  path.addLine(to: CGPoint(x: x + half, y: top - half))
  path.addLine(to: CGPoint(x: x + 125, y: top - half))
  path.move(to: CGPoint(x: x + half, y: bar))
  path.addLine(to: CGPoint(x: x + 107, y: bar))
  return path
}

let rule = CGPath(
  roundedRect: CGRect(x: 362, y: 232, width: 300, height: 36), cornerWidth: 18, cornerHeight: 18, transform: nil)

/// The sparkle: a four-pointed star over the top-left corner of the page.
func sparklePath() -> CGPath {
  let centre = CGPoint(x: 290, y: 800)
  let star = CGMutablePath()
  for point in 0..<8 {
    let angle = CGFloat(point) * .pi / 4 + .pi / 2
    let radius: CGFloat = point.isMultiple(of: 2) ? 180 : 46
    let vertex = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
    if point == 0 { star.move(to: vertex) } else { star.addLine(to: vertex) }
  }
  star.closeSubpath()
  return star
}

// MARK: - Drawing

/// The crimson-to-violet gradient, from the top left to the bottom right of the canvas.
func fillGradient(in context: CGContext) {
  let colors = [gradientStart.cgColor(), gradientMid.cgColor(), brandTint.cgColor()] as CFArray
  let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
}

/// Runs `body` so that what it draws erases what is below it; the system's background shows through.
func knockOut(in context: CGContext, _ body: () -> Void) {
  context.saveGState()
  context.setBlendMode(.destinationOut)
  body()
  context.restoreGState()
}

/// The beta badge of the Staging icon: a pill over the bottom-right corner of the page.
func drawStagingBadge(_ variant: Variant, in context: CGContext) {
  let rect = CGRect(x: 640, y: 120, width: 250, height: 150)
  let pill = CGPath(roundedRect: rect, cornerWidth: 75, cornerHeight: 75, transform: nil)
  // A gap around the pill separates it from the page.
  if variant == .standard {
    context.setStrokeColor(white)
    context.setLineWidth(20)
    context.addPath(pill)
    context.strokePath()
  } else {
    knockOut(in: context) {
      context.setStrokeColor(white)
      context.setLineWidth(40)
      context.addPath(pill)
      context.strokePath()
    }
  }
  context.setFillColor(variant == .tinted ? white : stagingBadge.cgColor())
  context.addPath(pill)
  context.fillPath()

  let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 130, nil)!
  let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
  ]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: "β", attributes: attributes))
  let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
  let drawGlyph = {
    context.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
    CTLineDraw(line, context)
  }
  if variant == .tinted { knockOut(in: context, drawGlyph) } else { drawGlyph() }
}

func draw(_ variant: Variant, staging: Bool, in context: CGContext) {
  if variant == .standard { fillGradient(in: context) } else { context.clear(CGRect(x: 0, y: 0, width: size, height: size)) }

  // The page: white, or the gradient where the system supplies a dark background.
  if variant == .dark {
    context.saveGState()
    context.addPath(pagePath())
    context.clip()
    fillGradient(in: context)
    context.restoreGState()
  } else {
    context.setFillColor(white)
    context.addPath(pagePath())
    context.fillPath()
  }

  switch variant {
  case .standard: context.setFillColor(foldTint.cgColor())
  case .dark: context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
  case .tinted: context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
  }
  context.addPath(foldPath())
  context.fillPath()

  // The "PDF" mark and the rule under it.
  let drawMark = {
    context.setStrokeColor(variant == .standard ? brandTint.cgColor() : white)
    context.setLineWidth(markStem)
    context.setLineCap(.butt)
    context.setLineJoin(.miter)
    context.addPath(pdfMark())
    context.strokePath()
    context.setFillColor(variant == .standard ? brandTint.cgColor(alpha: 0.35) : white)
    context.addPath(rule)
    context.fillPath()
  }
  if variant == .standard { drawMark() } else { knockOut(in: context, drawMark) }

  // The sparkle, with a ring that separates it from the page and the field.
  let star = sparklePath()
  let ring = {
    context.setStrokeColor(white)
    context.setLineWidth(56)
    context.setLineJoin(.round)
    context.addPath(star)
    context.strokePath()
  }
  if variant == .standard { ring() } else { knockOut(in: context, ring) }
  let grey = intelligenceDark.grey
  context.setFillColor(
    variant == .tinted ? CGColor(srgbRed: grey, green: grey, blue: grey, alpha: 1) : intelligenceDark.cgColor())
  context.addPath(star)
  context.fillPath()

  if staging { drawStagingBadge(variant, in: context) }
}

func render(_ variant: Variant, staging: Bool, to url: URL) {
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
  draw(variant, staging: staging, in: context)
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
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
  print("wrote \(url.path)")
}

for (name, staging) in [("AppIcon", false), ("AppIcon-Staging", true)] {
  let iconSet = catalog.appendingPathComponent("\(name).appiconset")
  try! FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
  render(.standard, staging: staging, to: iconSet.appendingPathComponent("\(name).png"))
  render(.dark, staging: staging, to: iconSet.appendingPathComponent("\(name)-Dark.png"))
  render(.tinted, staging: staging, to: iconSet.appendingPathComponent("\(name)-Tinted.png"))

  let contents = """
    {
      "images" : [
        { "filename" : "\(name).png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
          "filename" : "\(name)-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
        },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
          "filename" : "\(name)-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
        }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
  try! contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
  print("wrote \(name).appiconset/Contents.json")
}

// MARK: - Icon Composer documents (Liquid Glass)

/// One layer of the Icon Composer document, drawn in the default appearance on a transparent canvas.
func writeLayer(to url: URL, _ body: (CGContext) -> Void) {
  let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  body(context)
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

func drawPageLayer(in context: CGContext) {
  context.setFillColor(white)
  context.addPath(pagePath())
  context.fillPath()
  context.setFillColor(foldTint.cgColor())
  context.addPath(foldPath())
  context.fillPath()
  context.setStrokeColor(brandTint.cgColor())
  context.setLineWidth(markStem)
  context.addPath(pdfMark())
  context.strokePath()
  context.setFillColor(brandTint.cgColor(alpha: 0.35))
  context.addPath(rule)
  context.fillPath()
}

func drawSparkleLayer(in context: CGContext) {
  let star = sparklePath()
  context.setStrokeColor(white)
  context.setLineWidth(56)
  context.setLineJoin(.round)
  context.addPath(star)
  context.strokePath()
  context.setFillColor(intelligenceDark.cgColor())
  context.addPath(star)
  context.fillPath()
}

/// Groups are listed front to back. The field is the document's fill; the system adds the glass.
func iconDocument(staging: Bool) -> String {
  func colour(_ c: RGBColor) -> String { String(format: "srgb:%.5f,%.5f,%.5f,1.00000", c.red, c.green, c.blue) }
  func group(_ layer: String) -> String {
    """
        {
          "layers" : [ { "glass" : true, "image-name" : "\(layer).png", "name" : "\(layer)" } ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "translucency" : { "enabled" : false, "value" : 0.5 }
        }
    """
  }
  let groups = ((staging ? ["badge"] : []) + ["sparkle", "page"]).map(group).joined(separator: ",\n")
  return """
    {
      "fill" : {
        "linear-gradient" : [ "\(colour(gradientStart))", "\(colour(brandTint))" ]
      },
      "groups" : [
    \(groups)
      ],
      "supported-platforms" : { "squares" : [ "iOS" ] }
    }

    """
}

for (name, staging) in [("AppIcon", false), ("AppIcon-Staging", true)] {
  let document = root.appendingPathComponent("App/PDFAlgoPro/Resources/\(name).icon")
  let assets = document.appendingPathComponent("Assets")
  try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
  writeLayer(to: assets.appendingPathComponent("page.png"), drawPageLayer)
  writeLayer(to: assets.appendingPathComponent("sparkle.png"), drawSparkleLayer)
  if staging { writeLayer(to: assets.appendingPathComponent("badge.png")) { drawStagingBadge(.standard, in: $0) } }
  try! iconDocument(staging: staging).write(
    to: document.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
  print("wrote \(name).icon")
}
