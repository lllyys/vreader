---
branch: feat/feature-74-wi1-locate-bloom-renderlayer
threadId: codex-exec (run-codex.sh)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #74 WI-1: locate-bloom render layer (Gate 4)

## Implementation summary

The foundational, dormant render layer for the highlight-landing "locate bloom"
(design `reader-highlight-landing.md`). `HighlightingLayoutManager` gains a
`landingHighlight` (range + color + intensity + theme family) painted as a
SEPARATE layer that REPLACES (not stacks on) the equal-range persisted fill — the
design's single wash value-lift, defeating the dedup no-op. A pure
`LandingBloomPaint` helper maps `(intensity, family)` → wash alpha (lerp
`fillAlpha`→0.86), ring (1.6), glow (16), glow alpha (0.55 light / 0.85 dark), and
`suppressesPersisted` decides the equal-range replacement. `HighlightableTextView`
gets `setLandingHighlight` / `clearLandingHighlight`. Nothing SETS the layer in
WI-1 → dormant, no user-visible delta → foundational tier, no device verification.

Plan: `dev-docs/plans/20260603-feature-74-locate-bloom.md` (Gate-2, 3 rounds,
READY TO BUILD).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| LandingBloomPaintTests.swift | Medium | The 6 tests only exercise the pure `LandingBloomPaint` math; none prove the real render-layer contract on `HighlightableTextView` (landing state stored/cleared, suppression honored through the layout-manager). A WI-1 code-path regression could ship while the math tests pass. | **Fixed.** Added `HighlightableTextViewLandingTests` (3): `setLandingHighlight` stores the layer on the layout manager (range/color/intensity/family), `clearLandingHighlight` tears it down, a fresh view has no layer (dormant). |

Codex confirmed correct by inspection: the equal-range persisted fill is REPLACED
not stacked; the wash uses the lifted alpha and ring/glow are gated on
`ringWidth > 0` inside `saveGState`/`restoreGState` (no state leak); WI-1 is
dormant (nothing calls the new APIs); the `fill(for:)` refactor onto
`solidSwatch` is output-identical to the prior implementation.

## Verdict

`ship-as-is` — zero open Critical/High/Medium after the test-coverage fix.

## Verification

- Unit: `LandingBloomPaintTests` (6 — rest source-alpha, peak, mid lerp, glow
  light/dark, clamp, suppression) + `HighlightableTextViewLandingTests` (3 —
  set/clear/dormant render-layer contract).
- Device: **none required** — WI-1 is foundational/dormant (no trigger sets the
  layer; no user-visible change). The visible bloom + its themes are verified in
  WI-2 (animation + trigger).
