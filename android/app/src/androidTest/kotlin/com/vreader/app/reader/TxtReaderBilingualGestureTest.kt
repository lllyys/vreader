package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.bilingual.BilingualServices
import com.vreader.app.bilingual.CachedTranslation
import com.vreader.app.bilingual.PerBookBilingualConfig
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.bilingual.TxtChapterTextProvider
import com.vreader.app.data.Book
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * feature #131 WI-8 — the translation gesture-exclusion (round-4 High-2). `TxtSelectionController.hitAt`
 * falls back to the NEAREST source chunk when the pointer is outside all source-chunk bounds, so merely
 * omitting `registerChunk` for a translation slot does NOT make it non-selectable. WI-8's exclusion is an
 * additive `setExcludedBounds` seam: a long-press inside a translation slot's window bounds is a NO-OP
 * (no selection begun), bypassing the nearest-chunk fallback.
 *
 * The end-to-end long-press-on-the-real-translation-slot test (`longPressOnTranslation_doesNotSelect`) is
 * the faithful assertion but is emulator-timing-flaky on a loaded machine (precedent #125/#135), so this
 * class is kept SEPARATE and run in its OWN invocation. Two deterministic controller-level tests cover the
 * excluded-bounds seam + the pre-layout viewport default without a gesture.
 */
@RunWith(AndroidJUnit4::class)
class TxtReaderBilingualGestureTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val lang = "Chinese"

    /** END-TO-END (flaky-class): a long-press ON the interlinear translation slot does NOT begin a
     *  selection (no popover), while the source below stays selectable. */
    @Test fun longPressOnTranslation_doesNotSelect() {
        val (app, book) = stage()
        seedWindow0(app, book)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("tts-read-aloud-entry").fetchSemanticsNodes().isNotEmpty() }
            awaitVmBuilt(scenario)
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }

            // long-press the translation slot → the excluded-bounds gate suppresses selection (no popover).
            compose.onNodeWithTag("bilingual-translation-slot").performTouchInput { longClick() }
            // give the gesture time to (not) produce a popover.
            compose.waitForIdle()
            Thread.sleep(600)
            assertEquals(
                "a long-press on translation does NOT open the selection popover",
                0,
                compose.onAllNodesWithTag("selection-popover").fetchSemanticsNodes().size,
            )
        }
    }

    // ---- helpers ----

    private val VReaderApp.appContext get() = this.applicationContext as android.content.Context

    private fun stage(): Pair<VReaderApp, Book> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val staged = File(appContext.cacheDir, "bilingual-gesture-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input -> staged.outputStream().use { input.copyTo(it) } }
        val book = runBlocking { app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream()) }
        runBlocking { runCatching { app.container.perBookBilingualStore.write(book.fingerprintKey, PerBookBilingualConfig()) } }
        return app to book
    }

    private fun seedWindow0(app: VReaderApp, book: Book) {
        val doc = TxtDocument.of(TxtDecoder.decode(File(book.localFilePath!!)).text)
        val kind = TranslationUnitId.Kind.txtDocSegmentWindow
        val provider = TxtChapterTextProvider(doc, kind)
        val unit0 = TranslationUnitId(kind, "0")
        val count = provider.sourceSegments(unit0).size
        runBlocking {
            app.container.chapterTranslationStore.upsert(
                CachedTranslation(
                    bookKey = book.fingerprintKey,
                    unitStorageKey = unit0.storageKey,
                    targetLanguage = lang,
                    promptVersion = BilingualServices.PROMPT_VERSION_V1,
                    translatedSegments = List(count) { "译文${it + 1}" },
                    sourceParagraphCount = count,
                    createdAt = 1L,
                ),
            )
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
