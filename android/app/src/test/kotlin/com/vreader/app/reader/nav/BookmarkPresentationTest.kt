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

    private fun index(vararg entries: TocEntry): BookmarkTocIndex =
        BookmarkTocIndex.build(entries.toList())

    @Test fun epub_chapterIsNearestTocEntryAtOrAbove() {
        val toc = index(
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
        val toc = index(
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
        val toc = index(
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
            BookFormat.epub, index(), null, dateRenderer,
        )
        assertNull(row.chapter)
    }

    @Test fun epub_partialTocMissingTotalProgressionUsesHrefFallback() {
        // Not every entry carries totalProgression (a partially-populated TOC): totalProgression is
        // NOT a reliable cross-chapter key here, so build-time validation flags it non-monotonic and
        // the lookup falls back to href matching — returning the correct chapter, not a wrong one.
        val toc = index(
            TocEntry("Chapter 1", 0, "1",
                Locator(sha, 1234L, "epub", href = "ch1.xhtml", progression = 0.0), null),
            // Chapter 2 lacks totalProgression.
            TocEntry("Chapter 2", 0, "17",
                Locator(sha, 1234L, "epub", href = "ch2.xhtml", progression = 0.0), null),
            TocEntry("Chapter 3", 0, "42",
                Locator(sha, 1234L, "epub", href = "ch3.xhtml", progression = 0.0,
                    totalProgression = 0.6), null),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch2.xhtml", progression = 0.5),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertEquals("Chapter 2", row.chapter)
        assertEquals("17", row.pageLabel)
    }

    @Test fun epub_soleMissingTotalProgressionOutsideProbePathStillDetected() {
        // The auditor's targeted case: a large ODD-sized TOC whose SOLE null totalProgression lies
        // OUTSIDE the binary-search probe path. Build-time validation (a full single O(n) pass) flags
        // the TOC non-monotonic regardless of where the null sits, so the lookup uses the href fallback
        // and returns the right chapter instead of a fabricated one from a broken binary search.
        val n = 1023 // odd size
        val entries = (0 until n).map { i ->
            val tp = if (i == 0) null else i.toDouble() / n // the null is at index 0 (skipped by a right-leaning probe)
            TocEntry("C$i", 0, "$i",
                Locator(sha, 1234L, "epub", href = "c$i.xhtml", progression = 0.0, totalProgression = tp),
                null)
        }
        val toc = BookmarkTocIndex.build(entries)
        // Target has totalProgression + a matching href.
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "c700.xhtml", progression = 0.0, totalProgression = 700.0 / n),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertEquals("C700", row.chapter)
    }

    @Test fun epub_hrefFallbackPicksGreatestProgressionNotListOrder() {
        // Same-href entries OUT of list order + a non-monotonic TOC (forces the href fallback). The
        // fallback must pick the entry with the GREATEST progression <= target, not the last in list
        // order. (Also includes a distinct href to keep the TOC non-monotonic and multi-chapter.)
        val toc = index(
            TocEntry("Preface", 0, "0",
                Locator(sha, 1234L, "epub", href = "front.xhtml", progression = 0.0), null),
            TocEntry("Section A (0.40)", 0, "10",
                Locator(sha, 1234L, "epub", href = "ch.xhtml", progression = 0.40), null),
            TocEntry("Section B (0.10)", 0, "5",
                Locator(sha, 1234L, "epub", href = "ch.xhtml", progression = 0.10), null),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch.xhtml", progression = 0.50),
            BookFormat.epub, toc, null, dateRenderer,
        )
        // A=0.40 is the nearest at/above; B=0.10 is farther even though it appears LAST in the list.
        assertEquals("Section A (0.40)", row.chapter)
        assertEquals("10", row.pageLabel)
    }

    @Test fun epub_hrefFallbackSkipsNullProgressionEntry() {
        // A same-href entry with a null progression is unplaceable -> skipped, never fabricated.
        val toc = index(
            TocEntry("Placeable (0.20)", 0, "8",
                Locator(sha, 1234L, "epub", href = "ch.xhtml", progression = 0.20), null),
            TocEntry("Unplaceable (null)", 0, "9",
                Locator(sha, 1234L, "epub", href = "ch.xhtml", progression = null), null),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "ch.xhtml", progression = 0.50),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertEquals("Placeable (0.20)", row.chapter)
    }

    @Test fun epub_targetWithoutTotalProgressionAndUnknownHrefYieldsNullChapter() {
        // The target has neither totalProgression nor a matching href -> no fabricated chapter.
        val toc = index(
            TocEntry("Chapter 1", 0, "1",
                Locator(sha, 1234L, "epub", href = "ch1.xhtml", progression = 0.0), null),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "unknown.xhtml", progression = 0.5),
            BookFormat.epub, toc, null, dateRenderer,
        )
        assertNull(row.chapter)
        assertNull(row.pageLabel)
    }

    @Test fun azw3_usesTocLikeEpub() {
        val toc = index(
            tocEntry("Part One", "p1", totalProgression = 0.0),
            tocEntry("Part Two", "p2", totalProgression = 0.5),
        )
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.azw3, href = "p2", totalProgression = 0.7),
            BookFormat.azw3, toc, null, dateRenderer,
        )
        assertEquals("Part Two", row.chapter)
    }

    // ---- huge book: correct nearest entry + bounded (O(log n)) LOOKUP cost ----

    @Test fun epub_hugeBookFindsCorrectNearestEntry() {
        val n = 100_000
        val toc = BookmarkTocIndex.build(
            (0 until n).map { i ->
                tocEntry("C$i", "c$i.xhtml", totalProgression = i.toDouble() / n, pageLabel = "$i")
            }
        )
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
        // The LOOKUP (post-build) is O(log n): a linear scan over 1M entries would touch ~1M entries,
        // binary search ~<=20. The index retains the given list by reference, so a counting list sees
        // both the build pass and each lookup; we reset the counter AFTER build to isolate the lookup.
        val n = 1_000_000
        val base = (0 until n).map { i ->
            tocEntry("C$i", "c$i.xhtml", totalProgression = i.toDouble() / n)
        }
        var accesses = 0
        val counting = object : AbstractList<TocEntry>() {
            override val size: Int get() = base.size
            override fun get(index: Int): TocEntry {
                accesses++
                return base[index]
            }
        }
        val toc = BookmarkTocIndex.build(counting)
        accesses = 0 // isolate the lookup from the O(n) build validation pass
        BookmarkPresentation.bookmarkRow(
            record(BookFormat.epub, href = "c999999.xhtml", totalProgression = 0.9999995),
            BookFormat.epub, toc, null, dateRenderer,
        )
        // O(log2 1_000_000) ~= 20; assert far below the linear (1M) bound.
        assertTrue("expected bounded (O(log n)) lookup, got $accesses", accesses <= 64)
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

    @Test fun pdf_pageZeroIsOne() {
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.pdf, page = 0),
            BookFormat.pdf, null, null, dateRenderer,
        )
        assertEquals("p. 1", row.pageLabel)
    }

    @Test fun pdf_negativePageDegradesToNull() {
        // A structurally-invalid stored page index must not render "p. 0" or crash.
        val loc = Locator(
            contentSHA256 = sha, fileByteCount = 1234L, format = "pdf",
        ).copy(page = -3)
        val row = BookmarkPresentation.bookmarkRow(
            BookmarkRecord("id-1", "pdf:$sha:1234", null, loc, epochMs, epochMs),
            BookFormat.pdf, null, null, dateRenderer,
        )
        assertNull(row.pageLabel)
    }

    @Test fun pdf_intMaxPageDegradesToNullNoOverflow() {
        val loc = Locator(
            contentSHA256 = sha, fileByteCount = 1234L, format = "pdf",
        ).copy(page = Int.MAX_VALUE)
        val row = BookmarkPresentation.bookmarkRow(
            BookmarkRecord("id-1", "pdf:$sha:1234", null, loc, epochMs, epochMs),
            BookFormat.pdf, null, null, dateRenderer,
        )
        // No `Int.MAX_VALUE + 1` overflow into a negative "p. -..." label.
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

    @Test fun txt_nullOffsetYieldsNullPreviewAndSkipsProvider() {
        var called = false
        val provider = BookmarkPreviewProvider { _, _ ->
            called = true
            "should-not-be-used"
        }
        val row = BookmarkPresentation.bookmarkRow(
            record(BookFormat.txt, charOffsetUTF16 = null),
            BookFormat.txt, null, provider, dateRenderer,
        )
        // A missing position must NOT fabricate a start-of-book preview.
        assertNull(row.preview)
        assertTrue("provider must not be invoked for a null offset", !called)
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
