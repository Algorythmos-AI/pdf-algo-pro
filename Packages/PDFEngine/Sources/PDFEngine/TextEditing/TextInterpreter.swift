import CoreGraphics
import Foundation

/// One text-showing operator of a page, with everything needed to find it, erase it and draw its
/// replacement in the same place.
struct TextRun {
  /// The index of the showing operator in the page's operations.
  let operation: Int
  let font: TextFont?
  /// The font size operand of `Tf`; Core Graphics writes 1 and puts the size in the text matrix.
  let fontSize: Double
  /// Text space to page space at the start of the run.
  let transform: CGAffineTransform
  /// The text shown, or `nil` when any of it could not be read.
  let text: String?
  /// How far the run moves the pen, in text space; `nil` when a glyph's width is not known.
  let advance: Double?
  /// How much of the advance is spaces at the end of the run, which leave no ink.
  let trailingSpace: Double
  /// The extra space after each letter that another letter follows in this operator, in text space.
  ///
  /// It is the character spacing in force, less what a number in a `TJ` array takes back before
  /// the next letter. Spaces are not letters: what surrounds them says how words are spaced.
  let letterGaps: [Double]
  let wordSpacing: Double
  /// Horizontal scaling as a fraction (1 is normal).
  let horizontalScale: Double
  let rise: Double
  /// The text rendering mode: 0 fills, 3 is invisible, 4 to 7 add to the clip.
  let renderingMode: Int
  /// The fill colour as 1 (grey), 3 (RGB) or 4 (CMYK) components; `nil` for a pattern or a colour
  /// space text editing does not redraw.
  let fill: [Double]?
  /// Whether the run is drawn with transparency, a blend mode or a soft mask.
  let hasTransparency: Bool
  /// The clip in force, in page space; `nil` when nothing clips.
  let clip: CGRect?
  /// Whether the clip is a shape text editing does not track, so what it hides is unknown.
  let clipIsComplex: Bool
  /// Whether the run sits in optional content (a layer), whose visibility is unknown here.
  let isInLayer: Bool
  /// Whether where the run starts is known: false after a run whose width is unknown.
  let positionIsKnown: Bool
  /// Whether the run starts where the one before it in the same text object ended.
  let continuesFromPen: Bool
  /// Whether a later run starts where this one ends, so erasing this one must keep its advance.
  var hasDependents = false
  /// The replacement-text span the run sits in, if any.
  let span: Int?
}

/// Something other than text painted on the page, and roughly where.
struct PaintedArea {
  let operation: Int
  let box: CGRect
}

/// A marked-content span that carries replacement text (`/ActualText`), as Core Graphics writes for
/// ligatures.
struct ReplacementSpan {
  let begin: Int
  var end: Int?
}

/// A page's content, interpreted: its text runs and what else is painted.
struct PageContent {
  let operations: [ContentOperation]
  let runs: [TextRun]
  let painted: [PaintedArea]
  let spans: [ReplacementSpan]
}

/// Walks a page's operators, tracking the graphics and text state the way a renderer does, to learn
/// where each piece of text is and how it is drawn.
///
/// It draws nothing.
struct TextInterpreter {
  private struct GraphicsState {
    var transform = CGAffineTransform.identity
    var fill: [Double]? = [0]
    var fillComponents = 1
    var alphaIsOpaque = true
    var blendIsNormal = true
    var hasSoftMask = false
    var clip: CGRect?
    var clipIsComplex = false
    var font: TextFont?
    var fontSize = 0.0
    var characterSpacing = 0.0
    var wordSpacing = 0.0
    var horizontalScale = 1.0
    var leading = 0.0
    var rise = 0.0
    var renderingMode = 0
  }

  private let file: PDFFile
  private let resources: [String: PDFObject]
  private let pageBox: CGRect
  private var fonts: [String: TextFont?] = [:]

  private var state = GraphicsState()
  private var stack: [GraphicsState] = []
  private var textMatrix = CGAffineTransform.identity
  private var lineMatrix = CGAffineTransform.identity
  private var positionIsKnown = true
  private var previousRunInObject: Int?

  private var pathBox: CGRect?
  /// The box of each segment of the path, for strokes: a stroked outline paints its edges, not
  /// what it encloses.
  private var pathSegments: [CGRect] = []
  private var currentPoint: CGPoint?
  private var subpathStart: CGPoint?
  private var pathRectangles = 0
  private var pathOtherSegments = 0
  private var pendingClip = false

  private var marked: [(span: Int?, isLayer: Bool)] = []
  private var consumedSpans: Set<Int> = []

  private var runs: [TextRun] = []
  private var painted: [PaintedArea] = []
  private var spans: [ReplacementSpan] = []

  /// How many forms deep this interpreter is; the page itself is 0.
  private let formDepth: Int
  /// How many forms this interpreter has read the content of.
  private var formsRead = 0

  init(file: PDFFile, page: PDFFile.Page) {
    self.init(file: file, resources: page.resources, pageBox: page.mediaBox, formDepth: 0)
  }

  private init(file: PDFFile, resources: [String: PDFObject], pageBox: CGRect, formDepth: Int) {
    self.file = file
    self.resources = resources
    self.pageBox = pageBox
    self.formDepth = formDepth
  }

  /// Interprets a page's operations.
  mutating func interpret(_ operations: [ContentOperation]) throws -> PageContent {
    for (index, operation) in operations.enumerated() {
      if index.isMultiple(of: 512) { try Task.checkCancellation() }
      try apply(operation, at: index)
    }
    return PageContent(operations: operations, runs: runs, painted: painted, spans: spans)
  }

  // MARK: - Operators

  private mutating func apply(_ operation: ContentOperation, at index: Int) throws {
    let operands = operation.operands
    let numbers = operands.compactMap(\.number)
    switch operation.name {
    case "q":
      guard stack.count < TextEditingLimits.operators else { throw PDFSyntaxError.tooLarge }
      stack.append(state)
    case "Q":
      if let saved = stack.popLast() { state = saved }
    case "cm":
      if let matrix = Self.matrix(numbers) { state.transform = matrix.concatenating(state.transform) }
    case "gs":
      try applyGraphicsState(named: operands.first?.name)

    // Colour
    case "g":
      setFill(numbers, components: 1)
    case "rg":
      setFill(numbers, components: 3)
    case "k":
      setFill(numbers, components: 4)
    case "cs":
      state.fillComponents = try components(ofColorSpace: operands.first?.name)
      state.fill = state.fillComponents == 0 ? nil : Array(repeating: 0, count: state.fillComponents)
    case "sc", "scn":
      // A name among the operands is a pattern.
      if numbers.count == operands.count, state.fillComponents > 0 {
        setFill(numbers, components: state.fillComponents)
      } else {
        state.fill = nil
      }

    // Paths and clipping
    case "m":
      if numbers.count == 2 {
        let point = pagePoint(numbers[0], numbers[1])
        addPathPoints([point])
        currentPoint = point
        subpathStart = point
      }
      pathOtherSegments += 1
    case "l":
      if numbers.count == 2 { addSegment(to: pagePoint(numbers[0], numbers[1]), through: []) }
      pathOtherSegments += 1
    case "c":
      if numbers.count == 6 {
        addSegment(
          to: pagePoint(numbers[4], numbers[5]),
          through: [pagePoint(numbers[0], numbers[1]), pagePoint(numbers[2], numbers[3])])
      }
      pathOtherSegments += 1
    case "v", "y":
      if numbers.count == 4 {
        addSegment(to: pagePoint(numbers[2], numbers[3]), through: [pagePoint(numbers[0], numbers[1])])
      }
      pathOtherSegments += 1
    case "h":
      if let subpathStart { addSegment(to: subpathStart, through: []) }
    case "re":
      if numbers.count == 4 {
        let corners = [
          pagePoint(numbers[0], numbers[1]), pagePoint(numbers[0] + numbers[2], numbers[1]),
          pagePoint(numbers[0] + numbers[2], numbers[1] + numbers[3]), pagePoint(numbers[0], numbers[1] + numbers[3]),
        ]
        currentPoint = corners[0]
        subpathStart = corners[0]
        for corner in corners.dropFirst() + [corners[0]] { addSegment(to: corner, through: []) }
      }
      pathRectangles += 1
    case "W", "W*":
      pendingClip = true
    case "n":
      endPath(.none, at: index)
    case "S", "s":
      if operation.name == "s", let subpathStart { addSegment(to: subpathStart, through: []) }
      endPath(.stroke, at: index)
    case "f", "F", "f*", "B", "B*", "b", "b*":
      endPath(.fill, at: index)
    case "sh":
      painted.append(PaintedArea(operation: index, box: state.clip ?? pageBox))
    case "BI":
      painted.append(PaintedArea(operation: index, box: Self.unitSquare.applying(state.transform)))
    case "Do":
      for box in try boxes(ofXObject: operands.first?.name) { painted.append(PaintedArea(operation: index, box: box)) }

    // Marked content
    case "BMC":
      marked.append((nil, false))
    case "BDC":
      try beginMarkedContent(operands, at: index)
    case "EMC":
      if let closed = marked.popLast(), let span = closed.span { spans[span].end = index }

    // Text
    case "BT":
      textMatrix = .identity
      lineMatrix = .identity
      positionIsKnown = true
      previousRunInObject = nil
    case "ET":
      previousRunInObject = nil
    case "Tf":
      state.font = try font(named: operands.first?.name)
      state.fontSize = numbers.first ?? 0
    case "Tc":
      state.characterSpacing = numbers.first ?? 0
    case "Tw":
      state.wordSpacing = numbers.first ?? 0
    case "Tz":
      state.horizontalScale = (numbers.first ?? 100) / 100
    case "TL":
      state.leading = numbers.first ?? 0
    case "Ts":
      state.rise = numbers.first ?? 0
    case "Tr":
      state.renderingMode = operands.first?.integer ?? 0
    case "Td":
      if numbers.count == 2 { moveLine(numbers[0], numbers[1]) }
    case "TD":
      if numbers.count == 2 {
        state.leading = -numbers[1]
        moveLine(numbers[0], numbers[1])
      }
    case "Tm":
      if let matrix = Self.matrix(numbers) {
        lineMatrix = matrix
        textMatrix = matrix
        positionIsKnown = true
        previousRunInObject = nil
      }
    case "T*":
      moveLine(0, -state.leading)
    case "Tj":
      show([operands.first ?? .null], at: index)
    case "TJ":
      show(operands.first?.array ?? [], at: index)
    case "'":
      moveLine(0, -state.leading)
      show([operands.first ?? .null], at: index)
    case "\"":
      if numbers.count >= 2 {
        state.wordSpacing = numbers[0]
        state.characterSpacing = numbers[1]
      }
      moveLine(0, -state.leading)
      show([operands.last ?? .null], at: index)
    default:
      break
    }
  }

  private static let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1)

  private static func matrix(_ numbers: [Double]) -> CGAffineTransform? {
    guard numbers.count == 6, numbers.allSatisfy(\.isFinite) else { return nil }
    return CGAffineTransform(a: numbers[0], b: numbers[1], c: numbers[2], d: numbers[3], tx: numbers[4], ty: numbers[5])
  }

  // MARK: - Graphics state

  private mutating func setFill(_ numbers: [Double], components: Int) {
    state.fillComponents = components
    state.fill = numbers.count == components ? numbers.map { min(1, max(0, $0)) } : nil
  }

  /// How many components a fill colour space has; 0 for one text editing does not redraw.
  private func components(ofColorSpace name: String?) throws -> Int {
    switch name {
    case "DeviceGray": return 1
    case "DeviceRGB": return 3
    case "DeviceCMYK": return 4
    default: break
    }
    guard let name, let spaces = try file.dictionary(resources["ColorSpace"]),
      let space = try file.resolve(spaces[name]).array, let family = space.first?.name
    else { return 0 }
    switch family {
    case "CalGray": return 1
    case "CalRGB": return 3
    case "ICCBased":
      guard space.count > 1, let profile = try file.dictionary(space[1]), let count = profile["N"]?.integer,
        [1, 3, 4].contains(count)
      else { return 0 }
      return count
    default: return 0
    }
  }

  private mutating func applyGraphicsState(named name: String?) throws {
    guard let name, let states = try file.dictionary(resources["ExtGState"]),
      let parameters = try file.dictionary(states[name])
    else { return }
    if let alpha = try file.resolve(parameters["ca"]).number { state.alphaIsOpaque = alpha >= 0.999 }
    switch try file.resolve(parameters["BM"]) {
    case .null: break
    case .name("Normal"), .name("Compatible"): state.blendIsNormal = true
    default: state.blendIsNormal = false
    }
    switch try file.resolve(parameters["SMask"]) {
    case .null: break
    case .name("None"): state.hasSoftMask = false
    default: state.hasSoftMask = true
    }
  }

  // MARK: - Paths

  private enum Paint { case none, stroke, fill }

  private func pagePoint(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: x, y: y).applying(state.transform)
  }

  private mutating func addPathPoints(_ points: [CGPoint]) {
    for point in points {
      let box = CGRect(origin: point, size: .zero)
      pathBox = pathBox.map { $0.union(box) } ?? box
    }
  }

  /// Adds a segment from the current point, through any control points, to a point.
  private mutating func addSegment(to end: CGPoint, through controls: [CGPoint]) {
    let points = [currentPoint ?? end] + controls + [end]
    addPathPoints(points)
    var box = CGRect(origin: points[0], size: .zero)
    for point in points.dropFirst() { box = box.union(CGRect(origin: point, size: .zero)) }
    if pathSegments.count < 4096 { pathSegments.append(box) }
    currentPoint = end
  }

  private mutating func endPath(_ paint: Paint, at index: Int) {
    switch paint {
    case .none:
      break
    case .fill:
      if let pathBox { painted.append(PaintedArea(operation: index, box: pathBox.insetBy(dx: -1, dy: -1))) }
    case .stroke:
      // A stroked outline, such as a table's grid, paints its lines and leaves what is inside clear.
      if pathSegments.count < 4096 {
        for segment in pathSegments {
          painted.append(PaintedArea(operation: index, box: segment.insetBy(dx: -1, dy: -1)))
        }
      } else if let pathBox {
        painted.append(PaintedArea(operation: index, box: pathBox.insetBy(dx: -1, dy: -1)))
      }
    }
    if pendingClip {
      let transform = state.transform
      let isAxisAligned = (transform.b == 0 && transform.c == 0) || (transform.a == 0 && transform.d == 0)
      if let pathBox, pathRectangles == 1, pathOtherSegments == 0, isAxisAligned {
        state.clip = state.clip.map { $0.intersection(pathBox) } ?? pathBox
      } else {
        state.clipIsComplex = true
      }
    }
    pendingClip = false
    pathBox = nil
    pathSegments = []
    currentPoint = nil
    subpathStart = nil
    pathRectangles = 0
    pathOtherSegments = 0
  }

  /// Where a reusable object paints.
  ///
  /// An image paints its unit square. A form is interpreted, two levels deep and a few times a page, so that a form
  /// whose declared box is the whole page but which paints only a footer counts as the footer.
  private mutating func boxes(ofXObject name: String?) throws -> [CGRect] {
    let whole = state.clip ?? pageBox
    guard let name, let objects = try file.dictionary(resources["XObject"]),
      case .reference(let number) = objects[name], let dictionary = try file.dictionary(objects[name])
    else { return [whole] }
    if dictionary["Subtype"] == .name("Image") { return [Self.unitSquare.applying(state.transform)] }
    guard dictionary["Subtype"] == .name("Form"), let bounds = try file.rectangle(dictionary["BBox"]) else {
      return [whole]
    }
    let numbers = try file.resolve(dictionary["Matrix"]).array?.compactMap(\.number) ?? []
    let transform = (Self.matrix(numbers) ?? .identity).concatenating(state.transform)
    let declared = bounds.applying(transform)
    // A page could place a large form many thousands of times; only the first few are read.
    guard formDepth < 2, formsRead < 32, let stream = try? file.stream(number),
      let operations = try? ContentStream.parse(stream.data)
    else { return [declared] }
    formsRead += 1
    var inner = TextInterpreter(
      file: file, resources: try file.dictionary(dictionary["Resources"]) ?? resources, pageBox: pageBox,
      formDepth: formDepth + 1)
    inner.state.transform = transform
    guard let content = try? inner.interpret(operations) else { return [declared] }
    var boxes = content.painted.map(\.box)
    // Text inside the form is not editable here, and it does occupy the page.
    for run in content.runs where run.renderingMode != 3 {
      let size = run.fontSize
      let width = run.advance ?? size
      boxes.append(CGRect(x: 0, y: -0.25 * size, width: width, height: 1.25 * size).applying(run.transform))
    }
    return boxes.map { $0.intersection(declared) }.filter { !$0.isNull && !$0.isEmpty }
  }

  // MARK: - Marked content

  private mutating func beginMarkedContent(_ operands: [PDFObject], at index: Int) throws {
    var properties = operands.count > 1 ? operands[1].dictionary : nil
    if properties == nil, operands.count > 1, let name = operands[1].name,
      let named = try file.dictionary(resources["Properties"])
    {
      properties = try file.dictionary(named[name])
    }
    let isLayer = operands.first?.name == "OC"
    if properties?["ActualText"] != nil {
      spans.append(ReplacementSpan(begin: index, end: nil))
      replacementText.append(Self.text(properties?["ActualText"]?.bytes ?? []))
      marked.append((spans.count - 1, isLayer))
    } else {
      marked.append((nil, isLayer))
    }
  }

  private var replacementText: [String] = []

  /// A text string: UTF-16 with a byte-order mark, otherwise treated as Latin-1.
  private static func text(_ bytes: [UInt8]) -> String {
    if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
      return String(bytes: bytes.dropFirst(2), encoding: .utf16BigEndian) ?? ""
    }
    return String(bytes: bytes, encoding: .isoLatin1) ?? ""
  }

  // MARK: - Text

  private mutating func font(named name: String?) throws -> TextFont? {
    guard let name else { return nil }
    if let cached = fonts[name] { return cached }
    var font: TextFont?
    if let all = try file.dictionary(resources["Font"]), let dictionary = try file.dictionary(all[name]) {
      // A font that cannot be read leaves its text unreadable, which is safe: not editable.
      font = try? TextFont(dictionary: dictionary, in: file)
    }
    fonts[name] = font
    return font
  }

  private mutating func moveLine(_ x: Double, _ y: Double) {
    lineMatrix = CGAffineTransform(translationX: x, y: y).concatenating(lineMatrix)
    textMatrix = lineMatrix
    positionIsKnown = true
    previousRunInObject = nil
  }

  /// Records a showing operator and advances the pen past it.
  private mutating func show(_ elements: [PDFObject], at index: Int) {
    let font = state.font
    let size = state.fontSize
    let scale = state.horizontalScale
    var text: String? = ""
    var advance: Double? = 0
    var trailingSpace = 0.0
    var letterGaps: [Double] = []
    // The extra space after the letter just shown; `nil` at the start and after a space.
    var gap: Double?
    for element in elements {
      if let adjustment = element.number {
        let shift = -adjustment / 1000 * size * scale
        advance = advance.map { $0 + shift }
        gap = gap.map { $0 - adjustment / 1000 * size }
        if trailingSpace > 0 { trailingSpace += shift }
        // A gap wider than a fifth of the font size reads as a space, as it does to PDFKit.
        if adjustment < -200, let current = text, !current.isEmpty, current.last != " " { text = current + " " }
        continue
      }
      guard let string = element.bytes, let font else {
        text = nil
        advance = nil
        continue
      }
      for glyph in font.glyphs(for: string) {
        if let gap, glyph.text != " " { letterGaps.append(gap) }
        gap = glyph.text == " " ? nil : state.characterSpacing
        if let glyphText = glyph.text { text = text.map { $0 + glyphText } } else { text = nil }
        if let width = glyph.width {
          let spacing = state.characterSpacing + (glyph.isWordSpace ? state.wordSpacing : 0)
          let step = (width / 1000 * size + spacing) * scale
          advance = advance.map { $0 + step }
          trailingSpace = glyph.text == " " ? trailingSpace + step : 0
        } else {
          advance = nil
        }
      }
    }

    let span = marked.last(where: { $0.span != nil })?.span
    if let span {
      // The span's replacement text stands for everything shown inside it.
      text = consumedSpans.insert(span).inserted ? replacementText[span] : ""
    }
    if let previous = previousRunInObject { runs[previous].hasDependents = true }
    runs.append(
      TextRun(
        operation: index, font: font, fontSize: size, transform: textMatrix.concatenating(state.transform),
        text: text, advance: advance, trailingSpace: max(0, trailingSpace), letterGaps: letterGaps,
        wordSpacing: state.wordSpacing,
        horizontalScale: scale, rise: state.rise, renderingMode: state.renderingMode, fill: state.fill,
        hasTransparency: !state.alphaIsOpaque || !state.blendIsNormal || state.hasSoftMask, clip: state.clip,
        clipIsComplex: state.clipIsComplex, isInLayer: marked.contains(where: \.isLayer),
        positionIsKnown: positionIsKnown, continuesFromPen: previousRunInObject != nil, span: span))
    previousRunInObject = runs.count - 1
    if let advance {
      textMatrix = CGAffineTransform(translationX: advance, y: 0).concatenating(textMatrix)
    } else {
      positionIsKnown = false
    }
  }
}
