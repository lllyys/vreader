---
branch: fix/bug-280-font-calibration
threadId: 019e74b9-1e55-7141-b070-44bb80c27fd1
rounds: 1
final_verdict: ship-as-is
date: 2026-05-30
---

# Gate-4 Codex audit — Bug #280 (GH #1257) font-size calibration re-tune

## Scope

Re-tune of `FontSizeCalibrationProfile.standard` from `epub: 1.12, foliate: 1.12`
to `epub: 1.0, foliate: 1.06`, driven by a new live-WKWebView cap-height
measurement test (`FontSizeCalibrationMeasurementTests.swift`). Plus four
pre-existing tests reframed from the un-verified `> 1.0` / `!= raw` premise to
routing/anchor-band invariants.

## Measurement (printed by the test, iPhone 17 Pro Sim, 2026-05-30)

- referenceUnified = 24
- txtCap = 16.910, epubCap = 16.906 → EPUB multiplier = 1.0002 (≈ 1.0)
- foliateCap = 15.891 → Foliate multiplier = 1.064 (shipped 1.06)
- Control (40px): epubControlMultiplier = 1.0004 — matches the reference
  1.0002 within 0.0002, so the cap-height ratio is size-invariant
  (methodology sound).

## Codex round 1 — verdict: ship-as-is

Zero Critical/High/Medium findings. Two Low findings, both fixed in the same
branch (test-file-only):

- **Low (fixed):** file-header comment claimed Foliate's UA default font
  resolves to the system font "same as EPUB"; the measured cap-heights
  contradict that (16.91 vs 15.89). Comment corrected to state the UA default
  is a different face, which is precisely why the two targets get different
  multipliers.
- **Low (fixed):** `MeasureLoadWaiter` waited only on `didFinish`, so a load
  failure could hang the test host. Added `didFail` /
  `didFailProvisionalNavigation` handlers that resolve the continuation; a
  failed load then throws `MeasurementError.noResult` (clean failure, no hang).

Codex audit notes (verbatim summary): clamp bands safe (EPUB 1.0 stays
12...64, Foliate 1.06 rounds/clamps through 8...72); no double-application —
EPUB routes through `calibratedEPUBFontSize` once, Foliate through
`calibratedFoliateSize` once before `themeCSS`; the four test reframings are
correct (removing `!= raw` for EPUB is correct now that `.epub == 1.0`;
removing EPUB==Foliate is correct because the measured font stacks differ).

Both Low fixes are test-file-only; the production literal change is unchanged
from what the audit reviewed. Full `vreaderTests` suite: 7651 tests / 751
suites passed.
