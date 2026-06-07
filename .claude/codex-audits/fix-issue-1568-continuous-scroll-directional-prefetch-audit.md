---
branch: fix/issue-1568-continuous-scroll-directional-prefetch
threadId: 019ea219-e6bc-75f0-a01c-c6baf7b832c8
rounds: 1
final_verdict: ship-as-is
date: 2026-06-07
---

# Codex audit — Bug #329 / GH #1568 directional prefetch

Fix: `EPUBContinuousScrollCoordinator.handleBoundarySignal` now prefetches only in
the reader's direction of travel (sticky `scrollBias` from the
`visibleSpineIndex + intraFraction` delta), so the spurious post-eviction
`nearTop` no longer reloads the just-evicted section (the evict→reload window
oscillation behind Bug #329).

## Scope
- `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` — `lastProgress` +
  sticky `scrollBias` state, directional gating in `handleBoundarySignal`,
  `invalidate()` reset.
- tests: `EPUBContinuousScrollCoordinatorTests` — 4 new directional tests.

## Findings

**No findings.** Codex confirmed:
- The sticky bias correctly suppresses the spurious post-eviction reload: a forward
  extend's false `nearTop` only triggers a backward prepend if progress drops by
  `> directionEpsilon`; when the eviction merely shifts `scrollTop`,
  `visibleSpineIndex + intraFraction` stays flat → the `.forward` bias blocks it.
- No reversal wedge: the bias flips as soon as progress moves the other way by
  `> 0.0005` (a tiny movement for normal sections); worst case is a brief delay,
  not a deadlock.
- The initial dual-side fill is preserved (`.none` → both directions on the first
  signal).
- The #1561 / Bug #327 directional eviction (`evictTrailing`) is untouched.
- `@MainActor` isolation is sound — `lastProgress` / `scrollBias` stay actor-isolated
  across the async suspension points.
- Stationary-keeps-bias is exactly the "eviction moved scrollTop, not the reader"
  case to treat as non-direction-changing.

## Device verification (honest)
The 37-test coordinator suite passes. On-device fine-grained scroll (60px steps,
DebugBridge) of real EPUB "The Half Second": the fix **eliminates the window
thrash + hard-stall** — the window now progresses (`[1,4]`, `dTop=60` throughout)
where the pre-fix build hard-stalled at `[1,3]` (`dTop=0`). A residual scrollTop
sawtooth remains under DISCRETE-STEP eval driving (each 0.4s-gap read races the
async extend/evict); Codex's static analysis + the continuous idb-swipe result
(window reached `[7,9]`) indicate this is a driving artifact, so real-finger
smoothness is to be confirmed on a physical-display device
(awaiting-device-verification).

## Verdict
**ship-as-is.** Logic confirmed correct + 37 tests green; the primary #329
mechanism (bidirectional prefetch reloading evicted sections → window thrash +
hard-stall) is resolved.
