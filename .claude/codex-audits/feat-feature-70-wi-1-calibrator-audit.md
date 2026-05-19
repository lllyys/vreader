---
branch: feat/feature-70-wi-1-calibrator
threadId: 019e3efb-fde9-77c2-95cf-824122699f83
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit log — Feature #70 (GH #491) WI-1 — FontSizeCalibration value types + FontSizeCalibrator mapper

Gate 4 (implementation audit) of the 6-gate feature workflow. Independent
auditor: Codex MCP, thread `019e3efb`. Read-only sandbox.

Audited diff: `vreader/Models/FontSizeCalibration.swift`,
`vreader/Services/FontSizeCalibrator.swift`,
`vreaderTests/Models/FontSizeCalibrationTests.swift`,
`vreaderTests/Services/FontSizeCalibratorTests.swift`.

## Round 1 findings

Codex returned 0 Critical / 0 High / 2 Medium / 1 Low. The implementation
itself matched the Gate-2-approved plan (4-case target enum with no PDF,
explicit named profile fields + total `switch`, unconditional re-clamp,
separate `.foliate` `8...72` path, pure `Sendable` value types). All
findings were in the test suite's rigor.

| # | File | Severity | Finding | Resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Services/FontSizeCalibratorTests.swift` | Medium | `calibratedSizeAppliesMultiplier` and `standardProfileMatchesMultiplierAtReferenceSize` hardcoded the `12...64` band for every target, including `.foliate`. Their sample values stayed inside both bands, so they did not verify the plan-critical requirement that `calibratedSize(..., .foliate)` uses the distinct `8...72` band — a regression that text-clamped `.foliate` could still pass. | Added a `clampBand(for:)` test helper returning `(8, 72)` for `.foliate` and `(12, 64)` for the text targets; both tests now compute expected bounds per target. Added `calibratedSizeForFoliateUsesFoliateBandNotTextBand` asserting `calibratedSize(forUnified: 12, target: .foliate) == 9` (text band would raise to 12) and `calibratedSize(forUnified: 64, target: .foliate) == 70` (text band would lower to 64). |
| 2 | `vreaderTests/Services/FontSizeCalibratorTests.swift` | Medium | `calibratedFoliateSizeRoundsHalfUp` accepted either `34` or `35` for a `34.5` halfway value, so it could not catch a rounding-mode regression; no negative-halfway coverage. | `FontSizeCalibrator.calibratedFoliateSize` now calls `calibrated.rounded(.toNearestOrAwayFromZero)` explicitly (was bare `.rounded()`), with a doc comment stating the contract. `calibratedFoliateSizeRoundsHalfwayAwayFromZero` now asserts exact values (`23 → 35` from 34.5, `25 → 38` from 37.5). New `negativeHalfwayRoundsAwayFromZero` pins the `-0.5 → -1` / `-34.5 → -35` conversion directly (the clamped API floors negatives at 8, so the rule is asserted on the underlying conversion). |
| 3 | `vreaderTests/Services/FontSizeCalibratorTests.swift` | Low | No coverage for non-finite injected multipliers (`NaN`, `±infinity`) — the audit scope explicitly called these out. | `calibratedSize` now has a `guard scaled.isFinite else { return lower }` — a non-finite scaled product (from a non-finite multiplier OR a non-finite `unified` input) falls back to the target band's lower bound (12 text / 8 Foliate), so the calibrator never hands `NaN`/infinity to a renderer. Added `nanMultiplierFallsBackToTargetLowerBound` (parameterized over all targets), `positiveInfinityMultiplierFallsBackToLowerBound`, `negativeInfinityMultiplierFallsBackToLowerBound`, `nonFiniteUnifiedInputFallsBackToLowerBound`. |

Round-1 verdict: follow-up-recommended.

## Round 2 re-review

Codex re-read the fix commit (`fix(#491 WI-1): apply Gate-4 audit findings`)
and confirmed:

- All 3 round-1 findings resolved. The `.foliate` band test would now fail
  if `.foliate` were clamped to `12...64`; the rounding contract is pinned in
  both production and tests including the negative-halfway case; the
  non-finite gap is closed with `NaN` / `+infinity` / `-infinity` / non-finite
  `unified` coverage.
- The non-finite lower-bound fallback design is sound: it preserves the
  mapper's core invariant (never emit `NaN`, infinity, or an out-of-range
  size to a renderer), and the lower bound is a deterministic, readable,
  target-valid, conservative choice for a pure mapper with no error channel.
- No new Critical/High/Medium issues introduced by the fix.

Round-2 verdict: **ship-as-is**.

## Outcome

Zero open Critical/High/Medium findings after 2 rounds. Gate 4 passes for
WI-1.
