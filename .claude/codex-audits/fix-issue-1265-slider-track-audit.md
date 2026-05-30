---
branch: fix/issue-1265-slider-track
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Manual audit — Bug #285 / GH #1265 slider-track facet (#1273 design)

Design-PROVIDED token wiring (exact values from the landed #1273 bundle); manual.

## Manual Audit Evidence

- **Files read**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/slider-track-rail.md`
  (the binding design — exact per-theme `sliderTrack` values + derivation), `ReaderThemeV2`
  (token pattern: per-theme `hex(r,g,b,alpha)`), `SettingsSliderRow.trackColor` (the inline
  `isDark ? white@0.1 : black@0.1` rail being replaced).
- **Change**: added `ReaderThemeV2.sliderTrack` with the design's EXACT values (paper/sepia =
  ink@0.22, dark/oled = ink@0.12; photo = ink@0.12 dark-family weight — photo isn't a cream-panel
  theme, not in the bug); replaced the inline rail expression with `Color(theme.sliderTrack)`.
  Not self-designed — the design specifies every value (Rule 51 satisfied via the committed bundle).
- **Edge cases**: state-independent token (default/dragging/min/max — design §4); dark family
  unchanged (no regression — verified by the existing `darkFamilyPaletteStillResolvesTokens`);
  photo gets the dark-family weight.
- **Risks accepted**: the rail clears ~1.6:1 not 3:1 — a deliberate design call (the fill+thumb
  carry WCAG 1.4.11; the rail is decorative extent). Documented in the design note.
- **Tests**: `sliderRailReadsOverCreamPanel` (≥1.5:1 + a real lift over the old black@0.1),
  `sliderTrackMatchesDesignDerivation` (pins ink@22%/ink@12%).
- **NOT covered (design-blocked)**: the secondary-text-to-AA facet of #285 (the `sub` token reads
  ~3.4–3.8:1, below 4.5) is a design-system token decision — filed as a separate `needs-design`.

## Verdict: ship-as-is (slider-track facet).
