---
kind: feature
id: 45
status_target: DONE
commit_sha: f47e1c55fb0ccc2489a3988f776a2f7775d307a9
app_version: 3.34.15 (build 502)
date: 2026-05-19
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (XCUITest -testPlan Verification)
result: partial
---

# Feature #45 — Verification harness sweep (round-6 sampling, post-v3.34.x)

Round-6 of the verify-cron progressive sampling. Re-ran the
`Verification.xctestplan` against merged `main` at v3.34.15 (commit
`f47e1c5`) to detect any regression in the round-5 PASSing tests
across the ~7-version delta since round-5 (v3.27.27, commit `9705693`,
2026-05-18). Features #54/#55/#57/#63/#65/#68/#69 merged in that
window, plus the Bug #225/#226 `TTSService` `rate` `didSet` infinite-
recursion fix (commit `4348476`) and assorted test-infra fixes.

## Result summary

**True round-6 shape: 27 tests — 12 PASSED, 15 SKIPPED, 0 FAILED.**
**GREEN. No regression. Byte-identical to the round-5 baseline.**

The result required a two-stage run because the shared simulator pool
was under heavy concurrent contention (the prompt warned four other
verification/fix agents may run test gates simultaneously; the
plan-run log's Feature41 line even shows a *different* agent's worktree
path — `agent-ae3766e47e5dfdd3d` — proving cross-agent pool sharing):

1. **Plan run** (contended pool): `xcodebuild test -testPlan Verification`
   reported **8 PASS / 13 SKIP / 6 FAIL**. The 6 "failures" —
   Feature28/29/34/36/40/41 (one method each) — were each a different
   element-resolution failure (`Button (First Match)` snapshot
   timeout, `settingsView` not appearing, `newCollectionButton` not
   hittable, `opdsEmptyState` retry-exhaustion, TTS-button absence)
   with **0 product assertion logic failures**. One Feature28 method
   stalled the test daemon for **427 seconds** ("Failed to get
   matching snapshots: Timed out while fetching snapshot from
   testmanagerd"); every subsequent class inherited a degraded
   `testmanagerd` automation state — the classic #221-class
   flaky-parallel-pool cascade signature (the prompt explicitly
   excludes that signature as a regression).
2. **Isolation re-run** (per procedure step 4): re-ran all 6 "failed"
   classes on a dedicated, freshly-created idle simulator
   (`vreader-f45-round6-iso`, no other agent sharing it). Result:
   **`** TEST SUCCEEDED **` — Executed 12 tests, 7 skipped, 0
   failures.** Every one of the 6 contended-run failures resolved to
   PASS or to the standing harness-gap SKIP. A real regression
   reproduces in isolation; none did. Confirmed: **the 6 plan-run
   failures were contention noise, not regressions.**

## Acceptance criteria

Feature #45's acceptance is the `Verification` xctestplan staying
GREEN (0 product-failure FAILs) with no regression in the
previously-PASSing methods. Round-6 verifies that.

| Criterion (from feature #45 row / plan) | Observed round-6 | Result |
|---|---|---|
| `Verification.xctestplan` runs end-to-end via `xcodebuild test -testPlan Verification` | 27 tests dispatched across 14 classes; plan run + isolation re-run both completed | **pass** |
| Zero product-regression FAILs (no method that PASSED in round-5 now logic-fails) | 0 product assertion failures. The 6 plan-run failures were XCUITest-infra failures (testmanagerd snapshot timeouts / element-resolution misses under contention), all PASS/SKIP-clean in isolation | **pass** |
| The 12 round-5 PASSing methods still PASS | All 12 hold (Feature11BottomChrome ×2, Feature23 ×2, Feature27 ×1, Feature28-picker ×1, Feature29-ui ×1, Feature34 ×2, Feature37 ×2 — Feature28/29/34 confirmed via isolation re-run) | **pass** |
| The 15 round-5 SKIPs remain documented fixture/env/harness gaps (not new product breakage) | All 15 SKIPs map to the same 9 method-groups round-5 listed; no SKIP escalated to a product FAIL | **partial — see below** |
| Full VERIFIED flip (every acceptance criterion exercised end-to-end with no SKIP) | NOT met — 15 SKIPs persist (fixture / env-var / TTS-harness gaps, all already tracked). Row stays `DONE`, not `VERIFIED` | **partial** |

`result: partial` because 15 of 27 methods still SKIP behind the
documented harness/fixture/env gaps — the VERIFIED flip remains gated.
Round-6 is a regression-detection sampling pass, not a VERIFIED flip.

## Per-class results (true round-6 — plan run for uncontended classes, isolation run for the 6 contended classes)

| Class | Methods | Pass | Skip | Source | Skip reason |
|---|---|---|---|---|---|
| Feature11EPUBBottomChromeVerificationTests | 2 | **2** | 0 | plan run | — |
| Feature11EPUBHighlightVerificationTests | 2 | 0 | 2 | plan run | "EPUB highlight … not present" — Bug #220 / GH #845 (WKWebView long-press step); reader-load hard gates clear, skip is deeper |
| Feature21PaginatedModeVerificationTests | 2 | 0 | 2 | plan run | "Reading Mode picker absent" / "readingProgressLabel not present" — no multi-page EPUB fixture |
| Feature23TXTTocVerificationTests | 2 | **2** | 0 | plan run | — |
| Feature27ReplacementRulesVerificationTests | 1 | **1** | 0 | plan run | — |
| Feature28ChineseConversionVerificationTests | 2 | **1** | 1 | **isolation** | conversion-applies: "CJK TXT fixture not present in DebugFixtureCatalog" — fixture gap |
| Feature29WebDAVVerificationTests | 2 | **1** | 1 | **isolation** | backup-executes: "CI_WEBDAV_URL / USERNAME / PASSWORD env vars not set" — env dependency |
| Feature31AutoPageTurnVerificationTests | 2 | 0 | 2 | plan run | auto-page-turn toggle/slider skip — fixture/harness gap |
| Feature34CollectionsVerificationTests | 2 | **2** | 0 | **isolation** | — |
| Feature35AnnotationsExportVerificationTests | 2 | 0 | 2 | plan run | export/import button skip — harness gap |
| Feature36OPDSVerificationTests | 2 | **1** | 1 | **isolation** | browse-with-live-fixture: "CI_OPDS_URL env var not set" — env dependency |
| Feature37PerBookSettingsVerificationTests | 2 | **2** | 0 | plan run | — (Bug #204 swipe-helper fix holding) |
| Feature40TTSSentenceHighlightVerificationTests | 2 | 0 | 2 | plan run + isolation | "Reader TTS button not present for this fixture/format" — TTS harness gap |
| Feature41TTSAutoScrollVerificationTests | 2 | 0 | 2 | plan run + isolation | "Reader TTS button not present" — TTS harness gap |
| **Total** | **27** | **12** | **15** | | **0 FAIL** |

## Comparison to round-5 baseline (v3.27.27, commit `9705693`, 2026-05-18)

| Metric | round-5 | round-6 (true) | Change |
|---|---|---|---|
| Total tests | 27 | 27 | 0 |
| Passed | 12 | 12 | 0 |
| Skipped | 15 | 15 | 0 |
| Failed (product) | 0 | 0 | 0 |
| SKIP method-groups | 9 | 9 | 0 |

The 9 SKIP method-groups are identical to round-5: Feature11Highlight,
Feature21, Feature28-conversion, Feature29-backup-executes,
Feature31, Feature35, Feature36-live, Feature40, Feature41. Every
class produced the same pass/skip verdict and the same skip reasons.
**Zero regressions** across the ~7-version delta (features
#54/#55/#57/#63/#65/#68/#69 + Bug #225/#226 TTSService recursion fix +
test-infra fixes). The 12 round-5 PASSing methods all held — including
the three (Feature28-picker, Feature29-ui, Feature34 ×2) that had to
be re-confirmed in isolation because the contended plan run
false-failed them.

## Commands run

```bash
# 1. Plan run on a freshly-erased iPhone 17 Pro Simulator (contended pool)
xcrun simctl erase 61149F0E-DC18-4BE2-BB37-52659F1F4F62
xcrun simctl boot 61149F0E-DC18-4BE2-BB37-52659F1F4F62
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader -testPlan Verification \
  -destination 'platform=iOS Simulator,id=61149F0E-DC18-4BE2-BB37-52659F1F4F62' \
  2>&1 | tee /tmp/feature45-round6.log
# → 8 PASS / 13 SKIP / 6 FAIL (contention-contaminated; testmanagerd
#   wedged 427 s on Feature28, cascade through Feature29/34/36/40/41)

# 2. Isolation re-run of the 6 "failed" classes on a DEDICATED idle simulator
xcrun simctl create "vreader-f45-round6-iso" "iPhone 17 Pro" \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcrun simctl boot A6829375-631F-45F6-8A11-492BC63986EF
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader -testPlan Verification \
  -destination 'platform=iOS Simulator,id=A6829375-631F-45F6-8A11-492BC63986EF' \
  -only-testing:vreaderUITests/Feature28ChineseConversionVerificationTests \
  -only-testing:vreaderUITests/Feature29WebDAVVerificationTests \
  -only-testing:vreaderUITests/Feature34CollectionsVerificationTests \
  -only-testing:vreaderUITests/Feature36OPDSVerificationTests \
  -only-testing:vreaderUITests/Feature40TTSSentenceHighlightVerificationTests \
  -only-testing:vreaderUITests/Feature41TTSAutoScrollVerificationTests \
  2>&1 | tee /tmp/feature45-round6-iso.log
# → ** TEST SUCCEEDED ** — Executed 12 tests, 7 skipped, 0 failures (174.8 s)
```

Plan run: ~21 min wall (build + tests, contended). Isolation run:
~3 min wall (192 s — build reused from DerivedData).

## Observations

- **Contention is the dominant failure mode for this harness on a
  shared simulator pool.** Two independent first attempts on the
  shared pool both cascaded: the first never finished (runner failed
  to initialize — "Timed out waiting for AX loaded notification"); the
  second produced 6 false failures. The decisive isolation re-run on
  a dedicated, single-tenant simulator turned all 6 green/skip. The
  procedure's step-4 isolation rule is exactly what separated noise
  from signal here — without it, round-6 would have falsely reported
  6 regressions.
- **The 427-second Feature28 `testmanagerd` stall is the cascade
  origin.** Once the simulator-side test daemon wedged on an AX
  snapshot request, every subsequent class on that booted instance
  hit element-resolution failures — different element each time,
  always 0 product-assertion failures. That progressive-degradation
  pattern (one class hangs, the rest fall like dominoes, each at a
  random element) is itself a fingerprint of harness flakiness, not
  product breakage: five unrelated features (#28/#29/#34/#36 +
  TTS #40/#41) do not all regress simultaneously in one version bump.
- **No new bugs filed.** Filing threshold for a round: a class must
  show a *product* regression — a method that logic-failed in
  isolation, or a previously-passing method newly broken on an idle
  device. None triggered. The 6 contended-run failures are the known
  #221-class flaky-parallel-pool signature, explicitly excluded from
  regression-filing.
- **TTS path unchanged despite the Bug #225/#226 `TTSService`
  recursion fix.** Feature40/41 still SKIP with "Reader TTS button not
  present" — the same TTS-harness gap from round-5. The recursion fix
  (`rate` `didSet`) is a service-layer correctness fix; it does not
  change whether the XCUITest harness can locate `readerTTSButton`
  for the chosen fixture/format. No progression, no regression.
- **Bug #204 / #214 / #220 fixes holding.** Feature37 (per-book
  settings, 2/2 PASS) and Feature11BottomChrome (Bug #214, 2/2 PASS)
  stayed clean — the round-3..round-5 progressions persist.

## Filing decisions

- **No new bug rows or GH issues filed** this round. Zero confirmed
  regressions; the 6 contended-run failures are confirmed harness
  contention noise (#221-class).
- **Feature #45 row Notes**: append a one-line round-6 entry — same
  shape at v3.34.15, no regression.

## Artifacts

- `/tmp/feature45-round6.log` — plan-run xcodebuild stdout (contended;
  ephemeral diagnostic, not committed).
- `/tmp/feature45-round6-iso.log` — isolation-run xcodebuild stdout
  (`** TEST SUCCEEDED **`; ephemeral, not committed).
- Plan-run xcresult: `~/Library/Developer/Xcode/DerivedData/vreader-ecfaliqpdarjpleewrynfwpoxcvh/Logs/Test/Test-vreader-2026.05.19_15-40-22-+0800.xcresult`
- Isolation-run xcresult: `~/Library/Developer/Xcode/DerivedData/vreader-ecfaliqpdarjpleewrynfwpoxcvh/Logs/Test/Test-vreader-2026.05.19_15-59-22-+0800.xcresult`

## VERIFIED gate status

Still blocked. Round-6 is GREEN (12 PASS / 15 SKIP / 0 FAIL) with no
regression, but the VERIFIED flip requires the 15 SKIPs to clear.
Path unchanged from round-5:

1. Multi-page EPUB fixture in `DebugFixtureCatalog` (blocks #21).
2. CJK TXT fixture (blocks #28-conversion).
3. `CI_WEBDAV_URL` / `CI_OPDS_URL` env config (blocks #29-backup,
   #36-live).
4. EPUB highlight WKWebView long-press harness step — Bug #220 / GH
   #845 (blocks #11-highlight).
5. TTS-button harness wiring for the chosen fixture/format (blocks
   #40, #41).
6. Auto-page-turn (#31) + annotations-export (#35) harness gaps.

Until those land, Feature #45 row stays `DONE` with the round-1
through round-6 sampling evidence files documenting the gate.
