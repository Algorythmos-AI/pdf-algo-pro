# Testing strategy

How PDF Algo Pro is tested: the test pyramid and who owns each layer, every suite (unit, UI,
snapshot, accessibility, performance, OCR accuracy, AI evaluation, regression against the golden
PDF corpus, `PDFEngine` contract tests), the coverage floor, how flaky tests are handled, where test
data may come from, and where each suite runs. The decision behind it is
[ADR-0014](adr/0014-testing-strategy-and-coverage.md); thresholds come from
[performance budgets](performance-budgets.md), [success metrics](success-metrics.md) and the
[AI evaluation framework](ai-evaluation-framework.md), and the gates that run the suites are in
[quality gates](process/quality-gates.md).

Owner: Quality · Reviewed: each milestone, and when a new Xcode version is adopted

## Principles

- **Tests are the specification.** A behaviour without a test is not finished
  ([Definition of Done](engineering-playbook.md#definition-of-done)).
- **Apple's frameworks first.** Swift Testing for unit and integration tests, XCTest for UI and
  performance tests, `.xctestplan` files to group them
  ([Swift Testing](https://developer.apple.com/documentation/testing),
  [XCTest](https://developer.apple.com/documentation/xctest),
  [test plans](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback)).
  The only third-party test library is `swift-snapshot-testing`, as a test-only dependency
  ([ADR-0018](adr/0018-snapshot-testing-test-only-dependency.md)).
- **Deterministic or deleted.** Tests use injected clocks, seeds and fakes; no sleeps, no network,
  no personal data.
- **Synthetic data only.** Every document a test touches is synthetic or licence-clean, never a real
  person's document ([test data governance](#test-data-governance)).
- **Thresholds live in one place.** This document links to the source of each number instead of
  copying it.

## Test pyramid and ownership

| Layer | Framework | Share of tests | Owner hat |
|---|---|---|---|
| Unit tests, per package | Swift Testing | Most (Assumption: about 70%) | The package's owner |
| Integration and contract tests (real Apple frameworks, `PDFEngine` contract, golden corpus, migrations) | Swift Testing | About 20% (Assumption:) | Architecture; PDF engine for the contract and corpus |
| Snapshot tests | Swift Testing + `swift-snapshot-testing` | Key screens and components | Design |
| UI tests, including accessibility audits | XCTest (XCUIAutomation) | About 10% (Assumption:), critical journeys only | Quality |
| Performance tests | XCTest metrics | One per budget row | Architecture |
| OCR accuracy suite | Swift Testing | One corpus, per language and condition | PDF engine |
| AI evaluation suite | Apple's Evaluations framework on Swift Testing | Per task, tier and language | AI |
| Manual: VoiceOver script, exploratory testing on TestFlight | Release checklist | Each release | Quality, with Design |

The shares are a guide for review, validated at each milestone by counting tests per layer; a
suite that grows top-heavy (many slow UI tests covering logic) is rebalanced.

## Unit tests

- **Per package**, in `Packages/<Name>/Tests/<Name>Tests/`, written with Swift Testing: `@Test`,
  `#expect`, `#require`, parameterised arguments and shared tags
  ([Swift style guide](swift-style-guide.md#test-code)).
- **Fakes through protocols.** Services are protocols in `Core`, so tests replace them with fakes
  from each package's `TestSupport` target (for example an in-memory `LibraryStore`, a
  `FakeDocumentOpener`, a scripted `TextRecognizing`). No mocking framework.
- **Time, randomness and identifiers are injected**, so every run is identical.
- **Parallel by default.** Swift Testing runs tests in parallel
  ([Parallelization](https://developer.apple.com/documentation/testing/parallelization)); a suite
  that must run serially says why with `.serialized`.
- **What unit tests must cover**: every feature model's state transitions, including cancellation
  and failure; the deep-link router (every URL, intent, Spotlight and widget entry becomes the right
  `Route`); error mapping to user-facing messages; flag resolution, including both states of each
  flag ([feature flags](engineering-playbook.md#feature-flags)); the error-type guarantee of each
  package's public API ([coding standards](coding-standards.md#error-handling)).
- **Integration tests** use real Apple frameworks in isolation: an in-memory SwiftData container,
  file coordination in a temporary directory, Core Spotlight indexing, StoreKit Testing with a local
  configuration and `SKTestSession` for `Commerce`
  ([StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)).
- **Migration tests** open a library index written by every previous schema version and check the
  migration and the fallback ladder ([ADR-0006](adr/0006-swiftdata-persistence.md)).

## UI tests

UI tests cover critical journeys end to end: the first-run introduction and the rules for the
offer that follows it (Close at once, no offer at a later launch, without the store, or with Pro;
FR-ONB-004), open and read, annotate and save, scan to a searchable PDF, sign, organise, ask with
citations, subscribe and restore, and the privacy centre.

- **Screen objects.** Each screen has a small type (`LibraryScreen`, `ReaderScreen`) that finds
  elements by accessibility identifier and exposes actions (`open(documentNamed:)`). Tests read as
  journeys; element queries live in one place.
- **Launch arguments select a test world.** In Debug builds only, the app reads arguments such as
  `-ui-testing` (which also resets state: temporary folders and throwaway settings),
  `-seed-library <fixture-set>`, `-skip-onboarding`, `-intelligence-unavailable`,
  `-entitlement none|trial|subscribed|expired`, `-allowance exhausted`, `-store unavailable`,
  `-purchase cancelled|failed|pending`, `-trial ineligible|none` and
  `-disable-animations`, and swaps
  in a container with fakes: a scripted intelligence router, a fixed entitlement (nobody is
  entitled unless the test says so, and the App Store is never asked), a free allowance with no
  limit unless the test asks for one that is used up, a local-only document store. Language, region and text size come from `-AppleLanguages`, `-AppleLocale` and
  `-UIPreferredContentSizeCategoryName`. Release builds contain none of this.
- **The store.** UI tests never reach the App Store, so StoreKit's view shows no plans there; they
  check what is the app's own around it (the triggers, Close, where closing leads). Buying is
  tested in the app's unit tests against StoreKit's local test environment (`SKTestSession` with
  `App/Tests/Store/Products.storekit`, whose amounts and periods are test data). That environment
  answers only in a test run started from Xcode: under `xcodebuild test`, as in CI, every call to it
  fails with `SKInternalErrorDomain` 3, a limit of the tools that others report too
  ([flutter/flutter#184678](https://github.com/flutter/flutter/issues/184678)). The suite checks
  for it and is skipped where it does not answer, so CI does not buy anything. Run from Xcode with
  the `PDFAlgoPro` scheme, the Debug app sees the same test products, so the offer can be looked at
  with its plans before the products exist in App Store Connect. Buying is therefore
  verified by running that suite from Xcode before a release that changes the store, and on a
  device with a sandbox account ([device smoke test](process/device-smoke-test.md)).
- **Deterministic data.** Libraries are seeded from generated fixtures, dates from an injected
  clock, AI answers from the scripted router. No network.
- **Stable identifiers.** Accessibility identifiers are constants shared by the app and the tests,
  never user-visible text, so French runs use the same tests.

## Snapshot tests

Visual regressions are caught with Point-Free's `swift-snapshot-testing`, used in test targets only
and never shipped ([ADR-0018](adr/0018-snapshot-testing-test-only-dependency.md),
[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)).

- **What is snapshotted:** every `DesignSystem` component in each state, and each key screen in its
  empty, loading, content and error states.
- **The matrix for each snapshot:** light and dark; the default text size, a large size and an
  accessibility size; English and French; left-to-right and right-to-left; compact and regular
  width. Screens use the full matrix; components use the states that change their layout.
- **Deterministic rendering.** Views get a fixed size or device layout, fake services and fixed
  dates. References depend on the operating-system version, so the test plan pins the simulator
  device and runtime, and references are re-recorded in a dedicated `test(ds):` pull request when
  that pin changes.
- **Recording is explicit.** The library records a missing reference automatically by default; CI
  sets `SNAPSHOT_TESTING_RECORD=never`, so a missing or changed reference fails instead of passing
  silently. References are recorded on the pinned CI simulator, because they depend on the exact
  runtime: run the `ci` workflow by hand on the branch with `record_snapshots` ticked
  (`gh workflow run ci.yml --ref <branch> -f record_snapshots=true`). The run records only the app
  tests the snapshots belong to, keeps the references as the `snapshots` artifact (`snapshots.tar`,
  unpacked at the repository root), and its `publish-snapshots` job pushes any that changed to a
  branch of their own, `snapshot-recordings/<run id>`, so they can be fetched with git where no Mac or
  artifact download is at hand. Look at each image, commit them to the pull request, where they are
  reviewed like code, and delete the recording branch. The recording run is red by design, because
  every snapshot assertion fails while recording (library documentation, same source), so it can
  never stand in for a passing `ios` check.
- **What is covered today (B8).** Onboarding, the empty library, Settings and Scan, each in light,
  dark and an accessibility text size (`App/Tests/SnapshotTests.swift`). The reader and the assistant
  follow, with a fixed document and the scripted router.
- **Tolerance.** `perceptualPrecision` slightly below 1 absorbs anti-aliasing differences
  (`Assumption:` 0.98, validated by running the suite twice on the pinned runtime and on a second
  machine); a larger tolerance needs a reason in review.
- References live in `__Snapshots__` folders next to the tests that own them.

## Accessibility tests

Accessibility is a requirement (NFR-A11Y-001, [success metrics](success-metrics.md)), tested three
ways.

1. **Automated audits in UI tests.** Each primary screen calls `performAccessibilityAudit()` on the
   running app, which checks contrast, element detection, hit regions, element descriptions,
   Dynamic Type, clipped text, traits and more
   ([performAccessibilityAudit](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)),
   [audit types](https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityaudittype)).
   Audits run at the default text size and at an accessibility size: `LargeTextUITests` starts the
   app at AX3 and audits every screen and sheet. Each audit records how long it took as a named
   activity in the log, so a timeout in CI shows how close it came. An issue may be ignored only
   through the audit's issue handler, for a documented reason (for example, contrast inside a PDF
   page, which is the author's content, not our interface), with an issue link.
2. **Contrast tests of design tokens.** A unit test computes the contrast ratio of every foreground
   and background token pair in light, dark and Increase Contrast variants, and fails below the HIG
   minimums of 4.5:1 for text up to 17 points and 3:1 for larger or bold text
   ([HIG: accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
   based on [WCAG 2.2](https://www.w3.org/TR/WCAG22/) level AA).
3. **A scripted manual VoiceOver pass** before every release, on a device: onboarding; open a
   document and move by headings and pages with the rotor; read aloud; annotate; scan; sign; ask a
   question and follow a citation; the paywall and restore; the privacy centre. Spot checks with
   Voice Control, Switch Control, the largest text size and a hardware keyboard on iPad. The
   [VoiceOver script](process/voiceover-script.md) holds the steps and the sign-off; the release
   checklist ([release management](release-management.md)) requires it.

## Performance tests

Every budget in [performance budgets](performance-budgets.md) has a performance test measured with
XCTest metrics, and the budget table is the only source of the thresholds (NFR-PERF-001).

| Metric | Measures | Budget rows |
|---|---|---|
| `XCTApplicationLaunchMetric` | Cold and warm launch | Launch |
| `XCTOSSignpostMetric` | Named signpost intervals, for example `Document.FirstPage`, `Search.Query`, `Scan.Searchable`, `AI.FirstToken` | Documents, OCR speed, AI latency |
| `XCTHitchMetric` | Hitches while scrolling a 500-page PDF | Scrolling |
| `XCTMemoryMetric` | Peak physical memory | Memory |
| `XCTCPUMetric` | CPU time and instructions for OCR and indexing | Battery and energy |
| `XCTStorageMetric` | Bytes written by save and export | Documents (save) |

Today the `Performance` test plan covers the rows listed under "How the budgets are measured today"
in [performance budgets](performance-budgets.md). Its classes end in `PerformanceTests`, so the plan
writer skips them in the pull-request plan and selects only them in `Performance.xctestplan`. The
nightly `performance` job reports the medians against the budgets without blocking.

The metrics are listed in [XCTMetric](https://developer.apple.com/documentation/xctest/xctmetric);
`XCTHitchMetric` needs iOS 26 or later ([XCTHitchMetric](https://developer.apple.com/documentation/xctest/xcthitchmetric)),
which the iOS 26 floor satisfies ([ADR-0023](adr/0023-ios-26-floor-built-with-xcode-27.md)).

- **Configuration.** Apple recommends running performance tests from a Release build with code
  coverage and sanitisers off ([Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)),
  so they have their own test plan, `Performance`, separate from the coverage run.
- **Thresholds.** XCTest baselines are stored per device in the Xcode project's shared data, which
  this repository does not commit because the project is generated
  ([ADR-0002](adr/0002-xcodegen-and-modular-spm.md)). The budgets are therefore checked by comparing
  the result bundle's measurements with the budget table (a proposed script; see the open questions).
- **Simulator versus device.** CI runs on a simulator and tracks trends; simulator numbers do not
  equal device numbers, so the release gate is a run on the reference devices before each App Store
  submission, as the budget table states.
- **Documents** come from the synthetic golden corpus: the 20-page, 500-page, 1,000-page mixed,
  100-page scanned and 50-page form documents named in the budgets.

## OCR accuracy testing

Recognition runs on the device with Vision's `RecognizeDocumentsRequest` (FR-SCAN-002,
[ADR-0008](adr/0008-ocr-and-scanning.md)). Accuracy is measured against a labelled corpus in
English and French.

### Corpus

- **Ground truth is known by construction.** Pages are generated from known text, rendered, then
  degraded in controlled ways; a smaller set is printed and photographed on the reference devices.
  All content is synthetic; photographs are stripped of location and device metadata.
- **Subsets**, each in English and French: printed, clean; printed, degraded (skew, blur, low light,
  shadows, compression); layouts (two columns, tables, forms, small print); handwriting (reported,
  not gated).
- **French coverage** includes accented capitals, `œ` and `æ`, guillemets and the narrow no-break
  spaces of French punctuation.
- **Size.** `Assumption:` at least 200 printed pages per language and 100 degraded pages; validated
  by checking that the measured rate is stable when the corpus is split in half.

### Metrics

- **Character error rate (CER)** = (S + D + I) / N, where S, D and I are the character
  substitutions, deletions and insertions in the minimum edit (Levenshtein) alignment between the
  recognised text and the ground truth, and N is the number of characters in the ground truth.
- **Word error rate (WER)** is the same calculation over words
  ([word error rate](https://en.wikipedia.org/wiki/Word_error_rate)).
- **Normalisation before scoring:** Unicode NFKC (so ligatures compare equal); all whitespace,
  including no-break spaces, collapsed to one space; line breaks treated as spaces. Typographic
  apostrophes and quotation marks compare equal to their ASCII forms: Vision returns `'` for `’`.
  The space before `;`, `:`, `!`, `?` and `»`, and after `«`, is ignored: French typography puts a
  narrow no-break space there, which recognition reports inconsistently, while the marks themselves
  still count. Case and accents are significant: `é` read as `e` is an error, and so is `æ` read as
  `a`.
- **Searchability:** every ground-truth word is found by in-document search on the right page after
  the text layer is written.

### Thresholds

| Subset | Gate | Source |
|---|---|---|
| Printed, clean, English and French | CER at most 2% | Public quality objective in [success metrics](success-metrics.md) (an initial `Assumption:` reviewed against the MVP baseline) |
| Printed, clean, English and French | WER at most 5% | `Assumption:` validated against the MVP baseline |
| Printed, degraded | CER at most 5% | `Assumption:` validated against the MVP baseline |
| Handwriting | Reported only | Not a V1 promise |
| Speed | As in [performance budgets](performance-budgets.md) | OCR speed rows |

**Regression delta rule.** A change may not worsen the CER of any subset by more than 0.2 percentage
points against the baseline recorded at the last release, even while it stays under the threshold
(`Assumption:` tolerance; validated by measuring run-to-run variation on the pinned runtime). A
change in accuracy caused by a new operating-system version is recorded in
[working memory](working-memory.md) and the baseline is re-recorded in its own pull request.

### What runs today

`OCRAccuracyTests` generates the corpus at run time (`OCRCorpus`) and runs it through
`VisionTextRecognizer`.

- **Pages:** eight sentences each, in Helvetica or Times. The French pages carry accented capitals,
  `œ`, `æ`, guillemets and narrow no-break spaces. Degraded pages are skewed by up to 1.5 degrees,
  blurred, low in contrast and speckled.
- **Every pull request** runs 3 clean and 2 degraded pages per language, and gates them.
- **`FULL_SUITE=1`** runs 200 clean and 100 degraded pages per language.
- **Report:** `reports/ocr-accuracy.md` when `REPORTS_DIR` is set, as the `ios` job does.
- **Not yet covered:** photographed pages and layouts (columns, tables, small print).

Baseline on the full corpus. Source: `FULL_SUITE=1 swift test --package-path Packages/OCR --filter accuracy`, run on macOS 26 on the owner's Mac on 30 September 2026. The simulator and device figures come from the release runs.

| Language | Condition | Pages | CER | WER |
|---|---|---|---|---|
| English | Clean | 200 | 0.00% | 0.01% |
| English | Degraded | 100 | 0.13% | 0.78% |
| French | Clean | 200 | 0.28% | 1.56% |
| French | Degraded | 100 | 0.51% | 2.63% |

### Decision: CER and WER on a synthetic corpus, gated per subset

- **Rationale.** CER and WER are the standard edit-distance measures for recognition, comparable
  across releases and languages; generating ground truth removes labelling errors and every privacy
  question about the pages.
- **Trade-offs.** Synthetic pages are cleaner than real-world scans; the photographed and degraded
  subsets narrow that gap but do not close it.
- **Alternatives considered.** Public OCR benchmark datasets (licences vary and many contain real
  people's documents); manual spot checks (not repeatable); confidence scores from Vision alone
  (they measure certainty, not correctness).
- **Risks.** Simulator and device results may differ: the release gate runs on a reference device,
  and CI tracks deltas. Apple's model changes with the OS: the suite runs on each new beta.
- **Future scalability impact.** New languages are added as new subsets with their own thresholds,
  without changing the method.

## AI evaluation

The AI evaluation suite is defined in the [AI evaluation framework](ai-evaluation-framework.md),
which owns its sets, metrics and thresholds (NFR-AI-001, [ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md)).
In summary:

- It runs on every prompt, model, schema or routing change, and in full before every release.
- Release thresholds include at least 95% correct citations on the evaluation set, the public target
  in [success metrics](success-metrics.md), plus grounding, hallucination, prompt-injection,
  latency and cost limits.
- The on-device model needs an Apple Intelligence-capable device, and its context is 4,096 tokens
  per session, so chunking and retrieval have their own tests. Where CI runners cannot run the
  model, the author runs the `AIEvaluation-OnDevice` test plan on a device and commits the result
  summary for CI to check (same source).
- Cloud tiers are evaluated on a dedicated evaluation device and Mac, never with provider
  credentials in this public repository's CI.
- Results are attached to the pull request, and reviewers read samples as well as scores
  ([code review guide](code-review-guide.md#reviewing-ai-and-prompt-changes)).

## Regression testing: the golden PDF corpus

The golden corpus is a set of synthetic PDFs that exercise the ways real documents differ and fail
(FR-READ-001). Every document-handling change runs against it.

### Corpus contents

| Category | Examples |
|---|---|
| Text | 20, 500 and 1,000 pages; mixed page sizes and rotations; outlines; links; right-to-left and CJK text; vertical text |
| Forms | AcroForm fields of every type; calculated fields; a flattened form; an XFA form (must fail gracefully) |
| Encrypted | User password; owner password with restricted permissions; RC4 and AES variants |
| Scanned | Image-only pages; scans with an existing text layer; mixed scanned and digital pages |
| Annotations and signatures | Every standard annotation type from other apps; ink signatures; a digitally signed file |
| Structure | Tagged PDFs; PDF/A; linearised files; files with incremental-update history; embedded files |
| Active content | Documents containing JavaScript, launch actions and remote references (must stay inert) |
| Huge | 1,000-page mixed documents; very large page images (`Assumption:` sizes set with the vendor spike) |
| Malformed | Truncated files, broken cross-reference tables, wrong stream lengths, circular references, deep nesting, invalid fonts |

Each category has expected outcomes: opens and renders, fails with a specific `PDFEngineError`, or
stays inert. None may crash or hang.

### What runs today

`GoldenCorpus` in the `PDFEngineTestSupport` target generates the corpus at run time, and
`PDFEngineTests.GoldenCorpusTests` checks it on every pull request, on macOS and the simulator.

- **Readable cases** are opened, rendered (first and last page), searched, annotated, saved and
  reopened. The checks are the page count, the text, the annotation, and encryption kept.
  - Text: 20, 500 and 1,000 pages; mixed page sizes with 90, 180 and 270 degree rotations; an
    outline; right-to-left and CJK text.
  - A form.
  - Every standard annotation type written by PDFKit.
  - A user password, and owner restrictions without an open password.
  - Image-only pages, and mixed scanned and digital pages.
  - Active content: a JavaScript open action and a launch link, which must stay inert.
- **Malformed cases** must fail cleanly or open, each within a one-minute limit, so a hang fails the
  test:
  - an empty file and a header only;
  - truncated files;
  - garbage after the header;
  - a broken cross-reference table;
  - a wrong stream length;
  - a circular page tree;
  - deep nesting;
  - a metadata key that isn't UTF-8. Fuzzing found this: PDFKit ended the app when saving such a file.
  - 40 fuzzed copies of a hand-written document, from a fixed seed, so every run on every platform
    tests the same bytes. A document drawn by Core Graphics embeds the time and the system version,
    so fuzzing one changed different bytes on each run.
- **Not yet covered.** These need files from other producers, and are added when licence-clean
  samples or generators exist:
  - XFA and calculated forms, a flattened form;
  - RC4 and AES variants;
  - digitally signed files;
  - tagged PDFs, PDF/A, linearised files, incremental updates, embedded files;
  - vertical text, very large page images, invalid fonts.

### Save round-trip integrity

For each editable document: open, change (annotate, fill, reorder, edit text), save, reopen, and
check that page count, text, annotations, form values and outline are as expected; a save with no
changes leaves the content unchanged; and a save interrupted part-way (simulated by failing the
write) leaves the previous version intact (NFR-REL-002). Digitally signed files are checked to
confirm the signature is still valid after an annotation-only save, or that the user was warned.

Saved files are also checked by a reader other than PDFKit (plan revision 3, §3 B2). In CI the
`pdf-export` job saves every golden-corpus document through the engine and uploads the files, and
`pdf-validation` runs `qpdf --check` on each with qpdf 12.4.2 (Apache-2.0), downloaded by pinned
version and SHA-256 (`scripts/ci/validate_pdfs.sh`). Warnings are reported; errors fail the job. Both
jobs are advisory for their first two weeks, then become required. The same job then renders every
page of every file with PDFium (pypdfium2 5.13.0, BSD-3-Clause and Apache-2.0, pinned by the wheel's
hash; `scripts/ci/pdfium_render.py`). A Core Graphics parse of each saved file runs in the corpus
tests themselves. The export job also runs the controller, toolkit and save fault-injection suites under
Thread Sanitizer (plan H4), because `PDFDocument` isn't thread-safe and saving is due to move off the
main actor.

### True-redaction verification

Redaction must remove content, not cover it (FR-EDIT-005). For every redaction test document,
after redacting known strings and saving:

- text extraction by `PDFEngine` **and** by PDFKit, as an independent second reader, finds none of
  the removed strings;
- a scan of the raw file bytes finds none of them in plain text or in the common PDF string
  encodings;
- image content under the redacted area is removed or overwritten, and document metadata, form
  values, annotations and the text layer no longer contain the strings;
- the file is fully rewritten, with no earlier revision left in an incremental-update section;
- the redaction marks themselves are gone, leaving only the visual fill.

A redaction feature that fails any of these does not ship.

### Malformed and fuzzed input

Documents are untrusted (NFR-SEC-002). A seeded mutator produces variants of corpus files (bit
flips, truncation, duplicated and deleted objects, oversized values). Every variant must open with a
typed error or render, within a time limit (Swift Testing's `.timeLimit` trait), without a crash.
Pull requests run a small fixed seed set; the nightly run uses many more seeds, and a nightly
configuration adds Address Sanitizer, because the vendor SDK is likely to contain C or C++ code
([Diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)).
Every crash found becomes a permanent corpus file.

## PDFEngine contract tests

`PDFEngine` is our boundary around a commercial SDK that has not been chosen yet
([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)). One contract suite, parameterised
over every implementation of the `PDFEngine` protocols (the vendor adapter, the PDFKit contingency
for the read-only protocols, and the fake used in feature tests), proves each implementation
behaves the same:

- open, page count, render a tile, extract and search text, open with a password;
- annotations and form values round-trip; page operations (merge, split, reorder, rotate) preserve
  content; redaction passes the verification above;
- malformed input produces the documented error, never an SDK error or a crash;
- cancellation is honoured, and results are `Sendable` value types with no SDK type in the API.

The same suite scores the vendor candidates in the spike and protects a later vendor switch. The
fake passes it too, so feature tests rely on a fake that behaves like the real engine.

## Coverage

- **Floor:** at least 80% line coverage overall and for every first-party target (NFR-QUAL-001,
  [ADR-0014](adr/0014-testing-strategy-and-coverage.md)).
- **How it is measured:** each test shard runs with coverage on; `ios-report` merges the shards'
  result bundles, exports the merged result with `xcrun xccov view --report --json`, checks that the
  merge kept every shard's coverage ([coverage_compare.py](../scripts/ci/coverage_compare.py)), and
  runs [coverage_gate.py](../scripts/ci/coverage_gate.py) with `--min 80`
  ([ci.yml](../.github/workflows/ci.yml)).
- **Exclusions**, as the script applies them: test bundles (targets ending in `.xctest` or
  `Tests`); files ending in `Previews.swift`; paths containing `/Generated/`, `/Tests/`, `/.build/`
  or `/DerivedData/`. Previews therefore go in `<View>+Previews.swift`
  ([Swift style guide](swift-style-guide.md#files-and-type-layout)).
- **Device-only files** (`DEVICE_ONLY` in the script) are excluded too, because they need hardware the
  simulator does not have: the document camera adapter, since `VNDocumentCameraViewController` raises
  "Document camera is not available" on the simulator, and the MetricKit adapter, which the simulator
  never calls (the log it writes to is tested). Each entry states its reason, every CI run
  prints the list, and each has an on-device check in the
  [release checklist](release-management.md). Keep such a file to the adapter alone; logic that can run
  on the simulator goes in another file, where it counts.
- **Never create hardware-only system controllers in tests** (the document camera, a capture
  session): on the simulator they raise an Objective-C exception, which ends the whole test process and
  fails every test in the bundle.
- **Coverage is a floor, not a goal.** Reviewers judge whether the covered lines are meaningfully
  asserted; a test that executes code without checking its result does not count in review.
- Excluding more code needs a pull request to the script, explained in its description; lowering
  the threshold needs a new ADR.

## Flaky tests

A flaky test passes and fails on the same code. It is treated as a bug in the test or the product,
never retried away: a retry lets a run finish, it never clears the test.

1. **Quarantine the same day it is seen.** Open an issue labelled `bug` and `flaky`
   ([labels.yml](../.github/labels.yml)), then keep the test running without failing the build: in
   Swift Testing, wrap the unstable part in `withKnownIssue(isIntermittent: true)` and add a `.bug` trait
   linking the issue ([known issues](https://developer.apple.com/documentation/testing/known-issues));
   in XCTest, use a non-strict expected failure. Disabling the test outright is the last resort.
2. **Fix or delete within five business days** (`Assumption:` validated by tracking quarantined
   tests at each milestone review). A test still quarantined after that is deleted, and the gap it
   leaves is recorded as debt ([technical debt](engineering-playbook.md#technical-debt)).
3. **One retry, for UI tests only, and every flake named** (PAP-062). In CI the UI shards run a
   failed test once more on a relaunched app, and its last repetition is its verdict; unit tests never
   retry. A test that passed only on retry is reported on the run as flaky with its first failure's
   message, more than three distinct flaky tests fail the run (`Assumption:` budget, see
   [quality gates](process/quality-gates.md#the-ios-job-graph)), and each one seen is quarantined as in
   step 1. Otherwise, Xcode's repetition modes are for reproducing a flake locally, not for hiding it.
4. The usual causes are timing, shared state, order dependence and real clocks; the fix removes the
   cause.

## Test data governance

- **Synthetic or licence-clean only.** No real person's document, scan, photograph or data ever
  enters the repository, CI, a screenshot or a bug report ([AGENTS.md](../AGENTS.md)).
- **Generated, not collected.** Fixtures are generated by code (Core Graphics and PDFKit, or the
  SDK where they cannot) with fixed seeds, at test time where that is fast and once per CI run
  where it is not. Encryption passwords for fixtures are generated test values that never resemble
  real credentials.
- **Committed only when necessary.** A PDF that cannot be generated (for example a crash
  reproducer) is committed under a `Tests/Fixtures/Synthetic/` folder, at the repository root or
  inside a package, with its provenance: how it was made, or its source and licence. The
  `invariants` gate fails on any PDF committed anywhere else, and `.gitignore` ignores PDFs outside
  those folders
  ([invariants.py](../scripts/ci/invariants.py), [.gitignore](../.gitignore)).
- **Licence-clean** means a licence that permits redistribution in this public repository,
  recorded next to the file; when in doubt, generate instead.
- **No production data in tests**, no copies of support attachments, and no document content in
  test logs or result bundles kept by CI.

## Test shards in CI

The `ios` gate runs the `PDFAlgoPro` plan from one build in three shards, each on its own runner and
simulator ([quality gates](process/quality-gates.md#the-ios-job-graph)). The selectors come from
[test_shards.py](../scripts/ci/test_shards.py) and [test_shards.json](../scripts/ci/test_shards.json):

| Shard | Runs | Retries |
|---|---|---|
| `unit` | Every test target except `PDFAlgoProUITests`: the packages' tests, the app's unit and snapshot tests | None |
| `ui-1` | The UI test classes listed under `ui-1` in `test_shards.json` | Once, on a relaunched app |
| `ui-2` | Every other UI test class | Once, on a relaunched app |

- **A new UI test class** lands in `ui-2` without any change, because `ui-2` is everything in
  `PDFAlgoProUITests` that `ui-1` does not list. `ios-report` checks that the shards together ran every
  test of the plan, each once.
- **Rebalancing:** when one UI shard is regularly much slower than the other (the run summary lists
  each shard's time in tests), move classes into or out of the `ui-1` list in `test_shards.json`. The
  script's tests check that every listed class exists in `App/UITests` and that none is listed twice.
- **On a Mac:** `scripts/dev/ci_tests.sh --shard unit|ui-1|ui-2` makes the same build and runs the same
  shard on the pinned simulator; `--only PDFAlgoProUITests/ReaderUITests` runs a focused set.
- **One test in CI:** a manual run of `ci.yml` with `only_testing` (for example
  `PDFAlgoProUITests/ReaderUITests/testGoToPageJumpsToTheNumberTyped`) runs only those tests, reported as `ios-focused`.

## Where each suite runs

The stages map to the gates in [quality gates](process/quality-gates.md). "PR" is a pull request
into `integration`; "Release PR" is `integration` into `main`; "Nightly" is a scheduled Xcode Cloud
workflow on `integration`, since Xcode Cloud can start workflows on a schedule
([Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference))
and the set of GitHub workflows is fixed at four ([ADR-0013](adr/0013-ci-cd.md)); "Pre-submission"
is the release checklist on reference devices.

| Suite | Test plan | PR | Release PR | Nightly | Pre-submission |
|---|---|---|---|---|---|
| Unit and integration | `PDFAlgoPro` | Yes | Yes | Yes | — |
| Coverage gate (80%, ADR-0014) | `PDFAlgoPro` | Yes | Yes | — | — |
| Snapshot | `PDFAlgoPro` | Yes | Yes | Full matrix | — |
| UI, critical journeys | `PDFAlgoPro` (smoke), `Release` (all) | Smoke | All | All, English and French | — |
| Accessibility audit | `PDFAlgoPro` | Yes | Yes | Yes | — |
| Contrast token tests | `PDFAlgoPro` | Yes | Yes | Yes | — |
| Golden corpus and contract | `PDFAlgoPro` (fast subset), `Release` (full) | Subset | Full | Full | — |
| Fuzzed input | `PDFAlgoPro` (fixed seeds), `Nightly` (many seeds, Address Sanitizer) | Fixed seeds | Fixed seeds | Extended | — |
| OCR accuracy | `Release` | Subset when `OCR` or `Scanning` change | Full | Full | On a reference device |
| Performance | `Performance` | — | Yes (simulator, trend) | Yes (trend) | On reference devices (gate) |
| AI evaluation | `AIEvaluation-OnDevice` | When `Intelligence` changes | Full on-device suite | Cloud tiers on the evaluation device | Full |
| Pseudolanguage and right-to-left runs | `Nightly` | — | — | Yes | — |
| Manual VoiceOver script, exploratory testing | Release checklist | — | — | — | Yes |

Today the `ios` gate in [ci.yml](../.github/workflows/ci.yml) runs one test plan, `PDFAlgoPro`
("unit, UI, accessibility audit, snapshots"), in three shards, for every pull request. Running the `Release` and
`Performance` plans on release pull requests, and the nightly Xcode Cloud workflow, are the target
design listed in the open questions. The `codeql (swift)` job runs nightly, on demand and on release pushes to `main`; when it becomes
a required check is decided in [GitHub governance](github-governance.md#protected-branches-rulesets-as-code).

## Open questions

- **Release PR test plans.** `ci.yml` uses a fixed `TEST_PLAN`; choosing `Release` and
  `Performance` for pull requests into `main` needs a `ci:` change, or an Xcode Cloud workflow on
  pull requests into `main` whose result becomes a required check.
- **Nightly workflow.** Set up the scheduled Xcode Cloud workflow on `integration` (part of the
  "Xcode Cloud workflows" readiness item in [readiness review](readiness-review.md)).
- **Performance gate script.** A proposed `scripts/ci/perf_gate.py` that reads XCTest measurements
  from the result bundle and compares them with the budget table, because XCTest baselines live in
  the generated, uncommitted project.
- **String Catalog completeness.** A release check that fails when French translations are missing
  or stale.
