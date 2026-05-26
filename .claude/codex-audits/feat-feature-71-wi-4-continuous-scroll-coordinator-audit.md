---
branch: feat/feature-71-wi-4-continuous-scroll-coordinator
threadId: 019e62b4-072d-7292-b275-f86057f56e2b
rounds: 2
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Feature #71 WI-4 (EPUBContinuousScrollCoordinator)

Independent Gate-4 audit (Codex MCP, separate process) of WI-4 of feature #71
(EPUB continuous cross-chapter scroll): the `@MainActor` host-side
window-transition coordinator.

Files audited:
- `vreader/Views/Reader/EPUBContinuousScrollCoordinator.swift` (new — WI-4 deliverable)
- `vreader/Views/Reader/EPUBSpineWindow.swift` (added `reanchored(to:)`)
- `vreaderTests/Views/Reader/EPUBContinuousScrollCoordinatorTests.swift` (new)
- `vreaderTests/Views/Reader/EPUBSpineWindowTests.swift` (added `reanchored` tests)

## Round 1 — 1 High + 1 Medium

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | `handle(_:)` re-anchored the shared `window` BEFORE the in-flight guard and before any successful eval. Two consequences: (a) `window`'s anchor mutated on provider/eval failure (contract breach — "window must not advance on failure"); (b) a same-generation duplicate signal arriving mid-flight could change the anchor, and when the first task resumed, `extend*()` + `evictIfNeeded()` ran against the mutated anchor — evicting the just-appended chapter instead of the far end. | **Fixed.** In-flight guard now runs FIRST (a duplicate in-flight signal mutates nothing). Re-anchoring is now a LOCAL snapshot (`let anchored = window.reanchored(to:)`); direction/target are decided from `anchored`; the shared `window` is committed as `anchored.extendForward()/.extendBackward()` ONLY after a successful eval, then eviction runs around that committed anchor. Failed / no-op / blocked signals never mutate `window`. |
| 2 | Medium | Tests missed the highest-risk regression: anchor mutation during a failed or in-flight materialization, and the "evict-eval-failure leaves the window un-trimmed" catalogue item. | **Fixed.** Added 3 behavior tests: `test_evaluatorThrows_anchorAlsoUnchanged` (full-state `window == original` when the signal's visible index differs from the anchor and eval throws), `test_duplicateInFlight_differentVisible_cannotChangeEvictedSide` (gated provider — a duplicate in flight carrying a different visible index cannot flip eviction to the appended side: `removed(0) && !removed(3)`), `test_evictEvalFails_leavesWindowUntrimmed` (`throwOnRemove` — append commits, trim does not). |

Codex confirmed everything else sound in round 1: `EPUBSpineWindow` + its tests
are clean, the generation re-check placement is right, `defer` is safe, and the
eviction-index computation (`(window.lo...window.hi).filter { !trimmed.contains($0) }`)
is correct for contiguous windows.

## Round 2 — clean

Codex re-read the updated files: **both findings resolved, no new issue
introduced.** Specifically confirmed:
- In-flight guard first → duplicate same-generation signals are a true no-op.
- Local re-anchor + commit-only-on-success fixes the failure/no-op contract breach.
- Committing `anchored.extend*()` is safe: under `@MainActor` the only way
  `window` could differ by commit time is a generation-changing
  `bumpGeneration()`/`reset(to:)`, which the post-await `generation == gen`
  checks already catch.
- Dropping the persistent re-anchor on no-op signals is NOT a correctness
  problem — anchor only matters for eviction, which only runs during a
  materialization that recomputes `anchored` from the fresh incoming signal.

## Verification

- Focused unit gate (UDID-pinned iPhone 17 Pro Sim, parallel off):
  `EPUBContinuousScrollCoordinatorTests` (13 tests) + `EPUBSpineWindowTests`
  (25 tests, incl. 5 new `reanchored`) — **0 failures**.

## Verdict

**Ship-as-is.** No open Critical/High/Medium after round 2. WI-4 is pure
host-side decision logic + a pure `EPUBSpineWindow` transition; no live
WKWebView (that is WI-5), no UI (rule 51 N/A).
