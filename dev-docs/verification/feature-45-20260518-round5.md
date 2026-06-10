---
kind: feature
id: 45
status_target: VERIFIED
commit_sha: 9705693df86ffb8c2855280e1837ce4488077639
app_version: 3.27.27 (build 441)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #45 — Verification harness sweep — round-5 regression sampling

Feature #45 is `DONE`. Its row documents progressive verify-cron sampling
rounds of the `Verification` xctestplan. Round-4
(`feature-45-20260518-round4.md`, result=partial) ran at v3.27.25 commit
`8cab12a`. Since then `main` advanced **2 commits** to v3.27.27 commit
`9705693`:

- `c83c7d3` — fix: Feature11 EPUB-highlight XCUITest seed + readiness probe
  (Bug #219 / GH #846)
- `9705693` — fix: EPUB cross-chapter search highlight — retry
  `window.find()` until chapter DOM settles (Bug #182 / GH #847)

Round-5 re-runs the full `Verification` xctestplan at current `main` to
confirm those commits did not regress the verification harness.

`c83c7d3` (Bug #219) is the reason this round is **warranted, not rote**:
it rewrote `Feature11EPUBHighlightVerificationTests` directly — flipping
the seed from `.books` (metadata-only EPUB records that never open) to
`.epubFixture` (a real, openable mini-epub3), AND converting the
reader-load gates (`openEPUBBook()`, `waitForEPUBReaderReady()`) from
`XCTSkip` to **hard `XCTAssertTrue`**. Round-4 ran at `8cab12a`, *before*
that change. Round-5 is the **first** run of `Feature11EPUBHighlightVerificationTests`
inside the full plan with the post-#219 hard-assert gates — so it samples
a real risk: if the `.epubFixture` seed or the EPUB reader-load had any
defect, what was a SKIP in round-4 would now be a **FAIL**.

This is a **regression-sampling round**, not the final-acceptance pass:
#45's `VERIFIED` flip is gated on the 9 currently-SKIPPED method-groups
being sampled clean (fixture/harness/env gaps), which is unchanged this
round. Feature #45 stays `DONE`.

(CU MCP display was unavailable this iteration — `screencapture`/display
state shows a `Screen Sharing Virtual Display` only, no real monitor, so
the MCP capture path cannot work. The whole round is driven by
`xcodebuild test`, no gestures — `xcodebuild test` does not need CU.)

## Scope

The `Verification` xctestplan as a whole, at current `main`. Verification
only; no code changed.

## Acceptance criteria

| # | Criterion | Observed | Result |
|---|---|---|---|
| 1 | The `Verification` xctestplan builds and runs end-to-end on the iPhone 17 Pro Simulator | `xcodebuild test -testPlan Verification` built with 0 compile errors and ran all 27 selected test methods across 14 classes; `** TEST SUCCEEDED **`, exit 0, 466.0 s test execution. | pass |
| 2 | Zero test failures (no regression vs round-4) | 27 executed, **0 failures (0 unexpected)**, 15 XCTSkip-gated, 12 PASS. Per-class shape is **byte-identical** to round-4 (12 / 15 / 0) and round-3/round-2. No regression across the v3.27.25→v3.27.27 commit range. | pass |
| 3 | Full acceptance — every Verification class sampled clean (no SKIPs) | NOT met — 15 of 27 methods (9 method-groups) remain XCTSkip-gated on fixture/harness/env gaps. Unchanged from round-4; not a product defect (see Observations). | partial — gates #45 `VERIFIED` |

`result: partial` — criteria 1-2 pass (the harness is GREEN, zero
regression); criterion 3 is unchanged-partial. Feature #45 stays `DONE`;
the `VERIFIED` flip remains gated on the 9 SKIP method-groups.

## Test class breakdown (round-5)

| Class | Exec | Pass | Skip | Δ vs round-4 |
|---|---|---|---|---|
| Feature11EPUBBottomChromeVerificationTests | 2 | 2 | 0 | — |
| Feature11EPUBHighlightVerificationTests | 2 | 0 | 2 | — (skip point moved deeper — see below) |
| Feature21PaginatedModeVerificationTests | 2 | 0 | 2 | — |
| Feature23TXTTocVerificationTests | 2 | 2 | 0 | — |
| Feature27ReplacementRulesVerificationTests | 1 | 1 | 0 | — |
| Feature28ChineseConversionVerificationTests | 2 | 1 | 1 | — |
| Feature29WebDAVVerificationTests | 2 | 1 | 1 | — |
| Feature31AutoPageTurnVerificationTests | 2 | 0 | 2 | — |
| Feature34CollectionsVerificationTests | 2 | 2 | 0 | — |
| Feature35AnnotationsExportVerificationTests | 2 | 0 | 2 | — |
| Feature36OPDSVerificationTests | 2 | 1 | 1 | — |
| Feature37PerBookSettingsVerificationTests | 2 | 2 | 0 | — |
| Feature40TTSSentenceHighlightVerificationTests | 2 | 0 | 2 | — |
| Feature41TTSAutoScrollVerificationTests | 2 | 0 | 2 | — |
| **Total** | **27** | **12** | **15** | **identical** |

## What round-5 settles: Bug #219's hard-assert conversion is safe

The headline result is `Feature11EPUBHighlightVerificationTests`: **2 exec
/ 0 pass / 2 skip — and 0 fail.** The count is unchanged from round-4, but
the *meaning* changed, and that is exactly what this round was run to
sample:

- **Round-4** (`8cab12a`, pre-#219): the class skipped at the
  reader-load gate — the `.books` seed carried metadata-only EPUB records
  that never open, so `openEPUBBook()` `XCTSkip`'d before any gesture
  (the "silent vacuous pass" Bug #219 / GH #844 was filed for).
- **Round-5** (`9705693`, post-#219): both methods skip at
  `Feature11EPUBHighlightVerificationTests.swift:147` and `:237` — the
  **WKWebView long-press selection step**, *after* clearing the now-hard
  `XCTAssertTrue` reader-load gates. Skip reasons: *"Highlight menu item
  not found after long-press"* and *"Highlight menu not found after
  settle-gated long-press"*.

That the tests reached line 147/237 (rather than failing at line 115-124 /
209-218, which are now hard asserts) proves Bug #219's fix is correct
end-to-end inside the full plan: the `.epubFixture` seed produces a real
openable EPUB, the reader and WKWebView mount, and the test proceeds all
the way to the gesture. The remaining 2 skips are now an honest "got to
the gesture; the gesture itself is the limitation" skip — the
`XCUICoordinate.press` → WKWebView text-selection harness gap already
tracked as **Bug #220 / GH #845** (filed today; the bugfix-cron skip-noted
it as a feature-#45 verification-harness-sweep candidate). No regression.

## Observations

- Round-5 is byte-identical in pass/skip/fail shape to round-4, round-3,
  and round-2: 12 PASS / 15 SKIP / 0 FAIL across 27 methods. Zero
  regressions across the round-4→round-5 commit range (`8cab12a..9705693`).
- The commit range includes Bug #219 (a direct rewrite of a Verification
  test class) and Bug #182 (an EPUB search-highlight JS change). Running
  the full `Verification` plan confirms neither regressed the harness;
  Bug #219's hard-assert conversion is positively confirmed safe (see
  above).
- The 15 SKIP methods are the same 9 method-groups as round-4, all gated
  on fixture/harness/env reasons (not product defects). Skip reasons
  captured verbatim from this run:
  - `Feature11EPUBHighlightVerificationTests` ×2 — *"Highlight menu …
    not found after long-press"* (WKWebView text-selection harness gap;
    Bug #220 / GH #845).
  - `Feature21PaginatedModeVerificationTests` ×2 — multi-page EPUB
    fixture / Reading-Mode-picker gap.
  - `Feature28ChineseConversionVerificationTests` ×1 — *"CJK TXT fixture
    not present in DebugFixtureCatalog"*.
  - `Feature29WebDAVVerificationTests` ×1 — *"CI_WEBDAV_URL /
    CI_WEBDAV_USERNAME / CI_WEBDAV_PASSWORD env vars not set"*.
  - `Feature31AutoPageTurnVerificationTests` ×2 — *"Auto Page Turn
    section not present — capability or layout gate not satisfied"*
    (MD-only capability + Bug #215 MD-paged-mode gap).
  - `Feature35AnnotationsExportVerificationTests` ×2 — export/import
    button reachability.
  - `Feature36OPDSVerificationTests` ×1 — *"CI_OPDS_URL env var not
    set"*.
  - `Feature40TTSSentenceHighlightVerificationTests` ×2 — *"Reader TTS
    button not present"* (TTS control-bar timing).
  - `Feature41TTSAutoScrollVerificationTests` ×2 — *"Reader TTS button
    not present for this fixture/format"* (TTS auto-scroll timing).
- `Feature37PerBookSettingsVerificationTests` (2/2 PASS) and
  `Feature11EPUBBottomChromeVerificationTests` (2/2 PASS) — both remain
  green.
- Verification-only round: no bug discovered, no code changed. Bug #220
  (the only skip cause that is a tracked defect rather than a pure
  fixture/env gap) was already filed today by the bugfix-cron — no new
  filing needed.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# main at commit 9705693 (v3.27.27 build 441) — Verification xctestplan
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -testPlan Verification \
  -destination "id=$SIM" \
  -resultBundlePath /tmp/f45r5.xcresult
# → ** TEST SUCCEEDED **  (exit 0)
# → Executed 27 tests, with 15 tests skipped and 0 failures (0 unexpected) in 466.0 s
```

## Artifacts

- `dev-docs/verification/artifacts/feature-45-r5-verification-testplan-20260518.txt`
  — extracted `Test Suite` / `Test Case` / `Test skipped` / `Executed …
  tests` / `TEST SUCCEEDED` lines from the `xcodebuild test` run.
- `/tmp/f45r5.xcresult` — full result bundle (local, not committed).

## Outcome

Feature #45 stays **DONE**. Round-5 confirms the `Verification` xctestplan
is GREEN at current `main` (v3.27.27 / `9705693`) with zero regressions
across the round-4→round-5 commit range. It additionally confirms — as a
positive result — that Bug #219's conversion of
`Feature11EPUBHighlightVerificationTests`'s reader-load gates from
`XCTSkip` to hard `XCTAssert` is safe: the tests now clear those gates
and skip deeper at the Bug #220 WKWebView-gesture limitation. The
`VERIFIED` flip remains gated on the 9 SKIP method-groups
(fixture/harness/env gaps) being sampled clean — unchanged this round. No
new bugs filed.
