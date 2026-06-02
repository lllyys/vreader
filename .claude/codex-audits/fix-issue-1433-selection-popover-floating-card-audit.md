---
branch: fix/issue-1433-selection-popover-floating-card
threadId: codex-exec (run-codex.sh)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Bug #317 (GH #1433): selection popover floating card

## Fix summary

The text-selection popover rendered as a system bottom `.sheet` (grabber +
`.presentationDetents` + dimmed backdrop) instead of the designed floating inset
card. Presentation-only fix: `SelectionPopoverPresenterModifier` now presents
`SelectionPopoverView` (which already renders its own rounded-card chrome) as a
floating overlay — a transparent full-screen tap-to-dismiss catcher + the card
inset `left/right 18`, `bottom 100` — matching `vreader-reader.jsx`'s
`SelectionPopover` (`position:absolute; left:18; right:18; bottom:100;
borderRadius:18`). Restore-to-designed → Rule 51 satisfied (no invented UI; the
designed card already exists in the committed `vreader-fidelity-v1` bundle).

Changed file: `vreader/Views/Reader/SelectionPopoverPresenter.swift` only.

## Round 1 — CLEAN

Codex confirmed:
- `onDismiss` fires on every actual close path (outside tap / close button via
  `dismiss()`; action-driven close via `if next == nil { onDismiss?() }`); no
  double-fire; replacing `pending` with a new payload is not a dismissal (the old
  `.sheet(isPresented:)` didn't fire onDismiss there either).
- ZStack ordering: the transparent catcher is below `SelectionPopoverView`, so
  card buttons resolve to the card; outside taps land on the catcher.
- The catcher exists only when `pending != nil` (whole overlay gated), so it
  never traps reader gestures when no popover is shown.
- Safe-area: catcher `.ignoresSafeArea()` for edge-to-edge outside taps; the card
  stays inset 18/100 per the design.
- Rule 51 satisfied — reuses the committed design's card + placement.

## Verdict

`ship-as-is` — zero findings. Presentation-only change; the action-router +
dismiss-policy logic is unchanged and covered by the existing
`SelectionPopoverPresenterTests` / `SelectionPopoverActionRouterTests`. Visual
behavior verified on device (floating card, not a sheet).
