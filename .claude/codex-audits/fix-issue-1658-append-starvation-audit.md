---
branch: fix/issue-1658-append-starvation
threadId: 019eb520-3dcc-70b2-a8e2-6940cadef3dd
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — Bug #347 (forward-append starvation under the round-4 gesture ceiling)

Sessions: r1 `019eb51b-6947-7b23-9863-cd101f293dc8`, r2
`019eb520-3dcc-70b2-a8e2-6940cadef3dd`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `EPUBContinuousScrollEvictionGuardTests.swift:357` — the drain test under-asserted ("<= 4", one-chapter overage): a partial drain would pass and re-starve the next fling chain | Medium | FIXED (9b5e4e64): tightened to `== maxSpan`; NEW `settleAfterHardCapGrowth_drainsTheWholeBacklog` grows to the hard cap and asserts the FIRST settled signal drains the entire backlog (exact span + every eviction run) |
| the tracker row pinned the removed soft-ceiling log line | Low | FIXED: the FIXED narrative references the new log lines |

Round 1 verified clean: the hard cap bounds growth; the settle drain loop
has no per-signal cap (full catch-up to targetSpan); dual-boundary echo
suppression intact; no other `touchGrowthCeilingSlack` consumers.

## Round 2 — clean

"The strengthened test now matches the actual contract instead of
under-asserting it… I didn't find a new regression in the coordinator
path." VERDICT: clean.

## Summary

2 rounds, 2 findings (1 Medium, 1 Low), fixed.
`EPUBContinuousScrollEvictionGuardTests` (incl. 3 new #347 tests) +
`EPUBContinuousScrollObserverJSTests` green. Ship as-is.

Close-gate note: the user's repro (chained flings with <160ms inter-fling
gaps) is physically unreproducible via idb — process-spawn latency between
idb commands exceeds the settle window, so every scripted sequence settles
between flings. The deterministic suite drives the REAL coordinator with
the exact never-settling signal shape (verification-exception class); a
device pan sweep covers the no-regression smoke.
