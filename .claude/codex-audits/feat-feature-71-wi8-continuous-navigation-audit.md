---
branch: feat/feature-71-wi8-continuous-navigation
threadId: 019e6873-1d00-7451-a429-fa3c90be0996
rounds: 3
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-8 (continuous-mode navigation)

Gate-4 implementation audit for in-reader TOC / bookmark / search navigation in
EPUB continuous-scroll mode. New surface:

- `EPUBContinuousScrollCoordinator.navigate(toSpineIndex:fraction:) async -> Bool`
  — in-window scroll + re-anchor, or out-of-window atomic clear-and-insert
  rebuild around the target.
- `EPUBContinuousScrollJS.clearAllAndInsertSectionJS(_:dividerTitle:)` — one
  transactional eval that `replaceChildren()`s the root and inserts the target
  anchor section (DOM is never left empty under a stale window).
- `EPUBReaderContainerView` `.readerNavigateToLocator` handler routes through the
  coordinator in continuous mode; updates `viewModel` position only on a `true`
  navigate result.
- `EPUBSpineWindow.spineCount` `private let` → `private(set) var` (rebuild support).

Files audited:
`vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift`,
`EPUBContinuousScrollJS.swift`, `EPUBReaderContainerView.swift`,
`EPUBSpineWindow.swift`,
`vreaderTests/Views/Reader/EPUBContinuousScrollCoordinatorTests.swift`.

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollCoordinator (navigate) | Critical | `navigate` shared the `isExtending` mutation lane with boundary-driven `extend`, but did not itself participate in single-flight — a navigate concurrent with an extend (or another navigate) could interleave DOM ops. | Fixed — out-of-window path claims `isExtending` for the whole rebuild; inner `extend` save/restores it. |
| EPUBContinuousScrollCoordinator (navigate in-window) | High | Re-anchored the eviction window before confirming the scroll eval succeeded — a failed scroll left the anchor pointing where the reader didn't go. | Fixed — re-anchor only AFTER a successful `evaluate`, inside the `do` success path. |
| EPUBContinuousScrollCoordinator (eviction) | High | Remove/eviction eval failure was ignored, so a window could be published as if the far side were evicted when the DOM still held it. | Fixed — eviction failure is logged and the window publish is gated on the eval. |
| EPUBContinuousScrollCoordinator (rebuild order) | High | Window was published before the anchor section was appended to the DOM, exposing a window state with no backing DOM. | Fixed — commit the rebuilt window AFTER the anchor insert eval. |

## Round 2 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollCoordinator (materializeInitialWindow) | Critical | Initial materialize did not own the mutation lane, so a navigate arriving while the initial anchor provider was suspended could interleave over the half-built initial DOM. | Fixed — `materializeInitialWindow` guards `!isExtending` and holds the lane across provider + append + fill. |
| EPUBReaderContainerView (nav handler) | High | Container updated `viewModel` position before the coordinator confirmed the jump, so a dropped navigate still moved the persisted position. | Fixed — `viewModel.navigateToSpine` is called only inside `if await coordinator.navigate(...)`. |
| EPUBContinuousScrollCoordinator (out-of-window) | High | Cleared the old sections before fetching the target body, so a provider failure left the DOM empty under a stale window. | Fixed — fetch the target body FIRST; the atomic `clearAllAndInsertSectionJS` only runs once the body is in hand. |

## Round 3 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollCoordinator:195 | High | In-window `navigate` was still not serialized — it never set `isExtending`, so two rapid in-window jumps both passed `guard !isExtending`, and a boundary signal could run during an in-window scroll eval. | Fixed — moved `isExtending = true` / `defer { isExtending = false }` to the TOP of `navigate`, holding the lane for the whole method (in-window scroll AND out-of-window rebuild). Added `navigate_rapidDoubleInWindow_secondIsDropped` test with a gated evaluator (`beforeEvaluate` async hook). |
| EPUBContinuousScrollCoordinator:243 | Medium | Out-of-window `navigate` returned `true` after `fillNeighboursAndScroll(...)` without checking whether the generation changed during the neighbour fill — a mode-switch/reopen mid-fill would still report success and update the position from a stale task. | Fixed — added `guard gen == generation else { return false }` after `fillNeighboursAndScroll`, before `return true`. |

## Round-3 verification (codex-reply)

> "Clean on this pass. No remaining Critical/High/Medium findings from the
> round-3 changes. Confirmed: in-window `navigate` now holds `isExtending` for
> the whole method … out-of-window `navigate` still preserves the lane through
> `fillNeighboursAndScroll`; nested `extend` save/restores keep the flag held.
> Final `guard gen == generation` after neighbor fill closes the stale-success
> return. The container only updates `viewModel` after `navigate` returns
> `true`. I don't see a new consistency issue from the restructure."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after 3 rounds. The coordinator is
`@MainActor`, so `isExtending` is a cooperative single-flight gate across `await`
suspension points (no true preemption); navigate now holds it for its whole body.
25 coordinator unit tests pass (incl. the new gated rapid-double test); full
`vreaderTests` suite green (7293 tests).

### Verification note (Gate 5)

This is a behavioral WI, but the user-facing surface (TOC / bookmark / search
jump in continuous mode) is harness-gapped for CU-free device verification:

- Continuous mode is flag-gated dark (`FeatureFlags.epubContinuousScroll`
  default false), reachable only with the persisted override on.
- No DebugBridge command drives a TOC tap / bookmark jump / search-result tap
  (same class as the verify-skill "no search-driver DebugBridge command" gap).
- The `mini-epub3.epub` fixture has 2 chapters — both fit the initial ±1 window,
  so the out-of-window rebuild branch cannot be exercised end-to-end.

The logic is covered comprehensively by the 25 coordinator unit tests
(in-window scroll+reanchor, out-of-window atomic clear+rebuild [6,8], out-of-range
no-op, while-extending drop, during-initial-materialize drop, rapid-double-in-window
drop, stale-generation guards). Final feature acceptance (flag flip to default +
full TOC/bookmark/search acceptance pass) remains the terminal WI-8 step, pending
a TOC-driver harness or CU verification.
