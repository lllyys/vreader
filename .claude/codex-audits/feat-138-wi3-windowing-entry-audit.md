---
branch: feat/138-wi3-windowing-entry
threadId: 019f63f5-2556-71c0-b3c4-2a07bd091205
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #138 WI-3 (Android TxtPaginator windowing entry points + seal discipline)

- **Auditor**: Codex (`gpt-5.5`, reasoning effort high), read-only sandbox, via `scripts/run-codex.sh` (rule 53).
- **Thread / session**: `019f63f5-2556-71c0-b3c4-2a07bd091205`
- **Scope**: the WI-3 diff on `feat/138-wi3-windowing-entry` —
  `android/app/src/main/kotlin/com/vreader/app/reader/paged/TxtPaginator.kt`
  (companion window constants + per-line cancellation check) and the new
  `android/app/src/test/kotlin/com/vreader/app/reader/paged/TxtPaginatorWindowingTest.kt`.
- **Prompt focus**: byte-identical incremental-vs-`index()` equivalence; seal discipline
  correctness (successor-known seal, final page at doc end, +1 lookahead); off-by-one at
  chunk/window boundaries; min-one-line forward progress; cursor immutability; cancellation gaps.

## Verdict

**ship-as-is** — all three findings from round 1 were fixed in-round (2 code/test hardening, 1
test-correctness bug). The auditor's concluding note confirms the sealed-page model is conceptually
correct ("emitted starts are the previous page once the successor start is known, the frontier is
the pending successor start, and the final page seals at doc end").

## Findings (round 1) + resolutions

### 1. High — `measurePages(K)` is a lower-bound target, not an exact cap (test overstated the contract)

`measureFrom` checks its `bound()` only at CHUNK boundaries (after `nextChunk++`), so a single runaway
(no-newline) chunk carrying many measured page breaks can seal MORE than `K` in one step. This is the
documented WI-1 `measureFrom` behavior ("seals AT LEAST enough … stops at the next chunk boundary …
never over-seals in a way that changes the page-start SEQUENCE"). The original WI-3 test
`measurePagesK_…` asserted EXACTLY K, masked by newline-per-row fixtures (1 line/chunk).

**Resolution (test + doc, not a code change — the code is correct):**
- Renamed the exact-K test to `measurePagesK_oneLinePerChunk_sealsExactlyKPages_frontierEqualsKthEnd`,
  making its 1-line-per-chunk precondition explicit (where exact-K legitimately holds).
- Added `measurePagesK_isLowerBound_notExactCap_forRunawayChunk`: a single 3000-char no-newline chunk
  proves `measurePages(1)` over-seals past K, AND that the over-sealed prefix is still byte-identical
  to `index()` (the SEQUENCE / append-equivalence property is unaffected — only the pause point moves).
- Clarified the `DEFAULT_INITIAL_WINDOW_PAGES` / `DEFAULT_EXTEND_PAGES` KDoc to state they are
  LOWER-BOUND targets, not exact caps.
- Annotated `measureThroughOffset_sealsExactlyEnoughToCoverX`'s tight `<= tp + 2` bound as relying on
  the 1-line-per-chunk fixture; coverage + `pageContaining(X)` exactness hold regardless.

### 2. High — cancellation could miss stale emits inside a chunk

`checkCancelled` / `ensureActive` were only per-CHUNK (before measuring). A cancel arriving while
iterating a large chunk's lines could still emit that chunk's remaining page starts before the loop
ended — a real gap for WI-4's supersede path.

**Resolution (code fix):** added a per-line `checkCancelled(token)` + `currentCoroutineContext().ensureActive()`
at the top of the `for (line in lines)` loop, BEFORE any `tryStartPage`/`emit`. A cancel now aborts
before the next stale emit. Added `cancellation_midChunk_stopsFurtherStaleEmits` (cancels inside the
emit callback after the first seal on a runaway one-chunk doc; asserts the abort throws with a bounded
emit count `< pageCount`). The prior `cancellation_abortsResumablePassMidLoop` (cancel-before-call)
is retained.

### 3. Medium — Markdown append-equivalence compared an MD drive against a TXT `index()`

The scenario matrix includes `isMarkdown = true` (`md-bullet-narrow`), but the `p.index(...)` calls in
the append-equivalence tests omitted `s.isMarkdown`, so the MD drive was compared to a TXT index (MD
strips `-`/`#` markers → potentially different starts) — a false-pass / wrong-reason risk.

**Resolution (test fix):** passed `s.isMarkdown` to every `p.index(...)` call in
`appendEquivalence_onePageAtATime`, `appendEquivalence_variedWindowSizes`, and
`finalPage_sealsAtDocEnd`, so an MD scenario now compares MD-drive vs MD-index.

## RED evidence (TDD discipline)

Before GREEN, the seal-emit was deliberately broken (`emit(candidate)` — the pending successor start —
instead of the sealed `emit(currentPageStart)`). The suite went RED on 6 tests including
`sealingPage0_…`, `sealedInvariant_…`, `measurePagesK_…`, and both min-one-line boundary tests. The
break was reverted; the append-equivalence test was additionally hardened (assert `collected[0] == 0`
+ strictly-increasing seals) so the exact off-by-one shift is caught by that test too.

## Test result

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --tests
'com.vreader.app.reader.paged.*'`: 107 paged JVM tests, 0 failures (14 new WI-3 windowing tests + the
43+ existing regression guard, all green). `renderPage(...)` and `index(...)` behavior unchanged.

## Files audited

- `android/app/src/main/kotlin/com/vreader/app/reader/paged/TxtPaginator.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/paged/TxtPaginatorWindowingTest.kt`
