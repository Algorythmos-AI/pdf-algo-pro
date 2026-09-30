# Swift style guide

How PDF Algo Pro's Swift and SwiftUI code is written: naming, file and type layout, access control,
value and reference types, observable models and view composition, actor isolation, async code,
errors, optionals, extensions, previews, environment values, test code, and the `swift-format`
configuration that CI enforces. It applies Swift 6 and current SwiftUI practice to the rules in the
[coding standards](coding-standards.md); where a formatter can decide, `swift-format` decides.

Owner: Architecture · Reviewed: after each WWDC, when a new Xcode or Swift version is adopted, and each milestone

## Baseline

- Swift 6 language mode, strict concurrency `complete`, warnings as errors, built with Xcode 27
  ([ADR-0001](adr/0001-platform-floor-and-swift-6.md)).
- SwiftUI and Observation everywhere; UIKit only inside adapters
  ([ADR-0003](adr/0003-swiftui-observation-and-di.md)).
- Two-space indentation and a 120-character line, matching [.editorconfig](../.editorconfig).
- The [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) are
  part of this guide; the sections below add what they leave open.

## Naming

Clarity at the point of use is the goal: a call site should read clearly without the declaration
beside it (API Design Guidelines).

| Rule | Example |
|---|---|
| Types and protocols `UpperCamelCase`; everything else `lowerCamelCase` | `DocumentID`, `pageCount` |
| Acronyms uniformly upper or lower case | `PDFDocumentView`, `pdfData`, `ocrResult`, `urlScheme` |
| Protocols describing what something is are nouns; capabilities end in `-able`, `-ible` or `-ing` | `LibraryStore`, `DocumentOpening`, `TextRecognizing` |
| Booleans read as assertions | `isEncrypted`, `hasTextLayer`, `canRedact` |
| Methods with side effects are verb phrases; without, noun phrases | `save()`, `redact(_:)`; `pageCount`, `distance(to:)` |
| Mutating and non-mutating pairs | `sort()` / `sorted()` |
| Factory methods start with `make` | `makeThumbnailRequest(for:)` |
| No abbreviations beyond terms of art | `configuration`, not `cfg`; `OCR` is a term of art |
| `async` functions are not suffixed | `open(_:)`, not `openAsync(_:)` |
| Enumeration cases are `lowerCamelCase` and name a state, not a flag | `.loading`, `.ready(pageCount:)` |
| Files are named after their primary type | `ReaderModel.swift` |

### Decision: US English spelling in identifiers

Identifiers, file names, module names, log categories and signpost names use US English spelling
(`organize`, `color`, `recognize`, `summarize`, `analyze`, `favorite`). Prose (documentation,
comments, documentation comments) uses Australian/British spelling, like every other document;
user-facing text is whatever the String Catalog says for each language.

- **Rationale.** Every identifier sits beside Apple's SDKs and the Swift standard library, which are
  spelled in US English (`Color`, `localizedDescription`, `RecognizeDocumentsRequest`). One
  spelling in code means autocompletion and search find our names and Apple's the same way, and
  nobody has to guess whether a type is `ColourToken` or `ColorToken`.
- **Trade-offs.** A domain word is spelled differently in code (`Organize.merge`) and in documents
  and UI copy ("Organise pages").
- **Alternatives considered.** British spelling in identifiers (matches the documents, but mixes
  spellings in every file that touches an Apple API); no rule (drift, and duplicate names that
  differ by one letter).
- **Risks.** Habit produces British spellings in new code; review and the glossary below catch
  them. (The planning drafts' British identifiers were renamed when this rule was adopted, before any
  code existed.)
- **Future scalability impact.** Contributors from anywhere meet the spelling they expect from the
  SDK; a spell-check lint can enforce the glossary later.

### Domain vocabulary

Use these names for these concepts everywhere in code, so the same thing is never called two names.

| Concept | Identifier | Not |
|---|---|---|
| A PDF the user owns | `Document`, `DocumentID` | `File`, `Doc`, `PDF` as a type name |
| The set of documents | `Library` | `Collection`, `Store` |
| One page | `Page`, `pageIndex` (zero-based), `pageNumber` (one-based, for display) | `pageNo` |
| Markup | `Annotation` | `Markup`, `Note` |
| Content removal | `Redaction` | `Blackout`, `Mask` |
| Recognised text | `Recognition`, `RecognizedPage` | `OCRText` |
| Page-merging and reordering | `Organize` | `Arrange` |
| An AI answer and its sources | `Answer`, `Citation` | `Response`, `Reference` |
| Where a model runs | `IntelligenceTier` (`.onDevice`, `.privateCloudCompute`, `.claude`) | `Provider` for the tier |
| A paid capability | `Entitlement` | `Feature`, `Unlock` |

## Files and type layout

```
Packages/
  Reader/                       feature packages live under Packages/Features/<Name>/
  PDFEngine/
    Package.swift
    Sources/PDFEngine/
      PDFEngine.swift           public protocols and value types
      Rendering/…               one folder per area once a package passes ~20 files
      Resources/Localizable.xcstrings
    Sources/PDFEngineTestSupport/   fakes shared with other packages' tests
    Tests/PDFEngineTests/
      __Snapshots__/            snapshot references, next to the tests that own them
App/
  PDFAlgoPro/                   app target: scenes, AppContainer, router
  UITests/
```

- **One primary type per file**, named after it. Small private helpers that serve only that type
  may share the file.
- **Previews live in `<Type>+Previews.swift`.** The coverage gate excludes files whose names end in
  `Previews.swift` ([coverage_gate.py](../scripts/ci/coverage_gate.py)); previews written inside the
  view's file count as uncovered lines.
- **Large conformances** go in `<Type>+<Protocol>.swift`.
- **All Swift lives under `App/` or `Packages/`**, because that is what CI formats and lints.
- **Order inside a type:** nested types; static properties; environment and state properties (for
  views); stored properties; initialisers; `body` or the main computed properties; methods, public
  before private. Separate groups with `// MARK: -` comments.
- **Imports** are sorted (the formatter does it) and minimal: import `Core` for protocols rather
  than a service package, and never import a module just to reach something re-exported.

## Access control

| Level | Use |
|---|---|
| `internal` (default, written implicitly) | Everything that does not need to leave the module |
| `private` | File- and type-private helpers; the formatter prefers `private` to `fileprivate` at file scope |
| `package` | Shared between targets of one package, for example with its `TestSupport` target ([SE-0386](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0386-package-access-modifier.md)) |
| `public` | The package's API for other packages; every `public` declaration has a documentation comment |
| `open` | Not used: nothing is subclassed across modules |

- Classes are `final` unless designed for subclassing (none are, so far).
- `@testable import` only in the package's own unit tests; prefer testing through `public` or
  `package` API so tests do not freeze internals.
- No underscored or SPI attributes (`@_spi`, `@_implementationOnly`) in first-party code.

## Value and reference types

- **Structs and enums by default.** Domain values in `Core` are immutable, `Sendable`, and
  `Equatable` or `Hashable` where comparisons make sense.
- **Classes only for identity or observation**: `@Observable` feature models and the few adapters
  that wrap a framework object.
- **Actors for shared mutable state across concurrency domains**: document I/O, the OCR queue,
  indexing, AI sessions ([coding standards](coding-standards.md#concurrency)).
- **Protocols at seams, not everywhere.** A protocol exists for a service boundary (so a fake can
  replace it) or a genuine family of types; a protocol with one conformer and no fake is removed.
- **Identifiers are types.** `DocumentID`, `PageIndex` and similar wrap raw values so they cannot be
  mixed up.

## Observable models and view composition

Feature models are `@Observable` final classes isolated to the main actor, one per screen or flow,
owned by the view with `@State` ([ADR-0003](adr/0003-swiftui-observation-and-di.md)). Observation
tracks only the properties a view reads, which keeps large document screens efficient
([Observation](https://developer.apple.com/documentation/observation)).

```swift
import Core
import Observation

/// Loads one document for the reader screen and tracks the reading position.
@MainActor
@Observable
final class ReaderModel {
  enum Phase: Equatable {
    case loading
    case ready(pageCount: Int)
    case failed(ReaderFailure)
  }

  private(set) var phase: Phase = .loading
  var currentPageIndex = 0

  private let documentID: DocumentID
  private let documents: any DocumentOpening

  init(documentID: DocumentID, documents: any DocumentOpening) {
    self.documentID = documentID
    self.documents = documents
  }

  /// Opens the document and moves to the ready or failed phase.
  func load() async {
    do {
      let summary = try await documents.open(documentID)
      phase = .ready(pageCount: summary.pageCount)
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(ReaderFailure(error))
    }
  }
}
```

- **Models expose intent methods** (`load()`, `redact(_:)`) and read-only state (`private(set)`);
  views never reach into services.
- **Services arrive through the initialiser**, as protocols from `Core`; no singletons.
- **Errors become state** (`.failed(...)`), mapped to a user-facing message in the feature
  ([coding standards](coding-standards.md#user-facing-error-messages)).
- **Large data stays out of observable state**: page images come from the engine's tiled rendering
  and the thumbnail cache.
- **No `ObservableObject` or `@Published`** in new code.

```swift
import DesignSystem
import SwiftUI

struct ReaderScreen: View {
  @State private var model: ReaderModel

  init(model: ReaderModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    Group {
      switch model.phase {
      case .loading:
        ProgressView()
      case .ready(let pageCount):
        PageStrip(pageCount: pageCount, currentPageIndex: $model.currentPageIndex)
      case .failed(let failure):
        ReaderFailureView(failure: failure) {
          Task { await model.load() }
        }
      }
    }
    .task { await model.load() }
  }
}
```

- **Small views.** `Assumption:` a `body` longer than about 40 lines is split into subviews;
  validated by reviewing the longest bodies at each milestone. Extract subviews as separate `View`
  structs rather than computed properties, so SwiftUI can compare them independently.
- **Pass the least data** a subview needs: values, `Binding`s or `@Bindable` for a model it edits;
  never a whole model "just in case".
- **Async work tied to a view** uses `.task` or `.task(id:)`, which SwiftUI cancels when the view
  disappears or the identifier changes; not `onAppear` with a `Task`.
- **Stable identity**: lists use domain identifiers, never array indices.
- **Styling** comes from `DesignSystem` components and view modifiers, never literal colours or
  fonts (colour literals are blocked by the `invariants` gate).
- **Accessibility is written with the view**: labels, grouping, traits and Dynamic Type layouts are
  part of the first version, not a follow-up ([coding standards](coding-standards.md#accessibility-by-default)).

## Main actor and isolation

- Feature models and view helpers are main-actor isolated; services are not.
- Mark pure helpers on main-actor types `nonisolated` when they touch no state.
- Use `await` on a main-actor function instead of `MainActor.run`; never `DispatchQueue.main`.
- `MainActor.assumeIsolated` only inside adapters where the framework documents a main-thread
  callback.
- In a main-actor-by-default package, declare `nonisolated` any type that a system framework calls
  from its own threads: `NSFilePresenter`, `Transferable` export and similar delegates and
  providers. Their properties and methods would otherwise be main-actor isolated. The compiler
  accepts the conformance, and the runtime isolation check then stops the app when the framework
  calls from another thread. That happened with the reader's file watcher (#101): file coordination
  read `presentedItemURL` off the main thread. A unit test that drives the callback from another
  thread catches this; typechecking does not.

### Decision: default isolation per package

Feature packages (`Features/*`) and `DesignSystem` set `.defaultIsolation(MainActor.self)` in
their manifests, and the app target sets the equivalent build setting. Every other package keeps
the default (`nonisolated`) and uses actors. All packages enable the upcoming feature
`NonisolatedNonsendingByDefault` from their first commit. Feature models still carry an explicit
`@MainActor`, as ADR-0003 describes, so the isolation is visible where they are declared.

- **Rationale.** SE-0466 lets a module infer `@MainActor` by default to remove false data-race
  errors in code that is effectively single-threaded, which is what UI code is
  ([SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)).
  Service packages must not drift onto the main actor, so they stay `nonisolated`. SE-0461 makes
  `nonisolated` async functions run on the caller's actor unless marked `@concurrent`
  ([SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md));
  upcoming features become the default in the next language mode
  ([SE-0362](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0362-piecemeal-future-features.md)),
  so adopting it before any code exists avoids a later migration.
- **Trade-offs.** Isolation depends on which package a file is in; the explicit annotation on
  models and this table compensate.
- **Alternatives considered.** Explicit `@MainActor` everywhere with no default (verbose, and the
  missing annotation is the common mistake); `MainActor` by default in every package (puts service
  work on the main actor, against the performance rules).
- **Risks.** With `NonisolatedNonsendingByDefault`, a CPU-heavy `nonisolated` async function
  called from a model runs on the main actor. Heavy work therefore lives in actors or `@concurrent`
  functions, and signposts plus performance tests catch mistakes
  ([performance budgets](performance-budgets.md)).
- **Future scalability impact.** Matches where the language is going; the same manifests work on
  macOS and visionOS.

## Async and await

- **Structured first**: `async let` for a fixed number of parallel calls; task groups with a
  concurrency bound for many (for example, OCR two pages at a time).
- **Check cancellation per unit of work** in long loops:

  ```swift
  for pageIndex in pageIndices {
    try Task.checkCancellation()
    let page = try await recognizer.recognize(pageAt: pageIndex)
    pages.append(page)
  }
  ```

- **Progress** is an `AsyncStream` whose `onTermination` cancels the underlying work.
- **Completion-handler APIs** are wrapped once, in an adapter, with a checked continuation that
  resumes exactly once on every path.
- **Time is injected**: code that waits or timestamps takes a `Clock` (production uses
  `ContinuousClock`), so tests never sleep.
- **No polling with `Task.sleep`** to wait for state; await the thing that produces it.

## Errors

- One error enumeration per package; untyped `throws` on public API with a `- Throws:` line; typed
  throws inside a package where every case is handled
  ([coding standards](coding-standards.md#decision-one-error-type-per-package-untyped-throws-at-package-boundaries)).
- Cases describe what went wrong in the package's terms and carry safe context:
  `case passwordRequired`, `case damaged(reason: DamageReason)`, never `case failed(String)`.
- Wrap framework and vendor errors at the boundary: `catch let error as NSError` inside the adapter,
  a `PDFEngineError` outside it.

## Optionals

- `guard let` for early exits, and the shorthand `if let value` when the name is unchanged.
- No force unwraps and no implicitly unwrapped optionals (the formatter enforces both outside tests).
  A literal that cannot fail, such as a constant URL, is built once in a `static let` with a
  `// swift-format-ignore: NeverForceUnwrap` comment giving the reason.
- No optional Booleans: model three states with an enumeration.
- `??` only with a meaningful default; an absent value that is really an error throws.

## Extensions

- One extension per protocol conformance, marked `// MARK: - Equatable` and so on.
- Access levels go on members, not on the extension (the formatter moves them).
- Extensions of Apple types live in `<Type>+<Purpose>.swift` in the package that needs them, and
  stay `internal` unless several packages need them (then they go in `Core` or `DesignSystem`).
- No retroactive conformance of an Apple type to an Apple protocol; wrap the type instead.

## SwiftUI previews

Every view has previews, in `<View>+Previews.swift`, built from synthetic data only.

- **Preview container.** One `PreviewModifier` supplies in-memory fakes and a synthetic library to
  every preview that uses it; its shared context is created once and cached
  ([PreviewModifier](https://developer.apple.com/documentation/swiftui/previewmodifier)).
- **Cover the states and settings that matter**: empty, loading, error and content; light and dark;
  an accessibility text size; French; right-to-left.
- **`@Previewable`** for inline state in a preview body
  ([Previewable](https://developer.apple.com/documentation/swiftui/previewable())).

```swift
import SwiftUI

/// Supplies fake services and a synthetic library to previews.
struct PreviewContainer: PreviewModifier {
  static func makeSharedContext() throws -> AppContainer {
    AppContainer.preview(library: .syntheticSample)
  }

  func body(content: Content, context: AppContainer) -> some View {
    content.environment(\.documentOpener, context.documentOpener)
  }
}

#Preview("Ready, accessibility size", traits: .modifier(PreviewContainer())) {
  ReaderScreen(model: .preview(phase: .ready(pageCount: 12)))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Failed, French, right to left", traits: .modifier(PreviewContainer())) {
  ReaderScreen(model: .preview(phase: .failed(.damaged)))
    .environment(\.locale, Locale(identifier: "fr"))
    .environment(\.layoutDirection, .rightToLeft)
}
```

## Environment values with `@Entry`

Services reach views through environment values declared with the `@Entry` macro
([Entry](https://developer.apple.com/documentation/swiftui/entry())); the app places the live
implementations from `AppContainer`, previews and tests place fakes.

```swift
extension EnvironmentValues {
  /// Opens documents for reading. The app injects the live implementation.
  @Entry var documentOpener: any DocumentOpening = UnimplementedDocumentOpener()
}
```

- The default is an **unimplemented** service that reports a fault and fails in Debug builds, so a
  missing injection is found in a preview or test, not by a user.
- Service protocols are `Sendable`, so the default value is safe to share.
- Environment values carry services and cross-cutting settings only; screen state belongs in the
  feature model.
- `@Entry` also declares `FocusedValues` for menu commands and keyboard shortcuts on iPad and Mac.

## Test code

Test strategy and suites are in the [testing strategy](testing-strategy.md); this is how tests are
written.

- **Swift Testing for unit and integration tests**: a suite is a `struct` named after the subject
  (`ReaderModelTests`); test functions are `lowerCamelCase` sentences about behaviour,
  with a display name when the sentence needs punctuation.

  ```swift
  @Suite("Reader model")
  struct ReaderModelTests {
    @Test("A wrong password leaves the reader in the password-required state")
    func wrongPasswordKeepsPasswordRequired() async throws {
      let documents = FakeDocumentOpener(result: .failure(.passwordRequired))
      let model = await ReaderModel(documentID: .sample, documents: documents)
      await model.load()
      #expect(await model.phase == .failed(.passwordRequired))
    }
  }
  ```

- **Parameterised tests** (`@Test(arguments:)`) instead of loops, so each case reports separately.
- **Tags** from one shared list (`.golden`, `.ocr`, `.snapshot`, `.slow`) select subsets in test
  plans ([Swift Testing traits](https://developer.apple.com/documentation/testing/traits)).
- **XCTest for UI and performance tests**: methods start with `test` and name the behaviour,
  `testScanCreatesSearchablePDF()`.
- **One behaviour per test**, arranged as set-up, action, expectation; fakes from the package's
  `TestSupport` target; no sleeping, no network, no shared mutable state (Swift Testing runs tests
  in parallel by default ([Parallelization](https://developer.apple.com/documentation/testing/parallelization))).

## Formatting with swift-format

### Decision: `swift-format` as the only formatter and linter

- **Rationale.** `swift-format` is part of the Swift toolchain from Swift 6 and Xcode 16 onwards, so
  it needs no dependency or ADR and always matches the compiler in use
  ([swift-format README](https://github.com/swiftlang/swift-format)). It both formats and lints,
  and its rule set covers most of this guide (force unwraps, documentation comments, naming).
- **Trade-offs.** Fewer rules than community linters, and no custom rules; the remaining rules live
  in review and in `invariants`.
- **Alternatives considered.** SwiftLint (a third-party tool with custom rules; needs an ADR,
  pinning and checksum verification); SwiftFormat (a third-party formatter with a different style);
  no formatter (style arguments in review).
- **Risks.** Rules and output can change between toolchain versions; the configuration is re-checked
  when Xcode is updated, in its own pull request.
- **Future scalability impact.** Style is never a review topic, whatever the number of contributors.

### Configuration

The file is `.swift-format` at the repository root, added in the first code pull request. It is
generated from the pinned toolchain with `xcrun swift-format dump-configuration` and then given the
values below, so it only contains settings that toolchain understands
([configuration reference](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md),
[rules](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md)).

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 2 },
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": false,
  "lineBreakBeforeEachGenericRequirement": false,
  "prioritizeKeepingFunctionOutputTogether": true,
  "indentConditionalCompilationBlocks": true,
  "lineBreakAroundMultilineExpressionChainComponents": false,
  "fileScopedDeclarationPrivacy": { "accessLevel": "private" },
  "indentSwitchCaseLabels": false,
  "spacesAroundRangeFormationOperators": false,
  "noAssignmentInExpressions": { "allowedFunctions": ["XCTAssertNoThrow"] },
  "multiElementCollectionTrailingCommas": true,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": true,
    "AlwaysUseLiteralForEmptyCollectionInit": true,
    "AlwaysUseLowerCamelCase": true,
    "AmbiguousTrailingClosureOverload": true,
    "AvoidRetroactiveConformances": true,
    "BeginDocumentationCommentWithOneLineSummary": true,
    "DoNotUseSemicolons": true,
    "DontRepeatTypeInStaticProperties": true,
    "FileScopedDeclarationPrivacy": true,
    "FullyIndirectEnum": true,
    "GroupNumericLiterals": true,
    "IdentifiersMustBeASCII": true,
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "NeverUseImplicitlyUnwrappedOptionals": true,
    "NoAccessLevelOnExtensionDeclaration": true,
    "NoAssignmentInExpressions": true,
    "NoBlockComments": true,
    "NoCasesWithOnlyFallthrough": true,
    "NoEmptyLinesOpeningClosingBraces": false,
    "NoEmptyTrailingClosureParentheses": true,
    "NoLabelsInCasePatterns": true,
    "NoLeadingUnderscores": true,
    "NoParensAroundConditions": true,
    "NoPlaygroundLiterals": true,
    "NoVoidReturnOnFunctionSignature": true,
    "OmitExplicitReturns": false,
    "OneCasePerLine": true,
    "OneVariableDeclarationPerLine": true,
    "OnlyOneTrailingClosureArgument": true,
    "OrderedImports": true,
    "ReplaceForEachWithForLoop": true,
    "ReturnVoidInsteadOfEmptyTuple": true,
    "TypeNamesShouldBeCapitalized": true,
    "UseEarlyExits": true,
    "UseExplicitNilCheckInConditions": true,
    "UseLetInEveryBoundCaseVariable": true,
    "UseShorthandTypeNames": true,
    "UseSingleLinePropertyGetter": true,
    "UseSynthesizedInitializer": true,
    "UseTripleSlashForDocumentationComments": true,
    "UseWhereClausesInForLoops": false,
    "ValidateDocumentationComments": true
  }
}
```

Choices that differ from the tool's defaults, and why:

| Setting | Default | Ours | Why |
|---|---|---|---|
| `lineLength` | 100 | 120 | Matches [.editorconfig](../.editorconfig); SwiftUI modifier chains and descriptive names read better |
| `prioritizeKeepingFunctionOutputTogether` | false | true | Keeps `async throws -> Result` on the signature line |
| `AllPublicDeclarationsHaveDocumentation`, `BeginDocumentationCommentWithOneLineSummary`, `ValidateDocumentationComments` | off | on | The API Design Guidelines ask for a documentation comment on every declaration; package APIs are our contracts. The cost is a comment on each public `body`. |
| `NeverForceUnwrap`, `NeverUseForceTry`, `NeverUseImplicitlyUnwrappedOptionals` | off | on | Crash-free input handling ([coding standards](coding-standards.md#error-handling)); the tool exempts test code |
| `NoLeadingUnderscores` | off | on | Underscores hide intent; property-wrapper storage (`_model`) is assigned, not declared, so it is unaffected |
| `AlwaysUseLiteralForEmptyCollectionInit`, `UseEarlyExits` | off | on | `[]` and `guard` are the idioms this guide asks for |

### How CI runs it

The `ios` job in [ci.yml](../.github/workflows/ci.yml) runs:

```sh
xcrun swift-format lint --strict --recursive App Packages
```

`swift-format` looks for `.swift-format` in each file's directory and then its parents, so the root
file applies everywhere; `--strict` turns lint warnings into a failing exit code
([swift-format README](https://github.com/swiftlang/swift-format)). Before pushing, run the same
command locally, after formatting in place:

```sh
xcrun swift-format format --in-place --recursive App Packages
```

### Suppressing a rule

`// swift-format-ignore: <RuleName>` on the line before a declaration or statement, with a comment
saying why ([ignoring source](https://github.com/swiftlang/swift-format/blob/main/Documentation/IgnoringSource.md)).
`// swift-format-ignore-file` is allowed only in generated code. A suppression without a reason is
not accepted in review.

## Open questions

- Which English variant is the development language of the String Catalogs (`en` written with
  British spelling, or `en` in US spelling with `en-AU` and `en-GB` variants).
- Confirm that the Xcode 27 toolchain's `swift-format` supports every rule named above when the
  file is generated; drop any it does not.
