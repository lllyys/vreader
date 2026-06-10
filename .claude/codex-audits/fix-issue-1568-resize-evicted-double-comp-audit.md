---
branch: fix/issue-1568-resize-evicted-double-comp
threadId: 019eb1ae-eaa6-72c1-b085-9878db701a8f
rounds: 1
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 mini-audit — Bug #329 round-3 follow-up (evicted-section resize double-compensation)

Follow-up to the round-3 audit (`019eb187`). The post-merge 1px re-close sweep
through the LONG image-bearing chapters (spine 7→11) caught 5 residual backward
jumps: scrollTop crashing toward 0 at multi-evict moments (11308→278, 6523→1),
then a backward-extend flash. Root cause: an EVICTED section fires a terminal
zero-size ResizeObserver entry; its detached `offsetTop` reads 0, passing the
above-viewport check → its height subtracted a SECOND time on top of
`removeChapterSectionJS`'s own compensation.

Fix: `if (!el.isConnected) { continue; }` as the first line of the RO callback.

## Verdict — ship-as-is, no findings

Codex confirmed: (1) the guard closes the only eviction-time compensation path;
(2) skipping WeakMap bookkeeping for disconnected elements is correct (identity-
keyed, GC reclaims); (3) live shrink/growth compensation preserved; (4) the
batched-entry ordering hazard (connected at observe, disconnected at delivery)
is covered — connection is checked at delivery time, the only dangerous moment.

Device re-sweep of the failing region (spine 7→11, 12166 ticks): 0 jumps,
0 stalls, 0 thrash.
