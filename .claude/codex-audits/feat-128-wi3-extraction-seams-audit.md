---
branch: feat/128-wi3-extraction-seams
threadId: 019f4ef8-6e1a-7840-8648-f5f9086b8e8c
rounds: 2
final_verdict: follow-up-recommended
date: 2026-07-11
---

# Gate-4 Codex audit — feature #128 WI-3 (search extraction/normalization seams)

Scope: `git diff origin/main..HEAD` — the six new `search/` files (SearchTextNormalizer,
SearchQueryBuilder, SnippetBuilder, BookTextExtractor seam, EpubTextExtractor, TxtMdTextExtractor)
+ the `BookOpener.BookMetadata.author` change + their JVM/instrumented tests. Read-only sandbox,
independent context (author/auditor separation). Runner: `scripts/run-codex.sh` (rule 53).

## Round 1 — verdict: block-recommended (thread 019f4ef3-ba26-70a3-a4ff-5ed90b3b20c8)

Three legitimate findings (the audit also echoed unrelated diff-embedded architecture text — feature
#94 / reader-chrome prose that lives in `docs/`; disregarded as noise, not part of this WI's code):

1. **High — CancellationException swallowed.** Both extractors caught `Throwable` around suspend
   calls (`sink.emit`, Readium's suspend iterator), swallowing `CancellationException` and breaking
   structured cancellation (would let indexing record a misleading `failed` state instead of stopping).
   **Fixed:** rethrow `CancellationException` first, then `catch (Exception)`; EPUB's `finally` still
   closes the publication. (`EpubTextExtractor.kt`, `TxtMdTextExtractor.kt`)

2. **Medium — EPUB extraction was not the documented bounded streaming.** `buffer` grew until a
   resource/heading boundary and only then split into chunks — a large chapter was fully materialized
   before its first `sink.emit`. **Fixed:** `emitFullChunks` flushes completed chunks from the buffer
   FRONT as it crosses `maxChunkChars`, retaining only a sub-chunk tail; state hoisted to a
   `StreamState` holder. Now O(batch), not O(resource). (`EpubTextExtractor.kt`)

3. **Medium — SnippetBuilder not token-aware for unspaced CJK.** Word runs split only on ASCII space,
   so `编程` queried against `关于编程的书` washed all six ideographs. **Fixed:** a code-point-precise
   `matchAt` scan grows a raw window per code point and returns the TIGHT raw span folding to a token,
   highlighting only the matched ideographs; added CJK snippet regression tests.
   (`SnippetBuilder.kt`, `SnippetBuilderTest.kt`)

## Round 2 — verdict: follow-up-recommended (thread 019f4ef8-6e1a-7840-8648-f5f9086b8e8c)

Confirmed all three round-1 fixes resolved:
- Both extractors rethrow `CancellationException`.
- EPUB front-draining retains only the tail for valid chunk sizes; split boundaries preserve
  surrogate pairs + tails; `chunkOrdinal` stays unique + monotonic across sections.
- Snippet matching advances by code point, terminates under its cap, highlights tight CJK spans, and
  its range shifting (`leadingWs`) / window filtering is consistent.
- No other Medium-or-higher nullability, coroutine, or resource-leak issue.

One NEW Medium:

4. **Medium — non-positive `maxChunkChars` could hang extraction.** The `EpubTextExtractor`
   constructor accepted any `Int`; with `0`, `drainRemaining()` makes no progress (`cut == 0`) and
   loops forever. **Fixed:** `init { require(maxChunkChars > 0) }` + a construction-guard regression
   test in the instrumented `EpubTextExtractorTest`.

## Disposition

Round-2 verdict `follow-up-recommended` meets the lane acceptance bar (ship-as-is or
follow-up-recommended). All Critical/High/Medium findings across both rounds are fixed in-branch.
The auditor could not run the Gradle gate (read-only sandbox / no emulator); the lane ran the JVM
gate itself: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` for the four targeted suites, and
`:app:compileDebugAndroidTestKotlin` compiles the instrumented `EpubTextExtractorTest` (the Gate-5
slice the orchestrator runs on the emulator).
