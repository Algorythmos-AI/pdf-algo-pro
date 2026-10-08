# Performance budgets

The speed, memory, battery, OCR and AI latency targets PDF Algo Pro must meet, how each is measured,
and where the gate runs. A budget is a requirement: a change that breaks one does not ship until it
is fixed or the budget is deliberately changed here with a reason.

Owner: Architecture · Reviewed: each milestone, and after each MetricKit review

## How to read this

- **Targets are ours, not measurements.** Each is an engineering decision. Where Apple publishes
  guidance, it is cited; every other number is an `Assumption:` to validate on the reference
  devices during the MVP, after which the table is updated with measured baselines.
- **p50 and p95** are across repeated runs on a reference device (tests) or across users
  (MetricKit and App Store Connect in the field).
- **Reference devices** (chosen when the MVP starts, recorded here):
  - *Baseline iPhone*: the oldest iPhone that iOS 27 supports.
  - *AI iPhone*: the oldest iPhone that supports Apple Intelligence
    ([Apple Intelligence](https://www.apple.com/apple-intelligence/)).
  - *Current iPhone Pro*: the newest Pro model.
  - *Reference iPad*: added for V2, when the iPad-first experience ships.
- **Test documents** come from the synthetic golden corpus: a 20-page text PDF, a 500-page text PDF,
  a 1,000-page mixed PDF, a 100-page scanned PDF, a 50-page form.

## How the budgets are measured today

The `Performance` test plan (P9 on the TestFlight tracking issue,
[#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)) measures the rows below with XCTest
metrics: three iterations each, compared by their median. The `performance` job in `ci.yml` runs it
nightly and on request, on the pinned simulator with an optimised build, and
[`perf_gate.py`](../scripts/ci/perf_gate.py) writes the comparison to the run summary and an
artifact. Pull requests run none of it, and nothing is blocked by it.

| Budget row | Test | What is timed |
|---|---|---|
| Cold launch to first frame | `LaunchPerformanceTests.testColdLaunchToTheFirstFrame` | `XCTApplicationLaunchMetric`, empty library |
| Open a 20-page PDF | `EnginePerformanceTests.testOpenA20PagePDFToTheFirstPage` | Opening the document and rendering page 1 at iPhone screen size |
| Open a 500-page PDF | `EnginePerformanceTests.testOpenA500PagePDFToTheFirstPage` | The same, for 500 pages |
| Page thumbnail grid (100 pages) | `EnginePerformanceTests.testRenderThe100PageThumbnailGrid` | All 100 thumbnails at the grid's size, more than a screen shows |
| Save after an edit (500-page PDF) | `EnginePerformanceTests.testSaveAfterAnEditIn500Pages` | The save only |
| Edit a line of text (500-page PDF) | `EnginePerformanceTests.testEditALineOfTextIn500Pages` | Finding the page's text, making the edit and proving it, to the new page on screen; not the save |
| Search across a 1,000-document library | `EnginePerformanceTests.testSearchA1000DocumentLibrary` | One query on a warm index |
| Scan → searchable PDF, 10 pages | `EnginePerformanceTests.testScanTenPagesToASearchablePDF` | Vision recognition and writing the PDF |
| Retrieval over a 500-page PDF | `RetrievalPerformanceTests.testRetrievalOver500Pages` | Ranking every page for a question |
| Retrieval over a 500-page PDF, words in their base forms | `RetrievalPerformanceTests.testRetrievalOver500PagesWithBaseForms` | The same, as internal builds match words (PAP-054); held to the same budget |

- **Tolerance.** `Assumption:` a simulator median within 120% of the p50 budget means no
  regression worth stopping for. The simulator is not the baseline iPhone, so its numbers show
  trends and large regressions. In the first run (2026-09-30, a development Mac):
  - document work was far inside its budgets;
  - cold launch took 2.1 s and ten scanned pages 12.8 s, both over.

  Validation: compare the first nightly runs with a device run of the same plan, and adjust the
  tolerance per row here if the two disagree by more than it allows.
- **Device timings.** Run the same plan on the baseline iPhone from Xcode: choose the `Performance`
  test plan, run the tests, then pass the result bundle to
  `xcrun xcresulttool get test-results metrics` and `perf_gate.py`. These are the timings the
  budgets refer to, recorded for each TestFlight build that reaches testers.
- **Signposts.** The same operations are marked with `OSSignposter` intervals in the Points of
  Interest category, named as in the tables (`Document.FirstPage`, `Document.Save`, `Search.Query`,
  `Scan.Searchable`, `AI.Retrieve`, `AI.Summary`, `Library.Ready`), for Instruments on a device.
- **Not yet measured:**
  - warm launch;
  - the 1,000-document library launch;
  - scrolling;
  - merging (no merge feature yet);
  - memory;
  - energy;
  - recognition speed;
  - model latency (`AI.FirstToken`, `AI.Summary`), which needs a device with Apple Intelligence.

  Each is added to the plan when its feature or fixture exists.

## Launch

| Budget | p50 | p95 | Measured by | Gate |
|---|---|---|---|---|
| Cold launch to first frame (baseline iPhone) | 400 ms | 600 ms | `XCTApplicationLaunchMetric`; MetricKit launch histograms | Release PR |
| Warm launch to first frame | 200 ms | 350 ms | `XCTApplicationLaunchMetric` | Release PR |
| Launch to interactive library (1,000 documents) | 700 ms | 1.2 s | signpost `Library.Ready` | Release PR |

Source for the cold-launch p50 target: Apple recommends the first frame within 400 ms of launch
([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)).
The p95 values and the other rows are `Assumption:` targets.

## Documents

| Budget | p50 | p95 | Measured by | Gate |
|---|---|---|---|---|
| Open a 20-page PDF to first page visible | 150 ms | 300 ms | signpost `Document.FirstPage` | Release PR |
| Open a 500-page PDF to first page visible | 300 ms | 600 ms | signpost `Document.FirstPage` | Release PR |
| Scrolling a 500-page PDF | no dropped frames at the display refresh rate in 95% of one-second windows | — | `XCTOSSignpostMetric` scroll deceleration; hitch rate | Release PR |
| Page thumbnail grid (100 pages) populated | 500 ms | 1 s | signpost `Thumbnails.Ready` | Release PR |
| Save after an edit (500-page PDF) | 300 ms | 800 ms | signpost `Document.Save` | Release PR |
| Edit a line of text (500-page PDF) | 500 ms | 1 s | `XCTClockMetric` around `applyTextEdits`; not the save | Release PR |
| Save after an edit (1,000-page mixed PDF), on the baseline device | 800 ms | 2 s | signpost `Document.Save` | Release PR |
| Merge two 100-page PDFs | 1 s | 2 s | signpost `Organize.Merge` | Release PR |
| Search across a 1,000-document library (index warm) | 100 ms | 250 ms | signpost `Search.Query` | Release PR |

All `Assumption:` targets.

## Memory

| Budget | Ceiling | Measured by | Gate |
|---|---|---|---|
| Library with 1,000 documents, idle | 120 MB | `XCTMemoryMetric` | Release PR |
| Reading a 500-page PDF | 250 MB | `XCTMemoryMetric` | Release PR |
| Reading a 1,000-page mixed PDF | 350 MB | `XCTMemoryMetric` | Release PR |
| Share extension (memory-limited by the system) | well under the extension limit; target 60 MB | Instruments allocations | Before each release |
| No leaks after open → read → close × 20 | 0 leaked documents | memory graph test | Release PR |

All `Assumption:` targets; the extension limit is set by the system and is not published as a
fixed number, so the target is deliberately conservative.

## Battery and energy

| Budget | Target | Measured by | Gate |
|---|---|---|---|
| Reading (screen on, scrolling occasionally) | energy impact "Low" in Xcode's energy gauge; no background CPU while idle | Xcode energy organiser; MetricKit `MXCPUMetric` | Before each release |
| OCR of 100 scanned pages | completes within one battery-percent budget of 3% on the baseline iPhone | device test, battery level before and after | Before each release |
| Background indexing | runs only as a `BGProcessingTask` requiring external power | code review + invariants | Every PR |
| AI on device, one summary of a 20-page PDF | no thermal state above `.fair` on the AI iPhone | `ProcessInfo.thermalState` log in the device test | Before each release |

All `Assumption:` targets.

## OCR speed

| Budget | p50 | p95 | Measured by | Gate |
|---|---|---|---|---|
| Recognition speed, printed text, baseline iPhone | 2 pages per second | 1 page per second | OCR suite timing | Release PR |
| Scan → searchable PDF, 10 pages | 8 s | 15 s | signpost `Scan.Searchable` | Release PR |

Accuracy targets (character and word error rates per language) are in the testing strategy
([testing strategy](testing-strategy.md)). All `Assumption:` targets.

## AI latency

| Budget | p50 | p95 | Measured by | Gate |
|---|---|---|---|---|
| On-device, first token of an answer | 800 ms | 1.5 s | signpost `AI.FirstToken` by tier | Release PR (AI evaluation suite) |
| On-device, summary of a 20-page PDF | 6 s | 12 s | signpost `AI.Summary` | Release PR |
| Private Cloud Compute, first token | 1.5 s | 3 s | signpost `AI.FirstToken` | Release PR (network-dependent; reported, not blocking) |
| Claude tier, first token | 1.5 s | 3.5 s | signpost `AI.FirstToken` | Release PR (reported, not blocking) |
| Retrieval over a 500-page PDF (chunks for an answer) | 150 ms | 400 ms | signpost `AI.Retrieve` | Release PR |

Cloud tiers depend on the network, so their budgets are tracked and alarmed on but do not block a
release. All `Assumption:` targets; see [AI evaluation framework](ai-evaluation-framework.md) and
[model selection](model-selection.md).

## App size

| Budget | Target | Measured by |
|---|---|---|
| Download size (App Store, typical device) | under 120 MB including the PDF SDK | App Store Connect size report |

`Assumption:` target; the PDF SDK's contribution is a scored criterion in the vendor spike
([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)).

## Field monitoring

MetricKit reports (launch, hangs, memory, energy, disk writes) are reviewed at each milestone and
after each release; App Store Connect metrics supply crash and launch trends. A regression in the
field against these budgets opens a `performance` issue with `priority:p1` or higher
([operations](operations.md)).
