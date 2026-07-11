package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.annotations.NoteRecord
import org.junit.Assert.assertEquals
import org.junit.Test
import vreader.contracts.Locator

/**
 * Feature #132 WI-7-hosts — [pdfAnnotationPage] resolves the tap-to-jump target PAGE index from an
 * [AnnotationItem]'s locator, clamped to a valid page for a document of `pageCount` pages. A PDF locator
 * carries its position in `Locator.page`; a locator with no page (or a negative one) clamps to 0, and a
 * page past the end clamps to the last page (a safe scroll target). The PDF analog of the TXT
 * [annotationScrollOffset] — the AZW3 host has NO such helper (its tap-to-jump is null; capability gate).
 */
class PdfAnnotationPageTest {
    private val sha = "c".repeat(64)

    private fun highlightItem(page: Int?): AnnotationItem.Highlight =
        AnnotationItem.Highlight(
            HighlightRecord(
                id = "h", bookKey = "pdf:$sha:4096", color = AnnotationColor.DEFAULT,
                selectedText = "quote", note = null,
                locator = Locator(contentSHA256 = sha, fileByteCount = 4096L, format = "pdf", page = page),
                anchor = null, createdAt = 1L, updatedAt = 1L,
            ),
        )

    private fun noteItem(page: Int?): AnnotationItem.Note =
        AnnotationItem.Note(
            NoteRecord(
                id = "n", bookKey = "pdf:$sha:4096", content = "note",
                locator = Locator(contentSHA256 = sha, fileByteCount = 4096L, format = "pdf", page = page),
                anchor = null, createdAt = 1L, updatedAt = 1L,
            ),
        )

    @Test fun highlightUsesLocatorPage() =
        assertEquals(3, pdfAnnotationPage(highlightItem(page = 3), pageCount = 10))

    @Test fun noteUsesLocatorPage() =
        assertEquals(7, pdfAnnotationPage(noteItem(page = 7), pageCount = 10))

    @Test fun nullPageClampsToZero() =
        assertEquals(0, pdfAnnotationPage(noteItem(page = null), pageCount = 10))

    @Test fun negativePageClampsToZero() =
        assertEquals(0, pdfAnnotationPage(highlightItem(page = -4), pageCount = 10))

    @Test fun pagePastEndClampsToLast() =
        assertEquals(9, pdfAnnotationPage(highlightItem(page = 42), pageCount = 10))

    @Test fun emptyDocumentClampsToZero() =
        assertEquals(0, pdfAnnotationPage(highlightItem(page = 5), pageCount = 0))
}
