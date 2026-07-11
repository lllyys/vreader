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
 *
 * Invariants asserted here:
 * - Spans are RAW UTF-16 offsets into the UN-folded chunk text (NOT display-collapsed, NOT segmented).
 * - A length-changing fold (NFKC full-width→half, ß→ss, combining-mark strip) does NOT shift the span.
 * - Surrogate pairs are never split (code-point iteration).
 * - A CJK Phrase span is TIGHT (关于编程的书 + 编程 → the 编程 span only).
 * - PrefixTerm matches at a word boundary; Term matches the whole token.
 * - Overlapping matches are deduped (non-overlapping, start-ordered).
 * - A folded-only match with no locatable raw anchor → 0 occurrences (head-fallback contract).
 * - COMPLETENESS: a 40-occurrence chunk requested with maxThisPage=10 is retrieved IN FULL across 4
 *   paged calls threading fromOccurrenceIndex; the union = all 40 in order, no gap/dupe, last slice's
 *   nextOccurrenceIndex == null.
 */
@RunWith(RobolectricTestRunner::class)
class RawOffsetMatcherTest {

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

    /** Assert every occurrence's span folds to the same normalized form as the FIRST query unit. */
    private fun assertSpanFoldsToFirstUnit(text: String, occ: RawOccurrence, expectedFold: String) {
        val slice = text.substring(occ.startUtf16, occ.endUtf16)
        assertEquals(expectedFold, SearchTextNormalizer.normalize(slice))
    }

    // ---- N occurrences in one chunk; exact raw spans ----

    @Test fun multipleLatinOccurrences_exactRawSpans_startOrdered() {
        // "cat" appears 3 times; PrefixTerm("cat") anchors on each. Whole words so tight span = "cat".
        val text = "cat sat on a cat near a cat"
        val q = sq("cat")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(3, occ.size)
        // Exact raw offsets of each "cat".
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

    // ---- ß → ss : a length-changing fold does NOT shift the raw span ----

    @Test fun eszettFoldsToSs_rawSpanStaysRaw() {
        // Query "strasse" (folded); raw text has "Straße" (6 UTF-16 units) — one raw char ß folds to
        // TWO fold-chars "ss". The returned span must be the RAW 6-unit "Straße", not a 7-char span.
        val text = "das Straße hier"
        val q = sq("Straße")   // -> PrefixTerm("strasse")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals("Straße", text.substring(s.startUtf16, s.endUtf16))
        assertEquals(6, s.endUtf16 - s.startUtf16)   // RAW length, not folded length
        assertSpanFoldsToFirstUnit(text, s, "strasse")
    }

    // ---- NFKC full-width → half-width : raw span preserved ----

    @Test fun fullWidthLatin_nfkcFold_rawSpanStaysRaw() {
        // Full-width "ｃｏｄｅ" (4 full-width code units) folds to half-width "code". The span must be
        // the RAW full-width run.
        val text = "the ｃｏｄｅ example"
        val q = sq("code")   // PrefixTerm("code")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val fullWidth = "ｃｏｄｅ"
        assertEquals(fullWidth, text.substring(occ[0].startUtf16, occ[0].endUtf16))
        assertSpanFoldsToFirstUnit(text, occ[0], "code")
    }

    // ---- combining marks : diacritic strip does not shift the raw span ----

    @Test fun combiningMarks_diacriticStrip_rawSpanStaysRaw() {
        // "café" written with a combining acute (e + U+0301) folds to "cafe". The span must include the
        // combining mark (raw), i.e. 5 UTF-16 units, not the folded 4.
        val text = "a café shop"   // "café" = c a f e ́  (combining acute), starts at raw index 2
        val q = sq("cafe")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals("café", text.substring(s.startUtf16, s.endUtf16))
        assertEquals(5, s.endUtf16 - s.startUtf16)   // includes the combining mark
        assertSpanFoldsToFirstUnit(text, s, "cafe")
    }

    // ---- surrogate pairs never split ----

    @Test fun surrogatePair_neverSplit_spanOnCodePointBoundary() {
        // A non-BMP CJK ideograph (CJK Ext B, U+20000, "𠀀") is a surrogate PAIR (2 UTF-16 units).
        // Query the two-char phrase 𠀀A? No — use it as a CJK char in a phrase with a BMP CJK char.
        val ext = "𠀀"          // U+20000, CJK Ext B — 2 UTF-16 units, isCjk == true
        val text = "x${ext}中y"           // ext at raw index 1..2, 中 at 3
        val q = sq("${ext}中")            // Phrase([ext, "中"]) — a 2-char CJK run
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        // span must be exactly the "𠀀中" run: start 1 (before the high surrogate), end 4 (after 中).
        assertEquals(1, s.startUtf16)
        assertEquals(4, s.endUtf16)
        assertEquals("${ext}中", text.substring(s.startUtf16, s.endUtf16))
        // start never lands inside a surrogate pair.
        assertTrue(!Character.isLowSurrogate(text[s.startUtf16]))
    }

    // ---- tight CJK phrase span ----

    @Test fun cjkPhrase_spanIsTight_notWholeRun() {
        // 关于编程的书 + query 编程 -> the 编程 span ONLY (indices 2..4), not the surrounding text.
        val text = "关于编程的书"
        val q = sq("编程")   // Phrase(["编","程"])
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals("编程", text.substring(s.startUtf16, s.endUtf16))
        assertEquals(2, s.startUtf16)
        assertEquals(4, s.endUtf16)
    }

    @Test fun cjkPhrase_multipleOccurrences_eachTight() {
        val text = "编程很好编程再来编程"  // 编程 at 0..2, 4..6, 8..10
        val q = sq("编程")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(3, occ.size)
        assertEquals(listOf(0, 4, 8), occ.map { it.startUtf16 })
        assertEquals(listOf(2, 6, 10), occ.map { it.endUtf16 })
        occ.forEach { assertEquals("编程", text.substring(it.startUtf16, it.endUtf16)) }
    }

    // ---- PrefixTerm boundary ----

    @Test fun prefixTerm_matchesAtWordBoundary_prefixNotSubstring() {
        // "prog" is a PrefixTerm. It must match "program" (prefix at a word start) but NOT the internal
        // "prog" inside "reprogram" (not at a word boundary).
        val text = "reprogram the program now"
        val q = sq("prog")   // PrefixTerm("prog")
        val occ = allOccurrences(text, q, pageSize = 100)
        // only "program" (word-initial) matches; the anchor span is the tight fold of the word prefix.
        assertEquals(1, occ.size)
        val s = occ[0]
        assertEquals("program", text.substring(s.startUtf16, s.endUtf16))
    }

    // ---- Term whole-token ----

    @Test fun term_matchesWholeTokenOnly_notPrefix() {
        // A Term is a whole-token match. "cats and dogs" -> Term("cats"), Term("and"), PrefixTerm("dogs").
        // The FIRST unit (anchor) is Term("cats"): matches the whole word "cats" but not "cat" or
        // "category".
        val text = "cat category cats scatter"
        val q = sq("cats and dogs")   // first unit Term("cats")
        val occ = allOccurrences(text, q, pageSize = 100)
        assertEquals(1, occ.size)
        assertEquals("cats", text.substring(occ[0].startUtf16, occ[0].endUtf16))
    }

    // ---- overlapping-match dedupe ----

    @Test fun overlappingMatches_deduped_nonOverlappingStartOrdered() {
        // "aa" queried against "aaaa": non-overlapping leftmost enumeration yields 2 matches (0..2,
        // 2..4), NOT 3 (which overlapping would produce).
        val text = "aaaa"
        val q = sq("aa")   // PrefixTerm("aa")
        val occ = allOccurrences(text, q, pageSize = 100)
        // matches are non-overlapping: each start >= previous end.
        for (i in 1 until occ.size) {
            assertTrue("occ $i overlaps prev", occ[i].startUtf16 >= occ[i - 1].endUtf16)
        }
        assertTrue("expected at least 1 non-overlapping match", occ.isNotEmpty())
    }

    // ---- folded-only, no raw anchor → 0 occurrences (head fallback) ----

    @Test fun noRawAnchor_returnsZeroOccurrences() {
        // The chunk does NOT actually contain the query's first unit as a raw anchor. (The FTS index
        // matched some OTHER chunk / via AND across units, but this specific chunk has no locatable
        // anchor for the first unit.) The matcher returns an empty slice — the repository head-fallback.
        val text = "nothing relevant here at all"
        val q = sq("zzzz")   // PrefixTerm("zzzz") — no anchor
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
        // A chunk with EXACTLY 40 occurrences of "x" (whole-token). maxThisPage=10 → 4 gapless,
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
        // no duplicates.
        assertEquals(40, union.map { it.startUtf16 }.toSet().size)
    }

    @Test fun occurrenceIndex_stableAcrossResumeFromMiddle() {
        // Resuming at fromOccurrenceIndex = 5 lands on the exact 6th occurrence (occurrenceIndex 5),
        // identical to what a full page-0 enumeration reports at index 5.
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
