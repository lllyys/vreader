---
branch: feat/133-wi3-raw-offset-matcher
threadId: 019f52df-9a6d-7f60-a294-0a6ec56249bb, 019f52e7-107a-7b71-8da2-faaa87291012, 019f52e9-94b0-7a33-b7fb-4d1c49e44541
rounds: 3
final_verdict: follow-up-recommended
date: 2026-07-12
---

# Gate-4 audit — feature #133 WI-3 (RawOffsetMatcher)

Independent Codex audit (`scripts/run-codex.sh`, model `gpt-5.6-sol`, rule 53) of the raw-offset
in-book occurrence matcher. Three rounds; all findings resolved in-lane. No Critical or High findings
in any round; final round's sole Medium is closed by a targeted normalization-aware boundary fix + test.

## Files audited (the branch diff vs `origin/main`)

- `android/app/src/main/kotlin/com/vreader/app/search/RawOffsetMatcher.kt` (NEW)
- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchModels.kt` (NEW — `RawOccurrence`,
  `RawOccurrenceSlice`, `SearchCursor`)
- `android/app/src/test/kotlin/com/vreader/app/search/RawOffsetMatcherTest.kt` (NEW — Robolectric/JVM)

## Round 1 — verdict: block-recommended (session 019f52df…)

Findings + resolutions:

1. **[Critical→fixed] Word boundaries did not match FTS `unicode61` token semantics.** `isSeparator`
   recognized only whitespace/control, so punctuation-glued runs (`cat,` / `(cat)` / `cat—dog`) missed
   real anchors → an FTS-hit chunk could have no raw anchor. **Fix:** `isSeparator` now mirrors
   unicode61 — letters + digits + combining marks (Mn/Mc/Me) are token chars; punctuation/symbols and
   CJK are separators. Added `punctuationBoundsWords_notGluedIntoOneRun`.
2. **[Medium→fixed] Overlap-dedupe test was tautological.** `"aaaa"`/`"aa"` matched the whole word as
   one span, asserting nothing about overlap. **Fix:** replaced with a precise CJK-phrase case
   (`编编编编` + `编编` → exactly 2 non-overlapping spans `[0,2)`/`[2,4)`, never 3).
3. **[Medium→fixed] "folded-only" test was not folded-only.** **Fix (round-1 then refined round-2):**
   a genuinely distinct head-fallback case.
4. **[Medium→fixed] Exact-offset coverage incomplete.** **Fix:** exact absolute start/end offsets on
   the ß / full-width / combining / surrogate spans; added `surrogatePair_beforeAnchor_notSplitOnAdvance`.
5. **[Medium→addressed round-2] OOM guard returning `null` = false exhaustion.**

## Round 2 — verdict: follow-up-recommended, no Critical/High (session 019f52e7…)

1. **[Medium→fixed] The OOM-guard "resume" created a false completeness claim / infinite empty-page
   loop at the (unreachable) boundary.** **Fix:** removed the absolute-index guard entirely — the
   enumeration is naturally bounded (every iteration advances the scan cursor by ≥1 UTF-16 unit, so
   occurrences ≤ chunk length and the loop always terminates); completeness holds unconditionally with
   no false-exhaustion edge.
2. **[Medium→fixed] The head-fallback test duplicated plain-absence.** **Fix:** reworked to a distinct
   case — the anchor's fold is PRESENT only as a substring inside longer words (`category`/`scatter`),
   never a valid whole-word anchor → Term whole-token equality rejects it → 0 occurrences.

## Round 3 — verdict: follow-up-recommended, no Critical/High (session 019f52e9…)

1. **[Medium→fixed] Raw word boundaries could diverge from the normalized token stream for
   compatibility characters.** A raw compatibility char (e.g. superscript `²` U+00B2, category No)
   classified as a separator, yet its NFKC fold is a token char (`² → 2`), so FTS sees `x²y` as ONE
   unicode61 token → an FTS hit could have no raw anchor. **Fix:** `isSeparator` now also treats a raw
   code point as token continuation when its NFKC fold is non-empty and entirely letters/digits
   (`normalizesToTokenChars`); the boundary predicate mirrors the normalized token stream while the
   returned span stays RAW (`x²y` span = the raw 3 units, folds to `x2y`). Added
   `compatibilityChar_nfkcFoldsToDigit_staysInsideWord`.

Round-3 also independently confirmed sound: raw UTF-16 spans under length-changing folds, surrogate-safe
code-point iteration, tight CJK phrase spans, deterministic leftmost non-overlapping enumeration, the
distinct head-fallback test, and complete/stable paging (no gap/dupe, exact-page exhaustion → `null`,
correct resume on discovery of a further occurrence) with natural termination (no artificial cap).

## Final state

- All Critical/High/Medium findings across the 3 rounds are RESOLVED in-lane (each with a fix + a test).
- Final Codex verdict: **follow-up-recommended** — no open Critical/High; the round-3 Medium is closed.
- Test gate: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` for `*RawOffsetMatcherTest` (Robolectric/JVM) and the
  full `:app:testDebugUnitTest` JVM suite (no regression). Pure-JVM — no emulator required.
  (Codex's own narrow-gate note "`NO_EMULATOR`" is expected: these are Robolectric unit tests run by
  the lane via `scripts/run-android-tests.sh`, not instrumentation.)
