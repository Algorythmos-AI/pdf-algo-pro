import Core
import DesignSystem
import SwiftUI
import UIKit

/// The assistant sheet over the reader.
public struct AssistantView: View {
  @State private var model: AssistantModel
  @Environment(\.dismiss) private var dismiss

  /// Creates the sheet for a model.
  public init(model: AssistantModel) {
    _model = State(initialValue: model)
  }

  /// The sheet.
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.s200) {
          Picker(selection: $model.task) {
            ForEach(AssistantTask.allCases) { task in Self.title(for: task).tag(task) }
          } label: {
            Text("Task", bundle: .module)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("assistant.task")
          if model.task == .explainContract { ContractDisclosure() }
          if model.task == .ask { questionField }
          content
        }
        .padding(Spacing.s200)
        .readableWidth()
      }
      .background(Color.ds.backgroundGrouped)
      .navigationTitle(Self.title(for: model.task))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", bundle: .module)
          }
        }
        if let text = model.shareableText {
          ToolbarItem(placement: .primaryAction) {
            ShareLink(item: text) {
              Label {
                Text("Share", bundle: .module)
              } icon: {
                Image(systemName: "square.and.arrow.up")
              }
            }
            .simultaneousGesture(TapGesture().onEnded { Task { await model.recordKept() } })
          }
        }
      }
      .task { await model.start() }
    }
    .presentationDetents([.medium, .large])
  }

  private var questionField: some View {
    HStack {
      TextField(text: $model.question) { Text("Ask about this document", bundle: .module) }
        .textFieldStyle(.roundedBorder)
        .submitLabel(.send)
        .onSubmit { Task { await model.ask() } }
        .accessibilityIdentifier("assistant.question")
      Button {
        Task { await model.ask() }
      } label: {
        Image(systemName: "arrow.up.circle.fill").font(.title2)
      }
      .accessibilityLabel(Text("Ask", bundle: .module))
      .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }

  @ViewBuilder private var content: some View {
    switch model.phase {
    case .idle:
      Text("Answers come only from this document and cite their pages.", bundle: .module)
        .font(.callout).foregroundStyle(Color.ds.labelSecondary)
    case .working:
      HStack(spacing: Spacing.s100) {
        ProgressView()
        Text("Reading the document on this device…", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
      }
      .accessibilityElement(children: .combine)
    case .answered(let answer):
      answerCard(answer)
    case .extracted(let extraction):
      extractionCard(extraction)
    case .unavailable(let reason):
      ContentUnavailableView {
        Label {
          Text("Document intelligence isn't available", bundle: .module)
        } icon: {
          Image(systemName: "sparkles")
        }
      } description: {
        Self.explanation(for: reason)
      }
      .accessibilityIdentifier("assistant.unavailable")
    case .noText:
      ContentUnavailableView {
        Label {
          Text("No text to read yet", bundle: .module)
        } icon: {
          Image(systemName: "text.viewfinder")
        }
      } description: {
        Text(
          "This looks like a scan. Choose Recognise text in the reader's More menu, then try again.", bundle: .module)
      }
    case .failed:
      ContentUnavailableView {
        Label {
          Text("That didn't work", bundle: .module)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
      } description: {
        Text("The request didn't finish. Your document hasn't changed. Try again.", bundle: .module)
      } actions: {
        Button {
          Task { await model.start() }
        } label: {
          Text("Try again", bundle: .module)
        }
      }
    }
  }

  private func answerCard(_ answer: Answer) -> some View {
    VStack(alignment: .leading, spacing: Spacing.s150) {
      if let question = model.answeredQuestion {
        Text(question).font(.headline).accessibilityAddTraits(.isHeader)
      }
      TierBadge(tier: answer.tier)
      if answer.isGrounded {
        Text(answer.text).font(.body).textSelection(.enabled).accessibilityIdentifier("assistant.answer")
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: Spacing.s100) {
            ForEach(answer.citations) { citation in
              CitationChip(citation: citation) { model.reveal(citation) }
            }
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sources", bundle: .module))
        Button {
          UIPasteboard.general.string = model.shareableText
          Task { await model.recordKept() }
        } label: {
          Label {
            Text("Copy", bundle: .module)
          } icon: {
            Image(systemName: "doc.on.doc")
          }
        }
        GeneratedFootnote()
      } else {
        Label {
          Text("Not found in this document", bundle: .module)
        } icon: {
          Image(systemName: "questionmark.circle")
        }
        .font(.headline)
        .accessibilityIdentifier("assistant.notFound")
        Text("The answer isn't in the text of this document, so nothing was guessed.", bundle: .module)
          .font(.callout).foregroundStyle(Color.ds.labelSecondary)
      }
    }
    .cardStyle()
  }

  private func extractionCard(_ extraction: Extraction) -> some View {
    VStack(alignment: .leading, spacing: Spacing.s150) {
      TierBadge(tier: extraction.tier)
      if extraction.fields.isEmpty {
        Text("No fields were found in this document.", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
      }
      ForEach(extraction.fields) { field in
        VStack(alignment: .leading, spacing: Spacing.s050) {
          HStack {
            Self.fieldName(field.key).font(.subheadline.weight(.semibold))
            Spacer()
            if field.isVerified, let pageIndex = field.pageIndex {
              CitationChip(citation: Citation(pageIndex: pageIndex, quote: field.value)) {
                model.reveal(Citation(pageIndex: pageIndex, quote: field.value))
              }
            } else {
              Label {
                Text("Check this value", bundle: .module)
              } icon: {
                Image(systemName: "exclamationmark.triangle")
              }
              .font(.caption).foregroundStyle(Color.ds.statusWarning)
            }
          }
          TextField(text: Binding(get: { field.value }, set: { model.setValue($0, forField: field.key) })) {
            Self.fieldName(field.key)
          }
          .textFieldStyle(.roundedBorder)
        }
      }
      Button {
        UIPasteboard.general.string = extraction.csv
        Task { await model.recordKept() }
      } label: {
        Label {
          Text("Copy as CSV", bundle: .module)
        } icon: {
          Image(systemName: "tablecells")
        }
      }
      GeneratedFootnote()
    }
    .cardStyle()
  }

  // MARK: - Copy

  static func title(for task: AssistantTask) -> Text {
    switch task {
    case .summarize: Text("Summarise", bundle: .module)
    case .ask: Text("Ask", bundle: .module)
    case .extract: Text("Extract", bundle: .module)
    case .explainContract: Text("Contract", bundle: .module)
    }
  }

  static func explanation(for reason: IntelligenceUnavailableReason) -> Text {
    switch reason {
    case .deviceNotEligible:
      Text(
        "This device doesn't support Apple Intelligence. Reading, search, markup and scanning all still work.",
        bundle: .module)
    case .appleIntelligenceNotEnabled:
      Text(
        "Turn on Apple Intelligence in the Settings app to use it here. Everything else works without it.",
        bundle: .module)
    case .modelNotReady:
      Text("Apple Intelligence is still getting ready on this device. Try again in a little while.", bundle: .module)
    case .hiddenBySettings:
      Text("AI features are turned off in Settings.", bundle: .module)
    case .requestTooLarge:
      Text(
        "This request is too large for the on-device model. Try a shorter question or a smaller document.",
        bundle: .module)
    }
  }

  static func fieldName(_ key: String) -> Text {
    switch key {
    case "documentType": Text("Document type", bundle: .module)
    case "reference": Text("Reference number", bundle: .module)
    case "issueDate": Text("Date", bundle: .module)
    case "dueDate": Text("Due date", bundle: .module)
    case "total": Text("Total", bundle: .module)
    case "seller": Text("From", bundle: .module)
    case "buyer": Text("To", bundle: .module)
    default: Text(key)
    }
  }
}
