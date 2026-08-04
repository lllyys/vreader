package com.vreader.app.reader.nav

import com.vreader.app.data.Book
import com.vreader.app.reader.txtBookmarkLocator
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.CoroutineContext

/**
 * Feature #139 WI-4 — [TxtMdTocProvider]: the one [TocProvider] serving BOTH non-Readium text
 * formats, turning a decoded document into the Contents sheet's [TocEntry] rows.
 *
 * The properties this suite exists to protect:
 *
 * - **Format routing is real**, not incidental: the same fixture yields the MD scanner's answer
 *   under `md` and the TXT rule engine's *different* answer under `txt`.
 * - **A row's `canonicalLocator` is CONSTRUCTION-IDENTICAL to a #135 bookmark** at the same source
 *   offset — that identity is what makes "the chapter I jumped to" and "the chapter I bookmarked"
 *   the same position across restore/engine swap.
 * - **The 50 000 cap REJECTS, never truncates**, and both boundaries are pinned — which together
 *   also pin that the provider passes exactly `MAX_TOC_ENTRIES + 1` as its scan budget (a smaller
 *   limit fails the at-exactly test; a larger one fails the at-max-plus-one test).
 * - **Detection policy is EXACTLY iOS's**: the `>= 2` match threshold plus that cap. There is no
 *   density guard, no saturation guard, no ambiguous-rule set and no format-specific exemption —
 *   divergence D4 was deleted (plan §4.4, Option A), and [noDensityOrSaturationGuardExists] fails
 *   loudly if one is reintroduced.
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class TxtMdTocProviderTest {

    private companion object {
        /** 64 lowercase-hex chars — a well-formed identity triple leg. */
        val SHA: String = "ab12cd34".repeat(8)
        const val BYTES: Long = 4_096L

        /** Matches NO rule in [TxtTocRules]: no leading digit+punctuation, no marker char, no keyword. */
        const val BODY = "hello world"

        /**
         * One fixture, two legitimate readings — the routing oracle.
         *
         * As **MD** it is two ATX headings ("Alpha" depth 0, "Beta" depth 1) and two paragraph
         * lines. As **TXT** it is two rule-1 chapter headings (`第…章`) and two lines matching
         * nothing (`#` starts no rule). The two answers are disjoint, so neither routing test can
         * pass through the other's code path.
         */
        val MIXED: String = "# Alpha\n第一章 甲\n第二章 乙\n## Beta\n"

        /** The MD reading of [MIXED]. */
        val MIXED_AS_MD = listOf("Alpha", "Beta")

        /** The TXT reading of [MIXED]. */
        val MIXED_AS_TXT = listOf("第一章 甲", "第二章 乙")
    }

    // ------------------------------------------------------------------ harness

    private fun book(format: BookFormat): Book = Book(
        fingerprintKey = "${format.name}:$SHA:$BYTES",
        title = "Fixture",
        originalFormat = format,
        contentSHA256 = SHA,
        fileByteCount = BYTES,
        addedAt = 0L,
    )

    /** The provider under test, on an unconfined dispatcher (the hop itself has its own test). */
    private fun provider(
        text: String,
        format: BookFormat,
        dispatcher: CoroutineDispatcher = Dispatchers.Unconfined,
        book: Book = book(format),
    ) = TxtMdTocProvider(text = text, book = book, format = format, dispatcher = dispatcher)

    private fun toc(
        text: String,
        format: BookFormat,
        book: Book = book(format),
    ): List<TocEntry> = runBlocking { provider(text, format, book = book).toc() }

    private fun titles(text: String, format: BookFormat): List<String?> =
        toc(text, format).map { it.title }

    /** `n` TXT chapter headings, one per line, every line a heading (100 % saturation). */
    private fun txtChapters(n: Int, body: Boolean = false): String = buildString(n * 12) {
        for (i in 1..n) {
            append("第").append(i).append("章 甲\n")
            if (body) append(BODY).append('\n')
        }
    }

    /** `n` ATX headings, one per line, every line a heading (100 % saturation). */
    private fun mdHeadings(n: Int): String = buildString(n * 10) {
        for (i in 1..n) append("## Item ").append(i).append('\n')
    }

    /** The raw-source offset of the line containing [needle] — the assertion's own oracle. */
    private fun offsetOfLineContaining(text: String, needle: String): Int {
        val at = text.indexOf(needle)
        assertTrue("fixture does not contain '$needle'", at >= 0)
        return text.lastIndexOfAny(charArrayOf('\n', '\r'), at) + 1
    }

    // ------------------------------------------------------------------ format routing

    @Test fun txtFormat_routesToRuleEngine() {
        assertEquals(MIXED_AS_TXT, titles(MIXED, BookFormat.txt))
    }

    @Test fun mdFormat_routesToMdScanner() {
        assertEquals(MIXED_AS_MD, titles(MIXED, BookFormat.md))
    }

    @Test fun unsupportedFormat_returnsEmptyList() {
        // A mis-constructed provider degrades to "no Contents", never to a crash in a working reader.
        for (format in listOf(BookFormat.epub, BookFormat.pdf, BookFormat.azw3)) {
            assertEquals("format=$format", emptyList<TocEntry>(), toc(MIXED, format))
        }
    }

    // ------------------------------------------------------------------ the empty outcomes

    @Test fun noHeadings_returnsEmptyList() {
        // Empty is the "hide the Contents control" signal (ReaderChromeScaffold), not an error.
        val prose = "$BODY\n$BODY\n$BODY\n"
        assertEquals(emptyList<TocEntry>(), toc(prose, BookFormat.txt))
        assertEquals(emptyList<TocEntry>(), toc(prose, BookFormat.md))
    }

    @Test fun emptyText_returnsEmptyList() {
        assertEquals(emptyList<TocEntry>(), toc("", BookFormat.txt))
        assertEquals(emptyList<TocEntry>(), toc("", BookFormat.md))
    }

    @Test fun singleHeading_belowMatchThreshold_returnsEmptyList() {
        // iOS's `>= 2` confidence threshold, observed end-to-end: one match is a coincidence.
        assertEquals(emptyList<TocEntry>(), toc("第一章 甲\n$BODY\n", BookFormat.txt))
        // MD has no threshold — a single ATX heading IS a heading (syntactically unambiguous).
        assertEquals(listOf("Only"), titles("# Only\n$BODY\n", BookFormat.md))
    }

    // ------------------------------------------------------------------ entry shape

    @Test fun entries_carryIdentityTripleFromBook() {
        val book = book(BookFormat.md)
        val entries = toc(MIXED, BookFormat.md, book = book)
        assertEquals(MIXED_AS_MD.size, entries.size)
        for (entry in entries) {
            assertEquals(book.contentSHA256, entry.canonicalLocator.contentSHA256)
            assertEquals(book.fileByteCount, entry.canonicalLocator.fileByteCount)
            assertEquals(book.originalFormat.name, entry.canonicalLocator.format)
            assertEquals(book.fingerprintKey, entry.canonicalLocator.fingerprintKey)
        }
    }

    @Test fun entries_canonicalLocatorMatches_txtBookmarkLocator_forSameOffset() {
        // The load-bearing parity assertion: a TOC row and a #135 bookmark at the same source
        // offset must be the SAME canonical position, field for field.
        val book = book(BookFormat.txt)
        val entries = toc(MIXED, BookFormat.txt, book = book)
        assertEquals(MIXED_AS_TXT.size, entries.size)
        for ((index, title) in MIXED_AS_TXT.withIndex()) {
            val offset = offsetOfLineContaining(MIXED, title)
            assertEquals("entry $index", txtBookmarkLocator(book, offset), entries[index].canonicalLocator)
            assertEquals("entry $index offset", offset, entries[index].canonicalLocator.charOffsetUTF16)
        }
    }

    @Test fun entries_epubReadiumLocatorIsNull() {
        val entries = toc(MIXED, BookFormat.md) + toc(MIXED, BookFormat.txt)
        assertEquals(MIXED_AS_MD.size + MIXED_AS_TXT.size, entries.size)
        entries.forEach { assertNull(it.epubReadiumLocator) }
    }

    @Test fun entries_pageLabelIsNull() {
        // Scroll layout has no page; the paged #138 index is windowed, so a label would force a
        // measure of every chapter at sheet-build time. Null is both correct and cheap.
        val entries = toc(MIXED, BookFormat.md) + toc(MIXED, BookFormat.txt)
        assertEquals(MIXED_AS_MD.size + MIXED_AS_TXT.size, entries.size)
        entries.forEach { assertNull(it.pageLabel) }
    }

    @Test fun txtEntries_areAllDepthZero() {
        val entries = toc(txtChapters(5), BookFormat.txt)
        assertEquals(5, entries.size)
        assertEquals(List(5) { 0 }, entries.map { it.depth })
    }

    @Test fun mdEntries_carryScannerDepth() {
        val entries = toc("# Top\n$BODY\n## Second\n$BODY\n### Third\n", BookFormat.md)
        assertEquals(listOf("Top", "Second", "Third"), entries.map { it.title })
        assertEquals(listOf(0, 1, 2), entries.map { it.depth })
    }

    @Test fun entries_areInAscendingDocumentOrder() {
        val offsets = toc(txtChapters(6), BookFormat.txt).map {
            requireNotNull(it.canonicalLocator.charOffsetUTF16) { "every TXT/MD row carries a source offset" }
        }
        assertEquals(6, offsets.size)
        assertEquals(offsets.sorted(), offsets)
        assertEquals(offsets.distinct(), offsets)
    }

    @Test fun titles_arePreservedVerbatim_includingCjkAndAstralPlane() {
        // A surrogate pair in a title must survive, and the offset must be the LINE start.
        val astral = "𝕬"   // U+1D56C MATHEMATICAL BOLD FRAKTUR CAPITAL A
        val text = "# 甲$astral 標題\n$BODY\n## 乙\n"
        val entries = toc(text, BookFormat.md)
        assertEquals(listOf("甲$astral 標題", "乙"), entries.map { it.title })
        assertEquals(0, entries[0].canonicalLocator.charOffsetUTF16)
        assertEquals(
            offsetOfLineContaining(text, "## 乙"),
            entries[1].canonicalLocator.charOffsetUTF16,
        )
    }

    // ------------------------------------------------------------------ the cap (reject, never truncate)

    @Test fun cap_aboveMaxTocEntries_returnsEmpty_notTruncated() {
        // A Contents list that silently stops at 50 000 of a larger book is worse than none — the
        // user cannot tell it is incomplete. So: reject the whole thing.
        val entries = toc(mdHeadings(TxtMdTocProvider.MAX_TOC_ENTRIES + 10), BookFormat.md)
        assertEquals(emptyList<TocEntry>(), entries)
    }

    @Test fun cap_atExactlyMaxTocEntries_returnsEntries() {
        val entries = toc(mdHeadings(TxtMdTocProvider.MAX_TOC_ENTRIES), BookFormat.md)
        assertEquals(TxtMdTocProvider.MAX_TOC_ENTRIES, entries.size)
    }

    @Test fun cap_atMaxPlusOne_returnsEmpty() {
        val entries = toc(mdHeadings(TxtMdTocProvider.MAX_TOC_ENTRIES + 1), BookFormat.md)
        assertEquals(emptyList<TocEntry>(), entries)
    }

    @Test fun cap_rejectionHappensWithoutMaterializingFullList() {
        val text = mdHeadings(TxtMdTocProvider.MAX_TOC_ENTRIES + 10_000)
        assertEquals(emptyList<TocEntry>(), toc(text, BookFormat.md))
        // The bound the provider relies on: the scan STOPS at `cap + 1` rather than building the
        // document's full 60 000-heading list and truncating it afterwards.
        val bounded = runBlocking {
            MdTocScanner.scan(text, TxtMdTocProvider.MAX_TOC_ENTRIES + 1)
        }
        assertTrue(bounded.hitLimit)
        assertEquals(TxtMdTocProvider.MAX_TOC_ENTRIES + 1, bounded.headings.size)
    }

    @Test fun applyCap_isTheWholePolicy() {
        // The cap decision reads ONLY `hitLimit` — no count, no ratio, no format, no rule identity.
        val headings = listOf(DetectedHeading("a", 0), DetectedHeading("b", 4))
        assertEquals(headings, TxtMdTocProvider.applyCap(ExtractResult(headings, hitLimit = false)))
        assertEquals(emptyList<DetectedHeading>(), TxtMdTocProvider.applyCap(ExtractResult(headings, hitLimit = true)))
        assertEquals(emptyList<DetectedHeading>(), TxtMdTocProvider.applyCap(ExtractResult.EMPTY))
    }

    // ------------------------------------------------------------------ D4 deletion is pinned

    @Test fun noDensityOrSaturationGuardExists() {
        // Divergence D4 (invented density/saturation guards) was DELETED after four Gate-2 rounds
        // failed to make it sound; iOS ships no such guard. Each case below would be REJECTED by
        // at least one of the four withdrawn schemes, and must be KEPT IN FULL:
        //   (a) TXT, explicit rule 1, 100 % saturation  → R3/R4's 90 % saturation guard
        //   (b) TXT, ambiguous rule 4 ("1. …"), 100 %   → R2/R4's 25 % ambiguous-rule guard
        //   (c) MD, every line a heading, 100 %         → R1/R3's unconditional density guard
        assertEquals(200, toc(txtChapters(200), BookFormat.txt).size)

        val numbered = buildString { for (i in 1..150) append(i).append(". Title\n") }
        assertEquals(150, toc(numbered, BookFormat.txt).size)

        assertEquals(120, toc(mdHeadings(120), BookFormat.md).size)
    }

    @Test fun eightLineDocWithThreeHeadings_isKept() {
        // Gate-2 R1's false rejection (37.5 % density). Trivially true now the guards are gone —
        // kept as a tripwire.
        val text = "第一章 甲\n$BODY\n$BODY\n第二章 乙\n$BODY\n第三章 丙\n$BODY\n$BODY\n"
        assertEquals(listOf("第一章 甲", "第二章 乙", "第三章 丙"), titles(text, BookFormat.txt))
    }

    @Test fun mdAllHeadingOutline_isKept() {
        // Gate-2 R3's false rejection: a legitimate 100 %-heading Markdown outline. Also a tripwire.
        assertEquals(40, toc(mdHeadings(40), BookFormat.md).size)
    }

    @Test fun twentyFiveThousandChapterNovel_isKept() {
        // Real Chinese web novels reach 20 000–30 000 chapters; the cap must sit above them.
        val entries = toc(txtChapters(25_000, body = true), BookFormat.txt)
        assertEquals(25_000, entries.size)
        assertEquals("第1章 甲", entries.first().title)
        assertEquals("第25000章 甲", entries.last().title)
    }

    // ------------------------------------------------------------------ threading

    @Test fun runsOnInjectedDispatcher_providerOwnsWithContext() {
        // The PROVIDER owns the hop (plan §4.5) — the host must not have to wrap the call, and
        // nothing may hardcode Dispatchers.IO/Default. Without an internal `withContext`, the
        // recording dispatcher would never see a dispatch at all.
        val dispatcher = RecordingDispatcher()
        try {
            val callerThread = Thread.currentThread().name
            val entries = runBlocking { provider(MIXED, BookFormat.txt, dispatcher).toc() }
            assertEquals(MIXED_AS_TXT, entries.map { it.title })
            assertTrue("provider never hopped to the injected dispatcher", dispatcher.dispatches.get() >= 1)
            assertEquals(setOf(RecordingDispatcher.THREAD_NAME), dispatcher.observedThreads())
            assertNotEquals(RecordingDispatcher.THREAD_NAME, callerThread)
        } finally {
            dispatcher.shutdown()
        }
    }

    /** A real dispatcher (one named thread) that records every dispatch it is asked to perform. */
    private class RecordingDispatcher : CoroutineDispatcher() {
        private val threads = Collections.synchronizedSet(mutableSetOf<String>())
        private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, THREAD_NAME) }
        val dispatches = AtomicInteger(0)

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            dispatches.incrementAndGet()
            executor.execute {
                threads.add(Thread.currentThread().name)
                block.run()
            }
        }

        fun observedThreads(): Set<String> = synchronized(threads) { threads.toSet() }

        fun shutdown() {
            executor.shutdownNow()
        }

        companion object {
            const val THREAD_NAME = "toc-provider-test-dispatcher"
        }
    }
}
