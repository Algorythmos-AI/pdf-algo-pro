import Compression
import CoreGraphics
import Foundation
import ImageIO

/// Re-encodes the pictures in a file PDFKit wrote as JPEG, for the compression presets (FR-ORG-004, #308).
///
/// On iOS 26 and macOS, PDFKit's `saveImagesAsJPEGOption` and `optimizeImagesForScreenOption` re-encode
/// a document's pictures as it writes them. On iOS 27.0 it ignores both and writes every picture as it
/// was, so a compressed scan came out the size it went in. This step does that part itself: it reads the
/// file PDFKit wrote and writes it again with each picture it understands stored as a JPEG, at most
/// `maximumSide` pixels on its longest side. Every other object, text, line art, annotations, the outline
/// and the links, is copied byte for byte.
///
/// Where PDFKit already re-encoded the pictures there is nothing left to do, and it returns `nil`.
///
/// It understands what PDFKit writes: a cross-reference table, not a stream, and no encryption; and only
/// pictures with eight bits per sample, in grey or RGB, stored as they are, with Flate (with or without a
/// PNG predictor) or as JPEG. Anything else it leaves as it is. A picture that comes out no smaller is kept.
enum PDFImageRecompression {
  /// How a preset re-encodes pictures.
  struct Settings: Equatable {
    /// The longest side a picture keeps, in pixels; `nil` keeps every picture's size.
    var maximumSide: Int?
    /// The JPEG quality, from 0 to 1.
    var quality: Double
  }

  /// The largest picture it decodes, in pixels, so a damaged size can't exhaust memory.
  static let largestPicture = 60_000_000

  /// The file with its pictures re-encoded, or `nil` when it can't read the file or no picture got smaller.
  static func recompressed(_ data: Data, settings: Settings) -> Data? {
    guard let file = ReadFile(bytes: [UInt8](data)) else { return nil }
    var replacements: [Int: Data] = [:]
    for (number, offset) in file.offsets {
      guard !file.masks.contains(number), let object = file.object(at: offset),
        object.dictionary["Subtype"] == .name("Image"), let stream = object.stream,
        let picture = reencoded(object.dictionary, stream: file.bytes[stream], file: file, settings: settings)
      else { continue }
      var serialized = Data("\(number) \(object.generation) obj\n".utf8)
      serialized += picture.dictionary.serialized + Data("\nstream\n".utf8)
      serialized += picture.data + Data("\nendstream\nendobj\n".utf8)
      replacements[number] = serialized
    }
    guard !replacements.isEmpty else { return nil }
    return file.rewritten(replacing: replacements)
  }

  // MARK: - Pictures

  private enum Encoding {
    case plain
    case flate(predictor: Int)
    case jpeg
  }

  /// The picture as a JPEG with its new dictionary, when it can be read and comes out smaller.
  private static func reencoded(
    _ dictionary: WrittenPDFDictionary, stream: ArraySlice<UInt8>, file: ReadFile, settings: Settings
  ) -> (dictionary: WrittenPDFDictionary, data: Data)? {
    guard let width = file.integer(dictionary["Width"]), let height = file.integer(dictionary["Height"]),
      width > 0, height > 0, width <= largestPicture / height,
      file.integer(dictionary["BitsPerComponent"]) == 8,
      dictionary["ImageMask"] == nil, dictionary["Mask"] == nil, dictionary["Decode"] == nil,
      let components = components(of: dictionary["ColorSpace"], in: file),
      let encoding = encoding(of: dictionary, components: components, width: width, in: file)
    else { return nil }
    let longest = max(width, height)
    let shrinks = settings.maximumSide.map { longest > $0 } ?? false
    let source: CGImage?
    switch encoding {
    case .jpeg:
      // A JPEG is only made smaller, never encoded again at its own size, which would only lose detail.
      guard shrinks else { return nil }
      source = CGImageSourceCreateWithData(Data(stream) as CFData, nil).flatMap {
        CGImageSourceCreateImageAtIndex($0, 0, nil)
      }
    case .plain:
      source = image(Array(stream), width: width, height: height, components: components)
    case .flate(let predictor):
      let rowLength = width * components + (predictor >= 10 ? 1 : 0)
      guard let inflated = inflate(stream, count: rowLength * height) else { return nil }
      let samples =
        predictor >= 10
        ? unpredicted(inflated, width: width, height: height, components: components) : inflated
      source = samples.flatMap { image($0, width: width, height: height, components: components) }
    }
    guard let source else { return nil }
    var picture = source
    if shrinks, let side = settings.maximumSide {
      let scale = Double(side) / Double(longest)
      let size = (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
      guard let scaled = resized(source, to: size, components: components) else { return nil }
      picture = scaled
    }
    guard let jpeg = jpeg(picture, quality: settings.quality), jpeg.count < stream.count else { return nil }
    var updated = dictionary
    updated["Width"] = .number(String(picture.width))
    updated["Height"] = .number(String(picture.height))
    updated["Filter"] = .name("DCTDecode")
    updated["DecodeParms"] = nil
    updated["Length"] = .number(String(jpeg.count))
    return (updated, jpeg)
  }

  /// 1 for grey, 3 for RGB, or `nil` for any other colour space.
  private static func components(of value: WrittenPDFValue?, in file: ReadFile) -> Int? {
    switch file.resolve(value) {
    case .name("DeviceGray"): return 1
    case .name("DeviceRGB"): return 3
    case .array(let parts) where parts.count == 2 && parts[0] == .name("ICCBased"):
      let count = file.dictionary(parts[1]).flatMap { file.integer($0["N"]) }
      return count == 1 || count == 3 ? count : nil
    default: return nil
    }
  }

  private static func encoding(
    of dictionary: WrittenPDFDictionary, components: Int, width: Int, in file: ReadFile
  ) -> Encoding? {
    var filter = file.resolve(dictionary["Filter"])
    var parameters = file.resolve(dictionary["DecodeParms"])
    if case .array(let filters)? = filter {
      guard filters.count <= 1 else { return nil }
      filter = filters.first
      if case .array(let all)? = parameters { parameters = all.first.flatMap { file.resolve($0) } }
    }
    switch filter {
    case nil: return .plain
    case .name("DCTDecode")?: return .jpeg
    case .name("FlateDecode")?:
      guard let parameters = file.dictionary(parameters) else { return .flate(predictor: 1) }
      let predictor = file.integer(parameters["Predictor"]) ?? 1
      let colors = file.integer(parameters["Colors"]) ?? 1
      let bits = file.integer(parameters["BitsPerComponent"]) ?? 8
      let columns = file.integer(parameters["Columns"]) ?? 1
      if predictor == 1 { return .flate(predictor: 1) }
      // A PNG predictor over the picture's own samples; the TIFF one, and any other layout, is left alone.
      guard predictor >= 10, predictor <= 15, bits == 8, colors == components, columns == width else { return nil }
      return .flate(predictor: predictor)
    default: return nil
    }
  }

  /// A zlib stream (RFC 1950) inflated to exactly `count` bytes, or `nil` when it holds fewer.
  static func inflate(_ stream: ArraySlice<UInt8>, count: Int) -> [UInt8]? {
    guard stream.count > 2, count > 0 else { return nil }
    let method = stream[stream.startIndex]
    let flags = stream[stream.startIndex + 1]
    // Deflate, a valid header check, and no preset dictionary.
    guard method & 0x0F == 8, (Int(method) << 8 | Int(flags)) % 31 == 0, flags & 0x20 == 0 else { return nil }
    let body = Array(stream.dropFirst(2))
    var output = [UInt8](repeating: 0, count: count)
    let written = body.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        guard let from = source.baseAddress, let into = destination.baseAddress else { return 0 }
        return compression_decode_buffer(into, count, from, source.count, nil, COMPRESSION_ZLIB)
      }
    }
    return written == count ? output : nil
  }

  /// Samples with the PNG predictor undone (ISO 32000-1, 7.4.4.4; PNG, section 9): each row starts with
  /// the filter it was written with.
  static func unpredicted(_ data: [UInt8], width: Int, height: Int, components: Int) -> [UInt8]? {
    let rowLength = width * components
    var output = [UInt8](repeating: 0, count: rowLength * height)
    var previous = [UInt8](repeating: 0, count: rowLength)
    for row in 0..<height {
      let start = row * (rowLength + 1)
      let filter = data[start]
      var current = Array(data[(start + 1)..<(start + 1 + rowLength)])
      for index in 0..<rowLength {
        let left = index >= components ? Int(current[index - components]) : 0
        let up = Int(previous[index])
        let upLeft = index >= components ? Int(previous[index - components]) : 0
        let predicted: Int
        switch filter {
        case 0: predicted = 0
        case 1: predicted = left
        case 2: predicted = up
        case 3: predicted = (left + up) / 2
        case 4:
          let estimate = left + up - upLeft
          let (toLeft, toUp, toUpLeft) = (abs(estimate - left), abs(estimate - up), abs(estimate - upLeft))
          predicted = toLeft <= toUp && toLeft <= toUpLeft ? left : (toUp <= toUpLeft ? up : upLeft)
        default: return nil
        }
        current[index] = current[index] &+ UInt8(truncatingIfNeeded: predicted)
      }
      output.replaceSubrange((row * rowLength)..<((row + 1) * rowLength), with: current)
      previous = current
    }
    return output
  }

  private static func image(_ samples: [UInt8], width: Int, height: Int, components: Int) -> CGImage? {
    guard samples.count >= width * height * components,
      let provider = CGDataProvider(data: Data(samples.prefix(width * height * components)) as CFData)
    else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * components,
      bytesPerRow: width * components, space: space(components),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent)
  }

  private static func resized(_ image: CGImage, to size: (Int, Int), components: Int) -> CGImage? {
    let alpha = components == 3 ? CGImageAlphaInfo.noneSkipLast : .none
    guard
      let context = CGContext(
        data: nil, width: size.0, height: size.1, bitsPerComponent: 8, bytesPerRow: 0, space: space(components),
        bitmapInfo: alpha.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size.0, height: size.1))
    return context.makeImage()
  }

  private static func space(_ components: Int) -> CGColorSpace {
    components == 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray()
  }

  private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}

// MARK: - The file

extension PDFImageRecompression {
  /// A PDF file read through its cross-reference table, and written again with some objects replaced.
  private struct ReadFile {
    struct Object {
      var generation: Int
      var dictionary: WrittenPDFDictionary
      /// Where a stream's data is, for a stream.
      var stream: Range<Int>?
    }

    let bytes: [UInt8]
    /// The newest offset of each object in use.
    private(set) var offsets: [Int: Int] = [:]
    /// The pictures another picture uses as its mask: re-encoding one would blur its edges.
    private(set) var masks: Set<Int> = []
    private var trailer = WrittenPDFDictionary()
    /// Every place an object or a cross-reference section starts: an object runs to the next one.
    private var boundaries: [Int] = []

    init?(bytes: [UInt8]) {
      self.bytes = bytes
      let tail = String(decoding: bytes.suffix(1024), as: UTF8.self)
      guard let range = tail.range(of: "startxref", options: .backwards),
        let start = Int(tail[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber }),
        start < bytes.count
      else { return nil }
      var reader = WrittenPDFReader(bytes: bytes, position: start)
      var section: Int? = start
      var newest: WrittenPDFDictionary?
      var starts: Set<Int> = [bytes.count]
      while let at = section, !starts.contains(at) {
        starts.insert(at)
        reader.position = at
        guard reader.keyword() == "xref", let entries = reader.crossReferenceEntries(),
          reader.keyword() == "trailer", case .dictionary(let dictionary)? = reader.value(),
          dictionary["XRefStm"] == nil
        else { return nil }
        for (number, offset) in entries where offset < bytes.count {
          starts.insert(offset)
          if offsets[number] == nil { offsets[number] = offset }
        }
        if newest == nil { newest = dictionary }
        if case .number(let previous)? = dictionary["Prev"], let value = Int(previous) {
          section = value
        } else {
          section = nil
        }
      }
      guard let newest, newest["Encrypt"] == nil, newest["Root"] != nil, !offsets.isEmpty else { return nil }
      trailer = newest
      boundaries = starts.sorted()
      for offset in offsets.values {
        guard let object = object(at: offset), object.dictionary["Subtype"] == .name("Image") else { continue }
        for key in ["SMask", "Mask"] {
          if case .reference(let number, _)? = object.dictionary[key] { masks.insert(number) }
        }
      }
    }

    /// The object at `offset`: its generation, its dictionary and, for a stream, where its data is.
    func object(at offset: Int) -> Object? {
      var reader = WrittenPDFReader(bytes: bytes, position: offset)
      guard Int(reader.keyword()) != nil, let generation = Int(reader.keyword()), reader.keyword() == "obj",
        case .dictionary(let dictionary)? = reader.value()
      else { return nil }
      var object = Object(generation: generation, dictionary: dictionary)
      let mark = reader.position
      guard reader.keyword() == "stream" else {
        reader.position = mark
        return object
      }
      var start = reader.position
      if start < bytes.count, bytes[start] == 13 { start += 1 }
      if start < bytes.count, bytes[start] == 10 { start += 1 }
      guard let length = integer(dictionary["Length"]), length >= 0, start + length <= bytes.count else { return nil }
      reader.position = start + length
      guard reader.keyword() == "endstream" else { return nil }
      object.stream = start..<(start + length)
      return object
    }

    func resolve(_ value: WrittenPDFValue?) -> WrittenPDFValue? {
      guard case .reference(let number, _)? = value else { return value }
      guard let offset = offsets[number] else { return nil }
      var reader = WrittenPDFReader(bytes: bytes, position: offset)
      guard reader.objectHeader() == number else { return nil }
      return reader.value()
    }

    func integer(_ value: WrittenPDFValue?) -> Int? {
      guard case .number(let text)? = resolve(value) else { return nil }
      return Int(text)
    }

    func dictionary(_ value: WrittenPDFValue?) -> WrittenPDFDictionary? {
      guard case .dictionary(let dictionary)? = resolve(value) else { return nil }
      return dictionary
    }

    /// The bytes of the object at `offset`, to the next object or cross-reference section.
    private func span(at offset: Int) -> Range<Int> {
      var low = 0
      var high = boundaries.count
      while low < high {
        let middle = (low + high) / 2
        if boundaries[middle] <= offset { low = middle + 1 } else { high = middle }
      }
      return offset..<(low < boundaries.count ? boundaries[low] : bytes.count)
    }

    /// The file written again, objects in the order they were, each replacement in place of its object,
    /// with one cross-reference table and the trailer it had, less what pointed at the old sections; or
    /// `nil` when an object can't be read.
    func rewritten(replacing replacements: [Int: Data]) -> Data? {
      let ordered = offsets.sorted { $0.value < $1.value }
      var data = Data(bytes[0..<(ordered.first?.value ?? 0)])
      var written: [Int: (offset: Int, generation: Int)] = [:]
      for (number, offset) in ordered {
        var reader = WrittenPDFReader(bytes: bytes, position: offset)
        guard Int(reader.keyword()) == number, let generation = Int(reader.keyword()), reader.keyword() == "obj"
        else { return nil }
        written[number] = (data.count, generation)
        if let replacement = replacements[number] {
          data += replacement
        } else {
          data += Data(bytes[span(at: offset)])
        }
      }
      if data.last != 10 { data.append(10) }
      let start = data.count
      data += Data("xref\n0 1\n0000000000 65535 f\r\n".utf8)
      let numbers = written.keys.sorted()
      var index = 0
      while index < numbers.count {
        var end = index
        while end + 1 < numbers.count, numbers[end + 1] == numbers[end] + 1 { end += 1 }
        data += Data("\(numbers[index]) \(end - index + 1)\n".utf8)
        for number in numbers[index...end] {
          guard let entry = written[number] else { return nil }
          data += Data(String(format: "%010ld %05ld n\r\n", entry.offset, entry.generation).utf8)
        }
        index = end + 1
      }
      var newTrailer = trailer
      newTrailer["Prev"] = nil
      let size = max(integer(trailer["Size"]) ?? 0, (numbers.last ?? 0) + 1)
      newTrailer["Size"] = .number(String(size))
      data += Data("trailer\n".utf8) + newTrailer.serialized + Data("\nstartxref\n\(start)\n%%EOF\n".utf8)
      return data
    }
  }
}
