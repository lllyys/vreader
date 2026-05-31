---
branch: feat/feature-75-wi3-pageaxis-probe
threadId: codex-exec-readonly
rounds: 3
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Feature #75 WI-3 (pre-pagination page-axis probe)

Read-only `codex exec` audit, 3 rounds. Behavioral WI.

## Summary

`setupPagination` now evaluates `EPUBPageAxisProbe.computedStyleJS` FIRST (before
injecting pagination CSS), resolves the per-document `PageAxis` (hint `.auto`),
stores `coordinator.currentPageAxis`, then a new `paginate()` injects CSS +
counts pages + navigates using that axis. `updateUIView`'s page-nav also reads
`currentPageAxis`. New `EPUBPageAxisProbe` (JS + JSON parse + resolve) is pure +
unit-tested.

## Round 1 (High)

- The async probe→paginate chain wasn't scoped to the load generation — a chapter
  change mid-chain could write the wrong axis / publish a wrong page count. Fixed:
  monotonic `paginationGeneration` incremented per `setupPagination`; the probe
  callback + the totalPages hops guard `== generation`.

## Round 2 (High + Medium)

- `onPaginationReady` Task and the pending-nav eval still ran unguarded. Fixed:
  the `Task { @MainActor }` re-checks the generation before `onPaginationReady`;
  the pending nav is gated by `if paginationGeneration == generation` immediately
  before the eval.

## Round 3 (Medium — ACCEPTED with rationale)

- Once `evaluateJavaScript(injectJS)` is dispatched, a newer `setupPagination`
  could start before that JS runs, so the stale CSS could momentarily inject.
  **Accepted**: `injectPaginationCSSJS` removes-and-replaces the
  `#vreader-pagination` style element by id, so the newer generation's injection
  overwrites any stale one — the END-STATE CSS is always the latest generation's.
  The only effect is a sub-frame transient if two chapter loads race within the
  eval latency; the guarded completion (totalPages/onPaginationReady/nav) of the
  stale chain still bails, so no wrong page count / nav. No page-side token added
  — the cost (a JS contract token round-trip) exceeds the benefit for a
  self-correcting transient.

## Verdict

ship-as-is. LTR is behaviorally unchanged (axis defaults LTR → byte-identical CSS
+ positive offsets; probe failure falls back through `.auto` to LTR). Tests:
`EPUBPageAxisProbeTests` (resolve + robustness) green; EPUB bridge suite green.
The visual RTL/vertical rendering is device-verified at the WI-5/WI-6 acceptance
gate (binding per the plan) — this WI delivers the probe + axis plumbing.
