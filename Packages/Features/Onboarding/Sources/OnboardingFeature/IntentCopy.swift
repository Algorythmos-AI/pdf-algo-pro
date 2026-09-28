import Core
import SwiftUI

/// The words and symbol for each onboarding intent (design system, onboarding intent picker).
public enum IntentCopy {
  /// The option's title.
  public static func title(_ intent: OnboardingIntent) -> Text {
    switch intent {
    case .chatWithPDF: Text("Chat with PDF", bundle: .module)
    case .summarizeDocument: Text("Summarise document", bundle: .module)
    case .extractData: Text("Extract data with AI", bundle: .module)
    case .analyzeContract: Text("Analyse contract", bundle: .module)
    case .editText: Text("Edit PDF text", bundle: .module)
    case .annotate: Text("Annotate or highlight", bundle: .module)
    case .sign: Text("Sign", bundle: .module)
    case .convert: Text("Convert PDF to Word, Excel or PowerPoint", bundle: .module)
    case .organize: Text("Merge or organise pages", bundle: .module)
    case .read: Text("Read or view", bundle: .module)
    case .scan: Text("Scan to PDF", bundle: .module)
    case .allTools: Text("All tools", bundle: .module)
    }
  }

  /// The option's one-line description.
  public static func detail(_ intent: OnboardingIntent) -> Text {
    switch intent {
    case .chatWithPDF: Text("Ask questions and get answers with page citations.", bundle: .module)
    case .summarizeDocument: Text("Get the main points, each linked to its page.", bundle: .module)
    case .extractData: Text("Pull invoice numbers, dates and totals into a table.", bundle: .module)
    case .analyzeContract: Text("Explains contracts. Not legal advice.", bundle: .module)
    case .editText: Text("Change words in existing PDFs.", bundle: .module)
    case .annotate: Text("Highlight, underline and add notes.", bundle: .module)
    case .sign: Text("Fill in forms and sign.", bundle: .module)
    case .convert: Text("Turn PDFs into editable Office files.", bundle: .module)
    case .organize: Text("Combine files and reorder pages.", bundle: .module)
    case .read: Text("Open, search and read comfortably.", bundle: .module)
    case .scan: Text("Turn paper into searchable PDFs.", bundle: .module)
    case .allTools: Text("See everything PDF Algo Pro can do.", bundle: .module)
    }
  }

  /// The option's SF Symbol.
  public static func symbol(_ intent: OnboardingIntent) -> String {
    switch intent {
    case .chatWithPDF: "bubble.left.and.text.bubble.right"
    case .summarizeDocument: "text.append"
    case .extractData: "tablecells"
    case .analyzeContract: "doc.text.magnifyingglass"
    case .editText: "character.cursor.ibeam"
    case .annotate: "highlighter"
    case .sign: "signature"
    case .convert: "arrow.triangle.2.circlepath.doc.on.clipboard"
    case .organize: "square.grid.3x1.below.line.grid.1x2"
    case .read: "book"
    case .scan: "doc.viewfinder"
    case .allTools: "square.grid.2x2"
    }
  }
}
