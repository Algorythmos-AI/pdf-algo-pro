import CoreGraphics
import Foundation

/// A one-page PDF, read as far as text editing needs: its content, its text runs and its regions.
struct PageAnalysis {
  let file: PDFFile
  let page: PDFFile.Page
  /// The page's decoded content, all streams joined.
  let bytes: [UInt8]
  let content: PageContent
  let regions: [TextRegion]

  /// Reads a one-page PDF.
  ///
  /// - Throws: `PDFSyntaxError` when the page is malformed, unsupported or over `TextEditingLimits`.
  init(_ data: Data) throws {
    file = try PDFFile(data)
    page = try file.firstPage()
    var joined: [UInt8] = []
    for number in page.contents {
      joined.append(contentsOf: try file.stream(number).data)
      // Streams are joined as if separated by whitespace (PDF 32000-1, 7.8.2).
      joined.append(10)
      guard joined.count <= TextEditingLimits.contentBytes else { throw PDFSyntaxError.tooLarge }
    }
    bytes = joined
    var interpreter = TextInterpreter(file: file, page: page)
    content = try interpreter.interpret(try ContentStream.parse(joined))
    regions = TextRegionBuilder.regions(of: content, pageBox: page.mediaBox)
  }

}

extension TextRegion {
  /// The region as features see it.
  var editable: EditableTextRegion {
    let color: TextColor =
      switch fill.count {
      case 3: TextColor(fill[0], fill[1], fill[2])
      case 4: TextColor((1 - fill[0]) * (1 - fill[3]), (1 - fill[1]) * (1 - fill[3]), (1 - fill[2]) * (1 - fill[3]))
      default: TextColor(fill.first ?? 0, fill.first ?? 0, fill.first ?? 0)
      }
    let capability: TextEditingCapability =
      if let refusal {
        .visualReplacementOnly(refusal)
      } else if FontMatcher.hasDeviceFont(for: font) {
        .direct
      } else {
        .limited(.fontSubstituted)
      }
    return EditableTextRegion(
      id: id, text: text, bounds: bounds, angle: angle,
      style: TextStyle(
        fontName: font.postScriptName, pointSize: pointSize, isBold: font.isBold, isItalic: font.isItalic,
        isMonospaced: font.isFixedPitch, color: color),
      capability: capability)
  }
}

/// Edits existing text with the platform's own frameworks, for the documents where that is safe.
///
/// It works on one page at a time, given as a one-page PDF that PDFKit wrote:
///
/// 1. Read the page's content and find its text (`PageAnalysis`).
/// 2. Erase the old text from the content, leaving every other operator's effect unchanged
///    (`TextEraser`), and append that as an incremental update (`PDFFile.replacingContent`).
/// 3. Draw the erased page and the new text, set with Core Text in the original typeface where the
///    device or the document has it (`TextRedrawer`). Core Graphics writes ordinary text operators
///    and embeds the font, so the result is real text in the page's content.
/// 4. Prove the result (`EditProof`) or refuse.
///
/// It never covers text and never adds an annotation. What it cannot edit it refuses, and the
/// caller decides what to offer instead. See `docs/pdf-text-editing-architecture.md`.
public struct ContentStreamTextEditor: PDFTextEditing {
  /// Creates an editor.
  public init() {}

  /// The existing text of a page.
  ///
  /// See `PDFTextEditing`.
  @concurrent public func text(ofPage page: Data) async -> EditablePageText {
    guard let analysis = try? PageAnalysis(page) else { return EditablePageText(regions: [], kind: .unreadable) }
    let showsText = analysis.content.runs.contains { $0.renderingMode != 3 }
    return EditablePageText(regions: analysis.regions.map(\.editable), kind: showsText ? .text : .image)
  }

  /// Applies edits to a page, all or nothing.
  ///
  /// See `PDFTextEditing`.
  @concurrent public func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult {
    guard !edits.isEmpty else { return TextEditResult(page: nil, outcomes: []) }
    guard let analysis = try? PageAnalysis(page) else {
      return TextEditResult(page: nil, outcomes: edits.map { _ in .refused(.pageNotEditable) })
    }
    var plans: [PlannedText] = []
    var outcomes: [TextEditOutcome] = []
    var seen: Set<Int> = []
    for edit in edits {
      guard let region = analysis.regions.first(where: { $0.id == edit.regionID }), region.text == edit.original,
        seen.insert(edit.regionID).inserted
      else {
        outcomes.append(.refused(.stale))
        continue
      }
      if let refusal = region.refusal {
        outcomes.append(.refused(refusal))
        continue
      }
      switch TextRedrawer.plan(region, replacement: edit.replacement) {
      case .planned(let plan):
        plans.append(plan)
        outcomes.append(.edited(plan.mode))
      case .declined(let outcome):
        outcomes.append(outcome)
      }
    }
    guard plans.count == edits.count else { return TextEditResult(page: nil, outcomes: outcomes) }

    func refused(_ refusal: TextEditRefusal) -> TextEditResult {
      TextEditResult(page: nil, outcomes: edits.map { _ in .refused(refusal) })
    }
    guard
      let content = try? TextEraser.erasing(plans.map(\.region), in: analysis.content, bytes: analysis.bytes),
      let erased = try? analysis.file.replacingContent(of: analysis.page, with: content),
      let edited = try? TextRedrawer.draw(plans, over: erased)
    else { return refused(.pageNotEditable) }
    if let failure = EditProof.failure(
      before: page, erased: erased, after: edited, plans: plans, regions: analysis.regions)
    {
      return TextEditResult(
        page: nil, outcomes: edits.map { _ in .refused(failure.refusal) }, proofFailure: failure.check)
    }
    return TextEditResult(page: edited, outcomes: outcomes)
  }
}
