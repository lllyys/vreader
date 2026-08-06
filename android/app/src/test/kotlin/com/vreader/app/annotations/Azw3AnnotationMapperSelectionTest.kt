package com.vreader.app.annotations

import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.FoliateMessage
import com.vreader.app.reader.foliate.FoliateMessageParser
import com.vreader.app.reader.foliate.SelectionRect
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import java.text.Normalizer

/**
 * Feature #142 WI-2 — [Azw3AnnotationMapper.selectionToInputs]: a foliate `selection` message ->
 * the persistable (Locator + anchor + text) triple.
 *
 * Assertions go through the REAL persistence path ([HighlightRecord.toEntity]) wherever the claim is
 * about what survives storage, so a test cannot pass against a serializer that silently mangles the
 * quote. Pure JVM: nothing here touches Android, Room or a WebView.
 */
class Azw3AnnotationMapperSelectionTest {

    // A CFI in the shape the bundle mints for MOBI/KF8: `CFI.fake.fromIndex(i)` = /6/((i+1)*2),
    // joined indirectly with the range CFI.
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

    /** Persist the mapper's output the way the app does, so assertions observe the STORED form. */
    private fun store(inputs: Azw3SelectionInputs) = HighlightRecord(
        id = "h1", bookKey = book.fingerprintKey, color = AnnotationColor.DEFAULT,
        selectedText = inputs.selectedText, note = null,
        locator = inputs.locator, anchor = inputs.anchor,
        createdAt = 1L, updatedAt = 1L,
    ).toEntity()

    private fun decodeLocator(json: String): Locator =
        Json { ignoreUnknownKeys = true }.decodeFromString(json)

    // ---- locator + anchor shape -----------------------------------------------------------

    @Test fun buildsLocatorFieldForField() {
        val loc = Azw3AnnotationMapper.selectionToInputs(selection(), book)!!.locator
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

    @Test fun anchorIsEpubWithEmptyHrefAndTheSelectionCfi() {
        val anchor = Azw3AnnotationMapper.selectionToInputs(selection(), book)!!.anchor
        assertEquals("", anchor.href)
        assertEquals(realShapeCfi, anchor.cfi)
        assertNull(anchor.serializedRange)
        assertNull(anchor.readiumLocatorJSON)
    }

    /**
     * The locator must address the BOOK IT CAME FROM. iOS derives the format from the book's own
     * fingerprint (`FoliateSpikeView+Selection.swift`), so a locator whose `fingerprintKey` differs
     * from the book's is an orphan annotation no reader can resolve. Stated so it DISCRIMINATES: a
     * hardcoded `azw3` passes the azw3 case and fails this one.
     */
    @Test fun formatFollowsTheBookNotAConstant() {
        val azw3 = Azw3AnnotationMapper.selectionToInputs(selection(), book)!!
        assertEquals(book.fingerprintKey, azw3.locator.fingerprintKey)

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

    /**
     * The rect is view-only and sectionIndex is derived from the CFI's first step — neither is
     * stored. Asserted on the PERSISTED columns (not DTO equality), so this pins what reaches Room.
     */
    @Test fun rectAndSectionIndexReachNoPersistedColumn() {
        val a = store(Azw3AnnotationMapper.selectionToInputs(selection(sectionIndex = 0, rect = null), book)!!)
        val b = store(
            Azw3AnnotationMapper.selectionToInputs(
                selection(sectionIndex = 999, rect = SelectionRect(1.0, 2.0, 3.0, 4.0)), book,
            )!!,
        )
        assertEquals(a.locatorJSON, b.locatorJSON)
        assertEquals(a.anchorJSON, b.anchorJSON)
        assertEquals(a.profileKey, b.profileKey)
        assertEquals(a.anchorKey, b.anchorKey)
        assertEquals(a.selectedText, b.selectedText)
    }

    // ---- unusable selections --------------------------------------------------------------

    @Test fun blankText_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(text = "   \n\t "), book))
    }

    @Test fun emptyText_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(text = ""), book))
    }

    @Test fun blankCfi_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(cfi = "  "), book))
    }

    @Test fun emptyCfi_isNull() {
        assertNull(Azw3AnnotationMapper.selectionToInputs(selection(cfi = ""), book))
    }

    // ---- Unicode: the real book is CJK, so this is the primary case -----------------------

    /** The stored quote is byte-exact through the REAL persistence path — no normalization, no
     *  escaping damage, no truncation. */
    @Test fun cjkQuoteIsByteExactThroughThePersistedLocator() {
        val cjk = "被偷走的勇气：自我"
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = cjk), book)!!
        assertEquals(cjk, inputs.selectedText)
        assertEquals(cjk, inputs.locator.textQuote)
        assertEquals(cjk, decodeLocator(store(inputs).locatorJSON).textQuote)
    }

    @Test fun surrogatePairsAndEmojiAreByteExactThroughThePersistedLocator() {
        val astral = "𝕳ello 👨‍👩‍👧‍👦 𠀋"
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = astral), book)!!
        assertEquals(astral, inputs.selectedText)
        assertEquals(astral, decodeLocator(store(inputs).locatorJSON).textQuote)
    }

    /**
     * The dedupe key folds Unicode where the stored form does not. `canonicalJson()` NFC-normalizes
     * `textQuote` to match Swift `precomposedStringWithCanonicalMapping` (bug #356), so the SAME text
     * selected as NFD and as NFC dedupes to one row cross-platform — while the STORED quote keeps
     * whatever the engine handed us. Both halves are asserted; neither is assumed.
     *
     * The fixture is built with the JDK normalizer, never typed as two literals: an editor or a
     * source-file round-trip can silently recompose an NFD literal, which would make this test pass
     * vacuously.
     */
    @Test fun profileKeyFoldsNfdToNfcWhileTheStoredQuoteKeepsItsOriginalForm() {
        val nfc = Normalizer.normalize("café 한글", Normalizer.Form.NFC)
        val nfd = Normalizer.normalize(nfc, Normalizer.Form.NFD)
        assertNotEquals("fixture must actually differ in code points", nfc, nfd)

        val fromNfc = store(Azw3AnnotationMapper.selectionToInputs(selection(text = nfc), book)!!)
        val fromNfd = store(Azw3AnnotationMapper.selectionToInputs(selection(text = nfd), book)!!)

        // Same range, same logical text -> ONE dedupe identity, across platforms.
        assertEquals(fromNfc.profileKey, fromNfd.profileKey)
        // ... but each row still stores exactly the bytes its engine produced.
        assertEquals(nfc, decodeLocator(fromNfc.locatorJSON).textQuote)
        assertEquals(nfd, decodeLocator(fromNfd.locatorJSON).textQuote)
    }

    /** A CJK quote participates in the dedupe key like any other: same range -> same key, different
     *  range or different quote -> different key. (An ASCII-only case would not catch a quote
     *  dropped from the canonical form only for non-ASCII input.) */
    @Test fun profileKeyIsStableForTheSameCjkRangeAndDistinctForAnother() {
        val cjk = "被偷走的勇气"
        val a = store(Azw3AnnotationMapper.selectionToInputs(selection(text = cjk), book)!!)
        val b = store(Azw3AnnotationMapper.selectionToInputs(selection(text = cjk), book)!!)
        val otherRange = store(
            Azw3AnnotationMapper.selectionToInputs(
                selection(text = cjk, cfi = "epubcfi(/6/26!/4/2/6,/1:0,/1:9)"), book,
            )!!,
        )
        val otherQuote = store(Azw3AnnotationMapper.selectionToInputs(selection(text = "自我"), book)!!)

        assertEquals(a.profileKey, b.profileKey)
        assertNotEquals(a.profileKey, otherRange.profileKey)
        assertNotEquals(a.profileKey, otherQuote.profileKey)
    }

    // ---- field-cap boundaries -------------------------------------------------------------

    /** A text AT the parser's cap is legal and must arrive intact — the mapper must never
     *  re-truncate what the parser already admitted. */
    @Test fun textAtTheParserCapIsCarriedIntact() {
        val atCap = "字".repeat(FoliateMessageParser.MAX_SELECTION_CHARS)
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = atCap), book)!!
        assertEquals(FoliateMessageParser.MAX_SELECTION_CHARS, inputs.selectedText.length)
        assertEquals(atCap, decodeLocator(store(inputs).locatorJSON).textQuote)
    }

    /** Same for the CFI cap: a maximal CFI must survive verbatim, because a CFI that is "almost
     *  right" resolves to a DIFFERENT range rather than a less precise one. */
    @Test fun cfiAtTheParserCapIsCarriedIntact() {
        val prefix = "epubcfi(/6/24!/4/2/6,"
        val atCap = prefix + "1".repeat(FoliateMessageParser.MAX_CFI_CHARS - prefix.length - 1) + ")"
        assertEquals(FoliateMessageParser.MAX_CFI_CHARS, atCap.length)
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(cfi = atCap), book)!!
        assertEquals(atCap, inputs.locator.cfi)
        assertEquals(atCap, inputs.anchor.cfi)
        assertEquals(atCap, decodeLocator(store(inputs).locatorJSON).cfi)
    }

    /**
     * The division of responsibility, pinned: enforcing the size caps is the PARSER's job — it drops
     * an over-cap message WHOLESALE rather than truncating — so a direct mapper call deliberately
     * passes over-cap values through untouched. A "defensive" truncation added here later would
     * silently corrupt the dedupe key and the backup row; this test fails if anyone adds one.
     */
    @Test fun overCapInputIsPassedThroughBecauseTheParserOwnsTheCaps() {
        val overCap = "字".repeat(FoliateMessageParser.MAX_SELECTION_CHARS + 1)
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(text = overCap), book)!!
        assertEquals(FoliateMessageParser.MAX_SELECTION_CHARS + 1, inputs.selectedText.length)
        assertEquals(overCap, inputs.locator.textQuote)

        // ... and this is what actually stops an over-cap selection reaching the mapper in production.
        val tooLong = "x".repeat(FoliateMessageParser.MAX_SELECTION_CHARS + 1)
        val raw = """{"name":"selection","detail":{"text":"$tooLong","cfi":"$realShapeCfi","index":11}}"""
        assertNull(FoliateMessageParser.parse(raw))
    }

    /** The CFI round-trips verbatim into BOTH stores — no trimming, case folding or re-encoding. */
    @Test fun cfiRoundTripsVerbatimIntoBothLocatorAndAnchor() {
        val inputs = Azw3AnnotationMapper.selectionToInputs(selection(cfi = realShapeCfi), book)!!
        assertEquals(realShapeCfi, inputs.locator.cfi)
        assertEquals(realShapeCfi, inputs.anchor.cfi)
    }
}
