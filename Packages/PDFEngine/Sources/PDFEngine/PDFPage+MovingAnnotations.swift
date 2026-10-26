import PDFKit

extension PDFPage {
  /// Moves every annotation on this page to `page`, in order, each once.
  ///
  /// A note's pop-up goes with it once. On macOS and iOS 27, PDFKit puts a pop-up of its own beside a
  /// note added to a page, so moving the old one as well made two; on iOS 26.5 it puts none, so leaving
  /// the old one behind lost it (#307). A pop-up, which follows its note on the page, therefore moves
  /// only when the note before it brought none.
  ///
  /// - Parameters:
  ///   - page: The page to move them to; it must already be in its document, or a form field loses its
  ///     name when the page is inserted.
  ///   - adjust: Changes each annotation that moves, before it is added (to shift it, say).
  func moveAnnotations(to page: PDFPage, adjusting adjust: (PDFAnnotation) -> Void = { _ in }) {
    var brought = 0
    for annotation in annotations {
      if annotation.type == "Popup", brought > 0 {
        brought -= 1
        removeAnnotation(annotation)
        continue
      }
      removeAnnotation(annotation)
      adjust(annotation)
      let before = page.annotations.count
      page.addAnnotation(annotation)
      if annotation.type != "Popup" { brought = page.annotations.count - before - 1 }
    }
  }
}
