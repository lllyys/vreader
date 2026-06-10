---
kind: feature
id: 45
status_target: VERIFIED
commit_sha: 6936ccf848c75770b0ea1801477e7c0e49ca48fa
app_version: 3.27.23 (build 437)
date: 2026-05-18
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #45 round-3 — Verification test-plan progressive sampling

## Context

Round-1 / round-2 sampling (`feature-45-20260516-sampling.md`,
`feature-45-20260516-round2.md`) last ran the `Verification` test
plan on 2026-05-16 at v3.24.6 (commit `a6103e5`): 25 tests, 12 PASS /
13 SKIP / 0 FAIL.

Since then a large amount of churn landed on `main`: the feature #60
visual-identity re-skin, the Bug #209 harness repair (the re-skin had
broken 9 verify tests — repaired to 0 fail), Bug #210 (Feature34
`firstMatch`), Bug #204 (Feature37 swipe-to-reveal harness fix), and
Bug #214 (which added a new `Feature11EPUBBottomChromeVerificationTests`
class). Round-3 re-runs the full plan against current `main`
(`6936ccf`, v3.27.23 build 437) to confirm no regression and to
re-sample the previously-gated classes.

## Acceptance criteria

Feature #45's contract: the `Verification` test plan runs end-to-end
and the simulator-automatable backlog items are covered. `VERIFIED`
requires the gated classes to be sampled clean + a Gate 5 evidence
file.

| Criterion | Round-2 (2026-05-16) | Round-3 (2026-05-18) | Pass/fail |
|---|---|---|---|
| Plan runs end-to-end, transport success | 25 tests dispatched | **27 tests dispatched** (+2 = new Feature11 EPUB class) | **PASS** |
| Zero product failures | 0 FAILED | **0 FAILED** | **PASS** |
| No regression from intervening commits | n/a | 0 FAILED across the feature #60 re-skin + Bug #209/#210/#214 changes | **PASS** |
| All gated classes sampled clean | 7 classes gated | 9 method-groups still SKIP (fixture/harness/env) | **partial** |

**Overall**: `partial`. The harness is GREEN (0 failures) and two
classes newly sample clean, but several classes still XCTSkip on
fixture/harness/environment gaps, so feature #45 cannot flip to
`VERIFIED` yet.

## Results

`** TEST SUCCEEDED **` — 27 tests, 12 PASS / 15 SKIP / 0 FAIL,
443 s test execution.

**PASS (12):**

- `Feature11EPUBBottomChromeVerificationTests` — 2/2 (NEW, Bug #214)
- `Feature23TXTTocVerificationTests` — 2/2
- `Feature27ReplacementRulesVerificationTests` — 1/1 (UI surface)
- `Feature28ChineseConversionVerificationTests` — 1 (picker present)
- `Feature29WebDAVVerificationTests` — 1 (backup UI available)
- `Feature34CollectionsVerificationTests` — 2/2 (Bug #210 fix holds)
- `Feature36OPDSVerificationTests` — 1 (OPDS UI surface)
- `Feature37PerBookSettingsVerificationTests` — **2/2 (NEWLY CLEAN — Bug #204 fix landed)**

**SKIP (15):** `Feature11EPUBHighlightVerificationTests` ×2 (EPUB
load timing), `Feature21PaginatedModeVerificationTests` ×2 (no
multi-page EPUB fixture), `Feature28…conversion_applies` ×1,
`Feature29…backup_executes` ×1 (needs live WebDAV),
`Feature31AutoPageTurnVerificationTests` ×2 (toggle/slider not
reachable in-harness), `Feature35AnnotationsExportVerificationTests`
×2, `Feature36…live_fixture` ×1, `Feature40TTSSentenceHighlight…` ×2
(TTS control-bar timing), `Feature41TTSAutoScroll…` ×2 (same).

**FAIL: none.**

## Delta vs. round-2

- **Feature37 (2 methods): gated → PASS.** Bug #204 / GH #746 fixed
  the XCUITest swipe-to-reveal harness gap; both Feature37 methods now
  run and pass. One of round-2's 7 gated classes is now clean.
- **Feature11EPUBBottomChrome (2 methods): new → PASS.** Bug #214's
  regression test for the EPUB/PDF a11y-identifier clobber works.
- **0 failures** despite the feature #60 re-skin (the change that
  caused the Bug #209 regression) — the Bug #209 repair holds on
  `main`, and #210/#214 introduced no new harness breakage.

## Commands run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -testPlan Verification \
  -destination 'id=61149F0E-DC18-4BE2-BB37-52659F1F4F62'
# → ** TEST SUCCEEDED **; Executed 27 tests, 15 skipped, 0 failures, 443 s
```

## Observations

- The 15 SKIPs are all previously-documented fixture/harness/env
  gaps, not new gates: no multi-page EPUB fixture (Feature21), TTS
  control-bar timing under headless XCUITest (Feature40/41), live
  WebDAV / live OPDS fixtures (Feature29/36), EPUB highlight load
  timing (Feature11Highlight). None is a product defect.
- `Feature31AutoPageTurnVerificationTests` SKIPs both methods — the
  auto-page-turn toggle/slider is not reached in-harness. Distinct
  from Bug #215 (the MD-paged-mode product defect found in feature
  #31 round-6); this is a harness-reachability skip, already in the
  gated set.
- No GH issue filed — round-3 found zero failures.

## Artifacts

- Full xcodebuild log: `/tmp/verify-plan-round3.log` (4704 lines;
  transient — not committed).

## Verdict

`partial`. The `Verification` harness is GREEN at current `main`
(v3.27.23) with 0 failures and no regressions from the substantial
feature #60 / Bug #209-#214 churn since round-2; Feature37 newly
samples clean. Feature #45 stays `DONE` — the `VERIFIED` flip remains
gated on the 9 SKIP method-groups, which need new fixtures
(multi-page EPUB) and harness work (TTS control-bar timing) tracked
separately. Re-sample after those fixture/harness gaps close.
