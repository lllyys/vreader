---
branch: fix/issue-491-font-size-slider-max-raise
threadId: 019e14b6-46db-7820-ad5f-ed96dd692d50
rounds: 2
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex audit — bug #166 PARTIAL fix (font size slider max too small for EPUB)

GH issue: #491. Severity: high. Scope: partial — see "Out of scope" below.

## Scope (partial fix by design)

Bug #166 has two sub-pieces:

1. **Slider ceiling too low** — `TypographySettings.fontSizeRange = 12...32` doesn't give EPUB users enough headroom because the WKWebView CSS `font-size` injection compounds with the book's own stylesheet base sizes.
2. **Cross-format perceptual inconsistency** — same numeric value renders at different perceived sizes across TXT (UITextView pt) / EPUB (CSS injection) / PDF (PDFView scale) / AZW3 (Foliate-js) / MD (UITextView). Requires per-renderer measurement + a unified pt→logical-size mapping layer.

This PR addresses ONLY sub-piece 1 by raising the upper bound to 64pt. Sub-piece 2 remains as a documented residual and will be split out as a separate feature row or follow-up bug when calibration work is planned. The bug row moves to `PARTIALLY FIXED` rather than `FIXED`.

## Files changed

Production:
- `vreader/Models/TypographySettings.swift` — single constant change `static let fontSizeRange: ClosedRange<CGFloat> = 12...32` → `12...64`. File header docstring updated to match. Inline docstring on the constant explains the bound + the deliberate scope limit.

Tests:
- `vreaderTests/Models/TypographySettingsTests.swift` — 7 new tests + 2 updated existing:
  - **Updated**: `fontSizeClampedToMaximum` (test value 40 → 100 so the clamp still fires above the new bound), `fontSizeAtMaxBoundary` (boundary value 32 → 64).
  - **New**: `fontSizeRangeUpperBoundIs64`, `fontSizeRangeLowerBoundUnchangedAt12`, `fontSizeAt48ptStaysExact`, `fontSizeAt64ptStaysExactNotClamped`, `fontSizeAt65ptClampsDownTo64`, `decodedFontSizeAbove64ClampsToBound`.
- `vreaderTests/Services/Foliate/FoliateStyleMapperTests.swift` — `themeCSSIncludesLargeFontSize` wording updated ("max font size" → "large font size"); new `themeCSSAcceptsAppMaxFontSize64` test pins the 64-pass-through against the Foliate path's own `8...72` sanitizer.

## Round 1 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Low | `TypographySettings.swift:5` (file header) | Header comment said "Font size range 12...32", now contradicts the actual 12...64 constant. | **Fixed**. Updated to "Font size range 12...64" plus a note explaining the bug #166 partial-fix raise rationale. |
| 2 | Low | `FoliateStyleMapperTests.swift:25` | Assertion message said "Must handle max font size" for the 32-test; that's stale after the app-side max became 64. | **Fixed**. Wording changed to "Must handle large font size". Also added new `themeCSSAcceptsAppMaxFontSize64` test that explicitly pins the new max passes through the Foliate path's `8...72` sanitizer unchanged. |

## Round 2 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Low | `docs/bugs.md:73` (Bug #166 detail) | Root-cause text still said `TypographySettings.fontSizeRange = 12...32 in TypographySettings.swift:28`. Misleading post-PR. | **Fixed**. Dropped the stale path reference, marked sub-piece (a) as DONE in this iteration with the actual constant change documented; sub-piece (b) marked OPEN with explicit feature-class scope note. |
| 2 | Low | `docs/bugs.md:265` (Bug #166 row) | Status still TODO; title still describes "slider max (32pt) too small". Misleading post-merge. | **Fixed**. Status → `PARTIALLY FIXED`; Notes column now distinguishes "slider ceiling fixed to 12...64" from "cross-format perceptual normalization remains open under the same bug/follow-up". |

Round-2 verdict: ship-as-is.

> "I did not find any other production CSS or code path still capping app font size at 32. The remaining 32 references I found are either historical bug-context text or intentional test prose about the old bug condition. Verdict: ship-as-is." — Codex round 2

## Test gate

`xcodebuild test -only-testing:vreaderTests/TypographySettingsTests -only-testing:vreaderTests/FoliateStyleMapperTests` — **75/75 green** (31 typography + 44 Foliate-style; 7 new + 2 boundary-updated).

## Cross-format scope confirmation (audited by Codex)

- **EPUB native** (`EPUBReaderContainerView` CSS injection): uses `typography.fontSize` directly via `epubOverrideCSS(fontSize:...)`; clamp happens at the source. 64pt → `font-size: 64px` injection — confirmed working.
- **Foliate AZW3/MOBI**: `FoliateStyleMapper.themeCSS` has its own `8...72` sanitizer; 64 passes through unchanged. Pinned by new `themeCSSAcceptsAppMaxFontSize64` test.
- **TXT/MD native** (`UITextView` font size): pt = logical points 1:1; 64pt renders directly. No clamp path stale.
- **PDF**: `PDFView` uses its own page-scaling, not directly driven by `typography.fontSize`. Not affected by this raise.
- **Persistence**: `TypographySettings` decode clamps via `Self.clamp(rawFontSize, to: Self.fontSizeRange)`. Existing 12..32 values pass through unchanged (within the new 12..64 range). No migration needed.

## Plan compliance

Fix scope matches the bug body's `Fix: (a)` option:
- [x] Slider max raised from 32pt to 64pt; slider auto-extends via `TypographySettings.fontSizeRange`.
- [x] Clamp on set/init/decode keeps existing values valid; no persistence migration needed.
- [x] AZW3/Foliate path's own 8...72 sanitizer passes 64 through; explicit regression test added.
- [x] No other clamp/cap on 32 exists in production code (audited).
- [ ] Cross-format perceptual calibration — OUT OF SCOPE, feature-class follow-up.

## Files OUT of scope

- `vreader/Views/Reader/EPUBReaderContainerView.swift` — passes `typography.fontSize` to `epubOverrideCSS`; no change needed.
- `vreader/Services/Foliate/FoliateStyleMapper.swift` — has its own 8...72 sanitizer; 64 passes through.
- PDF / TXT / MD renderers — no app-side 32 clamp; renderer-native font size handling.
- Cross-format perceptual normalization layer — feature-class, deferred.
