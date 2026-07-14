package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.bilingual.BilingualServices
import com.vreader.app.bilingual.CachedTranslation
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.bilingual.TxtChapterTextProvider
import com.vreader.app.data.Book
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * feature #131 WI-8 — the TXT/MD bilingual interlinear host integration WIRED into TxtReaderActivity.
 * The render is Compose (unlike EPUB's WebView DOM injection); each source chunk's lazy item wraps its
 * byte-unchanged source `Text` and the muted, NON-registered translation slot(s) anchored to it in ONE
 * `Column`, so lazy-index == chunk-index is preserved (round-4 H2).
 *
 * There is NO active AI provider configured in these tests, so the ONLY way a translation lands is the
 * SEEDED cache (the prefetcher's cache-FIRST path returns before resolving a provider) — a rendered
 * translation IS the zero-provider proof. The long-press-does-NOT-select gesture-exclusion test is in a
 * SEPARATE class (TxtReaderBilingualGestureTest) so it runs in its own invocation (long-press connected
 * tests are emulator-timing-flaky; precedent #125/#135).
 *
 * The `Chinese` default target language yields `译文…` translations; the language key normalizes the same
 * way the VM keys the cache.
 */
@RunWith(AndroidJUnit4::class)
class TxtReaderBilingualConnectedTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val lang = "Chinese"   // BilingualLanguages default target key

    /** enable → setup → confirm → interlinear renders from the seeded cache (ZERO provider). */
    @Test fun enable_setup_confirm_rendersInterlinearFromCache_zeroProvider() {
        val (app, book) = stage("bilingual-render")
        seedWindow0(app, book)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            awaitVmBuilt(scenario)

            // ENABLE → the first-enable setup sheet is raised; "Turn on bilingual mode" confirms + dismisses it.
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()

            // The window-0 unit's translation slot renders from the seeded cache (zero provider). The
            // window has 3 segments → 3 translation-text children, so assert AT LEAST one carries `译文`.
            compose.waitUntil(8_000) {
                compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("bilingual-translation-slot").assertIsDisplayed()
            assertTrue(
                "a seeded translation segment (译文…) is rendered",
                compose.onAllNodesWithText("译文", substring = true).fetchSemanticsNodes().isNotEmpty(),
            )
        }
    }

    /** disable → the translation slot is gone; the source selection/render is byte-parity with the OFF baseline. */
    @Test fun disable_removesInterlinear_sourceParity() {
        val (app, book) = stage("bilingual-disable")
        seedWindow0(app, book)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            awaitVmBuilt(scenario)
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }

            onActivityBlocking(scenario) { it.disableBilingualForTest() }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isEmpty() }
            assertEquals(0, compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().size)
            // The source text is still rendered + selectable (unchanged).
            compose.onNodeWithText("quick brown fox", substring = true).assertIsDisplayed()
        }
    }

    /** reopen persists enabled + renders from cache with ZERO client calls (the config store round-trips). */
    @Test fun reopen_persistsEnabled_rendersFromCache_zeroProvider() {
        val (app, book) = stage("bilingual-reopen")
        seedWindow0(app, book)
        // First open: enable + confirm, then let the config persist.
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            awaitVmBuilt(scenario)
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }
        }
        // Persisted enabled is authoritative — reopen hydrates enabled; NO setup sheet (not a first enable);
        // the interlinear renders from cache with zero provider.
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            awaitVmBuilt(scenario)
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-translation-slot").assertIsDisplayed()
            // reopen persisted enabled (not a fresh first-enable → no setup sheet auto-shown).
            val state = onActivityValue(scenario) { it.bilingualStateForTest() }
            assertTrue("reopen hydrated enabled", state!!.enabled)
        }
    }

    /** the source-chunk selection registrations are UNCHANGED by bilingual ON (H2): the TTS
     *  source-visibility query still reports the source chunk visible after enable (registration intact). */
    @Test fun enabledMode_sourceChunkRegistration_unchanged_ttsVisibilityWorks() {
        val (app, book) = stage("bilingual-registration")
        seedWindow0(app, book)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            awaitVmBuilt(scenario)
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }
            // The source chunk still renders + is displayed (its Text is byte-unchanged, still registered);
            // a translation child added below it does not perturb the source render.
            compose.onNodeWithText("quick brown fox", substring = true).assertIsDisplayed()
            // enabled state settled true, translations present under the window-0 unit.
            val state = onActivityValue(scenario) { it.bilingualStateForTest() }
            assertTrue(state!!.enabled)
            assertTrue(
                "window-0 unit has a cached translation",
                state.translationsByUnit.containsKey(TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0")),
            )
        }
    }

    /** the anchor helper's window boundaries agree with TxtChapterTextProvider's unit resolution
     *  (parity — the render anchors line up with the unit the provider prefetches). Multi-window +
     *  paragraph-spanning + one-chunk + final-chunk anchor math (H1/Low-2) — pure, no Activity. */
    @Test fun anchorHelper_parityWithProvider_andAnchorMath() {
        // 20 blank-line-delimited paragraphs, each ONE line (one chunk) with a blank line between,
        // so windows of 8 span multiple anchor chunks; the final paragraph is the final content chunk.
        val paras = (1..20).map { "Paragraph number $it." }
        val text = paras.joinToString("\n\n") + "\n"
        val doc = TxtDocument.of(text)
        val kind = TranslationUnitId.Kind.txtDocSegmentWindow
        val provider = TxtChapterTextProvider(doc, kind)
        val anchors = BilingualTxtAnchors(doc, kind)

        // 20 paragraphs / windowSize 8 → 3 windows (0,1,2); each anchored to its last paragraph's chunk.
        val entries = anchors.anchorEntries()
        assertEquals("3 windows over 20 paragraphs", 3, entries.values.flatten().size)
        // Every unit the anchor map emits is a real provider unit (parity by construction).
        val providerUnits = provider.units().toSet()
        entries.values.flatten().forEach { unit ->
            assertTrue("anchored unit $unit is a provider unit", providerUnits.contains(unit))
        }
        // For each window, the offset at the START of its last paragraph resolves (via the provider's
        // unitContaining) to the SAME window the anchor map assigns to that paragraph's chunk.
        var segIndex = 0
        val spans = com.vreader.app.bilingual.ChapterSegmenter.paragraphRanges(text)
        for ((chunk, units) in entries) {
            units.forEach { unit ->
                // the provider resolves a mid-window offset to the same unit the map anchored to this chunk.
                val anyOffsetInWindow = spans[minOf(segIndex, spans.size - 1)].start
                assertEquals(
                    "provider unitContaining agrees with the anchor unit",
                    unit,
                    provider.unitContaining(anyOffsetInWindow),
                )
                segIndex += TxtChapterTextProvider.DEFAULT_WINDOW_SIZE
            }
        }

        // one-chunk document (one paragraph) → exactly one anchor at chunk 0.
        val one = BilingualTxtAnchors(TxtDocument.of("Only one paragraph.\n"), kind)
        assertEquals(1, one.anchorEntries().values.flatten().size)

        // final-chunk anchor: the last paragraph's chunk carries the last window's unit.
        val lastChunk = doc.chunkForOffset(spans.last().endExclusive - 1)
        assertTrue("final window anchors to the final content chunk", anchors.unitsForChunk(lastChunk).isNotEmpty())
    }

    /** MD source mapping: a .md book builds a mdDocSegmentWindow VM + renders from a seeded md cache. */
    @Test fun md_buildsMdKindVm_rendersFromCache() {
        val (app, book) = stageAsset("bilingual-md", "sample-note.md", "sample-note.md")
        // Seed under the MD kind's window-0 unit (segment count from the real MD provider).
        val doc = com.vreader.app.reader.TxtDocument.of(
            com.vreader.app.reader.TxtDecoder.decode(File(book.localFilePath!!)).text,
        )
        val kind = TranslationUnitId.Kind.mdDocSegmentWindow
        val provider = TxtChapterTextProvider(doc, kind)
        val unit0 = TranslationUnitId(kind, "0")
        val count = provider.sourceSegments(unit0).size
        seedUnit(app, book, unit0, List(count) { "译文${it + 1}" }, count)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            awaitVmBuilt(scenario)
            // the VM was built with the MD kind (a non-null state proves the mdDocSegmentWindow path built).
            val built = onActivityValue(scenario) { it.bilingualStateForTest() != null }
            assertTrue("md book built a bilingual VM", built)
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-translation-slot").assertIsDisplayed()
        }
    }

    /** with bilingual ON, the saved position round-trips to the SAME chunk on reopen (lazy-index ==
     *  chunk-index preserved — round-4 H2). Uses the tall 100-line resume fixture; a saved offset at line
     *  080 reopens scrolled to that chunk, not the top. */
    @Test fun enabledMode_positionSave_roundTripsToSameChunk() {
        val (app, book) = stageAsset("bilingual-pos", "resume-sample.txt", "resume-sample.txt")
        // Persist bilingual ENABLED for this book + save a position at line 080 (offset 2528).
        runBlocking {
            app.container.perBookBilingualStore.write(
                book.fingerprintKey,
                com.vreader.app.bilingual.PerBookBilingualConfig(enabled = true, targetLanguage = lang),
            )
            val locator = vreader.contracts.Locator(book.contentSHA256, book.fileByteCount, "txt", charOffsetUTF16 = 2528)
            app.container.repository.savePosition(vreader.contracts.VReaderLocator.wrapLegacy(locator), 1L)
        }
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            compose.waitUntil(8_000) { compose.onAllNodesWithText("Line 080", substring = true).fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("Line 080", substring = true).assertIsDisplayed()
            // Reopened scrolled to the saved offset (bilingual ON) — line 001 is NOT at the top.
            assertEquals(
                "reopened past the top with bilingual ON — line 001 not visible",
                0,
                compose.onAllNodesWithText("Line 001 of", substring = true).fetchSemanticsNodes().size,
            )
            // The top-visible chunk (firstVisibleItemIndex) is the resume chunk (chunkForOffset(2528)).
            val doc = TxtDocument.of(TxtDecoder.decode(File(book.localFilePath!!)).text)
            val expected = doc.chunkForOffset(2528)
            var actual = -1
            for (i in 0 until 40) { scenario.onActivity { actual = it.firstVisibleChunkForTest() ?: -1 }; if (actual == expected) break; Thread.sleep(50) }
            assertEquals("bilingual ON: firstVisibleItemIndex == chunkForOffset(savedOffset)", expected, actual)
        }
    }

    /** with bilingual ON, the TTS source-visibility seam is honored: a source chunk scrolled OFF the
     *  viewport reports NOT-visible (→ the guard would scroll it back), while the top chunk reports
     *  visible (round-5/6 High — the translation-only-visible → scroll condition; round-4 audit Medium-2). */
    @Test fun enabledMode_sourceVisibilitySeam_offscreenChunkNotVisible() {
        val (app, book) = stageAsset("bilingual-vis", "resume-sample.txt", "resume-sample.txt")
        // Persist enabled + CLEAR any leaked saved position (this fixture's fingerprint is shared with the
        // position round-trip test, whose saved offset would otherwise leak in) so the open top is known.
        runBlocking {
            app.container.perBookBilingualStore.write(
                book.fingerprintKey,
                com.vreader.app.bilingual.PerBookBilingualConfig(enabled = true, targetLanguage = lang),
            )
            val top = vreader.contracts.Locator(book.contentSHA256, book.fileByteCount, "txt", charOffsetUTF16 = 0)
            app.container.repository.savePosition(vreader.contracts.VReaderLocator.wrapLegacy(top), 2L)
        }
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("tts-read-aloud-entry").fetchSemanticsNodes().isNotEmpty() }
            awaitVmBuilt(scenario)
            // Scroll far down so chunk 0 (line 001) is well above the viewport.
            onActivityBlocking(scenario) { it.scrollToItemForTest(60) }
            compose.waitForIdle()
            // chunk 0's source is off-screen → NOT visible (the seam the TTS auto-scroll guard reads); a
            // chunk near the current top IS visible. Poll both against the live query (round-4 audit Medium-2).
            var chunk0Visible: Boolean? = true
            var topVisible: Boolean? = false
            for (i in 0 until 80) {
                scenario.onActivity {
                    chunk0Visible = it.isSourceChunkInViewportForTest(0)
                    topVisible = it.isSourceChunkInViewportForTest(it.firstVisibleChunkForTest() ?: 60)
                }
                if (chunk0Visible == false && topVisible == true) break
                Thread.sleep(50)
            }
            assertFalse("chunk 0 source scrolled off-viewport reports NOT visible", chunk0Visible == true)
            assertTrue("the top source chunk reports visible", topVisible == true)
        }
    }

    // ---- helpers ----

    private val VReaderApp.appContext get() = this.applicationContext as android.content.Context

    private fun stage(tag: String): Pair<VReaderApp, Book> = stageAsset(tag, "sample.txt", "sample.txt")

    private fun stageAsset(tag: String, asset: String, name: String): Pair<VReaderApp, Book> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val staged = File(appContext.cacheDir, "$tag-${System.nanoTime()}-$name")
        instrumentation.context.assets.open(asset).use { input -> staged.outputStream().use { input.copyTo(it) } }
        val book = runBlocking { app.container.importer.importStream("content://test/$name", name, staged.inputStream()) }
        // clean any persisted bilingual config so a re-run starts from the disabled first-enable state.
        runBlocking { runCatching { app.container.perBookBilingualStore.write(book.fingerprintKey, com.vreader.app.bilingual.PerBookBilingualConfig()) } }
        return app to book
    }

    /** Seed the window-0 unit's cache row for sample.txt (3 blank-line paragraphs → 3 segments). */
    private fun seedWindow0(app: VReaderApp, book: Book) {
        val doc = TxtDocument.of(com.vreader.app.reader.TxtDecoder.decode(File(book.localFilePath!!)).text)
        val kind = TranslationUnitId.Kind.txtDocSegmentWindow
        val provider = TxtChapterTextProvider(doc, kind)
        val unit0 = TranslationUnitId(kind, "0")
        val count = provider.sourceSegments(unit0).size
        seedUnit(app, book, unit0, List(count) { "译文${it + 1}" }, count)
    }

    private fun seedUnit(app: VReaderApp, book: Book, unit: TranslationUnitId, segments: List<String>, sourceCount: Int) {
        runBlocking {
            app.container.chapterTranslationStore.upsert(
                CachedTranslation(
                    bookKey = book.fingerprintKey,
                    unitStorageKey = unit.storageKey,
                    targetLanguage = lang,
                    promptVersion = BilingualServices.PROMPT_VERSION_V1,
                    translatedSegments = segments,
                    sourceParagraphCount = sourceCount,
                    createdAt = 1L,
                ),
            )
        }
    }

    /** Wait until the reader body is up — the designed Read-aloud entry slot is present once a TXT/MD
     *  document is Loaded (format-agnostic), so it is a robust "the reader rendered" signal. */
    private fun awaitBody(scenario: ActivityScenario<TxtReaderActivity>) {
        compose.waitUntil(8_000) {
            compose.onAllNodesWithTag("tts-read-aloud-entry").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun awaitVmBuilt(scenario: ActivityScenario<TxtReaderActivity>) {
        for (i in 0 until 80) {
            var built = false
            scenario.onActivity { built = it.bilingualViewModelBuiltForTest() }
            if (built) return
            Thread.sleep(50)
        }
        throw AssertionError("bilingual VM never built")
    }

    private fun <T> onActivityValue(scenario: ActivityScenario<TxtReaderActivity>, block: (TxtReaderActivity) -> T): T {
        var out: T? = null; var set = false
        scenario.onActivity { out = block(it); set = true }
        assertTrue("onActivity ran", set)
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    private fun <T> onActivityBlocking(scenario: ActivityScenario<TxtReaderActivity>, block: suspend (TxtReaderActivity) -> T): T {
        val latch = CountDownLatch(1)
        val result = arrayOfNulls<Any?>(1)
        val error = arrayOfNulls<Throwable>(1)
        scenario.onActivity { activity ->
            activity.lifecycleScope.launch {
                try { result[0] = block(activity) } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(30, TimeUnit.SECONDS)) throw AssertionError("host seam timed out")
        error[0]?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return result[0] as T
    }
}
