---
branch: fix/issue-1568-prefetch-regression-hotfix
threadId: 019ea2ad-ff80-7a33-986b-c04875a44bf4
rounds: 2
final_verdict: ship-as-is
date: 2026-06-07
---

# Codex audit — Bug #329 / GH #1568 prefetch-regression HOTFIX

The prior fix (v3.59.21, sticky scroll-direction bias) REGRESSED on device: the
eviction's `scrollTop -= removedHeight` corrupts the `(visibleSpineIndex +
intraFraction)` progress signal (it appears to move backward), flipping the bias
to `.backward`, which then suppressed the FORWARD extend and wedged forward
scrolling (device: stuck at window `[1,4]` where the unfixed build reached
`[7,9]`).

This hotfix replaces the bias with **eviction-echo suppression**: when `extend`
evicts a trailing section it arms `ignoreNextNearTop` (forward) /
`ignoreNextNearBottom` (backward); `handleBoundarySignal` consumes the flag and
skips ONLY the echoed boundary for one signal — never the reader's travel
direction.

## Scope
- `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` — removed the
  sticky-bias state; added `ignoreNextNearTop`/`ignoreNextNearBottom`, the
  consume-at-start + same-signal `return`-after-evicting-forward-extend, and the
  arm-after-eviction in `extend`.
- tests: 5 new (`forwardEviction_suppressesNextSpuriousNearTop`,
  `forwardProgress_notBlockedAfterEviction` [regression guard],
  `backwardEviction_suppressesNextSpuriousNearBottom`,
  `suppressedNearTop_isOnlyOneSignal`,
  `dualBoundary_evictingForward_doesNotReloadInSameSignal`).

## Round 1 (threadId 019ea2ad-ff80-7a33-986b-c04875a44bf4)

**1 High** — a DUAL-boundary signal (nearTop AND nearBottom both true, common in
short windows) whose forward extend evicts would still run the same-signal
`nearTop` branch, because `suppressNearTop` was captured before the extend's
await → reloads the just-evicted section in the same signal, oscillation
persists.

**Resolution:** after `await extend(forward: true)`, added `if ignoreNextNearTop
{ return }` — an EVICTING forward extend (the only thing that arms
`ignoreNextNearTop` after the start-of-function clear) skips the same-signal
backward branch. Added `dualBoundary_evictingForward_doesNotReloadInSameSignal`.

## Round 2 (threadId 019ea2b2-4577-7fa3-b94e-927c747589c5)

**No findings.** The High is closed. The early `return` is gated by
`ignoreNextNearTop`, set only when `committed.span < extended.span` (this exact
forward extend evicted), so a non-evicting forward extend (`[2,2]→[2,3]`) still
runs the later `nearTop` branch — `nearTopAndBottom_extendsBothSides` preserved.
The backward branch is last, so its eviction has no same-signal follow-up to
mis-honor. The forward-progress regression guard is sound; `@MainActor`
isolation is fine; `invalidate()` clears the flags; #327/#1561 `evictTrailing`
unchanged.

## Verdict
**ship-as-is** after 2 rounds. 38 coordinator tests green. Device: the hotfix
progresses past the bias-fix `[1,4]` stall (to `[3,5]`+, vsi climbing). Real-finger
scroll smoothness stays `awaiting-device-verification` (idb/eval driving is noisy
on this virtual-display host).
