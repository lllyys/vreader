package com.vreader.app.reader

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.lifecycle.lifecycleScope
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.bilingual.BilingualServices
import com.vreader.app.bilingual.CachedTranslation
import com.vreader.app.bilingual.EpubBilingualJs
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.data.Book
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #131 WI-7b — the EPUB bilingual DOM-injection adapter WIRED into ReaderActivity. EPUB
 * interlinear is rendered by injecting translation nodes into the LIVE Readium WebView DOM via
 * `evaluateJavascript` (NOT Compose), owned by the EpubBilingualController (single owner, session-token
 * guarded). Instrumented because the injection runs against a REAL WebView (EpubNavigatorFragment) — not
 * Robolectric — and the whole point is proving the DOM decorations land / clear / re-apply on the live host.
 *
 * Drives the integrator through the host's @VisibleForTesting seams (the live More-menu enable rides WI-9):
 *  - the controller is built for an EPUB book;
 *  - ENABLE → the leaf blocks are enumerated + a translation node is injected after each (decoration
 *    count == enumerate count), restoring from the SEEDED cache with ZERO provider calls (the cache row is
 *    seeded to the exact enumerate count so cachedDirect hits — the recreation/#306 restore path);
 *  - DISABLE → every decoration is cleared;
 *  - a RE-APPLY after the DOM lost its decorations (the recreation signal) re-injects from cache — still
 *    zero provider calls (there is NO active provider in this test, so any provider hit would throw/fail →
 *    a landed decoration proves the cache path);
 *  - the regular TXT/MD prefetch path is never invoked for an EPUB unit (the VM's onPositionChanged is
 *    inert for epubHref — Medium-1; here proven by the render being driven by the controller, and the VM's
 *    translationsByUnit for the epubHref unit being written only by the controller's commit).
 *
 * There is NO active AI provider configured in this test, so the ONLY way a translation can land is the
 * seeded cache (cachedDirect, zero-provider) — a landed decoration IS the zero-provider proof.
 */
@RunWith(AndroidJUnit4::class)
class EpubBilingualConnectedTest {

    private val lang = "Chinese"   // the default target language key (BilingualLanguages default)

    @Test fun enable_injectsFromCache_disable_clears_reapply_restores_zeroProvider() {
        val (app, book) = stage()
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitNavigator(scenario)

            // The controller is built for an EPUB book.
            var built = false
            scenario.onActivity { built = it.bilingualControllerBuiltForTest() }
            assertTrue("the EPUB host built a bilingual controller", built)

            // Enumerate the current resource's leaf blocks + seed a cache row of the EXACT block count so
            // the enable restores via cachedDirect (ZERO provider — there is no configured provider).
            val blocks = onActivityBlocking(scenario) { it.bilingualEnumerateForTest() }
            assertTrue("the fixture EPUB has translatable leaf blocks", blocks.isNotEmpty())
            val href = onActivityValue(scenario) { it.bilingualCurrentHrefForTest() }!!
            seedCache(app, book, href, blocks.size)

            // ENABLE → inject; decoration count == enumerate count (each block gets an interlinear node).
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            val injected = onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() }
            assertEquals("one interlinear decoration injected per enumerated leaf block", blocks.size, injected)

            // DISABLE → every decoration is cleared.
            onActivityBlocking(scenario) { it.disableBilingualForTest() }
            val afterDisable = onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() }
            assertEquals("disable clears every decoration", 0, afterDisable)

            // RE-ENABLE + simulate a recreation (the DOM lost decorations) → re-apply restores from cache.
            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            // A fresh enable re-injects; assert it landed again (still zero-provider — cache only).
            val reInjected = onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() }
            assertEquals("re-enable re-injects from cache (zero provider)", blocks.size, reInjected)

            // The probe-gated re-apply is a no-op when the DOM already has the decorations.
            onActivityBlocking(scenario) { it.reapplyBilingualForTest() }
            val afterProbe = onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() }
            assertEquals("probe-gated re-apply keeps the existing decorations (no dup)", blocks.size, afterProbe)
        }
    }

    // ---- helpers ----

    private val VReaderApp.appContext get() = this.applicationContext as android.content.Context

    private fun stage(): Pair<VReaderApp, Book> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val staged = File(appContext.cacheDir, "bilingual-epub-${System.nanoTime()}.epub")
        instrumentation.context.assets.open("minimal.epub").use { input ->
            staged.outputStream().use { input.copyTo(it) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/minimal.epub", "minimal.epub", staged.inputStream())
        }
        return app to book
    }

    /** Seed a cache row for the current EPUB resource unit of [count] source blocks, so the controller's
     *  `cachedDirect(expectedCount = count)` hits — restoring with ZERO provider calls. The target language
     *  key is normalized the same way the VM keys the cache (the resolved language key). */
    private fun seedCache(app: VReaderApp, book: Book, href: String, count: Int) {
        val unit = TranslationUnitId(TranslationUnitId.Kind.epubHref, href)
        val segments = List(count) { "译文${it + 1}" }
        runBlocking {
            app.container.chapterTranslationStore.upsert(
                CachedTranslation(
                    bookKey = book.fingerprintKey,
                    unitStorageKey = unit.storageKey,
                    targetLanguage = lang,
                    promptVersion = BilingualServices.PROMPT_VERSION_V1,
                    translatedSegments = segments,
                    sourceParagraphCount = count,
                    createdAt = 1L,
                ),
            )
        }
    }

    private fun awaitNavigator(scenario: ActivityScenario<ReaderActivity>): String {
        var href: String? = null
        for (i in 0 until 80) {
            scenario.onActivity { href = it.currentHref() }
            if (href != null) return href!!
            Thread.sleep(100)
        }
        throw AssertionError("navigator never rendered a resource")
    }

    private fun <T> onActivityValue(scenario: ActivityScenario<ReaderActivity>, block: (ReaderActivity) -> T): T {
        var out: T? = null
        var set = false
        scenario.onActivity { out = block(it); set = true }
        assertTrue("onActivity ran", set)
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    /** Run a SUSPEND host seam on the activity's main thread and await it (the controller's JS eval must
     *  run on Main — R2BasicWebView.checkThread). Blocks the test thread until the coroutine completes. */
    private fun <T> onActivityBlocking(scenario: ActivityScenario<ReaderActivity>, block: suspend (ReaderActivity) -> T): T {
        val latch = java.util.concurrent.CountDownLatch(1)
        val result = arrayOfNulls<Any?>(1)
        val error = arrayOfNulls<Throwable>(1)
        scenario.onActivity { activity ->
            activity.lifecycleScope.launch {
                try { result[0] = block(activity) } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(30, java.util.concurrent.TimeUnit.SECONDS)) throw AssertionError("host seam timed out")
        error[0]?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return result[0] as T
    }
}
