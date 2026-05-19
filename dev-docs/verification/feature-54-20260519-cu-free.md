---
kind: feature
id: 54
status_target: DONE
commit_sha: 306f7ce03f5bd262b5fc3718a31b3cd8240bdec9
app_version: 3.34.3 (build 490)
date: 2026-05-19
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #54 — Remove Native/Unified reading mode toggle (CU-free XCUITest verification)

Gate-5 verification for feature #54 via a **CU-free XCUITest suite**.
All 7 WIs are merged; the feature row is `DONE`. The prior evidence file
`feature-54-20260519.md` recorded `result: partial` because the
headless `simctl openurl` DebugBridge path could not commit the
`NavigationStack` reader-open push without a driven display
(computer-use is virtual-display-only on this host).

This run replaces the DebugBridge headless-nav path with
`vreaderUITests/Verification/Feature54ReadingModeRemovalVerificationTests.swift`
— an XCUITest suite that drives the app entirely through the
accessibility API (element queries + synthesized `.tap()` / `.swipeUp()`
gestures). XCUITest does NOT need computer-use and does NOT depend on
the DebugBridge URL-confirm dialog, so it completes what the CU /
DebugBridge path could not: criteria 1, 2 (structural half), and 5 are
now verified **end-to-end through the real UI**, not merely at the
unit/integration boundary.

> **Status note:** the feature row stays at `DONE` — it does NOT flip to
> `VERIFIED`. Criterion 3 (replacement rules in native EPUB without a
> mode switch) is part of the row's acceptance contract but was
> explicitly DEFERRED to Phase D by the Gate-1/Gate-2 plan, and Phase D
> has not shipped — so one acceptance criterion is genuinely
> unverifiable (it is not implemented). Per `SCHEMA.md` result
> semantics, a `partial` result "may NOT move the tracker status to
> `VERIFIED`"; the row stays `DONE` with a documented partial. This is
> not a CU-free-suite shortfall — the XCUITest suite verifies every
> criterion that #54 actually shipped (1, 2-MD, 5 here end-to-end via
> XCUITest; 4 device-side + unit in `feature-54-20260519.md`). The
> remaining gap is the deferred Phase D EPUB-replacement work, tracked
> in the feature row's plan §4. When Phase D ships criterion 3, a
> follow-up acceptance pass can flip #54 to `VERIFIED`.

## Acceptance criteria

| # | Criterion (from the feature row) | Observed | Result |
|---|---|---|---|
| 1 | No reading-mode picker in normal use | XCUITest opens a real book of each openable format (TXT/EPUB/MD), opens the reader Display panel, and scrolls it top-to-bottom (11 scroll positions, full 12-section panel). At **every** scroll position the suite asserts NO "Reading Mode" / "Tap Zones" / "Tap Zone" section header `staticText` and NO "Native" / "Unified" segment `button` exists. All 4 tests pass — the picker is provably absent from the live Display panel UI on all three formats. | **PASS** (end-to-end UI) |
| 2 | Replacement rules work in native EPUB **and** MD without a mode switch — **MD half** | The MD book opens into the native `markdownNative` engine (UITextView via `TXTTextViewBridge`) and renders, with NO Reading Mode picker in the Display panel — the structural "no mode switch" contract. Transform-application correctness (replacement + simp/trad over the source text) is covered by the 20 real-boundary integration tests cited below. The reader-mount UI step that the prior evidence could not observe headlessly is now observed: `test_verify_feature_54_md_native_engine_no_reading_mode_picker` passes. | **PASS** (structural via XCUITest; transform correctness via integration tests) |
| 3 | Replacement rules work in native EPUB without a mode switch — **EPUB half** | DEFERRED to Phase D (D-1) by the Gate-1/Gate-2 plan — native EPUB has no Swift string seam; it needs CFI-safe JS text-node preprocessing built against feature #42's engine decision. Out of #54's autonomous scope. Not implemented → no test can exercise it. | DEFERRED (by plan) |
| 4 | `readerReadingMode` key removed with migration | Verified device-side + by unit tests in the prior evidence file (`feature-54-20260519.md`): after launch `readerReadingMode` is absent from `com.vreader.app.plist`; per-book JSON carries no `readingMode` field; 14 `ReadingModeMigration` tests pass. This is a UserDefaults / launch-migration concern with no UI surface, so it is outside the XCUITest scope — no re-verification needed here. | **PASS** (device + unit — prior evidence) |
| 5 | All existing reader features unchanged | XCUITest opens TXT, EPUB, and MD books and asserts each opens into ITS native engine's rendering surface — TXT/MD into a `UITextView`/`UITableView` (`textNative` / `markdownNative`), EPUB into a `WKWebView` (`epubWKWebView`) — and the reader chrome (`readerBackButton`) is present. This proves `ReaderEngine.resolve` dispatch routes every openable format to its own native host after the `readingMode`-branch deletion. All 3 per-format tests pass. PDF (`pdfKit`) and AZW3/MOBI (`foliateWeb`) have no openable debug seed; their routing is covered by `ReaderEngineTests`. | **PASS** (end-to-end UI for TXT/EPUB/MD; unit for PDF/AZW3) |

`result: partial` — criteria 1, 2 (MD), 4, 5 PASS; criterion 3 (native
EPUB replacement rules) is DEFERRED by the plan to Phase D. The XCUITest
suite closes the headless-navigation gap that blocked the prior
`feature-54-20260519.md` partial: criteria 1, 2 (structural), and 5 are
upgraded from "unit + build" to true end-to-end UI verification.

## Commands run

```bash
# Worktree: .claude/worktrees/agent-acd888aafaa408513
# Branch:   test/feature-54-cu-free-verification (off origin/main @ 306f7ce)

# 1. Add the new XCUITest file to the project.
xcodegen generate

# 2. Run the CU-free verification suite on iPhone 17 Pro Simulator
#    (UDID 61149F0E-... pinned for explicit simulator ownership while
#    other agents run — rule 48).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,id=61149F0E-DC18-4BE2-BB37-52659F1F4F62' \
  -only-testing:vreaderUITests/Feature54ReadingModeRemovalVerificationTests
# → Executed 4 tests, with 0 failures in 126.062 seconds. ** TEST SUCCEEDED **
```

Per-test result:

```
test_verify_feature_54_epub_native_engine_no_reading_mode_picker  passed (32.5s)
test_verify_feature_54_md_native_engine_no_reading_mode_picker    passed (31.6s)
test_verify_feature_54_no_reading_mode_section_in_display_panel   passed (30.6s)
test_verify_feature_54_txt_native_engine_no_reading_mode_picker   passed (31.4s)
```

Transform-correctness integration tests (criterion 2's behavioral half),
re-run as part of the prior evidence file's `Commands run`:

```bash
xcodebuild test \
  -only-testing:vreaderTests/MDReaderReplacementRulesTests \
  -only-testing:vreaderTests/MDReplacementRuleFetcherTests \
  -only-testing:vreaderTests/MDFileLoaderTests \
  -only-testing:vreaderTests/ReaderEngineTests \
  -only-testing:vreaderTests/ReadingModeMigrationTests
# → 56 tests in 5 suites passed (prior evidence file).
```

## Observations

- **The XCUITest approach is the right tool for the headless-nav gap.**
  The prior `feature-54-20260519.md` partial was caused by
  `simctl openurl vreader-debug://open` returning `lastError: null`
  (the book was found in persistence) while the `settle` ready file
  reported `"no active reader"` — the `.debugBridgeOpenBook` →
  `NavigationStack` push does not commit without a driven UI, and
  computer-use is virtual-display-only on this host. XCUITest drives
  the library `bookCard_*` tap directly via the accessibility API and
  synthesizes the gesture, so the `NavigationStack` push commits
  exactly as it does for a real user. All three formats opened cleanly.

- **First suite revision failed on a brittle element query.** The
  initial draft asserted the reader container via
  `app.otherElements["txtReaderContainer"]` etc. All 4 tests failed at
  that assertion — the picker-absence sweep itself PASSED (the test log
  showed the full 11-swipe sweep completing with no Native/Unified
  found, then the panel closing cleanly). Root cause: feature #214
  scoped the `*ReaderContainer` / `*ReaderContent` identifiers to an
  inner SwiftUI `Group`, and a `Group` is a transparent container that
  does not reliably yield a queryable accessibility element. The
  existing `Feature11EPUBHighlightVerificationTests` already documents
  this and queries `app.webViews.firstMatch` by element TYPE instead.
  The suite was revised to verify the native engine by element type
  (`app.webViews` for EPUB's `epubWKWebView`; `app.textViews` /
  `app.tables` for the `textNative` / `markdownNative` UITextView /
  UITableView hosts). Re-run: 4/4 pass. This is a reusable lesson for
  the rest of the DONE-tier CU-free verification work (task #236):
  prefer element-TYPE queries over container-identifier queries when a
  SwiftUI `Group` carries the identifier.

- **Picker-absence is proven by exhaustive scroll traversal.** The
  Display panel is a scrollable `List` with 12 lazy-rendered sections.
  A removed section can never scroll into view, so the suite checks the
  forbidden labels at the initial position and after each of 10
  swipe-ups — a full traversal that never finds the picker is a sound
  proof of absence, not just a single-snapshot miss.

- **PDF and AZW3/MOBI are genuinely un-coverable by XCUITest here** —
  `TestSeeder` only provides real-file openable fixtures for TXT
  (`.warAndPeace`, `.twoBooks`, `.positionTest`), MD (`.mdTOC`,
  `.mdMultiPage`), and EPUB (`.epubFixture`). The `.books` PDF records
  are metadata-only and fail to open (Bug #209). Their `ReaderEngine`
  routing (`pdfKit`, `foliateWeb`) is a pure-function mapping fully
  covered by `ReaderEngineTests`; criterion 5 ("existing reader
  features unchanged") for those two formats rests on that unit
  coverage plus the fact that #54 did not touch their dispatch paths
  beyond replacing the `readingMode` branch with `ReaderEngine.resolve`.

## Artifacts

- New verification suite:
  `vreaderUITests/Verification/Feature54ReadingModeRemovalVerificationTests.swift`
  (4 tests; the pilot CU-free Gate-5 suite for task #236).
- `.xcresult` bundle (passing run):
  `~/Library/Developer/Xcode/DerivedData/vreader-cqkthfyebmvbymcmwcxowtxhnphm/Logs/Test/Test-vreader-2026.05.19_13-32-*.xcresult`
- Prior (DebugBridge headless) evidence file:
  `dev-docs/verification/feature-54-20260519.md`.
