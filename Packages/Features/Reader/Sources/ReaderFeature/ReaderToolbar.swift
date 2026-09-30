import Core
import PDFEngine
import SwiftUI
import UIKit

/// The reader's tools: Ask (when intelligence is shown), Markup and More.
struct ReaderToolbar: ToolbarContent {
  let model: ReaderModel
  @Binding var isAddingNote: Bool
  @Binding var isAddingTextBox: Bool

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      if model.isDrawing {
        Button {
          model.setDrawing(false)
        } label: {
          Text("Done", bundle: .module)
        }
        .accessibilityIdentifier("reader.doneDrawing")
      } else if model.phase == .ready {
        if model.showsIntelligence {
          Menu {
            Button {
              model.assistantTask = .summarize
            } label: {
              Label {
                Text("Summarise", bundle: .module)
              } icon: {
                Image(systemName: "text.append")
              }
            }
            Button {
              model.assistantTask = .ask
            } label: {
              Label {
                Text("Ask a question", bundle: .module)
              } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right")
              }
            }
            Button {
              model.assistantTask = .extract
            } label: {
              Label {
                Text("Extract data", bundle: .module)
              } icon: {
                Image(systemName: "tablecells")
              }
            }
            Button {
              model.assistantTask = .explainContract
            } label: {
              Label {
                Text("Explain contract", bundle: .module)
              } icon: {
                Image(systemName: "doc.text.magnifyingglass")
              }
            }
          } label: {
            Label {
              Text("Ask", bundle: .module)
            } icon: {
              Image(systemName: "sparkles")
            }
          }
          .accessibilityIdentifier("reader.ask")
        }
        Menu {
          ForEach(TextMarkup.allCases, id: \.self) { markup in
            Button {
              Task { await model.markUpSelection(markup) }
            } label: {
              Self.label(for: markup)
            }
          }
          Button {
            model.setDrawing(true)
          } label: {
            Label {
              Text("Draw", bundle: .module)
            } icon: {
              Image(systemName: "pencil.tip")
            }
          }
          Menu {
            ForEach([DrawingTool.rectangle, .oval, .arrow], id: \.self) { tool in
              Button {
                model.setDrawing(true, tool: tool)
              } label: {
                Self.label(for: tool)
              }
            }
          } label: {
            Label {
              Text("Shapes", bundle: .module)
            } icon: {
              Image(systemName: "square.on.circle")
            }
          }
          Button {
            isAddingTextBox = true
          } label: {
            Label {
              Text("Text box", bundle: .module)
            } icon: {
              Image(systemName: "character.textbox")
            }
          }
          Menu {
            Button {
              Task { await model.addStamp(.date(Date())) }
            } label: {
              Text("Today's date", bundle: .module)
            }
            Button {
              Task { await model.addStamp(.tick) }
            } label: {
              Text("Tick", bundle: .module)
            }
            Button {
              Task { await model.addStamp(.cross) }
            } label: {
              Text("Cross", bundle: .module)
            }
            Button {
              model.isAddingStampText = true
            } label: {
              Text("Text or initials…", bundle: .module)
            }
          } label: {
            Label {
              Text("Stamp", bundle: .module)
            } icon: {
              Image(systemName: "seal")
            }
          }
          Button {
            model.showSignatures()
          } label: {
            Label {
              Text("Signature", bundle: .module)
            } icon: {
              Image(systemName: "signature")
            }
          }
          Button {
            isAddingNote = true
          } label: {
            Label {
              Text("Add note", bundle: .module)
            } icon: {
              Image(systemName: "note.text.badge.plus")
            }
          }
          Button {
            Task { await model.undo() }
          } label: {
            Label {
              Text("Undo", bundle: .module)
            } icon: {
              Image(systemName: "arrow.uturn.backward")
            }
          }
          .disabled(!model.canUndo)
          Button {
            Task { await model.redo() }
          } label: {
            Label {
              Text("Redo", bundle: .module)
            } icon: {
              Image(systemName: "arrow.uturn.forward")
            }
          }
          .disabled(!model.canRedo)
        } label: {
          Label {
            Text("Markup", bundle: .module)
          } icon: {
            Image(systemName: "highlighter")
          }
        }
        .accessibilityIdentifier("reader.markup")
        Menu {
          Button {
            model.controller?.showFind()
          } label: {
            Label {
              Text("Find", bundle: .module)
            } icon: {
              Image(systemName: "magnifyingglass")
            }
          }
          .keyboardShortcut("f")
          Button {
            Task { await model.share() }
          } label: {
            Label {
              Text("Share", bundle: .module)
            } icon: {
              Image(systemName: "square.and.arrow.up")
            }
          }
          if model.allowsPrinting {
            Button {
              Task {
                guard let url = await model.fileForSharing() else { return }
                let printer = UIPrintInteractionController.shared
                printer.printingItem = url
                printer.present(animated: true)
              }
            } label: {
              Label {
                Text("Print", bundle: .module)
              } icon: {
                Image(systemName: "printer")
              }
            }
            .keyboardShortcut("p")
          }
          Button {
            model.showsGoToPage = true
          } label: {
            Label {
              Text("Go to page", bundle: .module)
            } icon: {
              Image(systemName: "number")
            }
          }
          Button {
            model.showsPages = true
          } label: {
            Label {
              Text("Pages", bundle: .module)
            } icon: {
              Image(systemName: "square.grid.2x2")
            }
          }
          Button {
            model.showsOutline = true
          } label: {
            Label {
              Text("Contents", bundle: .module)
            } icon: {
              Image(systemName: "list.bullet.indent")
            }
          }
          Section {
            Menu {
              Button {
                Task { await model.reduceSize(.email) }
              } label: {
                Text("Smallest, for email", bundle: .module)
              }
              Button {
                Task { await model.reduceSize(.balanced) }
              } label: {
                Text("Balanced, for printing", bundle: .module)
              }
            } label: {
              Label {
                Text("Reduce file size", bundle: .module)
              } icon: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
              }
            }
            if model.isPasswordProtected {
              if model.canRemovePassword {
                Button {
                  model.confirmsPasswordRemoval = true
                } label: {
                  Label {
                    Text("Remove password", bundle: .module)
                  } icon: {
                    Image(systemName: "lock.open")
                  }
                }
              }
            } else {
              Button {
                model.isAddingPassword = true
              } label: {
                Label {
                  Text("Add a password", bundle: .module)
                } icon: {
                  Image(systemName: "lock")
                }
              }
            }
            Button {
              Task { await model.shareFlattened() }
            } label: {
              Label {
                Text("Share a flattened copy", bundle: .module)
              } icon: {
                Image(systemName: "square.stack.3d.down.forward")
              }
            }
            Button {
              Task { await model.sharePageImage() }
            } label: {
              Label {
                Text("Share this page as an image", bundle: .module)
              } icon: {
                Image(systemName: "photo")
              }
            }
          }
          Picker(
            selection: Binding(get: { model.controller?.displayMode ?? .continuous }, set: { model.setDisplayMode($0) })
          ) {
            Text("Continuous", bundle: .module).tag(ReaderDisplayMode.continuous)
            Text("Single page", bundle: .module).tag(ReaderDisplayMode.singlePage)
          } label: {
            Text("Layout", bundle: .module)
          }
          Button {
            model.toggleReadAloud()
          } label: {
            Label {
              model.speech.isSpeaking ? Text("Stop reading", bundle: .module) : Text("Read aloud", bundle: .module)
            } icon: {
              Image(systemName: model.speech.isSpeaking ? "stop.circle" : "speaker.wave.2")
            }
          }
          if model.canRecognizeText {
            Button {
              model.recognizeText()
            } label: {
              Label {
                Text("Recognise text", bundle: .module)
              } icon: {
                Image(systemName: "text.viewfinder")
              }
            }
          }
          if model.canRestorePreviousVersion {
            Button {
              model.showsVersions = true
            } label: {
              Label {
                Text("Version history", bundle: .module)
              } icon: {
                Image(systemName: "clock.arrow.circlepath")
              }
            }
            .accessibilityIdentifier("reader.versions")
          }
        } label: {
          Label {
            Text("More", bundle: .module)
          } icon: {
            Image(systemName: "ellipsis.circle")
          }
        }
        .accessibilityIdentifier("reader.more")
      }
    }
  }

  static func label(for tool: DrawingTool) -> Label<Text, Image> {
    switch tool {
    case .pen:
      Label {
        Text("Draw", bundle: .module)
      } icon: {
        Image(systemName: "pencil.tip")
      }
    case .rectangle:
      Label {
        Text("Rectangle", bundle: .module)
      } icon: {
        Image(systemName: "rectangle")
      }
    case .oval:
      Label {
        Text("Oval", bundle: .module)
      } icon: {
        Image(systemName: "oval")
      }
    case .arrow:
      Label {
        Text("Arrow", bundle: .module)
      } icon: {
        Image(systemName: "arrow.up.right")
      }
    }
  }

  static func label(for markup: TextMarkup) -> Label<Text, Image> {
    switch markup {
    case .highlight:
      Label {
        Text("Highlight", bundle: .module)
      } icon: {
        Image(systemName: "highlighter")
      }
    case .underline:
      Label {
        Text("Underline", bundle: .module)
      } icon: {
        Image(systemName: "underline")
      }
    case .strikeThrough:
      Label {
        Text("Strike through", bundle: .module)
      } icon: {
        Image(systemName: "strikethrough")
      }
    }
  }
}
