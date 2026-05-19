---
branch: feat/feature-70-wi-3-epub-routing
threadId: 019e3f41-0ee5-7042-9256-fcabd98dd7f2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit log — Feature #70 (GH #491) WI-3 — route EPUB font size through FontSizeCalibrator

Gate 4 (implementation audit) of the 6-gate feature workflow. Independent
auditor: Codex MCP, thread `019e3f41`. Read-only sandbox.

Audited diff: `vreader/Views/Reader/EPUBReaderContainerView.swift`,
`vreaderTests/Models/ReaderThemeV2EPUBCSSCalibrationTests.swift`.

## Round 1 findings

0 Critical / 0 High / 0 Medium / 1 Low. Codex confirmed the one-line routing
change matched the plan (`fontSize:` argument only, `letterSpacing` untouched,
`$0` correctly the unwrapped `ReaderSettingsStore`, `.epub` calibrator path
clamping to `12...64`, scope tight, Bug #57 selectors intact).

| # | File | Severity | Finding | Resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Models/ReaderThemeV2EPUBCSSCalibrationTests.swift` | Low | The WI-3 tests built CSS directly via `ReaderThemeV2.epubOverrideCSS(fontSize: calibrated)` — they validated the calibrator + `epubOverrideCSS`, but did NOT exercise the actual `EPUBReaderContainerView` call site. A regression of that call site back to the raw `$0.typography.fontSize` would still pass every test. | Extracted a pure static helper `EPUBReaderContainerView.calibratedEPUBFontSize(for:)` returning `store.calibrator.calibratedSize(forUnified: store.typography.fontSize, target: .epub)`; the `epubOverrideCSS` call site now calls `Self.calibratedEPUBFontSize(for: $0)`. Added two tests (`containerHelperRoutesThroughCalibratorEpubTarget`, `containerHelperValueDiffersFromRawUnified`) that construct a real `@MainActor` `ReaderSettingsStore` and assert the helper returns the calibrated `.epub` value across 12/18/24/40/64 — a regression to the raw unified value is now caught. |

Round-1 verdict: follow-up-recommended.

## Round 2 re-review

Codex re-read the fix commit and confirmed:

- The round-1 Low is resolved. `EPUBReaderContainerView` exposes one pure
  helper; the live production `epubOverrideCSS` call site uses that exact
  helper; `rg` shows no parallel production path (the only non-test use is
  that call site).
- The new tests correctly exercise the helper on a real `@MainActor`
  `ReaderSettingsStore`, verify `.epub` calibration across multiple values,
  and assert the value differs from the raw unified `24`.
- No new issues; scope tight; the helper body still routes through the
  calibrator; the Bug #57 no-regression coverage remains intact.

Round-2 verdict: **ship-as-is**.

## Outcome

Zero open Critical/High/Medium findings after 2 rounds. Gate 4 passes for WI-3.
