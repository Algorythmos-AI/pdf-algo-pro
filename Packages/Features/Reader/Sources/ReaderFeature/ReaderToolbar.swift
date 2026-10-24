import AccessibilityIDs
import Core
import DesignSystem
import PDFEngine
import SwiftUI
import UIKit

/// The reader's tools: Edit (when editing text is offered), Ask (when intelligence is shown),
/// Markup and More.
struct ReaderToolbar: ToolbarContent {
  let model: ReaderModel
  @Binding var isAddingNote: Bool
  @Binding var isAddingTextBox: Bool
  /// Whether the bar is in its ordinary state and this build offers editing text.
  private var showsEdit: Bool {
    model.phase == .ready && !model.isDrawing && model.markupTool == nil && !model.isEditingText
      && model.textEditingAccess != .hidden
  }

  var body: some ToolbarContent {
    // Edit is the reader's one filled action, in a group of its own, apart from the icons.
    if showsEdit {
      // The capsule is the button's whole background; the bar adds no glass of its own behind it.
      // In a stack, so that the bar takes the item as a view of its own size, not as a bar button
      // in a square slot, which a longer word ("Modifier") would spill out of.
      ToolbarItem(placement: .primaryAction) { HStack(spacing: 0) { EditTextButton(model: model) } }
        .sharedBackgroundVisibility(.hidden)
      ToolbarSpacer(.fixed, placement: .primaryAction)
    }
    ToolbarItemGroup(placement: .primaryAction) {
      if model.isDrawing {
        // Undo is beside the work, not two menus away: a line or a shape that went wrong is taken
        // back with one tap (a tester's report, 2026-10-06).
        UndoRedoButtons(
          model: model, undoID: AccessibilityID.Reader.Drawing.undo, redoID: AccessibilityID.Reader.Drawing.redo)
        Button {
          model.setDrawing(false)
        } label: {
          Text("Done", bundle: .module).bold()
        }
        .accessibilityIdentifier(AccessibilityID.Reader.doneDrawing)
      } else if model.markupTool != nil {
        UndoRedoButtons(
          model: model, undoID: AccessibilityID.Reader.MarkupTool.undo,
          redoID: AccessibilityID.Reader.MarkupTool.redo)
        Button {
          model.stopMarkupTool()
        } label: {
          Text("Done", bundle: .module).bold()
        }
        .accessibilityIdentifier(AccessibilityID.Reader.doneMarkup)
      } else if model.isEditingText {
        // While text is being typed, Undo belongs to the typing, so these wait.
        Button {
          Task { await model.undo() }
        } label: {
          Label {
            Text("Undo", bundle: .module)
          } icon: {
            Image(systemName: "arrow.uturn.backward")
          }
        }
        .disabled(!model.canUndo || model.selectedTextRegion != nil)
        .keyboardShortcut("z")
        .accessibilityIdentifier(AccessibilityID.Reader.TextEdit.undo)
        Button {
          Task { await model.redo() }
        } label: {
          Label {
            Text("Redo", bundle: .module)
          } icon: {
            Image(systemName: "arrow.uturn.forward")
          }
        }
        .disabled(!model.canRedo || model.selectedTextRegion != nil)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .accessibilityIdentifier(AccessibilityID.Reader.TextEdit.redo)
        Button {
          Task { await model.endTextEditing() }
        } label: {
          Text("Done", bundle: .module).bold()
        }
        .disabled(model.selectedTextRegion != nil)
        .accessibilityIdentifier(AccessibilityID.Reader.doneEditingText)
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
            .accessibilityIdentifier(AccessibilityID.Reader.Ask.summarise)
            Button {
              model.assistantTask = .ask
            } label: {
              Label {
                Text("Ask a question", bundle: .module)
              } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Ask.question)
            Button {
              model.assistantTask = .extract
            } label: {
              Label {
                Text("Extract data", bundle: .module)
              } icon: {
                Image(systemName: "tablecells")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Ask.extract)
            Button {
              model.assistantTask = .explainContract
            } label: {
              Label {
                Text("Explain contract", bundle: .module)
              } icon: {
                Image(systemName: "doc.text.magnifyingglass")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Ask.contract)
          } label: {
            Label {
              Text("Ask", bundle: .module)
            } icon: {
              Image(systemName: "sparkles")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.ask)
        }
        Menu {
          ForEach(TextMarkup.allCases, id: \.self) { markup in
            Button {
              Task { await model.markUpSelection(markup) }
            } label: {
              Self.label(for: markup)
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Markup.text(markup.rawValue))
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
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.draw)
          Menu {
            ForEach([DrawingTool.rectangle, .oval, .arrow], id: \.self) { tool in
              Button {
                model.setDrawing(true, tool: tool)
              } label: {
                Self.label(for: tool)
              }
              .accessibilityIdentifier(AccessibilityID.Reader.Markup.shape(tool.rawValue))
            }
          } label: {
            Label {
              Text("Shapes", bundle: .module)
            } icon: {
              Image(systemName: "square.on.circle")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.shapes)
          Button {
            isAddingTextBox = true
          } label: {
            Label {
              Text("Text box", bundle: .module)
            } icon: {
              Image(systemName: "character.textbox")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.textBox)
          Button {
            model.showSignatures()
          } label: {
            Label {
              Text("Signature", bundle: .module)
            } icon: {
              Image(systemName: "signature")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.signature)
          Button {
            isAddingNote = true
          } label: {
            Label {
              Text("Add note", bundle: .module)
            } icon: {
              Image(systemName: "note.text.badge.plus")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.note)
          Menu {
            Button {
              Task { await model.addStamp(.date(Date())) }
            } label: {
              Text("Today's date", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Markup.Stamp.date)
            Button {
              Task { await model.addStamp(.tick) }
            } label: {
              Text("Tick", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Markup.Stamp.tick)
            Button {
              Task { await model.addStamp(.cross) }
            } label: {
              Text("Cross", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Markup.Stamp.cross)
            Button {
              model.isAddingStampText = true
            } label: {
              Text("Text or initials…", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Markup.Stamp.text)
          } label: {
            Label {
              Text("Stamp", bundle: .module)
            } icon: {
              Image(systemName: "seal")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.stamp)
          if model.canPasteAnnotation {
            Button {
              model.setPastingAnnotations(true)
            } label: {
              Label {
                Text("Paste", bundle: .module)
              } icon: {
                Image(systemName: "doc.on.clipboard")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.Markup.paste)
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
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.undo)
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
          .accessibilityIdentifier(AccessibilityID.Reader.Markup.redo)
          .disabled(!model.canRedo)
        } label: {
          Label {
            Text("Markup", bundle: .module)
          } icon: {
            Image(systemName: "highlighter")
          }
        }
        .accessibilityIdentifier(AccessibilityID.Reader.markup)
        Menu {
          // Find, Share and Print share one row of icons, so the whole menu fits without scrolling:
          // a menu scrolls silently after about eleven rows and hid Version history at the bottom.
          ControlGroup {
            Button {
              model.controller?.showFind()
            } label: {
              Label {
                Text("Find", bundle: .module)
              } icon: {
                Image(systemName: "magnifyingglass")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.More.find)
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
            .accessibilityIdentifier(AccessibilityID.Reader.More.share)
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
              .accessibilityIdentifier(AccessibilityID.Reader.More.print)
              .keyboardShortcut("p")
            }
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
          .accessibilityIdentifier(AccessibilityID.Reader.More.goToPage)
          Button {
            model.showsPages = true
          } label: {
            Label {
              Text("Pages", bundle: .module)
            } icon: {
              Image(systemName: "square.grid.2x2")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.More.pages)
          Button {
            model.showsOutline = true
          } label: {
            Label {
              Text("Contents", bundle: .module)
            } icon: {
              Image(systemName: "list.bullet.indent")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.More.contents)
          Button {
            Task { await model.toggleBookmark() }
          } label: {
            Label {
              model.isCurrentPageBookmarked
                ? Text("Remove bookmark", bundle: .module) : Text("Bookmark this page", bundle: .module)
            } icon: {
              Image(systemName: model.isCurrentPageBookmarked ? "bookmark.slash" : "bookmark")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.bookmark)
          Button {
            model.showsAnnotations = true
          } label: {
            Label {
              Text("Annotations", bundle: .module)
            } icon: {
              Image(systemName: "list.bullet.rectangle")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.annotations)
          Divider()
          // The export and protection tools sit one level down, so the menu fits on the screen.
          Menu {
            Menu {
              Button {
                Task { await model.reduceSize(.email) }
              } label: {
                Text("Smallest, for email", bundle: .module)
              }
              .accessibilityIdentifier(AccessibilityID.Reader.More.Reduce.smallest)
              Button {
                Task { await model.reduceSize(.balanced) }
              } label: {
                Text("Balanced, for printing", bundle: .module)
              }
              .accessibilityIdentifier(AccessibilityID.Reader.More.Reduce.balanced)
            } label: {
              Label {
                Text("Reduce file size", bundle: .module)
              } icon: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.More.reduce)
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
                .accessibilityIdentifier(AccessibilityID.Reader.More.removePassword)
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
              .accessibilityIdentifier(AccessibilityID.Reader.More.addPassword)
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
            .accessibilityIdentifier(AccessibilityID.Reader.More.flattened)
            Button {
              Task { await model.sharePageImage() }
            } label: {
              Label {
                Text("Share this page as an image", bundle: .module)
              } icon: {
                Image(systemName: "photo")
              }
            }
            .accessibilityIdentifier(AccessibilityID.Reader.More.pageImage)
          } label: {
            Label {
              Text("Export and protect", bundle: .module)
            } icon: {
              Image(systemName: "lock.doc")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.More.export)
          LayoutMenu(model: model)
          Button {
            model.toggleReadAloud()
          } label: {
            Label {
              model.speech.isSpeaking ? Text("Stop reading", bundle: .module) : Text("Read aloud", bundle: .module)
            } icon: {
              Image(systemName: model.speech.isSpeaking ? "stop.circle" : "speaker.wave.2")
            }
          }
          .accessibilityIdentifier(AccessibilityID.Reader.More.readAloud)
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
            .accessibilityIdentifier(AccessibilityID.Reader.More.recognise)
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
            .accessibilityIdentifier(AccessibilityID.Reader.versions)
          }
        } label: {
          Label {
            Text("More", bundle: .module)
          } icon: {
            Image(systemName: "ellipsis.circle")
          }
        }
        .accessibilityIdentifier(AccessibilityID.Reader.more)
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

/// The way into editing the text of the document: the reader's primary action, so it is the one
/// button in the bar that is filled and says what it does (design system, buttons and toolbars).
struct EditTextButton: View {
  let model: ReaderModel
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    Button {
      Task { await model.beginTextEditing() }
    } label: {
      Label {
        Text("Edit", bundle: .module)
      } icon: {
        Image(systemName: "character.cursor.ibeam")
      }
      .modifier(EditLabelStyle(showsIcon: sizeClass == .regular))
    }
    // The design system's capsule, which sets the label's colour itself: the system's prominent
    // glass picks a label colour that is too faint on the dark fill (colour rule 3).
    .buttonStyle(.primaryBar)
    .keyboardShortcut("e")
    .accessibilityHint(Text("Changes the text in this PDF", bundle: .module))
    .accessibilityIdentifier(AccessibilityID.Reader.edit)
  }
}

/// The word alone where the bar is narrow; the symbol beside it where there is room.
private struct EditLabelStyle: ViewModifier {
  let showsIcon: Bool

  func body(content: Content) -> some View {
    if showsIcon {
      content.labelStyle(.titleAndIcon)
    } else {
      content.labelStyle(.titleOnly)
    }
  }
}

/// Undo and Redo for the bar, while a tool is in hand.
struct UndoRedoButtons: View {
  let model: ReaderModel
  /// The buttons' identifiers, one pair for each mode, so each pair can be told apart in tests.
  let undoID: String
  /// See `undoID`.
  let redoID: String

  var body: some View {
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
    .keyboardShortcut("z")
    .accessibilityIdentifier(undoID)
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
    .keyboardShortcut("z", modifiers: [.command, .shift])
    .accessibilityIdentifier(redoID)
  }
}

/// The reader's layout choices: how pages are laid out and, where the build has it, the page strip.
struct LayoutMenu: View {
  let model: ReaderModel

  var body: some View {
    if model.offersReadingControls {
      // A menu around the choice, because a switch cannot sit among a picker's options.
      Menu {
        layout.pickerStyle(.inline)
        Toggle(isOn: Binding(get: { model.wantsPageStrip }, set: { model.setWantsPageStrip($0) })) {
          Text("Page strip", bundle: .module)
        }
        .accessibilityIdentifier(AccessibilityID.Reader.More.Layout.pageStrip)
      } label: {
        title
      }
      .accessibilityIdentifier(AccessibilityID.Reader.More.layout)
    } else {
      layout.pickerStyle(.menu)
        .accessibilityIdentifier(AccessibilityID.Reader.More.layout)
    }
  }

  private var title: some View {
    Label {
      Text("Layout", bundle: .module)
    } icon: {
      Image(systemName: "rectangle.split.1x2")
    }
  }

  private var layout: some View {
    Picker(
      selection: Binding(get: { model.controller?.displayMode ?? .continuous }, set: { model.setDisplayMode($0) })
    ) {
      Text("Continuous", bundle: .module).tag(ReaderDisplayMode.continuous)
      Text("Single page", bundle: .module).tag(ReaderDisplayMode.singlePage)
    } label: {
      title
    }
  }
}
