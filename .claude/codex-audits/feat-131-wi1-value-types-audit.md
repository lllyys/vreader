---
branch: feat/131-wi1-value-types
threadId: 019f54bb-a2e7-7e93-a30b-cc79e2d59273
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #131 WI-1 (bilingual value types + segmentation/chunk/contract)

Independent Codex audit (rule 53, `scripts/run-codex.sh`, read-only sandbox) of the
new pure-Kotlin package `com.vreader.app.bilingual` — ports of the iOS
`ChapterSegmenter` / `BilingualParagraphRanges` / `ChapterTranslationChunker` /
`TranslationChunkContract` plus the value types `Utf16Span`, `TranslationUnitId`,
`TranslationGranularity`, `BilingualLanguages`, and the `ChapterTranslationError`
mapper.

Model: gpt-5.6-sol. Author (Claude) ≠ auditor (Codex) — author/auditor
separation held (rule 48).

## Round 1 — session `019f54b6-9989-7273-b2f6-bef03ca306cc`

Verdict: follow-up-recommended. Zero Critical/High. Findings:

- **Medium — `java.text.BreakIterator` does not guarantee ICU extended-grapheme
  boundaries** (`TranslationChunker.graphemeBoundaries`). ZWJ emoji families,
  regional-indicator flags, and emoji modifiers are not contractually
  indivisible under `java.text`, so `subSplit` could split a user-perceived
  grapheme and `chunk` could compute a different budget than Swift `String.count`.
- **Medium — paragraph span/string peers do not satisfy the documented exact
  substring invariant** (`ChapterSegmenter`). `paragraphs()` normalizes soft-wrap
  CRLF/CR→LF while `paragraphRanges()` points at raw source, so
  `text.substring(span)` retains `\r\n` for a soft-wrapped paragraph. Matches iOS
  behavior and count-parity holds, but the unconditional doc claim overstated it.
- **Low — `Utf16Span` permitted negative coordinates** (only ordering validated).

## Fixes applied (commit `aa9b536`)

1. `TranslationChunker`: switched the grapheme-boundary provider to
   `android.icu.text.BreakIterator` (ICU extended grapheme clusters — the true
   Swift `Character` analog; bundled from API 24, `minSdk` = 26; same precedent
   as `search/SearchTextNormalizer.kt`). `graphemeBoundaries` / `graphemeCount` /
   `subSplit` / `chunk` all consume ICU boundaries end to end.
   `TranslationChunkerTest` is now `@RunWith(RobolectricTestRunner::class)` so the
   bundled ICU impl is present under the JVM. Added parity tests:
   ZWJ family (👨‍👩‍👧‍👦), regional-indicator flag (🇨🇳), emoji modifier (👍🏽),
   and a grapheme-budget `chunk` test.
2. `ChapterSegmenter`: file header + `paragraphRanges()` doc now state spans are
   SOURCE-coordinate (raw) and equal the string peer only after the same
   CRLF/CR→LF normalization; count-parity always holds. Added
   `paragraphRanges_softWrapCrlf_substringEqualsPeerAfterNormalization`.
3. `Utf16Span`: added `require(start >= 0)`; documented that
   `endExclusive <= source.length` stays the caller's responsibility (the value
   type carries no source reference). Added `requireThrowsOnNegativeStart`.

## Round 2 — session `019f54bb-a2e7-7e93-a30b-cc79e2d59273`

Verdict: **ship-as-is**. No Critical/High/Medium findings remain; no new
regressions. Codex verified end-to-end ICU grapheme handling, the corrected
paragraph-span contract + test, and the `Utf16Span` negative-start guard. It
noted the `java.text.BreakIterator` use that remains in `ChapterSegmenter` is
confined to SENTENCE segmentation (intentional, locale-dependent on both
platforms, not a grapheme-safety concern). One Low doc-only note — the
`ChapterSegmenterTest.kt` header still broadly claimed substring equality — was
then cleaned up opportunistically.

## Test gate

`scripts/run-android-tests.sh` (JVM, `:app:testDebugUnitTest --tests
'com.vreader.app.bilingual.*'`): `RUN-ANDROID-TESTS RESULT: SUCCEEDED`, 81/0
across the 8 bilingual test classes (Utf16Span 6, TranslationUnitId 5,
TranslationGranularity 1, BilingualLanguages 6, ChapterSegmenter 24,
TranslationChunker 16, TranslationChunkContract 12, ChapterTranslationErrorMapping 11).
