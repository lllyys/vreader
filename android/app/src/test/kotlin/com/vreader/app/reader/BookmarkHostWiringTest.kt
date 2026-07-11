package com.vreader.app.reader

import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.foliate.Azw3GoToResult
import com.vreader.app.reader.nav.BookmarkDateRenderer
import com.vreader.app.reader.nav.BookmarkPreviewProvider
import com.vreader.app.reader.nav.BookmarkTocIndex
import com.vreader.app.reader.nav.JumpResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Feature #135 WI-7 — the PURE, JVM-testable cores of the per-host bookmark wiring (the integrator that
 * lights up create/toggle/list/jump). The Compose/Activity glue rides WI-9 acceptance (per the #132/#134
 * precedent); this suite pins the deterministic seams:
 *  - EPUB current-position → canonical [Locator] mapping ([epubBookmarkLocator]);
 *  - the per-host bookmarks-list build from stored records ([bookmarkRowItems]);
 *  - the per-host jump-target resolution + its [JumpResult] mapping (EPUB/AZW3/TXT/PDF, incl. every
 *    out-of-range / failure degrade → [JumpResult.Failed] so the sheet stays open — rule 51).
 */
class BookmarkHostWiringTest {

    private val sha = "b".repeat(64)
    private val byteCount = 4096L
    private fun bookKey(f: BookFormat) = "${f.name}:$sha:$byteCount"

    private val fixedZone: ZoneId = ZoneId.of("UTC")
    private val fixedFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US)
    private val dateRenderer = BookmarkDateRenderer(fixedZone, fixedFormatter)
    private val epochMs = 1_783_728_000_000L // 2026-07-11T00:00:00Z

    private fun record(
        format: BookFormat,
        href: String? = null,
        progression: Double? = null,
        page: Int? = null,
        charOffsetUTF16: Int? = null,
        id: String = "id-1",
    ): BookmarkRecord = BookmarkRecord(
        id = id,
        bookKey = bookKey(format),
        title = null,
        locator = Locator(
            contentSHA256 = sha, fileByteCount = byteCount, format = format.name,
            href = href, progression = progression, page = page, charOffsetUTF16 = charOffsetUTF16,
        ),
        createdAt = epochMs,
        updatedAt = epochMs,
    )

    // ---- EPUB current-position → canonical Locator ----

    @Test fun epubLocator_carriesIdentityAndPosition() {
        val loc = epubBookmarkLocator(
            href = "chapter1.xhtml", progression = 0.4, totalProgression = 0.1, cfi = "epubcfi(/6/2!/4/2)",
            contentSHA256 = sha, fileByteCount = byteCount, format = BookFormat.epub.name,
        )
        assertEquals(bookKey(BookFormat.epub), loc.fingerprintKey)
        assertEquals("chapter1.xhtml", loc.href)
        assertEquals(0.4, loc.progression!!, 1e-9)
        assertEquals(0.1, loc.totalProgression!!, 1e-9)
        assertEquals("epubcfi(/6/2!/4/2)", loc.cfi)
        // A bookmark is a POSITION, not a selection — no text quote is carried (distinct from a highlight).
        assertNull(loc.textQuote)
    }

    @Test fun epubLocator_blankCfi_isNull() {
        val loc = epubBookmarkLocator(
            href = "c.xhtml", progression = 0.2, totalProgression = null, cfi = "",
            contentSHA256 = sha, fileByteCount = byteCount, format = BookFormat.epub.name,
        )
        assertNull(loc.cfi)
        assertNull(loc.totalProgression)
    }

    @Test fun epubLocator_isValid() {
        val loc = epubBookmarkLocator(
            href = "c.xhtml", progression = 0.5, totalProgression = 0.5, cfi = null,
            contentSHA256 = sha, fileByteCount = byteCount, format = BookFormat.epub.name,
        )
        assertNull(loc.validate()) // structurally valid → toReadium won't reject it up front
    }

    // ---- bookmarks list build ----

    @Test fun bookmarkRowItems_pdf_projectsPageLabel() {
        val items = bookmarkRowItems(
            records = listOf(record(BookFormat.pdf, page = 4)),
            format = BookFormat.pdf, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer,
        )
        assertEquals(1, items.size)
        assertEquals("p. 5", items[0].ui.pageLabel) // one-based
        assertEquals("2026-07-11", items[0].ui.dateLabel)
        assertEquals("id-1", items[0].record.id) // the record is carried back for the jump
    }

    @Test fun bookmarkRowItems_txt_usesPreviewProvider() {
        val provider = BookmarkPreviewProvider { offset, _ -> "snippet@$offset" }
        val items = bookmarkRowItems(
            records = listOf(record(BookFormat.txt, charOffsetUTF16 = 120)),
            format = BookFormat.txt, tocIndex = null, previewProvider = provider, dateRenderer = dateRenderer,
        )
        assertEquals("snippet@120", items[0].ui.preview)
        assertNull(items[0].ui.chapter)
    }

    @Test fun bookmarkRowItems_epub_usesTocIndexChapter() {
        val toc = BookmarkTocIndex.build(
            listOf(
                com.vreader.app.reader.nav.TocEntry(
                    title = "Chapter One", depth = 0, pageLabel = "1",
                    canonicalLocator = Locator(
                        contentSHA256 = sha, fileByteCount = byteCount, format = BookFormat.epub.name,
                        href = "c1.xhtml", progression = 0.0, totalProgression = 0.0,
                    ),
                    epubReadiumLocator = null,
                ),
            ),
        )
        val bm = record(BookFormat.epub, href = "c1.xhtml", progression = 0.5).copy(
            locator = record(BookFormat.epub, href = "c1.xhtml", progression = 0.5).locator.copy(totalProgression = 0.2),
        )
        val items = bookmarkRowItems(
            records = listOf(bm), format = BookFormat.epub, tocIndex = toc, previewProvider = null, dateRenderer = dateRenderer,
        )
        assertEquals("Chapter One", items[0].ui.chapter)
    }

    @Test fun bookmarkRowItems_empty_returnsEmpty() {
        val items = bookmarkRowItems(
            records = emptyList(), format = BookFormat.txt, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer,
        )
        assertTrue(items.isEmpty())
    }

    // ---- AZW3 jump-result mapping ----

    @Test fun azw3JumpResult_succeeded() =
        assertEquals(JumpResult.Succeeded, azw3JumpResult(Azw3GoToResult.Succeeded(cfi = "epubcfi(x)", fraction = 0.3)))

    @Test fun azw3JumpResult_timeoutFailedSuperseded_allFail() {
        assertEquals(JumpResult.Failed, azw3JumpResult(Azw3GoToResult.Timeout))
        assertEquals(JumpResult.Failed, azw3JumpResult(Azw3GoToResult.Failed))
        // A superseded jump (a newer jump replaced it) is not a landing → the sheet stays open too.
        assertEquals(JumpResult.Failed, azw3JumpResult(Azw3GoToResult.Superseded))
    }

    // ---- TXT scroll target (out-of-range → Failed) ----

    @Test fun txtBookmarkScrollTarget_inRange() {
        assertEquals(50, txtBookmarkScrollTarget(offset = 50, textLength = 100))
        assertEquals(99, txtBookmarkScrollTarget(offset = 99, textLength = 100)) // last valid index is in range
    }

    @Test fun txtBookmarkScrollTarget_atOrPastEof_null() {
        // At/past EOF is OUT of range → Failed (a corrupt / cross-file-restored anchor), the PDF-analog posture.
        assertNull(txtBookmarkScrollTarget(offset = 100, textLength = 100)) // offset == length → out of range
        assertNull(txtBookmarkScrollTarget(offset = 150, textLength = 100)) // offset > length → out of range
    }

    @Test fun txtBookmarkScrollTarget_negativeOrEmpty_null() {
        assertNull(txtBookmarkScrollTarget(offset = -1, textLength = 100)) // negative → Failed
        assertNull(txtBookmarkScrollTarget(offset = null, textLength = 100)) // no offset → Failed
        assertNull(txtBookmarkScrollTarget(offset = 0, textLength = 0)) // empty document → Failed
    }

    // ---- PDF page target (out-of-range → Failed) ----

    @Test fun pdfBookmarkPageTarget_inRange() =
        assertEquals(3, pdfBookmarkPageTarget(page = 3, pageCount = 10))

    @Test fun pdfBookmarkPageTarget_outOfRange_null() {
        assertNull(pdfBookmarkPageTarget(page = 10, pageCount = 10)) // page == count → out of range → Failed
        assertNull(pdfBookmarkPageTarget(page = -1, pageCount = 10)) // negative → Failed
        assertNull(pdfBookmarkPageTarget(page = null, pageCount = 10)) // no page → Failed
        assertNull(pdfBookmarkPageTarget(page = 0, pageCount = 0)) // empty document → Failed
    }
}
