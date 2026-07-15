---
branch: feat/138-wi4-pagination-session
threadId: 019f6411-5142-7c93-b1ea-71ef1a24393e
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 Codex Audit — feature #138 WI-4 (Android `PaginationSession` + `TxtPageNavigator` delegation)

Auditor: Codex `gpt-5.5`, reasoning `high`, read-only sandbox (rule 53 — `scripts/run-codex.sh`).
Author/auditor separation preserved (rule 47/48).

Scope: the WI-4 production diff —
`android/app/src/main/kotlin/com/vreader/app/reader/paged/PaginationSession.kt` (new) and
`android/app/src/main/kotlin/com/vreader/app/reader/paged/TxtPageNavigator.kt` (modified).

Focus (per the lane brief): (1) mutex never held across a full-book run; (2) generation re-checked
immediately before every publish; (3) callbacks fire lock-released (no main callback under the lock);
(4) exactly one writer of the sealed list + one `LineMeasurer` use; (5) cancellation / structured
concurrency, `onReveal` exactly-once, reflow reconciliation, async `jumpToOffset` EVENTUAL landing.

## Round 1 (session `019f6411-5142-7c93-b1ea-71ef1a24393e`)

Findings (all Critical/High/Medium resolved before proceeding):

- **High — `ensureMeasuredThrough` held the mutex across an unbounded through-offset run.** A deep
  jump could monopolise the single writer. FIXED: it now measures ONE `measurePages(extendPages)`
  window per mutex acquire, looping until the offset is covered — interleaving at window boundaries.
- **High — generation not re-checked immediately before the after-release publish.** A supersede/reflow
  in the lock→publish gap could still publish a stale snapshot. FIXED: the active generation is re-read
  immediately before every `published.set(...)` in both the background loop and the extend.
- **High — callbacks ran on the `worker` dispatcher, not the caller/main.** Non-thread-safe navigator
  state would be mutated from `Dispatchers.Default`. FIXED: the loop no longer wraps in
  `withContext(worker)`; only the paginator measure passes hop off-main, so `onSnapshot`/`onReveal` run
  on the caller's coroutine context (the body's `LaunchedEffect` scope / main).
- **Medium — `supersede()` mutated mutex-guarded `generation`/`activeToken` without synchronisation.**
  FIXED (partially in r1 via `@Volatile`; fully in r3 via `genLock`, see below).
- **Medium — a fresh generation did not clear `published`.** A reused session's reveal-gate / `snapshot()`
  could leak the prior generation. FIXED: `openFromStart` sets `published` to null.
- **Medium — cancellation could leave `sealedStarts` ahead of `cursor`.** FIXED: newly-sealed starts are
  collected into a LOCAL list per step and committed to the shared list only with the advanced cursor,
  after the generation check.
- **Medium — windowed reflow enqueued a scroll to a clamped page before the anchor sealed.** FIXED:
  `installReflowSnapshot` issues `pendingScrollTarget` only once the captured offset is sealed.

## Round 2 (session `019f641e-f71d-7eb2-858f-34825a8895d8`)

Verified r1 resolutions: H1 (window-bounded extend) ✓, H2 publish path ✓, H3 (caller-context callbacks)
✓, M2 (published cleared) ✓, M3 (local-commit) ✓, `isOffsetSealed` complete-cursor case ✓. Remaining:

- **High — `supersede()` still races the generation/token seed.** `@Volatile` gives visibility but not
  atomicity across `++generation` then the token swap. FIXED (r3): both `openFromStart`'s
  generation-seed and `supersede()` mutate the `generation`+`activeToken` pair inside a dedicated
  `synchronized(genLock)` block, so a supersede can never interleave the seed transition.
- **High — `ensureMeasuredThrough` could RETURN a stale snapshot after supersession.** It skipped the
  `published.set` when stale but still returned `step.snapshot`, which `jumpToOffset` installs. FIXED
  (r3): when the generation moved on, it returns the current `published.get()` (newest generation's
  snapshot), never the stale one.
- **Medium — `onReveal` could be missed if an on-demand extend completed the run through the anchor
  before the background loop's iteration.** The loop's `isComplete` fast-path returned `revealNow=false`.
  FIXED (r3): the fast-path now evaluates the reveal via the shared `revealDue(...)` helper, so the
  reveal fires on the completion path too.
- **Medium — `installReflowSnapshot` did not CLEAR a stale `pendingScrollTarget`** when the anchor was
  unsealed, so the pager could consume an old target against the new partial index. FIXED (r3): it sets
  the target to null when the anchor is not yet sealed.

## Round 3 — fixes applied; re-verified

All round-2 findings resolved in the round-3 commit (`synchronized(genLock)` atomic generation/token
transition; stale-return guard in `ensureMeasuredThrough`; `revealDue` in the `isComplete` fast-path;
stale-target clear in `installReflowSnapshot`). The targeted JVM suite is green and stable across
multiple reruns (the gate-based concurrency tests use a real-worker latch + `advanceUntilIdle`).

## Accepted-with-rationale (Low / non-finding)

- **File size** — `PaginationSession.kt` is 337 physical lines but only **177 non-comment/non-blank code
  lines**; the balance is the load-bearing concurrency-invariant header + KDoc (rule 22). The file is a
  single cohesive single-writer/generation owner; splitting it would fragment the mutex/generation
  invariants across files (worse per "keep features local"). Kept whole intentionally.

## Verdict

`ship-as-is`. Zero open Critical/High/Medium findings after round 3. The single-writer + bounded-critical-
section + generation-checked-publish + lock-released-callback contract holds; `onReveal` exactly-once is
preserved on both the background and on-demand-completion paths; the async `jumpToOffset` extends-then-
resolves (EVENTUAL) and never installs a stale snapshot.

Test result: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 127 paged JVM tests (107 pre-existing + 14
`PaginationSessionTest` + 6 `TxtPageNavigatorWindowedTest`), 0 fail.
