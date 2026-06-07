---
branch: fix/issue-1571-bilingual-chunker-oversized
threadId: 019ea2c5-6ae4-7253-b45f-e1706485a4c6
rounds: 2
final_verdict: ship-as-is
date: 2026-06-07
---

# Codex audit — Bug #330 / GH #1571 bilingual oversized-chapter chunking

Fix: translating a large chapter / oversized paragraph in bilingual mode errored
(oversized paragraph sent whole → provider context overflow; single chunk
failure aborted the whole chapter).

## Scope
- `vreader/Services/AI/ChapterTranslationChunker.swift` — new `subSplit(_:maxChars:)`.
- `vreader/Services/AI/ChapterTranslationService.swift` — `translateChunk`
  sub-splits an oversized single segment + rejoins; `translate` /
  `translatePreSegmented` chunk loops degrade per-chunk failures to source-only
  (throw only if all fail); partial results not cached.
- tests: chunker `subSplit_*` (5), service oversized/degradation/cache/cancel (6).

## Round 1 (threadId 019ea2c5-6ae4-7253-b45f-e1706485a4c6)

**2 High:**
1. Partial-degraded results were still written to the persistent cache → later
   cache hits served source-only holes forever (validity check is segment-count
   only). **Fixed:** cache `upsert` guarded by `if lastChunkError == nil`; a
   re-read of a degraded chapter misses the cache and retries. Test
   `partialDegradation_isNotCached_soReReadRetries`.
2. Typed cancellation swallowable: `send()` maps provider cancellation to
   `ChapterTranslationError.cancelled`, but the loops only caught raw
   `CancellationError` → `.cancelled` fell into the degrade-and-continue catch
   (a cancel on a later chunk after an earlier success returned partial success +
   could cache it). **Fixed:** `catch ChapterTranslationError.cancelled { throw
   .cancelled }` before the generic catch in BOTH loops. Test
   `typedCancellationOnLaterChunk_aborts_afterEarlierSuccess`.

Round 1 also confirmed `subSplit` is grapheme/surrogate-safe, terminates,
coerces non-positive budgets, rejoins losslessly, and the single-segment rejoin
is 1:1 correct.

## Round 2 (threadId 019ea2c9-ce72-7e91-a37a-f96957c06bf4)

**No findings.** `catch ChapterTranslationError.cancelled` is ordered before the
generic catch in both loops; the cache guard skips ONLY on degradation and still
caches full successes; `translatePreSegmented` aborts on cancel / degrades on
other failures / throws if all fail; no false-skip path (`lastChunkError` is
assigned only when a chunk degraded).

## Verdict
**ship-as-is** after 2 rounds. Chunker 17 + service 24 tests green. Token-aware
per-provider budget deferred (sub-split + graceful degradation already prevent
the error class).
