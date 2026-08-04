package com.vreader.app.reader

import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.nav.TxtMdTocProvider
import com.vreader.app.reader.nav.TxtTocRuleEngine
import com.vreader.app.reader.paged.ComposeLineMeasurer
import com.vreader.app.reader.paged.LineMeasurer
import com.vreader.app.reader.paged.PageContentBox
import com.vreader.app.reader.paged.PaginationSession
import com.vreader.app.reader.paged.TxtPageIndex
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.reader.settings.bodyTextStyle
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import vreader.contracts.BookFormat
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/**
 * Feature #139 WI-8 — the Gate-5b ACCEPTANCE suite: the TXT/MD table of contents exercised on REAL
 * documents, through the PRODUCTION entry point, with the plan's three §5 performance gates asserted
 * at their STATED budgets.
 *
 * The WI-7 connected tests prove the mechanism on generated fixtures; this class proves the feature
 * on the corpus a user actually opens:
 *
 *  - [realCjkBook_producesExpectedChapterCount] — the 14 MB / 7 029 609-char CJK novel opened the way
 *    a user opens it: **Library → tap the book → reader → Contents → tap a chapter row**. Asserts the
 *    plan's stated 1 859 chapters, a per-entry structural oracle against the real decoded bytes
 *    (every title stands verbatim at its own offset; offsets strictly increase), and that the tapped
 *    row actually moves the reader.
 *  - [realCjkBook_scanCompletesWithinBudget] — §5 gate 1: the whole-document scan on the real book
 *    within the stated **1 500 ms**, with no reader open.
 *  - [realCjkBook_scanUnderContention_withinBudget] — §5 gate 1 under REALISTIC CONTENTION: the same
 *    budget while #138's `PaginationSession` grinds the same real document on worker threads and the
 *    search indexer (started unconditionally by `VReaderApp.onCreate`) works the same fresh 14 MB
 *    import. The contention is PROVEN, not assumed: the sealed page count must have GROWN across the
 *    measured window.
 *  - [realCjkBook_openToFirstPage_doesNotRegress] — §5 gate 2, the BLOCKING PRIMARY gate. Reproduces
 *    #138's own measurement (`PaginationSession.openFromStart` → first published snapshot) on the
 *    real book twice: once with nothing else running (the #138 baseline, verified there at 8 ms) and
 *    once with a #139 TOC scan running CONCURRENTLY — the worst case in which the host's first-frame
 *    gate failed entirely. Both must meet #138's stated **< 2 000 ms** target, and the concurrent arm
 *    asserts the scan was genuinely still in flight when the first page published.
 *  - [realMdFile_producesNestedEntries] — the repo's own `docs/architecture.md`, opened through the
 *    same production path, checked against an INDEPENDENT in-test ATX oracle (fence-aware, written
 *    from the CommonMark rules rather than from `MdTocScanner`'s state machine) and shown to render
 *    its nesting as real indentation.
 *  - [realTxtWithoutHeadings_hidesContentsControl] — the other half of the acceptance criterion: a
 *    headings-free document reaches the reader through the Library with NO Contents control.
 *
 * **Fixtures — real books first (AGENTS.md), and the fallback is FAILURE, not synthesis.** Every
 * real-fixture accessor is `requireNotNull`/`require`-d with a byte-size or content identity check,
 * so a run without the pushed fixture FAILS LOUDLY instead of false-greening on a synthetic stand-in
 * (the durable #138 lesson — a hollow acceptance is worse than a red one). The connected task wipes
 * `/sdcard/Android/data/com.vreader.app/` at run end, so BOTH fixtures must be re-pushed per run:
 *
 * ```
 * adb -s emulator-5554 shell mkdir -p /sdcard/Android/data/com.vreader.app/files
 * adb -s emulator-5554 push test-books/books/txt/黑暗血时代.txt \
 *     /sdcard/Android/data/com.vreader.app/files/perf-cjk.txt
 * adb -s emulator-5554 push docs/architecture.md \
 *     /sdcard/Android/data/com.vreader.app/files/real-architecture.md
 * ```
 *
 * `test-books/books/` holds no `.md` file at all, so the MD format has no real *book*; a large,
 * deeply nested real repo document beats a hand-written fixture and satisfies the rule's intent. The
 * headings-free TXT case uses the committed `resume-sample.txt` asset under the rule's explicit
 * "deterministic tiny structure" exception — the assertion is the ABSENCE of a control, which needs a
 * document known to contain no chapter markers, not a large one.
 *
 * Run ONE class per connected invocation (MEMORY #129/#133); never drive the emulator while it runs.
 * Method order is PINNED (`NAME_ASCENDING`) so the logged measurements always appear in the same
 * order in the evidence file, and so a memory-heavy method's position in the run is reproducible
 * rather than an accident of JVM reflection order.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class TxtTocAcceptanceTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    private companion object {
        const val TAG = "WI139-ACCEPT"

        /** The pushed real 14 MB CJK novel + its exact byte size (a truncated push must NOT pass). */
        const val REAL_BOOK_FILE = "perf-cjk.txt"
        const val REAL_BOOK_BYTES = 14_059_220L
        const val REAL_BOOK_BYTES_TOLERANCE = 1_000L
        const val REAL_BOOK_DISPLAY_NAME = "黑暗血时代.txt"
        const val REAL_BOOK_TITLE = "黑暗血时代"

        /** Plan §5, measured on the real book with the ported rule: 1 859 chapters over 7 029 609 chars. */
        const val EXPECTED_CHAPTER_COUNT = 1_859
        const val EXPECTED_CHARS_UTF16 = 7_029_609
        const val EXPECTED_FIRST_CHAPTER_PREFIX = "第一章"
        const val EXPECTED_LAST_CHAPTER_PREFIX = "第一千八百六十章"

        /** The pushed real MD document (`docs/architecture.md`) + its identity markers. */
        const val REAL_MD_FILE = "real-architecture.md"
        const val REAL_MD_DISPLAY_NAME = "real-architecture.md"
        const val REAL_MD_TITLE = "real-architecture"
        const val REAL_MD_FIRST_LINE = "# VReader Architecture"
        const val REAL_MD_MIN_BYTES = 50_000L

        /**
         * Plan §5 gate 1 — the STATED whole-document scan budget on the real book, with and without
         * contention. Asserted as written; a looser ceiling would not be a gate (the Gate-4 finding
         * on #138 WI-6).
         */
        const val SCAN_BUDGET_MS = 1_500L

        /**
         * Plan §5 gate 2 (BLOCKING PRIMARY) — #138's own stated open-to-first-page target, verified
         * there at 8 ms. #139 must not regress it, so the SAME target is asserted here.
         */
        const val FIRST_PAGE_TARGET_MS = 2_000L

        /** Generous budgets: a 14 MB import + decode + first paint on a loaded emulator is slow, not hung. */
        const val UI_TIMEOUT_MS = 120_000L
    }

    @Before
    fun pinDefaults() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
        // Scroll is the default for every test that does not opt into Paged, and it must be CONFIRMED
        // committed, not merely requested (the TxtTocConnectedTest precedent: a DataStore write is
        // async, so a leftover Paged value from a previous test would otherwise reach the reader).
        confirmLayoutBlocking(ReaderLayout.Scroll)
    }

    /**
     * ONE `@After` (JUnit does not order two of them): finish any reader this test left standing —
     * a leftover resumed [TxtReaderActivity] would be picked up by the NEXT test's [resumedReader]
     * before its own reader launched, silently asserting against the wrong book — restore the default
     * layout, and then RELEASE MEMORY.
     *
     * The last part is load-bearing, not tidiness. Every method here holds a 14 MB decoded copy of the
     * real book (plus, in some, a `TxtDocument` and a pagination index); without an explicit
     * collection between methods the app process climbed past 1 GB RSS on this 2.5 GB emulator and was
     * `lowmemorykiller`-ed mid-class, truncating the run. This is the #137 benchmark's `System.gc()`
     * + settle idiom — memory hygiene, never a synchronisation primitive.
     */
    @After
    fun closeReadersRestoreScrollAndReleaseMemory() {
        finishAnyReader()
        runBlocking { app.container.readerSettingsStore.setLayout(ReaderLayout.Scroll) }
        System.gc()
        System.runFinalization()
        Thread.sleep(250)
        System.gc()
    }

    // ---- fixtures (real documents; require, never a synthetic fallback) ---------------------------

    /** The pushed real book's file, or null when absent / not the genuine 14 059 220-byte novel. */
    private fun realBookFileOrNull(): File? {
        val dir = instrumentation.targetContext.getExternalFilesDir(null) ?: return null
        val f = File(dir, REAL_BOOK_FILE)
        if (!f.exists() || !f.canRead()) return null
        if (kotlin.math.abs(f.length() - REAL_BOOK_BYTES) > REAL_BOOK_BYTES_TOLERANCE) {
            Log.w(TAG, "$REAL_BOOK_FILE size ${f.length()} != expected $REAL_BOOK_BYTES → NOT the real book")
            return null
        }
        return f
    }

    /**
     * The real book's file — REQUIRED. A missing or truncated push fails the test loudly; it never
     * degrades to a synthetic corpus, because an acceptance pass on a stand-in proves nothing about
     * the 14 MB CJK novel this feature exists to index.
     */
    private fun requireRealBookFile(): File = requireNotNull(realBookFileOrNull()) {
        "Gate-5b acceptance requires the REAL 14 MB CJK book at " +
            "getExternalFilesDir(null)/$REAL_BOOK_FILE ($REAL_BOOK_BYTES bytes). Push it before the run: " +
            "adb push test-books/books/txt/黑暗血时代.txt " +
            "/sdcard/Android/data/com.vreader.app/files/$REAL_BOOK_FILE"
    }

    /** The real book decoded exactly as the reader decodes it (BOM-stripped UTF-16LE). */
    private fun requireRealBookText(): String {
        val text = TxtDecoder.decode(requireRealBookFile()).text
        assertEquals(
            "the decoded real book must be the plan's 7,029,609-char corpus",
            EXPECTED_CHARS_UTF16, text.length,
        )
        return text
    }

    /** The pushed `docs/architecture.md` — REQUIRED, identity-checked by its first line and size. */
    private fun requireRealMdFile(): File {
        val dir = requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)) {
            "no external files dir on this device"
        }
        val f = File(dir, REAL_MD_FILE)
        require(f.exists() && f.canRead() && f.length() >= REAL_MD_MIN_BYTES) {
            "Gate-5b acceptance requires the REAL markdown document at " +
                "getExternalFilesDir(null)/$REAL_MD_FILE (>= $REAL_MD_MIN_BYTES bytes). Push it: " +
                "adb push docs/architecture.md /sdcard/Android/data/com.vreader.app/files/$REAL_MD_FILE"
        }
        val head = f.readText().take(REAL_MD_FIRST_LINE.length)
        require(head == REAL_MD_FIRST_LINE) {
            "$REAL_MD_FILE is not docs/architecture.md (it starts '$head')"
        }
        return f
    }

    // ---- import + production-path helpers ---------------------------------------------------------

    /** Import [file] through the REAL importer under [displayName] and reset its position to the top. */
    private fun importFile(file: File, displayName: String): Book = runBlocking {
        val book = app.container.importer.importStream(
            "content://test/$displayName", displayName, file.inputStream(),
        )
        app.container.repository.clearPosition(book.fingerprintKey)
        app.container.cacheOffset(book.fingerprintKey, 0)
        book
    }

    private fun importAsset(asset: String): Book {
        val staged = File(instrumentation.targetContext.cacheDir, "acc-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        return importFile(staged, asset)
    }

    private fun confirmLayoutBlocking(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        for (i in 0 until 100) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    /** Every [TxtReaderActivity] currently in a live stage (resumed, started or paused). */
    private fun liveReaders(): List<TxtReaderActivity> {
        var found: List<TxtReaderActivity> = emptyList()
        instrumentation.runOnMainSync {
            val monitor = ActivityLifecycleMonitorRegistry.getInstance()
            found = listOf(Stage.RESUMED, Stage.STARTED, Stage.PAUSED)
                .flatMap { monitor.getActivitiesInStage(it) }
                .filterIsInstance<TxtReaderActivity>()
                .distinct()
        }
        return found
    }

    /** The RESUMED reader the Library tap opened, or null. */
    private fun resumedReader(): TxtReaderActivity? {
        var found: TxtReaderActivity? = null
        instrumentation.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED)
                .filterIsInstance<TxtReaderActivity>()
                .firstOrNull()
        }
        return found
    }

    /** Finish every live reader and wait (bounded, non-throwing) for the stack to drain. */
    private fun finishAnyReader() {
        val readers = liveReaders()
        if (readers.isEmpty()) return
        instrumentation.runOnMainSync { readers.forEach { it.finish() } }
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (liveReaders().isNotEmpty() && SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(50)
        }
    }

    /** Read a reader seam on the main thread (several read Compose state, not just `@Volatile` fields). */
    private fun <T> TxtReaderActivity.read(block: (TxtReaderActivity) -> T): T {
        var value: Any? = null
        instrumentation.runOnMainSync { value = block(this) }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    /**
     * THE PRODUCTION ENTRY POINT (rule 47 Gate-5 "production reachability"): launch the app's real
     * launcher activity, find the book in the Library grid by its visible title, tap it, and hand
     * [block] the reader that tap opened. No `TxtReaderActivity.intent(...)`, no debug launcher, no
     * composable invoked directly — this is the path a user walks from app launch.
     *
     * The reader is finished on the way out so it cannot leak into the next test.
     */
    private fun openThroughLibrary(title: String, block: (TxtReaderActivity) -> Unit) {
        finishAnyReader()
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(title, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(title, substring = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { resumedReader() != null }
            try {
                block(requireNotNull(resumedReader()))
            } finally {
                finishAnyReader()
            }
        }
    }

    private fun nodeCount(tag: String) =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    /** Wait for the host's ONE gated scan to publish (a stuck gate must never read as "no chapters"). */
    private fun TxtReaderActivity.awaitScan(timeoutMs: Long = UI_TIMEOUT_MS) {
        compose.waitUntil(timeoutMs) { read { it.tocScanCompletedForTest() } }
        if (read { it.tocEntriesForTest().isNotEmpty() }) {
            // `currentTocIndex` and the row-jump lambda are composition-derived and land one
            // recomposition after the scan publishes (the WI-7 barrier).
            compose.waitUntil(timeoutMs) { read { it.currentTocIndexForTest() } >= 0 }
        }
    }

    /** Open the Contents sheet the way a user does — the bottom-chrome Contents control. */
    private fun openContentsSheet() {
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("chrome-contents") > 0 }
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).performClick()
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("toc-sheet-content") > 0 }
    }

    /** The laid-out left edge of a Contents row's title — the indentation a reader actually sees. */
    private fun titleLeftInRow(rowTag: String, title: String): Float {
        val row = compose.onNodeWithTag(rowTag, useUnmergedTree = true).fetchSemanticsNode()
        val child = row.children.firstOrNull { node ->
            node.config.getOrNull(SemanticsProperties.Text)?.any { it.text.contains(title) } == true
        } ?: throw AssertionError("no '$title' title text inside $rowTag")
        return child.positionInRoot.x
    }

    // ---- 1. production-path acceptance on the real 14 MB CJK novel --------------------------------

    /**
     * The headline acceptance: the real book's chapters are detected, reachable and navigable through
     * the production entry point.
     *
     * Every claim is checked against the REAL decoded bytes rather than against itself — the entry
     * count is the plan's stated 1 859, each entry's title stands verbatim at its own recorded source
     * offset, and the offsets strictly increase — so a scan that returned plausible-looking garbage
     * (or an empty list, which would pass a bare "did not crash" test) fails here.
     */
    @Test
    fun realCjkBook_producesExpectedChapterCount() {
        val text = requireRealBookText()
        importFile(requireRealBookFile(), REAL_BOOK_DISPLAY_NAME)

        openThroughLibrary(REAL_BOOK_TITLE) { reader ->
            reader.awaitScan()
            val entries = reader.read { it.tocEntriesForTest() }

            assertEquals(
                "the real book yields the plan's stated chapter count",
                EXPECTED_CHAPTER_COUNT, entries.size,
            )
            assertTrue(
                "first chapter is $EXPECTED_FIRST_CHAPTER_PREFIX… (was '${entries.first().title}')",
                entries.first().title?.startsWith(EXPECTED_FIRST_CHAPTER_PREFIX) == true,
            )
            assertTrue(
                "last chapter is $EXPECTED_LAST_CHAPTER_PREFIX… (was '${entries.last().title}')",
                entries.last().title?.startsWith(EXPECTED_LAST_CHAPTER_PREFIX) == true,
            )
            assertTxtEntriesAnchoredIn(text, entries)

            // The user-visible delta of this feature: Contents is REACHABLE on a TXT book.
            openContentsSheet()
            assertTrue("the Contents sheet lists the chapters", nodeCount("toc-row-0") > 0)
            assertEquals("no empty state for a book that HAS chapters", 0, nodeCount("toc-empty"))

            // …and a tapped row NAVIGATES. Row 3 = chapter 4, comfortably inside the lazily composed
            // window the sheet opens on (currentTocIndex is 0 at the top of the book).
            val target = 3
            val targetTitle = requireNotNull(entries[target].title)
            compose.onNodeWithTag("toc-row-$target", useUnmergedTree = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("toc-sheet-content") == 0 }
            compose.waitUntil(UI_TIMEOUT_MS) { reader.read { it.firstVisibleChunkForTest() ?: 0 } > 0 }
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(targetTitle, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.waitUntil(UI_TIMEOUT_MS) { reader.read { it.currentTocIndexForTest() } == target }
            assertEquals(
                "the highlighted chapter follows the jump",
                target, reader.read { it.currentTocIndexForTest() },
            )
            Log.i(
                TAG,
                "ACCEPT-TXT book=real:黑暗血时代.txt chars_utf16=${text.length} entries=${entries.size} " +
                    "first='${entries.first().title}' last='${entries.last().title}' " +
                    "jumped_row=$target landed_chunk=${reader.read { it.firstVisibleChunkForTest() }}",
            )
        }
    }

    /**
     * A structural oracle over EVERY TXT entry, against the real decoded text: each title is exactly
     * what stands at its own source offset (leading indent allowed — `extractHeadings` records the
     * match start and trims the title), and offsets strictly increase in document order.
     */
    private fun assertTxtEntriesAnchoredIn(text: String, entries: List<TocEntry>) {
        var previous = -1
        entries.forEachIndexed { i, entry ->
            val title = requireNotNull(entry.title) { "entry $i has no title" }
            val offset = requireNotNull(entry.canonicalLocator.charOffsetUTF16) { "entry $i has no offset" }
            assertTrue("entry $i offset $offset is inside the document", offset in text.indices)
            assertTrue("entry offsets strictly increase (entry $i: $previous → $offset)", offset > previous)
            previous = offset
            val window = text.substring(offset, minOf(text.length, offset + title.length + 64))
            assertTrue(
                "entry $i title '$title' must stand at its own offset $offset (found '${window.take(40)}')",
                window.trimStart().startsWith(title),
            )
        }
    }

    /**
     * The MD analog. An MD entry's offset is its LINE start — including the `#` markers, which the
     * title does not carry — so the anchor check is "the line at this offset is an ATX heading of
     * this entry's depth whose text contains this title", not a bare prefix match.
     */
    private fun assertMdEntriesAnchoredIn(text: String, entries: List<TocEntry>) {
        var previous = -1
        entries.forEachIndexed { i, entry ->
            val title = requireNotNull(entry.title) { "entry $i has no title" }
            val offset = requireNotNull(entry.canonicalLocator.charOffsetUTF16) { "entry $i has no offset" }
            assertTrue("entry $i offset $offset is inside the document", offset in text.indices)
            assertTrue("entry offsets strictly increase (entry $i: $previous → $offset)", offset > previous)
            previous = offset
            val line = text.substring(offset, minOf(text.length, offset + title.length + 96))
                .substringBefore('\n')
                .trim()
            val marker = "#".repeat(entry.depth + 1) + " "
            assertTrue(
                "entry $i must sit on its own depth-${entry.depth} ATX line (found '${line.take(60)}')",
                line.startsWith(marker) && line.contains(title),
            )
        }
    }

    // ---- 2. §5 gate 1 — the scan's own budget on the real book ------------------------------------

    /**
     * Plan §5 gate 1: the whole-document TXT scan on the real 14 MB book completes within the STATED
     * [SCAN_BUDGET_MS] with no reader open. Measured COLD — no warm-up run, because production scans
     * once per reader session with a cold `Pattern` cache and a cold JIT, so a warmed number would
     * flatter it.
     *
     * The correctness assertion is deliberately in the SAME test: a scan that returned nothing would
     * beat any latency budget, so the budget only means something next to the 1 859-entry result.
     */
    @Test
    fun realCjkBook_scanCompletesWithinBudget() {
        val text = requireRealBookText()
        val book = importFile(requireRealBookFile(), REAL_BOOK_DISPLAY_NAME)
        val provider = TxtMdTocProvider(text, book, BookFormat.txt, Dispatchers.Default)

        // Memory is measured ACROSS the scan, not just after it: an absolute reading would be the
        // whole process's posture (including everything earlier methods left behind) and would
        // attribute nothing. The delta is what the scan itself costs.
        System.gc()
        Thread.sleep(200)
        val runtime = Runtime.getRuntime()
        val pssBeforeMb = Debug.MemoryInfo().also { Debug.getMemoryInfo(it) }.totalPss / 1024
        val heapBeforeMb = (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576

        val t0 = SystemClock.elapsedRealtime()
        val entries = runBlocking { provider.toc() }
        val elapsedMs = SystemClock.elapsedRealtime() - t0

        val pssAfterMb = Debug.MemoryInfo().also { Debug.getMemoryInfo(it) }.totalPss / 1024
        val heapAfterMb = (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576

        // Diagnostic split — LOGGED, never gated. When this gate fails, the follow-up has to be
        // designed from where the time actually goes (one-time `Pattern.compile` + JIT vs steady-state
        // regex throughput; detection over the 512 KB sample vs extraction over all 7 M chars), not
        // from a single opaque total. Necessarily WARM, since it runs after the gated cold call — and
        // the cold-vs-warm gap is itself the answer to "is this compilation or throughput?".
        val d0 = SystemClock.elapsedRealtime()
        val rule = runBlocking { TxtTocRuleEngine.detectBestRule(text) }
        val warmDetectMs = SystemClock.elapsedRealtime() - d0
        val e0 = SystemClock.elapsedRealtime()
        val warmExtractCount = runBlocking {
            TxtTocRuleEngine.extractHeadings(text, requireNotNull(rule), TxtMdTocProvider.MAX_TOC_ENTRIES + 1)
        }.headings.size
        val warmExtractMs = SystemClock.elapsedRealtime() - e0

        Log.i(
            TAG,
            "SCAN-QUIET book=real:黑暗血时代.txt chars_utf16=${text.length} entries=${entries.size} " +
                "scan_ms=$elapsedMs budget_ms=$SCAN_BUDGET_MS met=${elapsedMs < SCAN_BUDGET_MS} " +
                "warm_detect_ms=$warmDetectMs warm_extract_ms=$warmExtractMs " +
                "warm_total_ms=${warmDetectMs + warmExtractMs} " +
                "winning_rule=${rule?.id}:${rule?.name} warm_extracted=$warmExtractCount " +
                "pss_mb=$pssBeforeMb->$pssAfterMb heap_mb=$heapBeforeMb->$heapAfterMb",
        )

        assertEquals("the scan found the real book's chapters", EXPECTED_CHAPTER_COUNT, entries.size)
        assertEquals("a repeat extraction is deterministic", entries.size, warmExtractCount)
        assertTxtEntriesAnchoredIn(text, entries)
        assertTrue("the scan latency must be measured (>0 ms)", elapsedMs > 0)
        assertTrue(
            "the real-book TOC scan ($elapsedMs ms) must meet the STATED ${SCAN_BUDGET_MS}ms budget (plan §5 gate 1)",
            elapsedMs < SCAN_BUDGET_MS,
        )
    }

    /**
     * Plan §5 gate 1 UNDER CONTENTION — the budget that actually matters, because §5 requires the
     * measurement on a busy device rather than a quiet one.
     *
     * The load is the real thing, not a synthetic spinner: #138's `PaginationSession` is driven over
     * the same real document with the same production shaping, so the background completion pass
     * (≈15 s of continuous measurement for this book's 30 695 pages) is saturating the emulator while
     * the scan runs, and the search indexer — started unconditionally by `VReaderApp.onCreate` — is
     * working through the same fresh 14 MB import.
     *
     * **Why the session is driven directly rather than by opening the reader.** A first pass that
     * opened `TxtReaderActivity` on this book in Paged layout measured the same thing but was
     * `lowmemorykiller`-ed at ~1 GB RSS on a 2.5 GB emulator, because it stacked a whole second
     * document copy, the compose tree over 254 109 chunks, the render cache and the host's OWN TOC
     * scan on top of the pagination index. That is a HARNESS artifact, not production: in the app
     * exactly ONE TOC scan runs against one pagination pass, which is what this arrangement
     * reproduces. The production path itself is covered by
     * [realCjkBook_producesExpectedChapterCount].
     *
     * The contention is PROVEN rather than assumed: the sealed page count must have GROWN across the
     * measured window. Without that, a run whose background pass had already finished would report a
     * quiet-device number under a "contention" name.
     */
    @Test
    fun realCjkBook_scanUnderContention_withinBudget() {
        val text = requireRealBookText()
        val book = importFile(requireRealBookFile(), REAL_BOOK_DISPLAY_NAME)
        val document = TxtDocument.of(text)
        val shaping = productionShaping()
        val provider = TxtMdTocProvider(text, book, BookFormat.txt, Dispatchers.Default)
        val indexStateBefore = runBlocking {
            app.container.database.searchDao().indexState(book.fingerprintKey)?.status
        }

        val session = PaginationSession(
            TxtPaginator(),
            initialWindowPages = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
            extendPages = TxtPaginator.DEFAULT_EXTEND_PAGES,
        )
        // A scope OFF the test thread: `openFromStart` measures on the CALLER's context, so the
        // background pass has to own real worker threads for this to be contention at all.
        val loadScope = CoroutineScope(Dispatchers.Default)
        val firstPublished = CompletableDeferred<Unit>()
        // AtomicInteger, not a captured `var`: the snapshots are published on a worker thread and read
        // from the test thread, and a plain captured local carries no visibility guarantee.
        val sealedPages = AtomicInteger(0)
        val load = loadScope.launch {
            session.openFromStart(
                document = document, style = shaping.style, contentBox = shaping.box,
                measurer = shaping.measurer, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { snap ->
                    sealedPages.set(snap.pageCount)
                    if (!firstPublished.isCompleted) firstPublished.complete(Unit)
                },
                onReveal = { },
            )
        }
        try {
            runBlocking { firstPublished.await() }   // pagination is now demonstrably in flight
            val pagesBefore = sealedPages.get()
            val t0 = SystemClock.elapsedRealtime()
            val entries = runBlocking { provider.toc() }
            val elapsedMs = SystemClock.elapsedRealtime() - t0
            val pagesAfter = sealedPages.get()

            Log.i(
                TAG,
                "SCAN-CONTENDED book=real:黑暗血时代.txt entries=${entries.size} scan_ms=$elapsedMs " +
                    "budget_ms=$SCAN_BUDGET_MS met=${elapsedMs < SCAN_BUDGET_MS} " +
                    "paged_pages=$pagesBefore->$pagesAfter search_index_state=$indexStateBefore",
            )

            assertTrue(
                "the background pagination must have been ACTIVE across the measured window " +
                    "(sealed pages $pagesBefore → $pagesAfter) — otherwise this is a quiet measurement",
                pagesAfter > pagesBefore,
            )
            assertEquals("the contended scan still found every chapter", EXPECTED_CHAPTER_COUNT, entries.size)
            assertTrue("the contended scan latency must be measured (>0 ms)", elapsedMs > 0)
            assertTrue(
                "the CONTENDED real-book TOC scan ($elapsedMs ms) must meet the STATED " +
                    "${SCAN_BUDGET_MS}ms budget (plan §5 gate 1)",
                elapsedMs < SCAN_BUDGET_MS,
            )
        } finally {
            load.cancel()
            loadScope.cancel()
        }
    }

    // ---- 3. §5 gate 2 — open-to-first-page non-regression (BLOCKING PRIMARY) ----------------------

    /**
     * Plan §5 gate 2 — **the primary blocking gate**: a TOC scan that meets its own budget but delays
     * first paint has failed the feature.
     *
     * Measured exactly as #138 measured it (`PaginationSession.openFromStart` → the FIRST published
     * snapshot on the real book), so the number is comparable to that feature's verified 8 ms rather
     * than to an invented baseline. Two arms:
     *
     *  1. **quiet** — the #138 baseline, re-measured in this build.
     *  2. **with a concurrent #139 scan** — the WORST case, in which the host's first-frame gate
     *     failed completely and the whole-document scan is grinding while the reader opens. The scan
     *     is asserted to have still been in flight at the first publish, so this arm cannot pass by
     *     having quietly finished first.
     *
     * BOTH arms must meet #138's stated < [FIRST_PAGE_TARGET_MS] target.
     *
     * Reading the two numbers: arm 1 runs FIRST and therefore pays this class's cold class-load and
     * JIT, so arm 2 is routinely the *faster* of the two. That ordering effect is why the gate is
     * stated as an absolute target on BOTH arms rather than as a ratio between them — a
     * quiet-vs-loaded delta on a cold-started process would be measuring the JIT, not the feature.
     */
    @Test
    fun realCjkBook_openToFirstPage_doesNotRegress() {
        val text = requireRealBookText()
        val book = importFile(requireRealBookFile(), REAL_BOOK_DISPLAY_NAME)
        val document = TxtDocument.of(text)
        val shaping = productionShaping()
        val provider = TxtMdTocProvider(text, book, BookFormat.txt, Dispatchers.Default)

        val quiet = measureOpenToFirstPage(document, shaping, provider = null)
        val contended = measureOpenToFirstPage(document, shaping, provider = provider)

        Log.i(
            TAG,
            "FIRST-PAGE book=real:黑暗血时代.txt chars_utf16=${text.length} chunks=${document.chunkCount} " +
                "quiet_first_page_ms=${quiet.firstPageMs} " +
                "with_toc_scan_first_page_ms=${contended.firstPageMs} " +
                "first_window_pages=${quiet.firstWindowPages}/${contended.firstWindowPages} " +
                "scan_in_flight_at_publish=${contended.scanStillRunning} target_ms=$FIRST_PAGE_TARGET_MS " +
                "met=${quiet.firstPageMs < FIRST_PAGE_TARGET_MS && contended.firstPageMs < FIRST_PAGE_TARGET_MS} " +
                "content_box=${shaping.box.widthPx.toInt()}x${shaping.box.heightPx.toInt()}",
        )

        assertTrue("quiet open-to-first-page must be measured (>0 ms)", quiet.firstPageMs > 0)
        assertTrue(
            "the first published window must seal at least the initial-window target " +
                "(${TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES}) — i.e. this is a genuine first page",
            quiet.firstWindowPages >= TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
        )
        assertTrue(
            "the first publish must be genuinely PARTIAL on a 14 MB book (windowed, not whole-doc)",
            quiet.firstWindowPages < 1_000,
        )
        assertTrue(
            "quiet open-to-first-page (${quiet.firstPageMs} ms) must meet #138's stated " +
                "< ${FIRST_PAGE_TARGET_MS}ms target — the #139 build has not moved the baseline",
            quiet.firstPageMs < FIRST_PAGE_TARGET_MS,
        )
        assertTrue(
            "the concurrent TOC scan must still have been RUNNING when the first page published — " +
                "otherwise the under-load arm proves nothing",
            contended.scanStillRunning,
        )
        assertTrue(
            "open-to-first-page WITH a concurrent #139 TOC scan (${contended.firstPageMs} ms) must " +
                "meet #138's stated < ${FIRST_PAGE_TARGET_MS}ms target (plan §5 gate 2, BLOCKING)",
            contended.firstPageMs < FIRST_PAGE_TARGET_MS,
        )
    }

    private class FirstPageMeasurement(
        val firstPageMs: Long,
        val firstWindowPages: Int,
        val scanStillRunning: Boolean,
    )

    /**
     * One cold `openFromStart` on [document], timed to its FIRST published snapshot. When [provider]
     * is non-null a #139 TOC scan is launched first and confirmed DISPATCHED (the scan coroutine
     * completes a started-signal before calling into the provider) so the pagination genuinely opens
     * against a busy CPU; whether it was still running at the publish is REPORTED, not assumed.
     *
     * The background completion loop is cancelled right after the first snapshot — this gate is about
     * the first page, and the full 30 695-page pass is #138's own already-verified measurement.
     */
    private fun measureOpenToFirstPage(
        document: TxtDocument,
        shaping: Shaping,
        provider: TxtMdTocProvider?,
    ): FirstPageMeasurement = runBlocking {
        val session = PaginationSession(
            TxtPaginator(),
            initialWindowPages = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
            extendPages = TxtPaginator.DEFAULT_EXTEND_PAGES,
        )
        var scanJob: Job? = null
        if (provider != null) {
            val dispatched = CompletableDeferred<Unit>()
            scanJob = launch(Dispatchers.Default) {
                dispatched.complete(Unit)
                runCatching { provider.toc() }
            }
            dispatched.await()   // the scan coroutine is on a worker thread before the clock starts
        }

        val firstPublished = CompletableDeferred<TxtPageIndex>()
        var firstPageMs = -1L
        var scanStillRunning = false
        val t0 = SystemClock.elapsedRealtime()
        val bg = launch {
            session.openFromStart(
                document = document, style = shaping.style, contentBox = shaping.box,
                measurer = shaping.measurer, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { snap ->
                    if (!firstPublished.isCompleted) {
                        firstPageMs = SystemClock.elapsedRealtime() - t0
                        scanStillRunning = scanJob?.isActive == true
                        firstPublished.complete(snap)
                    }
                },
                onReveal = { },
            )
        }
        val firstWindow = firstPublished.await()
        bg.cancelAndJoin()
        scanJob?.cancelAndJoin()
        FirstPageMeasurement(firstPageMs, firstWindow.pageCount, scanStillRunning)
    }

    /** The production shaping inputs a pagination pass needs (the `TxtReaderBody` triple). */
    private class Shaping(val measurer: LineMeasurer, val style: TextStyle, val box: PageContentBox)

    /**
     * The production shaping inputs, built WITHOUT a composition.
     *
     * `TxtPaginatorPerfBenchmark` captures these from a live `setContent`; this class drives
     * `ActivityScenario` (so it uses `createEmptyComposeRule`, which has no content to set), and all
     * three inputs are constructible directly: [Density] from the display metrics + font scale is
     * exactly what Compose's Android density is, `createFontFamilyResolver(context)` is the same
     * resolver it provides, and the benchmark's `LocalTextStyle.current` resolves to
     * [TextStyle.Default] there (its `setContent` installs no MaterialTheme), so
     * `TextStyle.Default.merge(bodyTextStyle())` is the same style. The content box is the device
     * screen minus the #129 default margins, as `TxtReaderBody` lays it out — which is what makes the
     * measured number comparable to #138's.
     */
    private fun productionShaping(): Shaping {
        val context = instrumentation.targetContext
        val defaults = ReaderSettings()
        val metrics = context.resources.displayMetrics
        val configuration = context.resources.configuration
        val density = Density(density = metrics.density, fontScale = configuration.fontScale)
        val box = with(density) {
            PageContentBox(
                widthPx = (configuration.screenWidthDp.dp.toPx() - 2 * defaults.marginDp.dp.toPx())
                    .coerceAtLeast(1f),
                heightPx = (configuration.screenHeightDp.dp.toPx() - 2 * 16.dp.toPx())
                    .coerceAtLeast(1f),
            )
        }
        assertTrue("content box must not be degenerate on a real screen", !box.isDegenerate)
        return Shaping(
            measurer = ComposeLineMeasurer(
                TextMeasurer(createFontFamilyResolver(context), density, LayoutDirection.Ltr),
            ),
            style = TextStyle.Default.merge(defaults.bodyTextStyle()),
            box = box,
        )
    }

    // ---- 4. real markdown, through the production path --------------------------------------------

    /**
     * The MD half of the acceptance, on the repo's own `docs/architecture.md` — a real, large, deeply
     * nested markdown document (`test-books/books/` contains no `.md` file at all, so this format has
     * no real *book*; a real repo document beats a hand-written fixture).
     *
     * The expectation is an INDEPENDENT in-test oracle ([atxHeadingOracle]) rather than a hardcoded
     * list, so the test proves agreement between two implementations of the CommonMark ATX rules and
     * survives the document being edited. Nesting is then asserted where a user perceives it — the
     * laid-out indentation of the row title — not merely as a `depth` field.
     */
    @Test
    fun realMdFile_producesNestedEntries() {
        val file = requireRealMdFile()
        val text = file.readText()
        val expected = atxHeadingOracle(text)
        assertTrue(
            "the real markdown document must be deeply structured (oracle found ${expected.size} headings)",
            expected.size >= 20,
        )
        assertTrue(
            "the real markdown document must nest at least three levels",
            expected.map { it.first }.distinct().size >= 3,
        )
        importFile(file, REAL_MD_DISPLAY_NAME)

        openThroughLibrary(REAL_MD_TITLE) { reader ->
            reader.awaitScan()
            val entries = reader.read { it.tocEntriesForTest() }

            assertEquals(
                "the scanned MD headings match the independent ATX oracle (depth, title)",
                expected, entries.map { it.depth to it.title },
            )
            assertMdEntriesAnchoredIn(text, entries)

            openContentsSheet()
            // Nesting must be VISIBLE. Compare a depth-1 row against a depth-2 row; row 0 is skipped
            // because the current-chapter marker adds its own arrangement spacing (the WI-7 note).
            val depthOne = entries.indexOfFirst { it.depth == 1 }
            val depthTwo = entries.indexOfFirst { it.depth == 2 }
            assertTrue("a depth-1 row exists past row 0 (was $depthOne)", depthOne in 1..10)
            assertTrue("a depth-2 row is inside the sheet's first composed window (was $depthTwo)", depthTwo in 1..10)
            val oneLeft = titleLeftInRow("toc-row-$depthOne", requireNotNull(entries[depthOne].title))
            val twoLeft = titleLeftInRow("toc-row-$depthTwo", requireNotNull(entries[depthTwo].title))
            assertTrue("depth 2 indents past depth 1 (was $twoLeft vs $oneLeft)", twoLeft > oneLeft)

            // A nested row navigates, exactly like a TXT chapter row.
            val targetTitle = requireNotNull(entries[depthTwo].title)
            compose.onNodeWithTag("toc-row-$depthTwo", useUnmergedTree = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("toc-sheet-content") == 0 }
            compose.waitUntil(UI_TIMEOUT_MS) { reader.read { it.firstVisibleChunkForTest() ?: 0 } > 0 }
            compose.waitUntil(UI_TIMEOUT_MS) { reader.read { it.currentTocIndexForTest() } == depthTwo }
            Log.i(
                TAG,
                "ACCEPT-MD doc=real:docs/architecture.md bytes=${file.length()} entries=${entries.size} " +
                    "depths=${entries.map { it.depth }.distinct().sorted()} jumped_row=$depthTwo " +
                    "jumped_title='$targetTitle'",
            )
        }
    }

    /**
     * An INDEPENDENT ATX-heading oracle: `(depth, title)` for every heading in [text], written from
     * the CommonMark rules (1–6 `#` then a literal space; title trimmed; a trailing closing-hash run
     * dropped only when something is left) with fence tracking — NOT from `MdTocScanner`'s state
     * machine. Setext headings are deliberately not modelled: the real document contains none, and a
     * disagreement introduced by a future edit should surface as a red test rather than be absorbed
     * here.
     */
    private fun atxHeadingOracle(text: String): List<Pair<Int, String?>> {
        val out = mutableListOf<Pair<Int, String?>>()
        var fence: Char? = null
        var fenceLength = 0
        for (raw in text.split("\n")) {
            val line = raw.trim()
            val runChar = line.firstOrNull()
            if (runChar == '`' || runChar == '~') {
                val run = line.takeWhile { it == runChar }.length
                if (run >= 3) {
                    if (fence == null) {
                        fence = runChar
                        fenceLength = run
                    } else if (runChar == fence && run >= fenceLength) {
                        fence = null
                        fenceLength = 0
                    }
                    continue
                }
            }
            if (fence != null) continue
            val hashes = line.takeWhile { it == '#' }.length
            if (hashes !in 1..6 || line.length <= hashes || line[hashes] != ' ') continue
            var title = line.substring(hashes + 1).trim()
            if (title.endsWith("#")) {
                val stripped = title.trimEnd('#').trim()
                if (stripped.isNotEmpty()) title = stripped
            }
            if (title.isEmpty()) continue
            out += (hashes - 1) to title
        }
        return out
    }

    // ---- 5. the other half of the criterion: no headings → no control -----------------------------

    /**
     * A headings-free document reaches the reader through the Library with NO Contents control —
     * asserted only AFTER the scan has genuinely COMPLETED, so a stranded gate can never be mistaken
     * for "this book has no chapters" (the WI-7 discipline, re-run here on the production path).
     *
     * Fixture exception (AGENTS.md "real books first"): the committed `resume-sample.txt` asset is the
     * deterministic-tiny-structure case — the assertion is the ABSENCE of a control, which needs a
     * document known to contain no chapter markers, not a large one.
     */
    @Test
    fun realTxtWithoutHeadings_hidesContentsControl() {
        importAsset("resume-sample.txt")
        openThroughLibrary("resume-sample") { reader ->
            reader.awaitScan()
            assertEquals(
                "no headings detected in the headings-free document",
                0, reader.read { it.tocEntriesForTest() }.size,
            )
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("reader-bottom-chrome") > 0 }
            assertEquals("the Contents control stays hidden with an empty TOC", 0, nodeCount("chrome-contents"))
            assertTrue("the rest of the bottom chrome is unaffected", nodeCount("chrome-notes") > 0)
        }
    }
}
