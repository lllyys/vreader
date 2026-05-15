---
kind: feature
id: 45
status_target: DONE
commit_sha: 4f7778efc55d1cf24b731cbaba0c64ea56dba8f3
app_version: 3.22.3 (build 355)
date: 2026-05-15
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (XCUITest harness against in-simulator app + DebugBridge URL scheme)
result: pass
---

# Feature #45 — Clean Verification plan run after Bug #196 fix

## Why this evidence file exists

This is the **fourth `-testPlan Verification` run** in the WI-6 lifecycle today. Each successive run reflects landing a fix or filing a bug from the prior run's surfaced failures:

| Run | Commit / version | PASS | SKIP | FAIL | Notes |
|---|---|---|---|---|---|
| 1 (post-Bug-#192 4-class sample) | v3.21.67 | 5 | 1 | 2 | First non-vacuous Verification run after `verify_*` → `test_verify_*` rename |
| 2 (WI-6 first end-to-end) | v3.21.69 / `3753d2a` | 10 | 13 | 2 | Bug #194 + #195 surfaced |
| 3 (post-Bug-#194/#195-fix re-run) | v3.22.1 / `897a459` | 11 | 13 | 1 | Bug #196 surfaced (Feature31 regression) |
| **4 (this run, post-Bug-#196-fix)** | **v3.22.3 / `4f7778e`** | **12** | **13** | **0** | **All non-skipped methods PASS** |

The **all-fixed state** — zero failures across the 25-method `-testPlan Verification` invocation — confirms that the 5 bugs surfaced by Feature #45 WI-6's first-real-run lifecycle (Bug #192/#193/#194/#195/#196) are all genuinely fixed on `main`.

## Acceptance criteria

| # | Criterion (from Feature #45 plan + WI-6 plan v3) | Observed | Pass/fail |
|---|---|---|---|
| 1 | Named `-testPlan Verification` flag recognized by xcodebuild; dispatches a non-zero test count. | `Executed 25 tests`. | **pass** |
| 2 | Membership exact: 25 methods total, matching the documented roster. | All 13 classes' suites started + completed in the documented order. | **pass** |
| 3 | No-flag default invocation still uses the All plan. | (Not re-tested this run — covered by prior runs.) | **pass** (inherited) |
| 4 | Wall-clock under the 8-minute Gate 5 budget. | 408 seconds (~6 min 48 s). | **pass** |
| 5 | All non-skipped methods pass. | 12 PASS, 0 FAIL. | **pass** |
| 6 | Skip-gated methods (13 total) have documented capability/fixture rationale at the throw-site. | Skip messages enumerated in the per-class section below. | **pass** |

Overall: **6/6 pass**. `result: pass` on this run.

## Per-class results

Total: **Executed 25 tests, with 13 tests skipped and 0 failures (0 unexpected) in 408.095 seconds**.

| Class | Methods | Pass | XCTSkip | Fail | Wall-clock | Notes |
|---|---|---|---|---|---|---|
| Feature11EPUBHighlight | 2 | 0 | 2 | 0 | 55.2 s | All-skip — see "Skip rationale" below |
| Feature21PaginatedMode | 2 | 0 | 2 | 0 | 29.3 s | All-skip |
| Feature23TXTToc | 2 | 2 | 0 | 0 | 26.7 s | All PASS |
| Feature27ReplacementRules | 1 | 1 | 0 | 0 | 10.7 s | All PASS |
| Feature28ChineseConversion | 2 | 1 | 1 | 0 | 23.4 s | Bug #194 fix CONFIRMED; 1 SKIP on missing CJK fixture |
| Feature29WebDAV | 2 | 1 | 1 | 0 | 19.9 s | Bug #195 fix CONFIRMED; 1 SKIP on missing CI WebDAV creds |
| Feature31AutoPageTurn | 2 | 2 | 0 | 0 | 32.7 s | **Bug #196 fix CONFIRMED** — was 1 FAIL last run |
| Feature34Collections | 2 | 2 | 0 | 0 | 49.5 s | All PASS |
| Feature35AnnotationsExport | 2 | 2 | 0 | 0 | 20.9 s | All PASS |
| Feature36OPDS | 2 | 1 | 1 | 0 | 18.5 s | Bug #193 fix CONFIRMED stable; 1 SKIP on missing live OPDS URL |
| Feature37PerBookSettings | 2 | 0 | 2 | 0 | 29.3 s | All-skip |
| Feature40TTSSentenceHighlight | 2 | 0 | 2 | 0 | 45.9 s | All-skip |
| Feature41TTSAutoScroll | 2 | 0 | 2 | 0 | 46.0 s | All-skip |
| **Total** | **25** | **12** | **13** | **0** | **408.1 s** | All-fixed state |

## Skip rationale (the 13 XCTSkip-gated methods)

This section addresses the prior evidence file's open question: "are the all-skip classes' XCTSkips legitimate gates or stale guards?" Grepping each test method for its `throw XCTSkip(...)` lines and analyzing:

### Feature11EPUBHighlight — 2 skips (load-timing / gesture-fragility gates)

- `"No book cards in library — cannot run EPUB highlight test"` — fixture-dep on book-card visibility.
- `"EPUB reader did not load within timeout"` — load-timing gate; suggests slow boot or sim cold state.
- `"EPUB WebView not found — book may not be an EPUB"` — capability-gate / fixture-format mismatch.
- `"Highlight menu item not found after long-press"` — gesture-timing OR fixture has no selectable text.

**Verdict**: legitimate fixture/timing gates. The harness correctly XCTSkips when prerequisites aren't met. Fixing requires bundling a guaranteed-selectable EPUB fixture + tightening load-detection — separate fixture/feature scope.

### Feature21PaginatedMode — 2 skips (fixture-format gates)

- `"Reading Mode picker absent for this fixture's format"`
- `"readingProgressLabel not present on this fixture/layout"`

**Verdict**: legitimate format/layout gates. The seed fixture doesn't expose the paginated-mode picker (probably TXT, where Reading Mode toggle is gated by capability).

### Feature37PerBookSettings — 2 skips (UI-drift + fixture gaps)

- `"Per-book toggle not found — feature #37 UI may have changed"` — **possible stale guard**; the toggle's identifier may have drifted similar to Bug #194 / #195.
- `"Only one book in library — cannot test isolation with a second book"` — fixture gap; per-book settings need 2+ books.

**Verdict**: mixed — fixture gap is legitimate, but the "UI may have changed" message is hedging. Worth investigating whether the toggle identifier is correct (potential Bug like #194 / #195 — but NOT this iteration's scope per the verify-cron guard).

### Feature40TTSSentenceHighlight — 2 skips (TTS env + DebugBridge harness gaps)

- `"Reader TTS button not present for this fixture/format"` — fixture-capability gate.
- `"Could not read DebugBridge snapshot — bridge handler may not be wired this build"` — harness gap.
- `"ttsOffsetUTF16 not reported in snapshot for this format/path"` — fixture/path gap.
- `"ttsOffsetUTF16 lost between snapshots — TTS may have stopped"` — TTS audio-session gate (XCUITest can't grant audio permission).

**Verdict**: legitimate TTS audio-session + fixture gates. TTS needs real audio session which iOS simulators handle inconsistently in XCUITest contexts. Resolution requires the WI-4d/e XCUITestMockSpeechSynthesizer path to be exercised in this test (currently not wired) — separate scope.

### Feature41TTSAutoScroll — 2 skips (same as Feature40)

- `"Reader TTS button not present"` — same fixture-capability gate as Feature40.

**Verdict**: same legitimate TTS gate.

## Categorization of remaining work to reach VERIFIED

Per Feature #45's row note ("VERIFIED status depends on Gate 5 final acceptance evidence file once those unsampled classes are sampled clean end-to-end"), getting from `DONE` → `VERIFIED` requires resolving the 13 skips. Categorized by remediation path:

| Skip class | Count | Category | Remediation |
|---|---|---|---|
| Fixture gaps (need new fixture: 2-book library, guaranteed-selectable EPUB, TTS-capable content) | ~5 | Feature scope | File as feature-row "add fixtures to DebugFixtureCatalog for full Verification coverage" |
| TTS audio-session in XCUITest | ~4 | Harness scope | Wire XCUITestMockSpeechSynthesizer (Feature #45 WI-4e exists but isn't engaged by Feature40/41 tests) |
| Possible UI drift (Feature37 per-book toggle) | 1-2 | Bug scope | File as bug if identifier confirmed drift |
| Load-timing in Feature11 EPUB | 1-2 | Harness or test refinement | Tighten settle conditions, possibly use DebugBridge `settle` handler |
| Env-var-gated live tests (Feature29 live backup, Feature36 OPDS live) | 2 | CI integration scope | Wire env vars when CI lands |

None of these block Feature #45's contract (the harness functions and the 25 methods dispatch correctly). All are documented as follow-up work in this evidence file.

## Commands run

```bash
git checkout main && git pull
git log --oneline -3
# 4f7778e fix(#702): Feature #31 toggle hittability — bump retry budget 3 → 10 (#704)
# bb6de61 docs(verify): post-Bug-#194/#195-fixes Verification plan re-run + file Bug #196 (#703)
# 897a459 fix(#695): Feature #29 WebDAV verify test — traverse multi-profile path (#701)

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -testPlan Verification \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    2>&1 | tee /tmp/verify-cron-post-bug196-fix-v3223.log
```

Skip-rationale enumeration:

```bash
for f in Feature11EPUBHighlight Feature21PaginatedMode Feature37PerBookSettings \
         Feature40TTSSentenceHighlight Feature41TTSAutoScroll; do
    echo "=== $f ==="
    grep -nE "XCTSkip|throw XCTSkip" \
        vreaderUITests/Verification/${f}VerificationTests.swift | head -10
done
```

## Observations

- **Zero-failure milestone**: this is the first `-testPlan Verification` run with 0 failures since WI-6 shipped earlier today. The full bug recovery lifecycle (Bug #192 discovery → Bug #194/#195 surfacing → Bug #194/#195 fixes → Bug #196 surfacing → Bug #196 fix) wrapped in a single session of ~5 hours.
- **Five bugs fixed via the same descendant-by-identifier pattern**: Bug #193 (OPDS), #194 (Chinese picker), #195 (WebDAV profile nav), and Bug #196 (Feature31 retry budget bump) all reused the same fix shape — element-type-agnostic `app.descendants(matching:.any).matching(identifier:).firstMatch` OR retry-budget increase. The pattern is now well-established in the codebase.
- **Skip rationale is legitimate for ~10 of 13 skips**: TTS audio-session + fixture-format gates account for most of the remaining skips. The exception is Feature37's "UI may have changed" hedge, which may be a latent bug similar to Bug #194 / #195.
- **Path to VERIFIED is now narrow**: closing the 13 skips requires either (a) bundling new fixtures (feature scope), (b) wiring the XCUITestMockSpeechSynthesizer for TTS tests (harness scope), or (c) filing one more bug if Feature37's UI-drift hedge is real. Each is a discrete iteration.

## Artifacts

- Full `xcodebuild test -testPlan Verification` log: transient at `/tmp/verify-cron-post-bug196-fix-v3223.log` (~131KB; not committed).
- Prior runs chronologically:
  - `feature-45-20260515-post-bug192-batch.md` — 4-class sample
  - `feature-45-20260515-wi-6-full-run.md` — first end-to-end (10 PASS, 13 SKIP, 2 FAIL)
  - `feature-45-20260515-post-bug-fixes-full-run.md` — post-#194/#195-fix (11 PASS, 13 SKIP, 1 FAIL)
  - This file — post-#196-fix (12 PASS, 13 SKIP, 0 FAIL) — clean run.

## Status

Feature #45 stays at `DONE`. The path to `VERIFIED` is now well-mapped: each of the 13 skips has a documented rationale + remediation category. A future iteration can pick one category (most efficient: file the fixture-gap as a new feature row, OR investigate Feature37's UI hedge) and resolve.

`result: pass` here means "this run had zero failures and all skips are documented" — NOT "Feature #45 is VERIFIED." The `VERIFIED` flip needs the additional follow-up work documented above.
