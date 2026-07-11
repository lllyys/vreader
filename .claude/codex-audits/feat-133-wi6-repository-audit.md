---
branch: feat/133-wi6-repository
threadId: 019f5320-1375-78f1-98d6-46177b6dcebc, 019f5323-7578-74a2-93b8-97b47a8d1e67
rounds: 2
final_verdict: ship-as-is
date: 2026-07-12
---

# Gate-4 audit — feature #133 WI-6 (InBookSearchRepository, the format-dispatch integrator)

Independent Codex audit (`scripts/run-codex.sh`, gpt-5.6-sol, read-only sandbox) of the WI-6 diff —
the format-dispatching in-book search repository unifying WI-1..WI-5. Two rounds; clean at round 2.

## Round 1 — verdict: block-recommended (1 High, 2 Medium)

Session `019f5320-1375-78f1-98d6-46177b6dcebc`.

1. **High — same-book EPUB query swap leaked the prior query's Readium iterator.** A fresh
   null-cursor EPUB request called `searchFirstPage()` without closing live cursors held for a prior
   query on the SAME book (`engineFor()` only closed cursors on a book CHANGE), so replacing query A
   with B on one open publication (the WI-8 flatMapLatest pattern) leaked A's iterator.
   → **Fixed:** `epubPage` now calls `closeAllEpubCursors()` on every fresh null-cursor request before
   `searchFirstPage()`. Regression tests `epub_sameBookNewQuery_closesPreviousQueryIterator` +
   `epub_closeAllEpubCursors_disposesHeldIterator`.

2. **Medium — an all-unresolvable resolver slice returned NoResults and discarded a valid
   continuation cursor.** When `resolver.resolve(...)` returned null for every occurrence in a slice,
   `hits` was empty and the final `hits.isEmpty()` returned `NoResults`, discarding a `nextCursor`
   that had established a valid continuation — so `moreAvailable` went false before whole-book
   exhaustion and later resolvable occurrences were lost.
   → **Fixed:** `NoResults` is returned ONLY when `hits.isEmpty() && nextCursor == null`; a continuable
   slice keeps its cursor and paging proceeds. Regression test
   `txt_sliceAllUnresolvable_keepsPaging_notPrematureNoResults`.

3. **Medium — the cancellation test cancelled during the DAO call, not during expansion.** It proved
   ordinary suspend-point cancellation (`gate.await()`), not the repository's explicit expansion-loop
   `ensureActive()`.
   → **Fixed:** `cancellation_midExpansion_stopsBeforeNextOccurrence` blocks INSIDE the per-occurrence
   expansion via a gated resolver on `Dispatchers.Default`, cancels after occurrence #1 begins, and
   asserts `resolvedCount == 1` — the expansion-body check stops before resolving occurrence #2.

## Round 2 — verdict: ship-as-is (No findings)

Session `019f5323-7578-74a2-93b8-97b47a8d1e67`. All three round-1 findings verified resolved. Re-checks
confirmed: no EPUB/FTS cross-wiring; resume-within-chunk union-completeness (inclusive re-fetch +
occurrence index → ordered, gapless, duplicate-free); MATCH-safety (only `SearchQueryBuilder`'s
sanitized MATCH string reaches the DAO; blank / operator-only → no DAO call); constructor-injected
dispatcher wrapping all repository work; no new findings.

## Test evidence

Full `:app:testDebugUnitTest` green at the audited HEAD — **968 tests, 0 failures, 0 errors**; the
targeted `InBookSearchRepositoryTest` = 15 cases (EPUB delegate/adapt/unsupported/no-results/overflow
completeness/same-book-swap-close/close-all; TXT/MD group-by-Section + multi-hit-chunk expansion +
cursor advance + resume-within-chunk completeness + more-available-only-at-exhaustion +
blank/special-only-no-DAO + MATCH-safety + all-unresolvable continuation + mid-expansion cancellation).
