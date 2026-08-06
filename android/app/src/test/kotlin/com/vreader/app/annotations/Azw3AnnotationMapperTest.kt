package com.vreader.app.annotations

import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.FoliateMessage
import com.vreader.app.reader.foliate.SelectionRect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import vreader.contracts.Locator

/**
 * Feature #142 WI-2 — [Azw3AnnotationMapper]: foliate selection <-> the annotation domain, and the
 * stored-record -> CFI direction that WI-3/WI-4 hand to `readerAPI.addAnnotation`.
 *
 * Pure JVM: nothing here touches Android, Room or a WebView.
 */
class Azw3AnnotationMapperTest {

    // A CFI in the shape the bundle actually mints for MOBI/KF8 (`CFI.fake.fromIndex(i)` = /6/(i+1)*2,
    // joined indirectly with the range CFI) — captured from the real book's shape, not invented.
    private val realShapeCfi = "epubcfi(/6/24!/4/2/6,/1:0,/1:37)"

    private val book = Book(
        fingerprintKey = "azw3:${"3".repeat(64)}:6594560",
        title = "被偷走的勇气",
        originalFormat = BookFormat.azw3,
        contentSHA256 = "3".repeat(64),
        fileByteCount = 6_594_560L,
        addedAt = 1L,
    )

    private fun selection(
        text: String = "the quick brown fox",
        cfi: String = realShapeCfi,
        sectionIndex: Int = 11,
        rect: SelectionRect? = SelectionRect(12.0, 34.0, 56.0, 7.0),
    ) = FoliateMessage.Selection(text = text, cfi = cfi, sectionIndex = sectionIndex, rect = rect)

    private fun locator(cfi: String?, quote: String? = "q") = Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = BookFormat.azw3.name,
        cfi = cfi,
        textQuote = quote,
    )

    private fun highlight(
        id: String = "h1",
        anchor: AnnotationAnchor? = null,
        locatorCfi: String? = realShapeCfi,
    ) = HighlightRecord(
        id = id,
        bookKey = book.fingerprintKey,
        color = AnnotationColor.DEFAULT,
        selectedText = "q",
        note = null,
        locator = locator(locatorCfi),
        anchor = anchor,
        createdAt = 1L,
        updatedAt = 1L,
    )

    // ---- selectionToInputs ----------------------------------------------------------------

    @Test fun selectionToInputs_buildsLocatorFieldForField() {
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(), book)
        assertNotNull(inputs)
        val loc = inputs!!.locator
        assertEquals("the quick brown fox", inputs.selectedText)
        assertEquals(book.contentSHA256, loc.contentSHA256)
        assertEquals(book.fileByteCount, loc.fileByteCount)
        assertEquals(BookFormat.azw3.name, loc.format)
        assertEquals(realShapeCfi, loc.cfi)
        assertEquals("the quick brown fox", loc.textQuote)
        // foliate exposes no stable per-section href and the selection event carries no progression.
        assertNull(loc.href)
        assertNull(loc.progression)
        assertNull(loc.totalProgression)
        assertNull(loc.page)
        assertNull(loc.charOffsetUTF16)
        assertNull(loc.textContextBefore)
        assertNull(loc.textContextAfter)
    }

    /**
     * The locator must address the BOOK IT CAME FROM. iOS derives the format from the book's own
     * fingerprint (`DocumentFingerprint(canonicalKey: selection.fingerprintKey)` —
     * `FoliateSpikeView+Selection.swift`), so a locator whose `fingerprintKey` differs from the
     * book's is an orphan annotation no reader can ever resolve.
     */
    @Test fun selectionToInputs_locatorAddressesTheSameBook() {
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(), book)
        assertEquals(book.fingerprintKey, inputs!!.locator.fingerprintKey)
    }

    /**
     * The same invariant stated so it DISCRIMINATES: the format comes from the book, never from a
     * hardcoded `azw3`. Any Kindle file already canonicalizes to `azw3`
     * (`DocumentFingerprint`: azw3/azw/mobi/prc -> azw3), so on the real path the two are identical —
     * but hardcoding would silently mint an orphan locator for anything else that ever reaches here.
     */
    @Test fun selectionToInputs_formatFollowsTheBookNotAConstant() {
        val other = book.copy(
            fingerprintKey = "epub:${"7".repeat(64)}:1024",
            originalFormat = BookFormat.epub,
            contentSHA256 = "7".repeat(64),
            fileByteCount = 1024L,
        )
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(), other)!!
        assertEquals(BookFormat.epub.name, inputs.locator.format)
        assertEquals(other.fingerprintKey, inputs.locator.fingerprintKey)
    }

    @Test fun selectionToInputs_anchorIsEpubWithEmptyHrefAndTheSelectionCfi() {
        val anchor = Azw3AnnotationMapper.selectionToInputs(selection(), book)!!.anchor
        assertEquals("", anchor.href)
        assertEquals(realShapeCfi, anchor.cfi)
        assertNull(anchor.serializedRange)
        assertNull(anchor.readiumLocatorJSON)
    }

    /** The rect is view-only (§4.2 "not stored") — it must not leak into anything persisted. */
    @Test fun selectionToInputs_ignoresTheRect() {
        val withRect = Azw3AnnotationMapper.selectionToInputs(selection(rect = SelectionRect(1.0, 2.0, 3.0, 4.0)), book)
        val withoutRect = Azw3AnnotationMapper.selectionToInputs(selection(rect = null), book)
        assertEquals(withRect, withoutRect)
    }

    /** sectionIndex is derived from the CFI's first step, never stored (§4.2 "derived, not stored"). */
    @Test fun selectionToInputs_ignoresTheSectionIndex() {
        val a = Azw3AnnotationMapper.selectionToInputs(selection(sectionIndex = 0), book)
        val b = Azw3AnnotationMapper.selectionToInputs(selection(sectionIndex = 999), book)
        assertEquals(a, b)
    }

    @Test fun selectionToInputs_blankText_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(text = "   \n\t "), book))
    }

    @Test fun selectionToInputs_emptyText_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(text = ""), book))
    }

    @Test fun selectionToInputs_blankCfi_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(cfi = "  "), book))
    }

    @Test fun selectionToInputs_emptyCfi_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(cfi = ""), book))
    }

    /** The real book is CJK — this is the primary case, not an afterthought. */
    @Test fun selectionToInputs_cjkQuoteSurvivesByteExactThroughCanonicalJson() {
        val cjk = "被偷走的勇气：自我"
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = cjk), book)!!
        assertEquals(cjk, inputs.selectedText)
        assertEquals(cjk, inputs.locator.textQuote)
        assertTrue(
            "canonicalJson must carry the CJK quote unmangled: ${inputs.locator.canonicalJson()}",
            inputs.locator.canonicalJson().contains(cjk),
        )
    }

    @Test fun selectionToInputs_surrogatePairsAndEmojiSurvive() {
        val astral = "𝕳ello 👨‍👩‍👧‍👦 𠀋"
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = astral), book)!!
        assertEquals(astral, inputs.selectedText)
        assertEquals(astral, inputs.locator.textQuote)
        assertEquals(astral.length, inputs.locator.textQuote!!.length)
    }

    /** The parser caps at MAX_SELECTION_CHARS and drops wholesale; a text AT the cap is legal and
     *  must arrive intact — the mapper must not re-truncate what the parser already admitted. */
    @Test fun selectionToInputs_textAtTheFieldCapIsCarriedIntact() {
        val atCap = "字".repeat(8_000)
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = atCap), book)!!
        assertEquals(8_000, inputs.selectedText.length)
        assertEquals(atCap, inputs.locator.textQuote)
    }

    /** Dedupe: the same selection twice yields the same profileKey (re-highlighting upserts); two
     *  different ranges never collide, because `canonicalJson()` includes the cfi. */
    @Test fun selectionToInputs_profileKeyIsStableForTheSameRangeAndDistinctForAnother() {
        val a = Azw3AnnotationMapper.selectionToInputs(selection(), book)!!
        val b = Azw3AnnotationMapper.selectionToInputs(selection(), book)!!
        val other = Azw3AnnotationMapper.selectionToInputs(selection(cfi = "epubcfi(/6/26!/4/2/6,/1:0,/1:9)"), book)!!
        assertEquals(profileKeyFor(book.fingerprintKey, a.locator), profileKeyFor(book.fingerprintKey, b.locator))
        assertNotEquals(profileKeyFor(book.fingerprintKey, a.locator), profileKeyFor(book.fingerprintKey, other.locator))
    }

    /** The CFI shape the bundle mints round-trips verbatim — no normalization, trimming or re-encoding. */
    @Test fun selectionToInputs_cfiRoundTripsVerbatimIntoBothLocatorAndAnchor() {
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(cfi = realShapeCfi), book)!!
        assertEquals(realShapeCfi, inputs.locator.cfi)
        assertEquals(realShapeCfi, inputs.anchor.cfi)
        assertEquals(inputs.locator.cfi, Azw3AnnotationMapper.cfiFor(highlight(anchor = inputs.anchor)))
    }

    // ---- cfiFor ---------------------------------------------------------------------------

    @Test fun cfiFor_prefersTheAnchor() {
        val record = highlight(
            anchor = AnnotationAnchor.Epub(href = "", cfi = "epubcfi(/6/8!/4/2,/1:0,/1:5)"),
            locatorCfi = realShapeCfi,
        )
        assertEquals("epubcfi(/6/8!/4/2,/1:0,/1:5)", Azw3AnnotationMapper.cfiFor(record))
    }

    /**
     * THE load-bearing case. The backup wire carries NO anchor:
     * `AnnotationsRepository.restoreAnnotations` inserts every restored highlight with
     * `anchor = null`. Without the locator fallback every AZW3 highlight restored from a backup is
     * permanently invisible — it can never be handed to `readerAPI.addAnnotation`.
     */
    @Test fun cfiFor_nullAnchor_fallsBackToTheLocatorCfi() {
        val restored = highlight(anchor = null, locatorCfi = realShapeCfi)
        assertEquals(realShapeCfi, Azw3AnnotationMapper.cfiFor(restored))
    }

    @Test fun cfiFor_nullAnchorAndNullLocatorCfi_isNull() {
        assertNull(Azw3AnnotationMapper.cfiFor(highlight(anchor = null, locatorCfi = null)))
    }

    @Test fun cfiFor_nullAnchorAndBlankLocatorCfi_isNull() {
        assertNull(Azw3AnnotationMapper.cfiFor(highlight(anchor = null, locatorCfi = "   ")))
    }

    /** A blank anchor cfi is not a usable annotation key — fall through rather than hand
     *  `addAnnotation` a string that resolves to nothing. */
    @Test fun cfiFor_blankAnchorCfi_fallsBackToTheLocatorCfi() {
        val record = highlight(anchor = AnnotationAnchor.Epub(href = "", cfi = ""), locatorCfi = realShapeCfi)
        assertEquals(realShapeCfi, Azw3AnnotationMapper.cfiFor(record))
    }

    /** A Text anchor on an AZW3 row (a mixed/corrupt import) carries no cfi — fall through. */
    @Test fun cfiFor_textAnchor_fallsBackToTheLocatorCfi() {
        val record = highlight(
            anchor = AnnotationAnchor.Text(sourceUnitId = "u", startUTF16 = 0, endUTF16 = 3),
            locatorCfi = realShapeCfi,
        )
        assertEquals(realShapeCfi, Azw3AnnotationMapper.cfiFor(record))
    }

    @Test fun cfiFor_textAnchorAndNoLocatorCfi_isNull() {
        val record = highlight(
            anchor = AnnotationAnchor.Text(sourceUnitId = "u", startUTF16 = 0, endUTF16 = 3),
            locatorCfi = null,
        )
        assertNull(Azw3AnnotationMapper.cfiFor(record))
    }

    // ---- highlightIdForCfi ----------------------------------------------------------------

    @Test fun highlightIdForCfi_exactMatchOnTheAnchor() {
        val records = listOf(
            highlight(id = "a", anchor = AnnotationAnchor.Epub("", "epubcfi(/6/8!/4/2,/1:0,/1:5)")),
            highlight(id = "b", anchor = AnnotationAnchor.Epub("", realShapeCfi)),
        )
        assertEquals("b", Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, records))
    }

    /**
     * A RESTORED highlight has `anchor == null`, so it is painted under its LOCATOR cfi — therefore
     * a tap on it reports that same cfi and must resolve. Resolving only against the anchor would
     * make every restored highlight paintable but untappable (no EDIT popover, no remove).
     */
    @Test fun highlightIdForCfi_resolvesARestoredHighlightByItsLocatorCfi() {
        val restored = highlight(id = "restored", anchor = null, locatorCfi = realShapeCfi)
        assertEquals("restored", Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, listOf(restored)))
    }

    @Test fun highlightIdForCfi_firstMatchWinsInListOrder() {
        val records = listOf(
            highlight(id = "first", anchor = AnnotationAnchor.Epub("", realShapeCfi)),
            highlight(id = "second", anchor = AnnotationAnchor.Epub("", realShapeCfi)),
        )
        assertEquals("first", Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, records))
        // ... and the ordering is the LIST's, not an internal reshuffle.
        assertEquals("second", Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, records.reversed()))
    }

    @Test fun highlightIdForCfi_noMatch_isNull() {
        val records = listOf(highlight(id = "a", anchor = AnnotationAnchor.Epub("", realShapeCfi)))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("epubcfi(/6/99!/4/2,/1:0,/1:1)", records))
    }

    @Test fun highlightIdForCfi_blankCfi_isNoMatch() {
        val records = listOf(highlight(id = "a", anchor = AnnotationAnchor.Epub("", ""), locatorCfi = null))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("", records))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi("   ", records))
    }

    @Test fun highlightIdForCfi_emptyRecords_isNull() {
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, emptyList()))
    }

    /** Records with no resolvable cfi at all are skipped, never matched by accident. */
    @Test fun highlightIdForCfi_skipsRecordsWithNoCfi() {
        val records = listOf(
            highlight(id = "cfi-less", anchor = null, locatorCfi = null),
            highlight(id = "real", anchor = null, locatorCfi = realShapeCfi),
        )
        assertEquals("real", Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, records))
    }

    /** Exact string equality: a CFI differing only by whitespace or case is a DIFFERENT range. */
    @Test fun highlightIdForCfi_isExactNotFuzzy() {
        val records = listOf(highlight(id = "a", anchor = AnnotationAnchor.Epub("", realShapeCfi)))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(" $realShapeCfi", records))
        assertNull(Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi.uppercase(), records))
    }

    /** Resolution is a function of the stored strings only — the same input list yields the same id
     *  on every call, in any process (no hashing, no identity, no iteration-order surprise). */
    @Test fun highlightIdForCfi_isDeterministicAcrossRepeatedCalls() {
        val records = listOf(
            highlight(id = "a", anchor = AnnotationAnchor.Epub("", "epubcfi(/6/8!/4/2,/1:0,/1:5)")),
            highlight(id = "b", anchor = null, locatorCfi = realShapeCfi),
            highlight(id = "c", anchor = AnnotationAnchor.Epub("", realShapeCfi)),
        )
        val results = (1..50).map { Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, records) }
        assertEquals(setOf("b"), results.toSet())
    }

    /** A CJK quote does not disturb CFI resolution (the quote is not part of the key). */
    @Test fun highlightIdForCfi_matchesRegardlessOfTheQuoteContent() {
        val cjk = highlight(id = "cjk", anchor = AnnotationAnchor.Epub("", realShapeCfi))
            .copy(selectedText = "被偷走的勇气")
        assertEquals("cjk", Azw3AnnotationMapper.highlightIdForCfi(realShapeCfi, listOf(cjk)))
    }
}
