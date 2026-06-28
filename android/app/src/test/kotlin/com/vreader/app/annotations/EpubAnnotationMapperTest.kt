package com.vreader.app.annotations

import com.vreader.app.data.Book
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import vreader.contracts.BookFormat

/** Feature #123 WI-3 — [EpubAnnotationMapper]: Readium selection <-> annotation domain. */
@RunWith(RobolectricTestRunner::class)
class EpubAnnotationMapperTest {
    private val book = Book(
        fingerprintKey = "epub:${"a".repeat(64)}:2048", title = "Moby Dick",
        originalFormat = BookFormat.epub, contentSHA256 = "a".repeat(64), fileByteCount = 2048L,
        addedAt = 1L,
    )

    private fun readiumLocator(highlight: String?, progression: Double? = 0.42) = ReadiumLocator(
        href = Url("chapter1.xhtml")!!,
        mediaType = MediaType.XHTML,
        locations = ReadiumLocator.Locations(progression = progression, totalProgression = 0.10),
        text = ReadiumLocator.Text(before = "Call me ", highlight = highlight, after = ". Some years ago"),
    )

    @Test fun selection_withHighlight_mapsToCanonicalLocatorAndAnchor() {
        val inputs = EpubAnnotationMapper.selectionToInputs(readiumLocator("Ishmael"), book)
        assertNotNull(inputs)
        assertEquals("Ishmael", inputs!!.selectedText)
        assertEquals("chapter1.xhtml", inputs.locator.href)
        assertEquals(0.42, inputs.locator.progression!!, 1e-9)
        assertEquals("Ishmael", inputs.locator.textQuote)
        assertEquals("Call me ", inputs.locator.textContextBefore)
        assertEquals(book.fingerprintKey, inputs.locator.fingerprintKey)
        assertEquals("chapter1.xhtml", inputs.anchor.href)
        assertNotNull("keeps the verbatim Readium JSON for lossless re-apply", inputs.anchor.readiumLocatorJSON)
    }

    @Test fun selection_withoutHighlight_isRejected() {
        assertNull(EpubAnnotationMapper.selectionToInputs(readiumLocator(null), book))
        assertNull(EpubAnnotationMapper.selectionToInputs(readiumLocator("   "), book))
    }

    @Test fun storedHighlight_reconstructsReadiumLocator_forDecoration() {
        val inputs = EpubAnnotationMapper.selectionToInputs(readiumLocator("Ishmael"), book)!!
        val record = HighlightRecord(
            id = "h1", bookKey = book.fingerprintKey, color = AnnotationColor.yellow,
            selectedText = inputs.selectedText, note = null, locator = inputs.locator,
            anchor = inputs.anchor, createdAt = 1L, updatedAt = 1L,
        )
        val readium = EpubAnnotationMapper.readiumLocatorFor(record)
        assertNotNull("round-trips the Readium locator via fromJSON", readium)
        assertEquals("chapter1.xhtml", readium!!.href.toString())
        assertEquals("Ishmael", readium.text.highlight)
    }

    @Test fun storedHighlight_withoutReadiumJson_returnsNull() {
        val record = HighlightRecord(
            id = "h1", bookKey = book.fingerprintKey, color = AnnotationColor.yellow,
            selectedText = "x", note = null,
            locator = vreader.contracts.Locator("a".repeat(64), 2048L, "epub", href = "c", cfi = "/4:1"),
            anchor = AnnotationAnchor.Epub(href = "c", cfi = "/4:1", readiumLocatorJSON = null),
            createdAt = 1L, updatedAt = 1L,
        )
        assertNull(EpubAnnotationMapper.readiumLocatorFor(record))
    }
}
