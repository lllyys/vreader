---
branch: fix/feature-71-wi8-deterministic-outofwindow-scroll
threadId: 019e68c7-9daa-76a1-b734-47449cefc0b4
rounds: 1
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-8 polish (deterministic out-of-window scroll at fraction 0)

Gate-4 audit for the fix that closes the 77px in-window/out-of-window landing
inconsistency found in WI-8 device verification.

## Problem

Out-of-window `navigate(toSpineIndex:fraction:)` with fraction 0 landed ~77px
short of the target chapter's `offsetTop`. `fillNeighboursAndScroll` skipped its
explicit scroll entirely when `fraction == 0` (guard `fraction > 0`); the
out-of-window rebuild prepends the backward neighbour above the anchor, and the
browser's scroll-anchoring then bumps `scrollTop` to keep the anchor visually in
place — landing one safe-area-inset short. The in-window branch always scrolls,
so the two branches landed differently.

## Fix

`fillNeighboursAndScroll` gained `force: Bool = false`; the scroll guard became
`if let fraction = scrollFraction, force || fraction > 0`. The navigate
out-of-window call passes `force: true` (deterministic land-on-anchor even at
fraction 0). `materializeInitialWindow` stays unforced, preserving the
fraction-0/nil restore-to-top semantics (its anchor sits at the document top;
scrolling to `offsetTop` would push the heading under the dynamic island — the
`materializeInitialWindow_zeroRestoreFraction_doesNotScroll` test guards this).

## Round 1 — findings

**No findings (clean).** Codex verbatim: "force=true is scoped to out-of-window
navigate; materializeInitialWindow remains unforced, so fraction 0/nil
restore-to-top semantics are preserved | no fix needed." Confirmed: `force:true`
is only passed from out-of-window navigate (where `fraction` is non-optional);
the `if let` still blocks nil even if force were true; generation guards
unchanged. One optional cosmetic suggestion (reorder `force || fraction > 0`)
applied.

## Verdict

**ship-as-is.** Zero findings.

## Device verification

iPhone 17 Pro Sim, `multi-chapter-epub`, continuous mode:
- Before: out-of-window `navigate?spine=3&fraction=0` → scrollTop 9970, sec3Top
  10047, gap 77.
- After: scrollTop **10047** = sec3Top, **gap 0** (deterministic, matches the
  in-window branch). "Chapter Four — DELTA" heading at viewport y=100/150, its
  paragraphs at y=200/300 — the target chapter fills the viewport.

26 coordinator tests pass incl. the new
`navigate_outOfWindow_fractionZero_stillScrollsToTarget`.
