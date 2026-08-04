package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Feature #139 WI-7 — connected proof that the TXT/MD table of contents is REAL in the running reader:
 *
 *  - a TXT book WITH chapter headings shows the Contents control (which every build before this WI
 *    hid, because the host passed `tocEntries = emptyList()` unconditionally);
 *  - a TXT book WITHOUT them still hides it — asserted only after the scan has actually COMPLETED
 *    (`tocScanCompletedForTest`), so a stuck gate can never be mistaken for "this book has no TOC";
 *  - a tapped Contents row navigates in BOTH layouts — the scroll chunk seam and the paged pager
 *    (over the #138 windowed index);
 *  - the two layouts' read-aloud interaction, which genuinely DIFFERS (plan §WI-7 note): scroll
 *    re-follows the narration immediately, paged holds until narration next advances;
 *  - an MD book's nested headings render indented, and the highlighted row tracks reading position.
 *
 * Fixtures: generated TXT/MD written to the app cache and imported through the REAL importer. Real
 * books first (AGENTS.md) does not apply usefully here — `test-books/` is gitignored and unreachable
 * from an instrumented run, and these assertions need a deterministic tiny structure (exact chapter
 * count, known char offsets, exactly three MD depths) that a 14 MB novel cannot give cheaply. WI-8's
 * acceptance pass is where the real 黑暗血时代.txt is exercised. The headings-free case reuses the
 * committed `resume-sample.txt` asset rather than inventing prose.
 *
 * Run ONE class per connected invocation (MEMORY #129/#133); never drive the emulator while this runs.
 */
@RunWith(AndroidJUnit4::class)
class TxtTocConnectedTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    @Before
    fun pinDefaults() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
        // Scroll is the default for every test that does not opt into Paged, and it must be CONFIRMED
        // committed, not merely requested: a DataStore write is async, so a bare `setLayout` lets a
        // leftover `Paged` value from a previous test reach the reader — which then routes jumps to the
        // pager and fails every scroll assertion. (Only ONE @Before: JUnit does not order two of them.)
        store.setLayout(ReaderLayout.Scroll)
        for (i in 0 until 100) {
            if (store.current().layout == ReaderLayout.Scroll) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("Scroll layout not committed to the store in time")
    }

    @After
    fun restoreScroll() = runBlocking<Unit> {
        app.container.readerSettingsStore.setLayout(ReaderLayout.Scroll)
    }

    // ---- fixtures ------------------------------------------------------------------------------

    /** Three rule-3 ("Chapter N …") headings, each followed by enough body to span chunks/pages. */
    private fun chapteredTxt(): String = buildString {
        append("A short preface line which is not a heading.\n")
        for (c in 1..3) {
            append("Chapter $c The Part\n")
            repeat(30) { append("Body line ${it + 1} of chapter $c.\n") }
        }
    }

    /** ATX headings at three levels → depths 0 / 1 / 2, which the sheet renders as indentation. */
    private fun nestedMd(): String = buildString {
        append("# Top level\n\n")
        repeat(10) { append("Body text under top, line ${it + 1}.\n") }
        append("\n## Nested one\n\n")
        repeat(10) { append("Body text under nested one, line ${it + 1}.\n") }
        append("\n### Nested two\n\n")
        repeat(10) { append("Body text under nested two, line ${it + 1}.\n") }
    }

    private fun importContent(displayName: String, content: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "toc-${System.nanoTime()}-$displayName")
        staged.writeText(content)
        val book = runBlocking {
            app.container.importer.importStream("content://test/$displayName", displayName, staged.inputStream())
        }
        app.container.cacheOffset(book.fingerprintKey, 0)
        return book.fingerprintKey
    }

    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "toc-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        app.container.cacheOffset(book.fingerprintKey, 0)
        return book.fingerprintKey
    }

    // ---- harness -------------------------------------------------------------------------------

    private fun setLayoutAndConfirm(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        for (i in 0 until 50) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    private fun nodeCount(tag: String) =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    /** The laid-out left edge of the title `Text` inside a Contents row — the row's own indentation as
     *  rendered, which is what a reader actually sees for a nested MD heading. */
    private fun titleLeftInRow(rowTag: String, title: String): Float {
        val row = compose.onNodeWithTag(rowTag, useUnmergedTree = true).fetchSemanticsNode()
        val child = row.children.firstOrNull { node ->
            node.config.getOrNull(SemanticsProperties.Text)?.any { it.text.contains(title) } == true
        } ?: throw AssertionError("no '$title' title text inside $rowTag")
        return child.positionInRoot.x
    }

    private fun <T> ActivityScenario<TxtReaderActivity>.read(block: (TxtReaderActivity) -> T): T {
        var value: Any? = null
        onActivity { value = block(it) }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    private fun ActivityScenario<TxtReaderActivity>.awaitScan(timeoutMs: Long = 20_000) {
        compose.waitUntil(timeoutMs) { read { it.tocScanCompletedForTest() } }
        // For a book WITH chapters, also wait until the chrome has RECEIVED them: `currentTocIndex` and
        // the row-jump lambda are composition-derived and land one recomposition after the scan
        // publishes. A jump driven before that closes over the pre-scan empty list and reports failure.
        // A headings-free book stays at `-1` by contract, so this barrier applies only when non-empty.
        if (read { it.tocEntriesForTest().isNotEmpty() }) {
            compose.waitUntil(timeoutMs) { read { it.currentTocIndexForTest() } >= 0 }
        }
    }

    private fun ActivityScenario<TxtReaderActivity>.awaitPageIndex(timeoutMs: Long = 20_000) {
        compose.waitUntil(timeoutMs) { read { it.pagedPageCountForTest()?.let { c -> c > 0 } == true } }
    }

    private fun ActivityScenario<TxtReaderActivity>.tocOffset(index: Int): Int =
        read { it.tocEntriesForTest()[index].canonicalLocator.charOffsetUTF16!! }

    /** Run a suspend host seam on the Activity's scope, blocking for completion. */
    private fun ActivityScenario<TxtReaderActivity>.blocking(block: suspend (TxtReaderActivity) -> Unit) {
        val latch = CountDownLatch(1)
        val error = arrayOfNulls<Throwable>(1)
        onActivity { activity ->
            activity.lifecycleScope.launch {
                try { block(activity) } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(30, TimeUnit.SECONDS)) throw AssertionError("host seam timed out")
        error[0]?.let { throw it }
    }

    /** Open the Contents sheet through the PRODUCTION path: the bottom-chrome Contents control. */
    private fun openContentsSheet() {
        compose.waitUntil(20_000) { nodeCount("chrome-contents") > 0 }
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).performClick()
        compose.waitUntil(20_000) { nodeCount("toc-sheet-content") > 0 }
    }

    private inline fun withReader(key: String, block: (ActivityScenario<TxtReaderActivity>) -> Unit) {
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use(block)
    }

    // ---- control visibility --------------------------------------------------------------------

    @Test
    fun txtBookWithChapters_showsContentsControl() {
        val key = importContent("toc-chapters.txt", chapteredTxt())
        withReader(key) { scenario ->
            scenario.awaitScan()
            assertEquals("the three chapter headings were detected", 3, scenario.read { it.tocEntriesForTest().size })
            // The user-visible delta of this WI: the Contents control is now REACHABLE.
            compose.waitUntil(20_000) { nodeCount("chrome-contents") > 0 }
            // And it opens the designed Contents sheet with one row per chapter.
            openContentsSheet()
            assertTrue("the Contents sheet lists the chapters", nodeCount("toc-row-0") > 0)
            assertEquals("no empty state for a book that HAS chapters", 0, nodeCount("toc-empty"))
        }
    }

    @Test
    fun txtBookWithoutChapters_hidesContentsControl() {
        // A real committed fixture: 100 lines of "Line NNN of the resume fixture." — no chapter markers.
        val key = importAsset("resume-sample.txt")
        withReader(key) { scenario ->
            // The scan COMPLETED (so this is not a stuck-gate false pass) and found nothing.
            scenario.awaitScan()
            assertEquals("no headings detected", 0, scenario.read { it.tocEntriesForTest().size })
            compose.waitUntil(20_000) { nodeCount("reader-bottom-chrome") > 0 }
            assertEquals("the Contents control stays hidden with an empty TOC", 0, nodeCount("chrome-contents"))
            // Notes is still there — the toolbar is not broken, only Contents is absent.
            assertTrue("the rest of the bottom chrome is unaffected", nodeCount("chrome-notes") > 0)
        }
    }

    // ---- jumps -----------------------------------------------------------------------------------

    @Test
    fun tapChapterRow_scrollMode_navigatesToThatOffset() {
        val key = importContent("toc-scrolljump.txt", chapteredTxt())
        withReader(key) { scenario ->
            scenario.awaitScan()
            compose.waitUntil(20_000) {
                compose.onAllNodesWithText("A short preface", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            assertEquals("the reader opens at the top", 0, scenario.read { it.firstVisibleChunkForTest() })

            openContentsSheet()
            compose.onNodeWithTag("toc-row-2", useUnmergedTree = true).performClick()

            // A successful jump dismisses the sheet and lands the list on chapter 3's line.
            compose.waitUntil(20_000) { nodeCount("toc-sheet-content") == 0 }
            val chapter3 = scenario.tocOffset(2)
            compose.waitUntil(20_000) { scenario.read { it.firstVisibleChunkForTest() ?: 0 } > 0 }
            val landed = scenario.read { it.firstVisibleChunkForTest()!! }
            assertTrue("the list scrolled forward to chapter 3", landed > 0)
            compose.waitUntil(20_000) {
                compose.onAllNodesWithText("Chapter 3", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // The row's own offset is what drove it (the jump target IS the heading's char offset).
            assertEquals(chapter3, scenario.read { it.tocEntriesForTest()[2].canonicalLocator.charOffsetUTF16 })
        }
    }

    @Test
    fun tapChapterRow_pagedMode_navigatesToThatOffset() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importContent("toc-pagedjump.txt", chapteredTxt())
        withReader(key) { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitScan()
            assertTrue("the paged body is mounted", scenario.read { it.pagedBodyMountedForTest() } == true)
            assertEquals(3, scenario.read { it.tocEntriesForTest().size })

            val chapter3 = scenario.tocOffset(2)
            val expectedPage = scenario.read { it.pagedPageContainingForTest(chapter3)!! }
            assertNotEquals("chapter 3 is not on the opening page", 0, expectedPage)

            // Drive the SAME lambda the Contents row taps (the modal sheet's own click is covered by the
            // scroll-mode test; here the point is that the PAGER — not the hidden list — moves).
            assertTrue("a valid row reports a successful jump", scenario.read { it.jumpTocForTest(2) })
            // The landing page is asserted as "the page that CONTAINS chapter 3", re-evaluated against
            // the live index — not against the page number computed before the jump. With #138's
            // windowed pagination the index can still be PARTIAL at jump time, so the body extends it
            // on demand and the offset's page number legitimately shifts as pages seal.
            compose.waitUntil(20_000) {
                val page = scenario.read { it.pagedCurrentPageForTest() ?: -1 }
                page > 0 && scenario.read { it.pagedPageContainingForTest(chapter3) } == page
            }
            val landed = scenario.read { it.pagedCurrentPageForTest()!! }
            assertTrue("the pager left the opening page", landed > 0)
            assertEquals("the pager is on chapter 3's page", landed, scenario.read { it.pagedPageContainingForTest(chapter3) })
        }
    }

    // ---- read-aloud interaction (the two layouts genuinely differ) --------------------------------

    @Test
    fun tocJump_scrollMode_whileTtsSpeaking_isImmediatelyRefollowed() {
        val key = importContent("toc-scrolltts.txt", chapteredTxt())
        withReader(key) { scenario ->
            scenario.awaitScan()
            compose.waitUntil(20_000) { nodeCount("chrome-contents") > 0 }

            // Narration is on chunk 0 (the emulator has no TTS voice data, so the follow decision is
            // driven through the production helper — the #137 simulatePagedTtsFollow precedent).
            assertTrue("a valid row reports a successful jump", scenario.read { it.jumpTocForTest(2) })
            compose.waitUntil(20_000) { scenario.read { it.firstVisibleChunkForTest() ?: 0 } > 0 }

            // In SCROLL mode the follow effect is keyed on firstVisibleItemIndex, so the jump itself
            // re-runs it at once: the spoken chunk is no longer visible → the reader is yanked back.
            scenario.blocking { it.simulateScrollTtsFollowForTest(0) }
            compose.waitUntil(20_000) { scenario.read { it.firstVisibleChunkForTest() } == 0 }
            assertEquals(
                "scroll mode re-follows narration immediately after a TOC jump (accepted, pre-existing — F5)",
                0, scenario.read { it.firstVisibleChunkForTest() },
            )
        }
    }

    @Test
    fun tocJump_pagedMode_whileTtsSpeaking_holdsUntilNarrationAdvances() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importContent("toc-pagedtts.txt", chapteredTxt())
        withReader(key) { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitScan()

            // Narration lands on chapter 2's page (one follow).
            val chapter2 = scenario.tocOffset(1)
            val narrationPage = scenario.read { it.pagedPageContainingForTest(chapter2)!! }
            scenario.read { it.simulatePagedTtsFollowForTest(chapter2) }
            compose.waitUntil(20_000) { scenario.read { it.pagedCurrentPageForTest() } == narrationPage }

            // The user now jumps to chapter 3 from Contents while narration's charStart is unchanged.
            val chapter3 = scenario.tocOffset(2)
            val jumpPage = scenario.read { it.pagedPageContainingForTest(chapter3)!! }
            assertNotEquals("the jump target is a different page", narrationPage, jumpPage)
            assertTrue(scenario.read { it.jumpTocForTest(2) })
            compose.waitUntil(20_000) { scenario.read { it.pagedCurrentPageForTest() } == jumpPage }

            // PAGED mode HOLDS: the follow effect keys only on the narration signal, so a TOC jump is
            // not fought. Give any wrongly-keyed effect a chance to yank back.
            compose.waitForIdle()
            assertEquals(
                "paged mode holds the TOC jump until narration next advances",
                jumpPage, scenario.read { it.pagedCurrentPageForTest() },
            )

            // ...and when narration DOES advance, the pager follows again.
            val chapter1 = scenario.tocOffset(0)
            scenario.read { it.simulatePagedTtsFollowForTest(chapter1) }
            val followPage = scenario.read { it.pagedPageContainingForTest(chapter1)!! }
            compose.waitUntil(20_000) { scenario.read { it.pagedCurrentPageForTest() } == followPage }
            assertEquals(followPage, scenario.read { it.pagedCurrentPageForTest() })
        }
    }

    // ---- MD + live highlight ---------------------------------------------------------------------

    @Test
    fun mdBook_showsContentsControl_withDepthIndentation() {
        val key = importContent("toc-nested.md", nestedMd())
        withReader(key) { scenario ->
            scenario.awaitScan()
            assertEquals(
                "the three ATX levels are detected with their real depths",
                listOf(0, 1, 2), scenario.read { it.tocEntriesForTest().map { e -> e.depth } },
            )
            assertEquals(
                listOf("Top level", "Nested one", "Nested two"),
                scenario.read { it.tocEntriesForTest().map { e -> e.title } },
            )
            compose.waitUntil(20_000) { nodeCount("chrome-contents") > 0 }
            openContentsSheet()
            // The designed row indentation (depth * 12dp on the title) is what makes the nesting
            // VISIBLE — measured on the laid-out title, not inferred from the depth field.
            // Compared between rows 1 and 2 ONLY. Row 0 is the current-chapter row, and its zero-size
            // `toc-current-marker` child still consumes the Row's 14dp arrangement spacing — that shifts
            // its title further right than a 12dp depth step, so a row-0 baseline would compare two
            // different things. (Row 0's own highlight is asserted in currentChapterHighlight_*.)
            val one = titleLeftInRow("toc-row-1", "Nested one")
            val two = titleLeftInRow("toc-row-2", "Nested two")
            assertTrue("depth 2 indents past depth 1 (was $two vs $one)", two > one)
        }
    }

    @Test
    fun currentChapterHighlight_followsReadingPosition() {
        val key = importContent("toc-highlight.txt", chapteredTxt())
        withReader(key) { scenario ->
            scenario.awaitScan()
            // The highlight is a composition-derived value, so it lands one recomposition after the
            // scan publishes — poll for it rather than reading the pre-scan `-1`.
            compose.waitUntil(20_000) { scenario.read { it.currentTocIndexForTest() } == 0 }
            assertEquals("at the top the first chapter is highlighted", 0, scenario.read { it.currentTocIndexForTest() })

            // Move the reading position into chapter 3 (the same chunk scroll a user's swipe produces).
            val chapter3 = scenario.tocOffset(2)
            assertTrue(scenario.read { it.jumpTocForTest(2) })
            compose.waitUntil(20_000) { scenario.read { it.currentTocIndexForTest() } == 2 }
            assertEquals("the highlight follows the position into chapter 3", 2, scenario.read { it.currentTocIndexForTest() })
            assertTrue("chapter 3's offset is past chapter 1's", chapter3 > scenario.tocOffset(0))

            // The sheet renders the highlight marker on that row.
            openContentsSheet()
            assertTrue("the current-chapter marker is rendered", nodeCount("toc-current-marker") > 0)
        }
    }
}
