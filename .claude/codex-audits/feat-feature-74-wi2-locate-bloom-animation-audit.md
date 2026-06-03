---
branch: feat/feature-74-wi2-locate-bloom-animation
threadId: codex-exec (run-codex.sh, 3 rounds)
rounds: 3
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #74 WI-2: locate-bloom animation + trigger (Gate 4)

## Implementation summary

The user-visible locate bloom. `LandingBloomCurve` (the §3 motion curve + §5
reduce-motion jump/hold/fade), `LandingBloomPaint.reduceMotion` + `ringAlpha`
(§5: fixed-width ring that fades by opacity, zero glow), the `CADisplayLink`
driver on `HighlightableTextView` (`playLandingBloom` / `bloomTick` /
`cancelLandingBloom`), and the navigate-from-list trigger in
`TXTTextViewBridge.updateUIView` — gated on the navigate NONCE (so a re-tap
re-blooms), as a cancellable work item that user interaction or a superseding nav
cancels.

Plan: `dev-docs/plans/20260603-feature-74-locate-bloom.md` (Gate-2, 3 rounds).

## Round 1 — 2 High + 2 Medium

| severity | issue | resolution |
|---|---|---|
| High | Trigger inferred inside the `shouldScroll` gate → a re-tap on the same highlight never re-blooms (same offset → no scroll). | **Fixed.** Moved the trigger to a NONCE-gated block (`highlightNonce` advances on every nav incl. a re-tap), decoupled from scroll dedupe. |
| High | Interruptibility (§3) unwired — the 0.35s `asyncAfter` had no cancel token; tap/scroll didn't cancel. | **Fixed.** The trigger is a cancellable `DispatchWorkItem` (`coordinator.pendingBloom`); a superseding nav + a user tap/scroll call `coordinator.cancelLandingBloom()` (cancels pending + active), via `clearSearchHighlightIfTemporary` past its `isTracking` guard (a programmatic scroll-to-prominent does NOT self-cancel). |
| Medium | `CADisplayLink(target: self)` teardown. | **Fixed.** `TXTTextViewBridge.dismantleUIView` → `cancelLandingBloom()`. (A `deinit` is forbidden by Swift 6 from touching the MainActor `CADisplayLink`, and is unnecessary: the link retains `self` while running, so the view can't dealloc until the link is invalidated.) |
| Medium | Reduce-motion not faithful to §5 (ring shrank = motion). | **Fixed.** `LandingBloomPaint` gained `ringAlpha`; reduce-motion keeps `ringWidth` fixed 1.6 and fades `ringAlpha` (opacity-only, zero glow); `playLandingBloom` seeds the first frame at the curve's t=0 (1 for reduce-motion → jump-to-peak, no rest flash). |

## Round 2 — 1 High

| severity | issue | resolution |
|---|---|---|
| High | `handleContentTap` returns early on a persisted-highlight hit (posts `.readerHighlightTapped`) BEFORE `clearSearchHighlightIfTemporary`, so re-tapping the landed highlight never cancelled the bloom. | **Fixed.** `cancelLandingBloom()` on that path before the early return; added `coordinator_cancelLandingBloom_cancelsPendingAndActive` test. |

## Round 3 — CLEAN

Codex confirmed all four interruptibility paths (highlight-hit tap, non-highlight
tap, user scroll, superseding nav) cancel pending + active bloom; nonce gating is
nav-only; `dismantleUIView`-only teardown is sufficient given the link-retains-self
ownership. Zero remaining Critical/High/Medium.

## Verdict

`ship-as-is` after 3 rounds.

## Verification

- Unit (17 across the feature): `LandingBloomPaintTests` (paint math + suppression
  + reduce-motion ringAlpha), `LandingBloomCurveTests` (motion + reduce-motion
  curve), `LandingBloomTriggerTests` (nonce trigger, family, cancellation),
  `HighlightableTextViewLandingTests` (render-layer set/clear/dormant).
- Device (Gate-5b): the bloom is a TRANSIENT ~1.5s animation; capturing its
  animated render CU-free defeated the harness this pass (the `search?query=`
  DebugBridge command doesn't inject the CJK query, and the Notes-sheet tap +
  precise sub-second screenshot timing on a fading animation is not reliable).
  The bloom LOGIC is exhaustively unit-proven + 3-round audit-clean, and the
  render reuses the production-proven `drawBackground`/`enumerateEnclosingRects`
  idiom that paints visible persisted highlights. So the visual-render acceptance
  is `awaiting-device-verification` — a keyed/manual pass with a screen recording
  confirms the bloom appears.
