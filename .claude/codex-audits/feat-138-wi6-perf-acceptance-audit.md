---
branch: feat/138-wi6-perf-acceptance
threadId: run-codex gpt-5.5/high (2 rounds; logs /tmp/wi6-codex-audit.txt, /tmp/wi6-codex-audit-r2.txt)
rounds: 2
final_verdict: ship-as-is
date: 2026-07-23
---

# Gate-4 audit — feature #138 WI-6 (windowed pagination perf/acceptance test)

Change under audit: extend `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPaginatorPerfBenchmark.kt`
with the two #138 WI-6 acceptance methods (`wi6_openToFirstPage_and_fullIndexParity_14mbCjk`,
`wi6_farJumpTo90Percent_eventuallyLands_recordsLatency`) + `captureShaping`/`Shaping` helpers, driving
`PaginationSession` / `TxtPaginator` / `TxtPageIndex`. Test-only, single file.

Two independent audit streams were run in parallel (per the "deep AND broad" reconciliation rule):

## Stream A — 5-lens adversarial workflow (deep, per-claim)

Workflow `wi6-acceptance-adversarial-review` — 5 Explore-agent skeptics (measurement-honesty,
assertion-tautology, parity-correctness, far-jump-realism, flakiness-threading) + a synthesis pass.
Verdict: **ship-as-is, 0 must-fix**; 12 accepted false-alarms (incl. 3 lenses raising a far-jump
"critical" that the synthesizer correctly refuted); 4 should-fix hardenings. Two zero-flake-risk
hardenings applied pre-Gate-4: a direct `frontier > target` far-jump assertion + tightening the
first-window assert to `>= DEFAULT_INITIAL_WINDOW_PAGES`.

## Stream B — Codex broad audit (gpt-5.5 / high)

### Round 1 — verdict: block-recommended

Codex caught defect classes the per-claim fan-out missed (the value of the broad pass):

- **High-1** — the acceptance methods fell back to `syntheticCjk()` when the real book was absent,
  making the "real 14 MB / 30,695-page" acceptance HOLLOW (the exact page-count assert was skipped
  under `usedReal == false`).
- **High-2** — the test LOGGED `first_page_target_met(<2000ms)` / `pss_target_met(<=300mb)` but only
  ASSERTED the looser `<3000ms` / `<=400MB` ceilings, so a future `first_page_ms=2500` / `pss=380`
  would false-green against the stated target.
- **Medium** — far-jump exactness short-circuited to a vacuous pass when `landed.isComplete`, and did
  not compare the landed page/range against a non-windowed ground-truth `index()`.
- **Low** — the file is now 540+ lines (mixes the #137 dev-benchmark + #138 acceptance).

### Fixes applied

- **High-1 FIXED** — both WI-6 acceptance methods now `requireNotNull(readRealBookOrNull())` (fail
  loudly if the byte-validated real 14 MB book is absent). The SEPARATE #137 dev-benchmark keeps its
  synthetic fallback (CI-safety) — intentional and now cleanly distinguished.
- **High-2 FIXED** — asserts the STATED targets: `firstPageMs < FIRST_PAGE_TARGET_MS` (2000) and
  `peakPssMb <= PSS_TARGET_MB` (300); the 3000ms/400MB ceiling constants were removed. The exact
  `== 30_695` page-count assert is now unconditional (real book required).
- **Medium FIXED** — far-jump now UNCONDITIONALLY asserts `landedStart <= target && target < landedEnd`
  AND compares the landed `page`/`pageStart`/`pageEndExclusive` against a non-windowed ground-truth
  `index()` for the same document (proves EXACT parity for the jumped-to offset).
- **Low ACCEPTED** — rationale: the task directed extending this file; the #137 + #138 methods share
  helpers (`MemorySampler`, `captureShaping`, `runIndex`, `readRealBookOrNull`) that a split would
  duplicate; it is a test file over a soft ~300-line guideline. `renderPage`-style extraction stays a
  named follow-up. (Codex round 2 confirmed the rationale reasonable.)

### Round 2 — verdict: ship-as-is

Codex re-reviewed the current file: High-1, High-2, Medium all confirmed resolved; Low accepted with
reasonable rationale; **no new blocking findings**.

## Verification (connected, emulator-5554, real 14 MB CJK book)

All 3 methods GREEN on the REAL book with the fixed assertions
(`RUN-ANDROID-TESTS RESULT: SUCCEEDED`, 3/3):

```
WI6-SUMMARY  book=real:黑暗血时代.txt pages=30695 first_page_ms=8 first_window_pages=3
  first_page_target_met(<2000ms)=true full_completion_ms=14951 snapshots=15347
  peak_pss_mb=290 peak_used_heap_mb=23 pss_target_met(<=300mb)=true parity_vs_137_index=byte-identical
WI6-FARJUMP  book=real target_offset=6326648 frontier_at_jump=616 extend_ms=13496
  landed_page=27383 landed_range=[6326445,6326655) truth_page=27383 sealed_pages=27385 complete=false
```

Post-run edit: one comment-only correction to the PSS-variance note (276/278/290 across three runs) —
compiled bytecode identical, so the connected GREEN validates the committed behavior.

**Final verdict: ship-as-is.**
