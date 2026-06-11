---
branch: fix/issue-1658-round2-scroll-starvation
threadId: 019eb699-bdc1-7cb3-bbf6-430cdc20c5fd
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Bug #347 round 2 — Codex audit

Fix: `EPUBContinuousScrollCoordinator` — hard-cap raise (12→47 slack,
rationale: mid-gesture compensation writers are deferred so the
oscillation storm the cap guarded cannot occur; the cap survives as a
far-out DOM bound), amortized eviction drain (`maxEvictionsPerExtend=2`
— the one-shot settle drain was the user's "jump"), and the gen-guarded
single-slot forward body prefetch (the boundary append becomes one DOM
eval — the fling-speed latency half of the starvation).
Runner: `scripts/run-codex.sh`. Round-2 session: `019eb6a3-c9ee-74c0-9c20-79df282da551`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `invalidate()` left `prefetchInFlightIndex` stale — a reopen could swallow the SAME next chapter's re-schedule for the cancelled provider's whole flight (losing the latency mitigation exactly where it matters) | Medium | **Fixed** — cleared in `invalidate()`; `prefetchInFlightIndexForTesting` seam + a pin asserting the marker clears IMMEDIATELY (before the cancelled task resumes). |

Round 1 explicitly confirmed: no arithmetic regression in the amortized
loop (the budget counter is `candidatePosition`, already the cumulative
index), generation/index guards on the cached body correct, cap-raise
rationale behaviorally consistent (evictions/prepends/resize
compensations all deferred until settle).

## Round 2 (verify)

Clean — the marker clears immediately, the pin is correct, no new issues.

## Verdict

ship-as-is. 61 tests green across the 3 continuous-scroll suites (incl.
the round-2 regression pins: appends continue past the old span-15 cap;
the settle drain is amortized; the prefetch pipeline pre-materializes +
consumes + survives invalidation). Device sweep evidence in the PR.
