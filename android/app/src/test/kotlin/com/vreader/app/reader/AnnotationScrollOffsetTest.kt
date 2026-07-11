package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.annotations.NoteRecord
import org.junit.Assert.assertEquals
import org.junit.Test
import vreader.contracts.Locator

/**
 * Feature #132 WI-6 — [annotationScrollOffset] resolves the tap-to-jump target UTF-16 offset from an
 * [AnnotationItem]'s locator. A highlight anchors at its `charRangeStartUTF16`; a standalone note at its
 * `charOffsetUTF16`; a locator carrying neither (or a negative value) clamps to 0 (a safe scroll target).
 */
class AnnotationScrollOffsetTest {
    private val sha = "b".repeat(64)

    private fun highlightItem(start: Int?, end: Int?, offset: Int? = null): AnnotationItem.Highlight =
        AnnotationItem.Highlight(
            HighlightRecord(
                id = "h", bookKey = "txt:$sha:2048", color = AnnotationColor.DEFAULT,
                selectedText = "quote", note = null,
                locator = Locator(
                    contentSHA256 = sha, fileByteCount = 2048L, format = "txt",
                    charRangeStartUTF16 = start, charRangeEndUTF16 = end, charOffsetUTF16 = offset,
                ),
                anchor = null, createdAt = 1L, updatedAt = 1L,
            ),
        )

    private fun noteItem(offset: Int?): AnnotationItem.Note =
        AnnotationItem.Note(
            NoteRecord(
                id = "n", bookKey = "txt:$sha:2048", content = "note",
                locator = Locator(
                    contentSHA256 = sha, fileByteCount = 2048L, format = "txt", charOffsetUTF16 = offset,
                ),
                anchor = null, createdAt = 1L, updatedAt = 1L,
            ),
        )

    @Test fun highlightUsesRangeStart() =
        assertEquals(128, annotationScrollOffset(highlightItem(start = 128, end = 140)))

    @Test fun noteUsesCharOffset() =
        assertEquals(99, annotationScrollOffset(noteItem(offset = 99)))

    @Test fun highlightFallsBackToCharOffsetWhenNoRange() =
        assertEquals(7, annotationScrollOffset(highlightItem(start = null, end = null, offset = 7)))

    @Test fun noOffsetInfoClampsToZero() =
        assertEquals(0, annotationScrollOffset(noteItem(offset = null)))

    @Test fun negativeOffsetClampsToZero() =
        assertEquals(0, annotationScrollOffset(noteItem(offset = -5)))
}
