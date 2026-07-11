package com.vreader.app.reader.nav

import com.vreader.app.annotations.BookmarkRecord
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
 * Feature #135 WI-4 — the pure, read-time per-format bookmark presentation projection
 * ([BookmarkPresentation.bookmarkRow]). PURE JVM, no Android/Compose deps: the row is DERIVED
 * every call from the stored record + the format + (EPUB) the ordered TOC + (TXT/MD) a preview
 * provider — nothing is ever stored (Risk-7). Deterministic date via an injected fixed
 * zone+formatter so the tests assert an exact string.
 */
class BookmarkPresentationTest {

    private val sha = "a".repeat(64)

    // A fixed, deterministic date renderer so the exact string is assertable.
    private val fixedZone: ZoneId = ZoneId.of("UTC")
    private val fixedFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US)
    private val dateRenderer = BookmarkDateRenderer(fixedZone, fixedFormatter)

    // 2026-07-11T00:00:00Z = 1_783_728_000_000 ms.
    private val epochMs = 1_783_728_000_000L

    private fun record(
        format: BookFormat,
        href: String? = null,
        progression: Double? = null,
        totalProgression: Double? = null,
        page: Int? = null,
        charOffsetUTF16: Int? = null,
        title: String? = null,
    ): BookmarkRecord {
        val loc = Locator(
            contentSHA256 = sha,
            fileByteCount = 1234L,
            format = format.name,
            href = href,
            progression = progression,
            totalProgression = totalProgression,
            page = page,
            charOffsetUTF16 = charOffsetUTF16,
        )
        return BookmarkRecord(
            id = "id-1",
            bookKey = "$format:$sha:1234",
            title = title,
            locator = loc,
            createdAt = epochMs,
            updatedAt = epochMs,
        )
    }

    private fun tocEntry(
        title: String?,
        href: String,
        totalProgression: Double,
        progression: Double = 0.0,
        pageLabel: String? = null,
    ) = TocEntry(
        title = title,
        depth = 0,
        pageLabel = pageLabel,
        canonicalLocator = Locator(
            contentSHA256 = sha,
            fileByteCount = 1234L,
            format = "epub",
            href = href,
            progression = progression,
            totalProgression = totalProgression,
        ),
        epubReadiumLocator = null,
    )

    // ---- EPUB: chapter + page from the TOC (nearest at/above) ----

    @Test fun epub_chapterIsNearestTocEntryAtOrAbove() {
        val toc = listOf(
            tocEntry("Chapter 1", "ch1.xhtml", totalProgression = 0.0, pageLabel = "1"),
            tocEntry("Chapter 2", "ch2.xhtml", totalProgression = 0.3, pageLabel = "17"),
            tocEntry("Chapter 3", "ch3.xhtml", totalProgression = 0.6, pageLabel = "42"),
        )
        // Bookmark inside chapter 2 (totalProgression 0.45) -> Chapter 2.
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch2.xhtml", progression = 0.5, totalProgression = 0.45),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertEquals("Chapter 2", row.chapter)
        assertEquals("17", row.pageLabel)
        assertNull(row.preview)
    }

    @Test fun epub_exactBoundaryPicksThatEntry() {
        val toc = listOf(
            tocEntry("Chapter 1", "ch1.xhtml", totalProgression = 0.0),
            tocEntry("Chapter 2", "ch2.xhtml", totalProgression = 0.3),
        )
        // Exactly at Chapter 2's start.
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch2.xhtml", totalProgression = 0.3),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertEquals("Chapter 2", row.chapter)
    }

    @Test fun epub_beforeFirstEntryHasNullChapter() {
        val toc = listOf(
            tocEntry("Chapter 1", "ch1.xhtml", totalProgression = 0.2),
            tocEntry("Chapter 2", "ch2.xhtml", totalProgression = 0.6),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "front.xhtml", totalProgression = 0.05),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertNull(row.chapter)
        assertNull(row.pageLabel)
    }

    @Test fun epub_nullTocDegradesToNullChapter() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch2.xhtml", totalProgression = 0.45),
            BookFormat.epub, null, null, dateRenderer,
        )
        assertNull(row.chapter)
        assertNull(row.pageLabel)
        assertNull(row.preview)
    }

    @Test fun epub_emptyTocDegradesToNullChapter() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch2.xhtml", totalProgression = 0.45),
            BookFormat.epub, emptyList(), null, dateRenderer,
        )
        assertNull(row.chapter)
    }

    @Test fun azw3_usesTocLikeEpub() {
        val toc = listOf(
            tocEntry("Part One", "p1", totalProgression = 0.0),
            tocEntry("Part Two", "p2", totalProgression = 0.5),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.azw3, href = "p2", totalProgression = 0.7),
            BookFormat.azw3, toc, null, dateRenderer,
        )
        assertEquals("Part Two", row.chapter)
    }

    // ---- huge book: correct nearest entry + bounded (O(log n)) cost ----

    @Test fun epub_hugeBookFindsCorrectNearestEntry() {
        val n = 100_000
        val toc = (0 until n).map { i ->
            tocEntry("C$i", "c$i.xhtml", totalProgression = i.toDouble() / n, pageLabel = "$i")
        }
        // A bookmark at totalProgression just past entry 73_456's start.
        val target = 73_456
        val tp = target.toDouble() / n + 0.0000005 // strictly inside entry `target`
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "c$target.xhtml", totalProgression = tp),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertEquals("C$target", row.chapter)
        assertEquals("$target", row.pageLabel)
    }

    @Test fun epub_hugeBookLookupIsBounded() {
        // Bounds the comparison count via an instrumented list; a linear scan over 1M entries
        // would perform ~1M comparisons, binary search ~<=21. Assert well under a linear bound.
        val n = 1_000_000
        val base = (0 until n).map { i ->
            tocEntry("C$i", "c$i.xhtml", totalProgression = i.toDouble() / n)
        }
        var comparisons = 0
        val counting = object : AbstractList<TocEntry>() {
            override val size: Int get() = base.size
            override fun get(index: Int): TocEntry {
                comparisons++
                return base[index]
            }
        }
        BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "c999999.xhtml", totalProgression = 0.9999995),
            BookFormat.epub, counting, null, dateRenderer,
        )
        // O(log2 1_000_000) ~= 20; allow generous slack but assert far below linear.
        assertTrue("expected bounded (O(log n)) access, got $comparisons", comparisons <= 64)
    }

    // ---- PDF: p.N ----

    @Test fun pdf_pageLabelIsOneBased() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.pdf, page = 41),
            BookFormat.pdf, null, null, dateRenderer,
        )
        assertEquals("p. 42", row.pageLabel)
        assertNull(row.chapter)
        assertNull(row.preview)
    }

    @Test fun pdf_nullPageDegradesToNullLabel() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.pdf, page = null),
            BookFormat.pdf, null, null, dateRenderer,
        )
        assertNull(row.pageLabel)
    }

    // ---- TXT/MD: bounded, single-line, ellipsized preview ----

    @Test fun txt_previewFromProvider() {
        val provider = BookmarkPreviewProvider { offset, maxLen ->
            assertEquals(500, offset)
            assertEquals(120, maxLen)
            "A short snippet."
        }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = 500),
            BookFormat.txt, null, provider, dateRenderer,
        )
        assertEquals("A short snippet.", row.preview)
        assertNull(row.chapter)
        assertNull(row.pageLabel)
    }

    @Test fun txt_previewClampedToMaxAndEllipsized() {
        // The provider returns a raw, too-long, multi-line snippet; the projection clamps it.
        val raw = "line one\nline two " + "x".repeat(200)
        val provider = BookmarkPreviewProvider { _, _ -> raw }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = 0),
            BookFormat.txt, null, provider, dateRenderer,
        )
        val preview = row.preview!!
        assertTrue("preview must be <= 120 chars, was ${preview.length}", preview.length <= 120)
        assertTrue("truncated preview must be ellipsized", preview.endsWith("…"))
        assertTrue("preview must be single-line", !preview.contains('\n'))
    }

    @Test fun txt_shortPreviewNotEllipsized() {
        val provider = BookmarkPreviewProvider { _, _ -> "Tiny." }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = 0),
            BookFormat.txt, null, provider, dateRenderer,
        )
        assertEquals("Tiny.", row.preview)
    }

    @Test fun md_usesSameProviderPath() {
        val provider = BookmarkPreviewProvider { _, _ -> "Markdown bit." }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.md, charOffsetUTF16 = 10),
            BookFormat.md, null, provider, dateRenderer,
        )
        assertEquals("Markdown bit.", row.preview)
    }

    @Test fun txt_nullProviderDegradesToNullPreview() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = 500),
            BookFormat.txt, null, null, dateRenderer,
        )
        assertNull(row.preview)
    }

    @Test fun txt_providerReturningNullDegradesToNullPreview() {
        val provider = BookmarkPreviewProvider { _, _ -> null }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = 500),
            BookFormat.txt, null, provider, dateRenderer,
        )
        assertNull(row.preview)
    }

    @Test fun txt_nullOffsetPassesClampedNonNegativeOffset() {
        var seen = -1
        val provider = BookmarkPreviewProvider { offset, _ ->
            seen = offset
            "ok"
        }
        BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = null),
            BookFormat.txt, null, provider, dateRenderer,
        )
        // A missing offset clamps to 0 (never negative -> no provider crash).
        assertEquals(0, seen)
    }

    @Test fun txt_negativeOffsetClampedToZero() {
        var seen = -1
        val provider = BookmarkPreviewProvider { offset, _ ->
            seen = offset
            "ok"
        }
        val loc = Locator(
            contentSHA256 = sha, fileByteCount = 1234L, format = "txt", charOffsetUTF16 = null,
        ).copy(charOffsetUTF16 = -50)
        BookmarkPresentation.bookmarkRow(
            BookmarkRecord("id-1", "txt:$sha:1234", null, loc, epochMs, epochMs),
            BookFormat.txt, null, provider, dateRenderer,
        )
        assertEquals(0, seen)
    }

    @Test fun txt_providerCJKPreservedWithinClamp() {
        // CJK snippet: the provider owns the substring; the projection only clamps/ellipsizes.
        val cjk = "第一章 " + "字".repeat(200)
        val provider = BookmarkPreviewProvider { _, _ -> cjk }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = 0),
            BookFormat.txt, null, provider, dateRenderer,
        )
        val preview = row.preview!!
        assertTrue(preview.length <= 120)
        assertTrue(preview.endsWith("…"))
    }

    // ---- deterministic date label ----

    @Test fun dateLabelIsDeterministic() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.pdf, page = 0),
            BookFormat.pdf, null, null, dateRenderer,
        )
        assertEquals("2026-07-11", row.dateLabel)
    }

    @Test fun dateLabelHonoursInjectedZone() {
        // Same instant, a zone west of UTC that rolls the calendar date back a day.
        val laRenderer = BookmarkDateRenderer(
            ZoneId.of("America/Los_Angeles"),
            DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.pdf, page = 0),
            BookFormat.pdf, null, null, laRenderer,
        )
        // 2026-07-11T00:00:00Z is 2026-07-10 17:00 in LA.
        assertEquals("2026-07-10", row.dateLabel)
    }
}
