package com.vreader.app.annotations

import com.vreader.app.reader.foliate.FoliateMessageParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import vreader.contracts.BookFormat
import vreader.contracts.Locator

/**
 * Feature #142 WI-2 — the stored-record direction of [Azw3AnnotationMapper]: `cfiFor` (which CFI is
 * handed to `readerAPI.addAnnotation`/`deleteAnnotation`) and `highlightIdForCfi` (an
 * `annotation-show` tap -> the highlight it belongs to).
 *
 * These two must agree: a record is painted under whatever `cfiFor` returns, so a tap reports that
 * same string back. Every test below is written against that pairing rather than against either
 * function alone. Pure JVM.
 */
class Azw3AnnotationMapperCfiTest {

    private val bookKey = "azw3:${"3".repeat(64)}:6594560"
    private val cfiA = "epubcfi(/6/24!/4/2/6,/1:0,/1:37)"
    private val cfiB = "epubcfi(/6/8!/4/2,/1:0,/1:5)"

    private fun locator(cfi: String?) = Locator(
        contentSHA256 = "3".repeat(64),
        fileByteCount = 6_594_560L,
        format = BookFormat.azw3.name,
        cfi = cfi,
        textQuote = "q",
    )

    private fun highlight(
        id: String = "h1",
        anchor: AnnotationAnchor? = null,
        locatorCfi: String? = cfiA,
    ) = HighlightRecord(
        id = id, bookKey = bookKey, color = AnnotationColor.DEFAULT,
        selectedText = "q", note = null,
        locator = locator(locatorCfi), anchor = anchor,
        createdAt = 1L, updatedAt = 1L,
    )

    private fun epubAnchor(cfi: String) = AnnotationAnchor.Epub(href = "", cfi = cfi)

    // ---- cfiFor: precedence ---------------------------------------------------------------

    @Test fun cfiFor_prefersTheAnchor() {
        assertEquals(cfiB, Azw3AnnotationMapper.cfiFor(highlight(anchor = epubAnchor(cfiB), locatorCfi = cfiA)))
    }

    /**
     * THE load-bearing case. The backup wire carries no anchor:
     * `AnnotationsRepository.restoreAnnotations` inserts every restored highlight with
     * `anchor = null`, and the on-wire `locatorJSON` is a plain `Locator`, so the CFI survives there
     * and nowhere else. Without this fallback every AZW3 highlight restored from a backup would be
     * stored, listed in the Notes sheet, and permanently impossible to paint.
     */
    @Test fun cfiFor_nullAnchor_fallsBackToTheLocatorCfi() {
        assertEquals(cfiA, Azw3AnnotationMapper.cfiFor(highlight(anchor = null, locatorCfi = cfiA)))
    }

    @Test fun cfiFor_nullAnchorAndNullLocatorCfi_isNull() {
        assertNull(Azw3AnnotationMapper.cfiFor(highlight(anchor = null, locatorCfi = null)))
    }

    @Test fun cfiFor_nullAnchorAndBlankLocatorCfi_isNull() {
        assertNull(Azw3AnnotationMapper.cfiFor(highlight(anchor = null, locatorCfi = "   ")))
    }

    /** A blank anchor CFI is not a usable annotation key — an empty string resolves to no range, so
     *  fall through rather than hand `addAnnotation` something that paints nothing. */
    @Test fun cfiFor_blankAnchorCfi_fallsBackToTheLocatorCfi() {
        assertEquals(cfiA, Azw3AnnotationMapper.cfiFor(highlight(anchor = epubAnchor(""), locatorCfi = cfiA)))
    }

    @Test fun cfiFor_whitespaceOnlyAnchorCfi_fallsBackToTheLocatorCfi() {
        assertEquals(cfiA, Azw3AnnotationMapper.cfiFor(highlight(anchor = epubAnchor("  \t "), locatorCfi = cfiA)))
    }

    /** A Text anchor on an AZW3 row (a mixed or corrupt import) carries no CFI at all. */
    @Test fun cfiFor_textAnchor_fallsBackToTheLocatorCfi() {
        val anchor = AnnotationAnchor.Text(sourceUnitId = "u", startUTF16 = 0, endUTF16 = 3)
        assertEquals(cfiA, Azw3AnnotationMapper.cfiFor(highlight(anchor = anchor, locatorCfi = cfiA)))
    }

    @Test fun cfiFor_textAnchorAndNoLocatorCfi_isNull() {
        val anchor = AnnotationAnchor.Text(sourceUnitId = "u", startUTF16 = 0, endUTF16 = 3)
        assertNull(Azw3AnnotationMapper.cfiFor(highlight(anchor = anchor, locatorCfi = null)))
    }

    /** A maximal CFI is returned verbatim — no truncation at the read side either. */
    @Test fun cfiFor_returnsAMaximalCfiVerbatim() {
        val prefix = "epubcfi(/6/24!/4/2/6,"
        val atCap = prefix + "1".repeat(FoliateMessageParser.MAX_CFI_CHARS - prefix.length - 1) + ")"
        assertEquals(FoliateMessageParser.MAX_CFI_CHARS, atCap.length)
        assertEquals(atCap, Azw3AnnotationMapper.cfiFor(highlight(anchor = epubAnchor(atCap))))
    }

    // ---- cfiFor + highlightIdForCfi: the anchor/locator DISAGREEMENT case ------------------

    /**
     * When a record's anchor and locator carry DIFFERENT CFIs (only reachable through a corrupt or
     * hand-edited import), the engine-precise anchor wins — `AnnotationAnchor` is by definition the
     * engine anchor, the `Locator` is the canonical half. The overlay is therefore painted at the
     * anchor's range, and the tap that comes back carries the anchor's CFI.
     *
     * The stale locator CFI must NOT resolve: it points at a range where nothing is painted, so
     * matching it would let a tap somewhere else edit or delete this highlight. Flipping the
     * precedence to locator-first, or matching on both, breaks exactly one of these three asserts.
     */
    @Test fun disagreeingAnchorAndLocator_anchorWinsAndTheStaleLocatorCfiDoesNotResolve() {
        val record = highlight(id = "conflicted", anchor = epubAnchor(cfiB), locatorCfi = cfiA)
        assertNotEquals(cfiA, cfiB)

        assertEquals(cfiB, Azw3AnnotationMapper.cfiFor(record))
        assertEquals("conflicted", Azw3AnnotationMapper.highlightIdForCfi(cfiB, listOf(record)))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(cfiA, listOf(record)))
    }

    // ---- highlightIdForCfi ----------------------------------------------------------------

    @Test fun highlightIdForCfi_exactMatchOnTheAnchor() {
        val records = listOf(
            highlight(id = "a", anchor = epubAnchor(cfiB)),
            highlight(id = "b", anchor = epubAnchor(cfiA)),
        )
        assertEquals("b", Azw3AnnotationMapper.highlightIdForCfi(cfiA, records))
    }

    /**
     * A RESTORED highlight has `anchor == null`, so it is painted under its LOCATOR CFI — therefore
     * a tap on it reports that same CFI and must resolve. Resolving against the anchor only (the
     * literal iOS `FoliateHighlightTapResolver` shape) would leave every restored highlight visible
     * but untappable: no EDIT popover, no way to change its colour, no way to remove it.
     */
    @Test fun highlightIdForCfi_resolvesARestoredHighlightByItsLocatorCfi() {
        val restored = highlight(id = "restored", anchor = null, locatorCfi = cfiA)
        assertEquals("restored", Azw3AnnotationMapper.highlightIdForCfi(cfiA, listOf(restored)))
    }

    @Test fun highlightIdForCfi_firstMatchWinsInListOrder() {
        val records = listOf(
            highlight(id = "first", anchor = epubAnchor(cfiA)),
            highlight(id = "second", anchor = epubAnchor(cfiA)),
        )
        assertEquals("first", Azw3AnnotationMapper.highlightIdForCfi(cfiA, records))
        // ... and the order is the CALLER's list order, not an internal reshuffle.
        assertEquals("second", Azw3AnnotationMapper.highlightIdForCfi(cfiA, records.reversed()))
    }

    /**
     * The live/restored duplicate pair, pinned. A live row and a row restored from a backup for the
     * SAME range share a `profileKey` but not an `anchorKey` (`anchorKeyFor(null)` is the
     * `__nil_anchor__` sentinel), so the `(profileKey, anchorKey)` unique index admits both — a
     * pre-existing property of the restore path shared by every format, not introduced here.
     *
     * WI-2's own contract under that duplicate is what this asserts: both rows resolve to the SAME
     * CFI (so foliate paints one overlay — `addAnnotation` removes and re-adds under the same value),
     * and the tap resolves to the caller's first row, deterministically rather than arbitrarily.
     */
    @Test fun highlightIdForCfi_liveAndRestoredDuplicatesShareACfiAndResolveDeterministically() {
        val live = highlight(id = "live", anchor = epubAnchor(cfiA), locatorCfi = cfiA)
        val restored = highlight(id = "restored", anchor = null, locatorCfi = cfiA)

        assertEquals(Azw3AnnotationMapper.cfiFor(live), Azw3AnnotationMapper.cfiFor(restored))
        assertEquals("live", Azw3AnnotationMapper.highlightIdForCfi(cfiA, listOf(live, restored)))
        assertEquals("restored", Azw3AnnotationMapper.highlightIdForCfi(cfiA, listOf(restored, live)))
    }

    @Test fun highlightIdForCfi_noMatch_isNull() {
        val records = listOf(highlight(id = "a", anchor = epubAnchor(cfiA)))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("epubcfi(/6/99!/4/2,/1:0,/1:1)", records))
    }

    @Test fun highlightIdForCfi_blankCfi_isNoMatch() {
        // A record that itself resolves to no CFI must not be matched by a blank tap value.
        val records = listOf(highlight(id = "a", anchor = epubAnchor(""), locatorCfi = null))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("", records))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("   ", records))
    }

    @Test fun highlightIdForCfi_emptyRecords_isNull() {
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(cfiA, emptyList()))
    }

    /** Records with no resolvable CFI are skipped, never matched by accident. */
    @Test fun highlightIdForCfi_skipsRecordsWithNoCfi() {
        val records = listOf(
            highlight(id = "cfi-less", anchor = null, locatorCfi = null),
            highlight(id = "real", anchor = null, locatorCfi = cfiA),
        )
        assertEquals("real", Azw3AnnotationMapper.highlightIdForCfi(cfiA, records))
    }

    /** Exact string equality: a CFI differing by whitespace or case denotes a DIFFERENT range, and a
     *  fuzzy match would paint or delete the wrong one. */
    @Test fun highlightIdForCfi_isExactNotFuzzy() {
        val records = listOf(highlight(id = "a", anchor = epubAnchor(cfiA)))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(" $cfiA", records))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("$cfiA ", records))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(cfiA.uppercase(), records))
    }

    /** Two CFIs differing only in their SECTION step are different ranges — the near-miss a
     *  prefix/startsWith match would wrongly accept. */
    @Test fun highlightIdForCfi_doesNotMatchADifferentSection() {
        val sameRangeOtherSection = cfiA.replace("/6/24!", "/6/26!")
        val records = listOf(highlight(id = "a", anchor = epubAnchor(cfiA)))
        assertNotEquals(cfiA, sameRangeOtherSection)
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(sameRangeOtherSection, records))
    }

    /** ... and a strict PREFIX of a stored CFI must not resolve either. */
    @Test fun highlightIdForCfi_doesNotMatchAPrefix() {
        val records = listOf(highlight(id = "a", anchor = epubAnchor(cfiA)))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(cfiA.dropLast(1), records))
    }

    /** The quote is not part of the key — a CJK highlight resolves exactly like an ASCII one. */
    @Test fun highlightIdForCfi_matchesRegardlessOfTheQuoteContent() {
        val cjk = highlight(id = "cjk", anchor = epubAnchor(cfiA)).copy(selectedText = "被偷走的勇气")
        assertEquals("cjk", Azw3AnnotationMapper.highlightIdForCfi(cfiA, listOf(cjk)))
    }
}
