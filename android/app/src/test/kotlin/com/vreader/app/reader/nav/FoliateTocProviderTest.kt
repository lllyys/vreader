package com.vreader.app.reader.nav

import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.FoliateTocItem
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
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
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.CoroutineContext

/**
 * Feature #140 WI-2 — [FoliateTocProvider]: the third [TocProvider], turning WI-1's nested
 * [FoliateTocItem] tree into the shipped Contents sheet's [TocEntry] rows.
 *
 * The properties this suite exists to protect:
 *
 * - **Emitted rows carry NO progression** (plan §5.2 defense 2). iOS's `FoliateTOCConverter` stamps
 *   TOC locators with `progression = 0.0`, harmless there because `FoliateNavSeek.navigationTarget`
 *   has no progression leg. Android's `FoliateGoToTarget.from` DOES have one, so a `0.0` would make
 *   every chapter tap resolve to `Fraction(0.0)` — a jump to the START of the book that still acks
 *   `ok:true` and dismisses the sheet. WI-3's `cfi → href → progression` precedence is defense 1;
 *   this is the INDEPENDENT defense 2, and [entryLocator_hasNoProgression] asserts the field is
 *   `null`, not merely that an href is present (an href-only assertion passes under both).
 * - **A blank label or href SKIPS the row but STILL WALKS its subitems** — iOS bug #262's round-1
 *   fix. The fixtures give the blank node real children and assert those children survive AND that
 *   their depth still incremented past the skipped parent; a childless fixture would let the test
 *   pass vacuously, and [consecutiveSkippedContainers_stillYieldTheirDescendants] closes the
 *   two-skips-in-a-row gap a single-skip fixture leaves open.
 * - **Hrefs are opaque and preserved BYTE-FOR-BYTE** — no trim, no normalization, no re-encoding.
 *   WI-3 hands the href straight to `readerAPI.goTo` and WI-4 matches `relocate.tocHref` byte-
 *   exactly, so any tidying here silently breaks navigation or the current-chapter highlight one WI
 *   later. Every href assertion compares against the exact input `String` (never `contains`, never a
 *   normalized form) across the three real shapes: an EPUB-relative path (with `#fragment` / query /
 *   non-ASCII, because the bundle `decodeURI`s it), the KF8 `kindle:pos:fid:…:off:…` URI and the
 *   MOBI6 `filepos:NNNN`.
 * - **The provider owns its dispatcher hop** on an INJECTED dispatcher (rule 50 §12.1), and the walk
 *   is cancellation-cooperative. Both are observed through the tree itself (a [ProbeList] records
 *   the thread each root node was read on and how many were read), not merely by "the call
 *   returned".
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class FoliateTocProviderTest {

    private companion object {
        /** 64 lowercase-hex chars — a well-formed identity triple leg. */
        val SHA: String = "ab12cd34".repeat(8)
        const val BYTES: Long = 6_288_371L

        /** A nested fixture: A ▸ (A1 ▸ A1a, A2), B. Depth-first order is A, A1, A1a, A2, B. */
        val NESTED: List<FoliateTocItem> = listOf(
            item(
                "A", "a.html",
                item("A1", "a1.html", item("A1a", "a1a.html")),
                item("A2", "a2.html"),
            ),
            item("B", "b.html"),
        )
        val NESTED_TITLES = listOf("A", "A1", "A1a", "A2", "B")
        val NESTED_HREFS = listOf("a.html", "a1.html", "a1a.html", "a2.html", "b.html")
        val NESTED_DEPTHS = listOf(0, 1, 2, 1, 0)

        fun item(label: String, href: String, vararg subitems: FoliateTocItem): FoliateTocItem =
            FoliateTocItem(label = label, href = href, subitems = subitems.toList())
    }

    // ------------------------------------------------------------------ harness

    private fun book(format: BookFormat = BookFormat.azw3): Book = Book(
        fingerprintKey = "${format.name}:$SHA:$BYTES",
        title = "Fixture",
        originalFormat = format,
        contentSHA256 = SHA,
        fileByteCount = BYTES,
        addedAt = 0L,
    )

    private fun toc(
        items: List<FoliateTocItem>,
        book: Book = book(),
        dispatcher: CoroutineDispatcher = Dispatchers.Unconfined,
    ): List<TocEntry> = runBlocking {
        FoliateTocProvider(items = items, book = book, dispatcher = dispatcher).toc()
    }

    private fun titles(items: List<FoliateTocItem>): List<String?> = toc(items).map { it.title }

    /** The single row a one-node fixture yields, href-bearing. */
    private fun singleRow(href: String, label: String = "Chapter"): TocEntry =
        toc(listOf(item(label, href))).single()

    // ------------------------------------------------------------------ flatten shape

    @Test fun flatTree_yieldsDepthZeroRowsInOrder() {
        val flat = listOf(item("One", "1.html"), item("Two", "2.html"), item("Three", "3.html"))
        val entries = toc(flat)
        assertEquals(listOf("One", "Two", "Three"), entries.map { it.title })
        assertEquals(listOf(0, 0, 0), entries.map { it.depth })
        assertEquals(listOf("1.html", "2.html", "3.html"), entries.map { it.canonicalLocator.href })
    }

    @Test fun nestedTree_isDepthFirst_parentBeforeChildren() {
        // Order, not just membership: a breadth-first walk would yield A, B, A1, A2, A1a.
        assertEquals(NESTED_TITLES, titles(NESTED))
    }

    @Test fun depthIncrementsOncePerNestingLevel() {
        assertEquals(NESTED_DEPTHS, toc(NESTED).map { it.depth })
    }

    @Test fun deepNesting_depthTracksEveryLevel() {
        // 12 levels — WI-1's MAX_TOC_DEPTH, i.e. the deepest tree the parser can hand us.
        var node = item("L11", "l11.html")
        for (level in 10 downTo 0) node = item("L$level", "l$level.html", node)
        val entries = toc(listOf(node))
        assertEquals((0..11).map { "L$it" }, entries.map { it.title })
        assertEquals((0..11).toList(), entries.map { it.depth })
    }

    @Test fun emptyTree_yieldsEmptyList_theHideTheControlSignal() {
        // ReaderChromeScaffold derives the Contents control's visibility from `tocEntries.isEmpty()`,
        // so an empty list is the documented "hide the control" signal — never an error channel.
        assertEquals(emptyList<TocEntry>(), toc(emptyList()))
    }

    @Test fun treeOfOnlyUnusableNodes_yieldsEmptyList() {
        val unusable = listOf(item("", "a.html"), item("Titled", ""), item("  ", "   "))
        assertEquals(emptyList<TocEntry>(), toc(unusable))
    }

    // ------------------------------------- iOS bug #262 parity: skip the row, WALK the subitems

    @Test fun blankLabel_isSkipped_butSubitemsAreStillWalked() {
        // An unlabelled container is a common TOC shape; losing its children loses the chapters.
        // The fixture deliberately gives the blank node children AND grandchildren.
        val tree = listOf(
            item(
                "   \n\t ", "container.html",
                item("Kid", "kid.html", item("Grandkid", "grandkid.html")),
            ),
            item("Sibling", "sibling.html"),
        )
        val entries = toc(tree)
        assertEquals(listOf("Kid", "Grandkid", "Sibling"), entries.map { it.title })
        // The skipped parent still counts as a nesting level: its child is depth 1, not depth 0.
        assertEquals(listOf(1, 2, 0), entries.map { it.depth })
    }

    @Test fun blankHref_isSkipped_butSubitemsAreStillWalked() {
        // `serializeTOC` writes a missing href as '' (foliate-bundle.js). Such a row would be
        // tappable and dead, so it is not emitted — but its children are navigable and must survive.
        val tree = listOf(
            item(
                "Part One", "",
                item("Kid", "kid.html", item("Grandkid", "grandkid.html")),
            ),
            item("Sibling", "sibling.html"),
        )
        val entries = toc(tree)
        assertEquals(listOf("Kid", "Grandkid", "Sibling"), entries.map { it.title })
        assertEquals(listOf(1, 2, 0), entries.map { it.depth })
    }

    @Test fun whitespaceOnlyHref_isSkipped_butSubitemsAreStillWalked() {
        val tree = listOf(item("Part One", "  \t ", item("Kid", "kid.html")))
        val entries = toc(tree)
        assertEquals(listOf("Kid"), entries.map { it.title })
        assertEquals(listOf(1), entries.map { it.depth })
    }

    @Test fun consecutiveSkippedContainers_stillYieldTheirDescendants() {
        // Gate-4 round 1 (Low): a single-skip fixture would still pass under a bug that only loses
        // children once TWO skipped containers nest. Skipped for a blank label, then for a blank
        // href, then a real chapter — which must survive at depth 2, both levels still counted.
        val tree = listOf(
            item(
                "  ", "grandparent.html",
                item("Untitled Part", "", item("Chapter", "chapter.html")),
            ),
        )
        val entries = toc(tree)
        assertEquals(listOf("Chapter"), entries.map { it.title })
        assertEquals(listOf(2), entries.map { it.depth })
        assertEquals(listOf("chapter.html"), entries.map { it.canonicalLocator.href })
    }

    // ------------------------------------------------------------------ label policy

    @Test fun labelIsTrimmed() {
        // WI-1's parser deliberately does NOT trim (filtering is this provider's job).
        assertEquals(listOf("Chapter One"), titles(listOf(item("\n  Chapter One \t ", "c1.html"))))
    }

    @Test fun labelInteriorIsPreserved_includingCjkAstralAndNewlines() {
        // Only the ENDS are trimmed. Interior whitespace/newlines and non-BMP characters survive —
        // the sheet normalizes at render, the model does not mangle the author's text.
        val label = " 第一章　甲\n乙 𝕬 "
        assertEquals(
            listOf("第一章　甲\n乙 𝕬"),
            titles(listOf(item(label, "c1.html"))),
        )
    }

    // ------------------------------------------------------------------ locator shape

    @Test fun entryLocator_carriesHref_andBookIdentityTriple() {
        val b = book()
        val entries = toc(NESTED, book = b)
        assertEquals(NESTED_TITLES.size, entries.size)
        assertEquals(NESTED_HREFS, entries.map { it.canonicalLocator.href })
        for (entry in entries) {
            assertEquals(b.contentSHA256, entry.canonicalLocator.contentSHA256)
            assertEquals(b.fileByteCount, entry.canonicalLocator.fileByteCount)
            assertEquals(b.originalFormat.name, entry.canonicalLocator.format)
            assertEquals(b.fingerprintKey, entry.canonicalLocator.fingerprintKey)
        }
    }

    @Test fun entryLocator_hasNoProgression() {
        // THE load-bearing assertion (plan §5.2 defense 2). iOS stamps 0.0 here; on Android that
        // would let `FoliateGoToTarget.from` return Fraction(0.0) and send every chapter tap to the
        // start of the book with a green "jump succeeded". Assert the FIELD IS NULL — an
        // "the href is present" assertion is satisfied by both null and 0.0 and proves nothing.
        val entries = toc(NESTED)
        assertEquals(NESTED_TITLES.size, entries.size)
        for (entry in entries) {
            assertNull("progression must be null, never 0.0", entry.canonicalLocator.progression)
            assertNull(entry.canonicalLocator.totalProgression)
        }
    }

    @Test fun entryLocator_carriesNoPositionFieldOtherThanHref() {
        // The row's destination is its href and nothing else: no cfi, no page, no char offsets, no
        // text anchor. Anything else here would give WI-3's precedence a competing leg to pick.
        val locator = singleRow("c1.html").canonicalLocator
        assertNull(locator.cfi)
        assertNull(locator.page)
        assertNull(locator.charOffsetUTF16)
        assertNull(locator.charRangeStartUTF16)
        assertNull(locator.charRangeEndUTF16)
        assertNull(locator.textQuote)
        assertNull(locator.textContextBefore)
        assertNull(locator.textContextAfter)
    }

    @Test fun entryLocator_formatComesFromBookOriginalFormatNotALiteral() {
        // `.azw`/`.mobi`/`.prc` all import as BookFormat.azw3 today, but the format leg must READ the
        // book, not spell a constant — otherwise a row keys differently from the same book's
        // bookmarks. Every enum value is exercised so a hardcoded "azw3" fails on four of five.
        for (format in BookFormat.entries) {
            val b = book(format)
            val row = toc(listOf(item("Chapter", "c1.html")), book = b).single()
            assertEquals("format=$format", format.name, row.canonicalLocator.format)
            assertEquals("format=$format", b.fingerprintKey, row.canonicalLocator.fingerprintKey)
        }
    }

    @Test fun entryLocator_isValid() {
        val entries = toc(NESTED)
        // Size first: a forEach over an accidentally-empty list would assert nothing (Gate-4 R1 Low).
        assertEquals(NESTED_TITLES.size, entries.size)
        entries.forEach { assertNull(it.canonicalLocator.validate()) }
    }

    @Test fun pageLabelAndReadiumLocator_areNull() {
        // No page model on this host (Book Details passes pageCount = null), and it is not a
        // Readium host — TocSheetRows renders `p. N` only when pageLabel is non-null.
        val entries = toc(NESTED)
        assertEquals(NESTED_TITLES.size, entries.size)
        entries.forEach {
            assertNull(it.pageLabel)
            assertNull(it.epubReadiumLocator)
        }
    }

    // ------------------------------------------------------------------ hrefs are opaque

    @Test fun hrefWithFragmentOrQuery_isPreservedByteForByte() {
        val fragment = "text/part0007.html#ch12"
        val query = "text/part0007.html?v=2&x=1#a%20b"
        assertEquals(fragment, singleRow(fragment).canonicalLocator.href)
        assertEquals(query, singleRow(query).canonicalLocator.href)
    }

    @Test fun twoHrefsDifferingOnlyByFragment_stayDistinctRows() {
        // WI-4 matches `relocate.tocHref` byte-exactly; collapsing the fragment would merge two
        // chapters into one highlight target.
        val entries = toc(listOf(item("A", "part0007.html#ch12"), item("B", "part0007.html#ch13")))
        assertEquals(
            listOf("part0007.html#ch12", "part0007.html#ch13"),
            entries.map { it.canonicalLocator.href },
        )
    }

    @Test fun kf8PosUriHref_isPreservedByteForByte() {
        val href = "kindle:pos:fid:0AB1:off:0000001234"
        assertEquals(href, singleRow(href).canonicalLocator.href)
    }

    @Test fun mobi6FileposHref_isPreservedByteForByte() {
        val href = "filepos:0000012345"
        assertEquals(href, singleRow(href).canonicalLocator.href)
    }

    @Test fun nonAsciiHref_isPreservedByteForByte() {
        // The bundle `decodeURI`s EPUB-path hrefs, so a CJK path arrives already decoded.
        val href = "文本/第一章 序章.xhtml#节1"
        assertEquals(href, singleRow(href).canonicalLocator.href)
    }

    @Test fun hrefIsNotUnicodeNormalized() {
        // Composed vs decomposed must stay distinct: the engine matches the bytes it emitted.
        // The two fixtures below are LITERAL UTF-8 in this source (bytes `63 61 66 65 cc 81` and
        // `63 61 66 c3 a9`) — the code points are named in the trailing comments. The
        // `assertNotEquals` guard is what makes that robust: if any editor or reformat ever
        // normalized this file, the fixtures would collapse and this test would fail loudly rather
        // than pass vacuously. (Gate-4 R1 Low: an earlier comment claimed \u escapes, which the
        // source did not carry.)
        val decomposed = "café/ch1.xhtml"   // e + U+0301 COMBINING ACUTE ACCENT
        val composed = "café/ch1.xhtml"      // U+00E9 LATIN SMALL LETTER E WITH ACUTE
        assertNotEquals(decomposed, composed)
        val entries = toc(listOf(item("A", decomposed), item("B", composed)))
        assertEquals(listOf(decomposed, composed), entries.map { it.canonicalLocator.href })
    }

    @Test fun hrefIsNotTrimmed_paddedHrefSurvivesVerbatim() {
        // A padded href is non-blank, so the row is KEPT — and carried verbatim. Trimming it here
        // would make it stop matching the `relocate.tocHref` the engine reports.
        val padded = " ch1.xhtml "
        assertEquals(padded, singleRow(padded).canonicalLocator.href)
    }

    // ------------------------------------------------------------------ threading + cancellation

    @Test fun runsOnTheInjectedDispatcher_notTheCaller() {
        // The PROVIDER owns the hop — the host must not wrap the call, and nothing may hardcode
        // Dispatchers.IO/Default. Observed through the TREE: the probe records the thread each root
        // node was read on, so this asserts where the WALK ran, not merely that a block was
        // dispatched somewhere.
        val dispatcher = RecordingDispatcher()
        try {
            val callerThread = currentThreadName()
            val walkThreads = Collections.synchronizedSet(mutableSetOf<String>())
            val probe = ProbeList(NESTED) { walkThreads.add(currentThreadName()) }
            val entries = toc(probe, dispatcher = dispatcher)
            assertEquals(NESTED_TITLES, entries.map { it.title })
            assertTrue("provider never hopped to the injected dispatcher", dispatcher.dispatches.get() >= 1)
            assertEquals(setOf(RecordingDispatcher.THREAD_NAME), walkThreads)
            assertNotEquals(RecordingDispatcher.THREAD_NAME, callerThread)
        } finally {
            dispatcher.shutdown()
        }
    }

    @Test fun cancellation_isCooperative() {
        // Cancelling mid-walk must STOP the walk, not merely make the (already-completed) call
        // report cancelled. The probe cancels the running job as the 5th root node is read; the walk
        // must then read no 6th node and publish no result.
        val reads = AtomicInteger(0)
        val jobRef = AtomicReference<Job?>(null)
        val nodes = (1..200).map { item("Ch $it", "c$it.html") }
        val probe = ProbeList(nodes) { if (reads.incrementAndGet() == 5) jobRef.get()?.cancel() }
        val result = AtomicReference<List<TocEntry>?>(null)

        runBlocking {
            val job = launch(Dispatchers.Unconfined, start = CoroutineStart.LAZY) {
                result.set(FoliateTocProvider(probe, book(), Dispatchers.Unconfined).toc())
            }
            jobRef.set(job)
            job.start()
            job.join()
            assertTrue("the job should have been cancelled", job.isCancelled)
        }

        assertEquals("the walk must stop at the cancellation point", 5, reads.get())
        assertNull("a cancelled walk must publish no rows", result.get())
    }

    // ------------------------------------------------------------------ probes

    /** The running thread's name without kotlinx.coroutines' debug-mode " @coroutine#N" suffix. */
    private fun currentThreadName(): String =
        Thread.currentThread().name.substringBefore(" @coroutine")

    /** A read-only list that reports every element read — the seam that observes WHERE and HOW FAR. */
    private class ProbeList(
        private val backing: List<FoliateTocItem>,
        private val onRead: (Int) -> Unit,
    ) : AbstractList<FoliateTocItem>() {
        override val size: Int get() = backing.size
        override fun get(index: Int): FoliateTocItem {
            onRead(index)
            return backing[index]
        }
    }

    /** A real dispatcher (one named thread) that records every dispatch it is asked to perform. */
    private class RecordingDispatcher : CoroutineDispatcher() {
        private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, THREAD_NAME) }
        val dispatches = AtomicInteger(0)

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            dispatches.incrementAndGet()
            executor.execute(block)
        }

        fun shutdown() {
            executor.shutdownNow()
        }

        companion object {
            const val THREAD_NAME = "foliate-toc-provider-test-dispatcher"
        }
    }
}
