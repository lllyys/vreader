---
branch: fix/issue-26-search-highlight-timing-race
threadId: 019df7cf-5f3e-7b81-bea7-c99cd4718a4e
rounds: 3
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #99 cause #3 fix (GH #26)

## Round 1 — initial findings

| File | Severity | Issue | Resolution |
|------|----------|-------|------------|
| `TXTTextViewBridge.swift:205` | Medium | Initial fix bumped the timer 0.3s → 1.5s — a fixed-delay heuristic that doesn't track actual scroll settling. Could still race on slower devices / heavier files. | Fixed in Round 2: replaced the timer mechanism entirely with a canonical-signal approach. |
| `TXTTextViewBridgeCoordinator.swift:75` | Medium | The 1.5s widening would block legitimate user dismissals during the entire interval — manual scroll within 1.5s after tapping a result wouldn't dismiss. `handleContentTap` was also affected. | Fixed: `clearSearchHighlightIfTemporary(scrollView:)` now reads `isTracking || isDragging || isDecelerating` from the scroll view; user scrolls fire clear immediately, programmatic-scroll-induced layout callbacks (all three false) skip. |
| `TXTTextViewBridgeTests.swift:100` | Low | Test was constant-pinning theater; didn't exercise behavior. | Fixed in Round 3: added 4 behavior tests covering all branches (idle, isTracking, isDragging, isDecelerating) using a `StubScrollView: UIScrollView` subclass. |
| `TXTTextViewBridge.swift:203` | Low | Comment said "line 145" but actual line was 154-155. | Fixed: removed line-number reference (whole comment block rewritten with the new mechanism). |
| `docs/bugs.md:229` | Low | Tracker rules require an `## Open Bug Detail` entry for IN PROGRESS bugs; #99 had none. | Fixed in Round 3: added detail entry summarizing the three causes and what was fixed. |

## Round 2 — verification re-pass

Replaced the timer-based heuristic with the structural fix Codex recommended:

- Removed `programmaticScrollCount` counter (was Issue 8 successor to bug #43's boolean)
- Removed the `DispatchQueue.main.asyncAfter` timer that decremented the counter
- `clearSearchHighlightIfTemporary` now takes optional `scrollView: UIScrollView? = nil`
- When called with a scroll view: only clears if `isTracking || isDragging || isDecelerating`
- When called with nil (chrome tap, search-clear notification): clears unconditionally

Codex confirmed:
> The structural fix itself is sound. `programmaticScrollCount` and the timer heuristic are gone from production code, `scrollViewDidScroll` now gates clearing on `isTracking || isDragging || isDecelerating`, and non-scroll dismiss paths clear unconditionally, so cause #3 is closed more cleanly than the timer bump.

## Round 3 — clean

Two remaining Lows (positive-path test coverage + Open Bug Detail entry) addressed. Codex verdict: "No findings."

## Final verdict

**ship-as-is** — but bug #99 stays IN PROGRESS and GH #26 stays open, because:

- This PR addresses cause #3 only (programmaticScrollCount timing race in TXTTextViewBridge)
- Cause #1 (chunked-reader cell-becomes-visible race) is documented as a remaining candidate
- Cause #2 (encoding offset mismatch) is documented as a remaining candidate

The structural fix is a strict improvement over both the original 0.3s timer AND my initial 1.5s bump. It uses UIScrollView's canonical user-interaction flags as the signal — no timer, no magic constant, no false-block of legitimate user scrolls. 42 tests pass across 3 affected suites, including 4 new behavior tests covering each branch of the gating logic.
