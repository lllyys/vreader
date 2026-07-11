package com.vreader.app.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #133 WI-3 — [RawOffsetMatcher]: locates EVERY occurrence of a [StructuredQuery] inside a
 * chunk's RAW text and returns per-occurrence RAW UTF-16 spans (round-2 Critical-2, half 2). This is
 * the counterpart to [SnippetBuilder] — where SnippetBuilder returns DISPLAY-collapsed offsets for
 * highlighting, this returns the TRUE raw-source offsets a TXT/MD jump needs, avoiding the FTS4
 * `offsets()` byte/segmented-offset trap.
 *
 * Robolectric-run so the normalizer's bundled `android.icu` case-fold is present. The query is always
 * built via [SearchQueryBuilder.structuredQuery] so the units mirror exactly what made the chunk MATCH.
 * CJK / combining / non-BMP chars are written as explicit `\uXXXX` escapes so the raw byte layout the
 * offset assertions depend on is unambiguous.
 *
 * Invariants asserted here:
 * - Spans are RAW UTF-16 offsets into the UN-folded chunk text (NOT display-collapsed, NOT segmented).
 * - A length-changing fold (NFKC full-width->half, ss<->ß, combining-mark strip) does NOT shift the span.
 * - Surrogate pairs are never split (code-point iteration).
 * - A CJK Phrase span is TIGHT (关于编程的书 + 编程 -> the 编程
 *   span only).
 * - PrefixTerm matches at a word boundary; Term matches the whole token; word boundaries respect FTS
 *   `unicode61` (punctuation is a separator).
 * - Overlapping matches are deduped (non-overlapping, start-ordered).
 * - A folded-only match with no locatable raw anchor -> 0 occurrences (head-fallback contract).
 * - COMPLETENESS: a 40-occurrence chunk requested with maxThisPage=10 is retrieved IN FULL across 4
 *   paged calls threading fromOccurrenceIndex; the union = all 40 in order, no gap/dupe, last slice's
 *   nextOccurrenceIndex == null.
 */
@RunWith(RobolectricTestRunner::class)
class RawOffsetMatcherTest {

    // Explicit escapes so the raw byte layout is unambiguous (offset assertions depend on it).
    private val guanYu = "关于"       // 关于
    private val bianCheng = "编程"    // 编程
    private val deShu = "的书"        // 的书
    private val henHao = "很好"       // 很好
    private val zaiLai = "再来"       // 再来
    private val zhong = "中"              // 中
    private val ext = "𠀀"          // U+20000 (CJK Ext B) — a surrogate PAIR, 2 UTF-16 units
    private val combiningAcute = "́"     // combining acute accent

    private fun sq(raw: String): StructuredQuery = SearchQueryBuilder.structuredQuery(raw)!!

    /** Collect ALL occurrences of [query] in [text] by paging with the given [pageSize]. */
    private fun allOccurrences(text: String, query: StructuredQuery, pageSize: Int): List<RawOccurrence> {
        val all = mutableListOf<RawOccurrence>()
        var from = 0
        while (true) {
            val slice = RawOffsetMatcher.occurrences(text, query, fromOccurrenceIndex = from, maxThisPage = pageSize)
            all.addAll(slice.occurrences)
            val next = slice.nextOccurrenceIndex ?: break
            from = next
        }
        return all
    }

    /** Assert the raw span folds to the same normalized form as the FIRST query unit. */
    private fun assertSpanFoldsTo(text: String, occ: RawOccurrence, expectedFold: String) {
        val slice = text.substring(occ.startUtf16, occ.endUtf16)
        assertEquals(expectedFold, SearchTextNormalizer.normalize(slice))
    }

    /** Assert no span boundary lands inside a UTF-16 surrogate pair. */
    private fun assertNoSurrogateSplit(text: String, occ: RawOccurrence) {
        // start is not a LOW surrogate (would mean we split the pair whose high half is at start-1).
        if (occ.startUtf16 in text.indices) {
            assertTrue("start splits a surrogate pair", !Character.isLowSurrogate(text[occ.startUtf16]))
        }
        // end is not the low half of a pair whose high half is at end-1 (i.e. end doesn't cut a pair).
        if (occ.endUtf16 in text.indices) {
            assertTrue("end splits a surrogate pair", !Character.isLowSurrogate(text[occ.endUtf16]))
        }
    }

    // ---- N occurrences in one chunk; exact raw spans ----

    @Test fun multipleLatinOccurrences_exactRawSpans_startOrdered() {
        // "cat" appears 3 times; PrefixTerm("cat") anchors on each. Whole words so tight span = "cat".
        val text = "cat sat on a cat near a cat"
        val q = sq("cat")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(3, occ.size)
        assertEquals(listOf(0, 13, 24), occ.map { it.startUtf16 })
        assertEquals(listOf(3, 16, 27), occ.map { it.endUtf16 })
        assertEquals(listOf(0, 1, 2), occ.map { it.occurrenceIndex })
        occ.forEach { assertEquals("cat", text.substring(it.startUtf16, it.endUtf16)) }
    }

    @Test fun rawSpan_isNotDisplayCollapsed() {
        // A run of whitespace between occurrences: the RAW offsets must reflect the un-collapsed text,
        // NOT the whitespace-collapsed display offsets SnippetBuilder would return.
        val text = "alpha     \n\t  beta   alpha"   // second "alpha" is at raw index 21
        val q = sq("alpha")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(2, occ.size)
        assertEquals(0, occ[0].startUtf16)
        assertEquals(21, occ[1].startUtf16)   // raw, not collapsed
        assertEquals("alpha", text.substring(occ[1].startUtf16, occ[1].endUtf16))
    }

    // ---- punctuation is a word separator (FTS unicode61 parity) ----

    @Test fun punctuationBoundsWords_notGluedIntoOneRun() {
        // Term("cat") must match "cat" even when glued to punctuation: "cat," / "(cat)" / "cat—dog".
        // Without unicode61-style separators these punctuation-glued runs would miss the anchor (the
        // FTS index matched via unicode61 tokens, so the raw matcher must use the same boundaries).
        val text = "cat, (cat) then cat—dog"   // — = em dash; 3 occurrences of the word "cat"
        // A query whose FIRST unit is Term("cat"): "cat and x" -> Term("cat"), Term("and"), PrefixTerm("x").
        val q = sq("cat and x")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(3, occ.size)
        assertEquals(listOf(0, 6, 16), occ.map { it.startUtf16 })
        occ.forEach { assertEquals("cat", text.substring(it.startUtf16, it.endUtf16)) }
    }

    // ---- compatibility char inside a word (NFKC-folds to a token char) stays in the word ----

    @Test fun compatibilityChar_nfkcFoldsToDigit_staysInsideWord() {
        // Raw "x²y" (² = U+00B2 superscript two, raw category No) normalizes to "x2y", which FTS sees as
        // ONE unicode61 token. The matcher must keep it as one word so a query "x2y" finds the anchor —
        // and the returned span stays RAW ("x²y", 3 UTF-16 units), not the folded "x2y".
        val superTwo = "²"                    // U+00B2
        val word = "x${superTwo}y"                  // raw 3 UTF-16 units
        val text = "a $word here"                   // word at raw index 2, ends at 5
        val q = sq("x2y")   // PrefixTerm("x2y")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals(2, s.startUtf16)
        assertEquals(5, s.endUtf16)
        assertEquals(word, text.substring(s.startUtf16, s.endUtf16))   // RAW span, includes the ²
        assertSpanFoldsTo(text, s, "x2y")
    }

    // ---- ß → ss : a length-changing fold does NOT shift the raw span ----

    @Test fun eszettFoldsToSs_rawSpanStaysRaw() {
        // Query "Straße" (ß) folds to "strasse"; raw "Straße" is 6 UTF-16 units, one raw ß
        // folding to TWO fold-chars. The span must be the RAW 6-unit word, not a 7-char folded span.
        val text = "das Straße hier"   // "Straße" starts at raw index 4, ends at 10 (6 units)
        val q = sq("Straße")           // -> PrefixTerm("strasse")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals(4, s.startUtf16)                // exact absolute raw offsets
        assertEquals(10, s.endUtf16)
        assertEquals("Straße", text.substring(s.startUtf16, s.endUtf16))
        assertEquals(6, s.endUtf16 - s.startUtf16)   // RAW length, not the 7-char folded length
        assertSpanFoldsTo(text, s, "strasse")
    }

    // ---- NFKC full-width → half-width : raw span preserved ----

    @Test fun fullWidthLatin_nfkcFold_rawSpanStaysRaw() {
        // Full-width "ｃｏｄｅ" (ｃｏｄｅ) folds to half-width "code". The span is the RAW run.
        val fullWidth = "ｃｏｄｅ"
        val text = "the $fullWidth example"    // run at raw index 4..8 (4 BMP full-width units)
        val q = sq("code")   // PrefixTerm("code")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        assertEquals(4, occ[0].startUtf16)            // exact absolute raw offsets
        assertEquals(8, occ[0].endUtf16)
        assertEquals(fullWidth, text.substring(occ[0].startUtf16, occ[0].endUtf16))
        assertSpanFoldsTo(text, occ[0], "code")
    }

    // ---- combining marks : diacritic strip does not shift the raw span ----

    @Test fun combiningMarks_diacriticStrip_rawSpanStaysRaw() {
        // "cafe" + combining acute over the 'e' folds to "cafe". The raw word is 5 UTF-16 units
        // (c a f e + the combining mark); the span must INCLUDE the combining mark, not drop it.
        val cafe = "cafe$combiningAcute"          // c a f e ́  — 5 UTF-16 units
        val text = "a $cafe shop"                       // word starts at raw index 2, ends at 7
        val q = sq("cafe")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals(2, s.startUtf16)                    // exact absolute raw offsets
        assertEquals(7, s.endUtf16)
        assertEquals(cafe, text.substring(s.startUtf16, s.endUtf16))
        assertEquals(5, s.endUtf16 - s.startUtf16)       // includes the combining mark (folded form = 4)
        assertSpanFoldsTo(text, s, "cafe")
    }

    // ---- surrogate pairs never split ----

    @Test fun surrogatePair_neverSplit_spanOnCodePointBoundary() {
        // A non-BMP CJK ideograph (CJK Ext B, U+20000) is a surrogate PAIR (2 UTF-16 units). Query a
        // 2-char CJK phrase [U+20000, 中] and assert the span brackets the pair without cutting it.
        val text = "x$ext${zhong}y"    // x(0) [hi(1) lo(2)] 中(3) y(4)
        val q = sq("$ext$zhong")       // Phrase([U+20000, 中]) — a 2-char CJK run
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals(1, s.startUtf16)   // before the high surrogate
        assertEquals(4, s.endUtf16)     // after 中
        assertEquals("$ext$zhong", text.substring(s.startUtf16, s.endUtf16))
        assertNoSurrogateSplit(text, s)
    }

    @Test fun surrogatePair_beforeAnchor_notSplitOnAdvance() {
        // A non-BMP char precedes a matchable BMP-only run: advancing past the pair must step over BOTH
        // UTF-16 units (Character.charCount == 2), never landing a scan start on the low surrogate.
        val text = "${ext}cat cat"     // pair at 0..1, "cat" at 2..5 and 6..9
        val q = sq("cat")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(2, occ.size)
        assertEquals(listOf(2, 6), occ.map { it.startUtf16 })
        occ.forEach { assertNoSurrogateSplit(text, it) }
    }

    // ---- tight CJK phrase span ----

    @Test fun cjkPhrase_spanIsTight_notWholeRun() {
        // 关于编程的书 + query 编程 -> the 编程 span ONLY (indices 2..4), not the surrounding text.
        val text = "$guanYu$bianCheng$deShu"   // 关于(0..1) 编程(2..3) 的书(4..5)
        val q = sq(bianCheng)   // Phrase([编, 程])
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals(2, s.startUtf16)
        assertEquals(4, s.endUtf16)
        assertEquals(bianCheng, text.substring(s.startUtf16, s.endUtf16))
    }

    @Test fun cjkPhrase_multipleOccurrences_eachTight() {
        val text = "$bianCheng$henHao$bianCheng$zaiLai$bianCheng"  // 编程 at 0..2, 4..6, 8..10
        val q = sq(bianCheng)
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(3, occ.size)
        assertEquals(listOf(0, 4, 8), occ.map { it.startUtf16 })
        assertEquals(listOf(2, 6, 10), occ.map { it.endUtf16 })
        occ.forEach { assertEquals(bianCheng, text.substring(it.startUtf16, it.endUtf16)) }
    }

    // ---- PrefixTerm boundary ----

    @Test fun prefixTerm_matchesAtWordBoundary_prefixNotSubstring() {
        // "prog" is a PrefixTerm. It must match "program" (prefix at a word start) but NOT the internal
        // "prog" inside "reprogram" (not at a word boundary).
        val text = "reprogram the program now"
        val q = sq("prog")   // PrefixTerm("prog")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals("program", text.substring(s.startUtf16, s.endUtf16))
        // The standalone word "program" starts at 14; the "prog" INSIDE "reprogram" (index 2) is NOT a
        // word-boundary match and is correctly skipped.
        assertEquals(14, s.startUtf16)
    }

    // ---- Term whole-token ----

    @Test fun term_matchesWholeTokenOnly_notPrefix() {
        // A Term is a whole-token match. "cats and dogs" -> Term("cats"), Term("and"), PrefixTerm("dogs").
        // The FIRST unit (anchor) is Term("cats"): matches the whole word "cats" but not "cat"/"category".
        val text = "cat category cats scatter"
        val q = sq("cats and dogs")   // first unit Term("cats")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        assertEquals("cats", text.substring(occ[0].startUtf16, occ[0].endUtf16))
        assertEquals(text.indexOf("cats"), occ[0].startUtf16)
    }

    // ---- overlapping-match dedupe (precise, CJK phrase where overlap is possible) ----

    @Test fun overlappingCjkPhrase_deduped_nonOverlappingLeftmost() {
        // Query phrase 编编 against 编编编编 (4 identical CJK chars). Overlapping matching would find 3
        // matches (0..2, 1..3, 2..4); the deterministic NON-overlapping leftmost rule finds exactly 2
        // (0..2 then advance to 2, 2..4), never 3. This validates the dedupe rule precisely.
        val bian = "编"                 // 编
        val text = bian.repeat(4)           // 编编编编
        val q = sq(bian + bian)             // Phrase([编, 编])
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(2, occ.size)
        assertEquals(listOf(0, 2), occ.map { it.startUtf16 })
        assertEquals(listOf(2, 4), occ.map { it.endUtf16 })
        // non-overlapping: each start >= previous end.
        for (i in 1 until occ.size) {
            assertTrue("occ $i overlaps prev", occ[i].startUtf16 >= occ[i - 1].endUtf16)
        }
    }

    // ---- folded-only, no raw anchor → 0 occurrences (head fallback) ----

    @Test fun noRawAnchor_returnsZeroOccurrences() {
        // The chunk does NOT contain the query's first unit as a raw anchor at all -> empty slice.
        val text = "nothing relevant here at all"
        val q = sq("zzzz")   // PrefixTerm("zzzz") — no anchor
        val slice = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 0, maxThisPage = 10)
        assertEquals(emptyList<RawOccurrence>(), slice.occurrences)
        assertNull(slice.nextOccurrenceIndex)
    }

    @Test fun anchorPresentOnlyAsSubstring_notWholeWord_returnsZero_headFallback() {
        // The anchor's fold appears in the chunk ONLY as a substring inside a longer word, never as a
        // locatable whole-word raw anchor. Term("cat") folds present inside "category"/"scatter" but
        // never as the word "cat" -> Term whole-token equality rejects both -> 0 occurrences. This is
        // the folded/AND head-fallback path (the FTS index may have matched a segmented form of the
        // chunk, but the raw matcher cannot locate a valid anchor span, so the repository jumps to the
        // section head). Distinct from plain absence: the fold IS present, just not as a valid anchor.
        val text = "the category has scatter but never the standalone term"
        val q = sq("cat and x")   // first unit Term("cat")
        val slice = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 0, maxThisPage = 10)
        assertEquals(emptyList<RawOccurrence>(), slice.occurrences)
        assertNull(slice.nextOccurrenceIndex)
    }

    @Test fun emptyText_returnsZeroOccurrences() {
        val slice = RawOffsetMatcher.occurrences("", sq("cat"), fromOccurrenceIndex = 0, maxThisPage = 10)
        assertEquals(emptyList<RawOccurrence>(), slice.occurrences)
        assertNull(slice.nextOccurrenceIndex)
    }

    // ---- COMPLETENESS: 40 occurrences, maxThisPage=10, retrieved in full across 4 paged calls ----

    @Test fun completeness_fortyOccurrences_maxTenPerPage_retrievedInFullAcrossFourPages() {
        // A chunk with EXACTLY 40 occurrences of "hit" (whole-token). maxThisPage=10 → 4 gapless,
        // dupe-free pages; the 4th slice's nextOccurrenceIndex == null.
        val builder = StringBuilder()
        val starts = mutableListOf<Int>()
        repeat(40) { i ->
            if (i > 0) builder.append(" ")   // space between occurrences → whole-token boundary
            starts.add(builder.length)
            builder.append("hit")
        }
        val text = builder.toString()
        val q = sq("hit")   // PrefixTerm("hit"); each whole word "hit" anchors one occurrence

        // Page 0: indices 0..9, nextOccurrenceIndex == 10.
        val p0 = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 0, maxThisPage = 10)
        assertEquals(10, p0.occurrences.size)
        assertEquals(0, p0.occurrences.first().occurrenceIndex)
        assertEquals(9, p0.occurrences.last().occurrenceIndex)
        assertEquals(10, p0.nextOccurrenceIndex)

        // Page 1: 10..19, next == 20.
        val p1 = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 10, maxThisPage = 10)
        assertEquals(10, p1.occurrences.size)
        assertEquals(10, p1.occurrences.first().occurrenceIndex)
        assertEquals(20, p1.nextOccurrenceIndex)

        // Page 2: 20..29, next == 30.
        val p2 = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 20, maxThisPage = 10)
        assertEquals(10, p2.occurrences.size)
        assertEquals(30, p2.nextOccurrenceIndex)

        // Page 3 (final): 30..39, next == null (chunk exhausted).
        val p3 = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 30, maxThisPage = 10)
        assertEquals(10, p3.occurrences.size)
        assertEquals(39, p3.occurrences.last().occurrenceIndex)
        assertNull(p3.nextOccurrenceIndex)

        // UNION across all 4 pages == all 40, in order, no gap, no duplicate.
        val union = p0.occurrences + p1.occurrences + p2.occurrences + p3.occurrences
        assertEquals(40, union.size)
        assertEquals((0..39).toList(), union.map { it.occurrenceIndex })
        assertEquals(starts, union.map { it.startUtf16 })   // exact raw offsets of every "hit"
        assertEquals(40, union.map { it.startUtf16 }.toSet().size)   // no duplicates
    }

    @Test fun occurrenceIndex_stableAcrossResumeFromMiddle() {
        // Resuming at fromOccurrenceIndex = 5 lands on the exact 6th occurrence (occurrenceIndex 5),
        // identical to what a full enumeration reports at index 5.
        val text = (0 until 12).joinToString(" ") { "hit" }
        val q = sq("hit")
        val full = allOccurrences(text, q, pageSize = 100)
        val resume = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 5, maxThisPage = 3)
        assertEquals(full[5].startUtf16, resume.occurrences.first().startUtf16)
        assertEquals(5, resume.occurrences.first().occurrenceIndex)
        assertEquals(listOf(5, 6, 7), resume.occurrences.map { it.occurrenceIndex })
    }

    @Test fun fromBeyondEnd_returnsEmpty_nullNext() {
        val text = "hit hit hit"
        val q = sq("hit")
        val slice = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 99, maxThisPage = 10)
        assertEquals(emptyList<RawOccurrence>(), slice.occurrences)
        assertNull(slice.nextOccurrenceIndex)
    }

    @Test fun maxThisPage_exactlyEqualsRemaining_nextIsNull() {
        // If the page window exactly consumes the remaining occurrences, nextOccurrenceIndex == null.
        val text = "hit hit hit"   // 3 occurrences
        val q = sq("hit")
        val slice = RawOffsetMatcher.occurrences(text, q, fromOccurrenceIndex = 0, maxThisPage = 3)
        assertEquals(3, slice.occurrences.size)
        assertNull(slice.nextOccurrenceIndex)
    }
}
