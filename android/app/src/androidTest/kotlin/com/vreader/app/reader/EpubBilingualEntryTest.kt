package com.vreader.app.reader

import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.bilingual.BilingualServices
import com.vreader.app.bilingual.CachedTranslation
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.data.Book
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * feature #131 WI-9 — the EPUB bilingual ENTRY finalize: (a) `onEpubBlocksEnumerated` now feeds the VM's
 * `translationsByUnit` for the EPUB unit (the controller is the single writer), and (b) a mid-book
 * language change reconciles the CURRENT resource's DOM via the controller's reconcile entry (not just
 * future resources). Drives the VM/controller through the host @VisibleForTesting seams (the live
 * More-menu enable rides the acceptance pass); the whole point is proving the DOM + VM state against the
 * REAL WebView (EpubNavigatorFragment).
 *
 * There is NO active AI provider in this test, so a landed decoration / a populated translationsByUnit is
 * the ZERO-PROVIDER proof (the seeded cache is the only translation source).
 */
@RunWith(AndroidJUnit4::class)
class EpubBilingualEntryTest {

    private val lang = "Chinese"
    private val altLang = "Japanese"

    /** finding (a): enabling on an EPUB injects the DOM AND the VM's translationsByUnit reflects the EPUB
     *  unit (the controller's onEpubBlocksEnumerated wiring — the pill/state UI stays honest for EPUB). */
    @Test fun enable_populatesVmTranslationsByUnit_forEpubUnit() {
        val (app, book) = stage()
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitNavigator(scenario)
            val blocks = onActivityBlocking(scenario) { it.bilingualEnumerateForTest() }
            assertTrue("the fixture EPUB has translatable leaf blocks", blocks.isNotEmpty())
            val href = onActivityValue(scenario) { it.bilingualCurrentHrefForTest() }!!
            seedCache(app, book, href, lang, blocks.size)

            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            val injected = onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() }
            assertEquals("one interlinear decoration per enumerated block", blocks.size, injected)

            // finding (a): the VM's translationsByUnit now carries the epubHref unit (the controller wrote it).
            val unit = TranslationUnitId(TranslationUnitId.Kind.epubHref, href)
            var present = false
            for (i in 0 until 60) {
                scenario.onActivity { present = it.bilingualVmTranslationsContainsForTest(unit) }
                if (present) break
                Thread.sleep(50)
            }
            assertTrue("the VM translationsByUnit reflects the EPUB unit (finding a)", present)
        }
    }

    /** finding (b): a mid-book language change re-injects the CURRENT resource from the new-language cache
     *  (the controller's reconcile entry) — the visible DOM reconciles, not just future resources. */
    @Test fun midBookLanguageChange_reconcilesCurrentResource() {
        val (app, book) = stage()
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitNavigator(scenario)
            val blocks = onActivityBlocking(scenario) { it.bilingualEnumerateForTest() }
            val href = onActivityValue(scenario) { it.bilingualCurrentHrefForTest() }!!
            // Seed BOTH language caches so the reconcile can restore the new language with zero provider.
            seedCache(app, book, href, lang, blocks.size)
            seedCache(app, book, href, altLang, blocks.size)

            onActivityBlocking(scenario) { it.enableBilingualForTest(languageKey = lang) }
            assertEquals("initial-language decorations injected", blocks.size, onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() })

            // Change language mid-book (stationary) → the reconcile re-enumerates + re-injects the CURRENT
            // resource for the new language (a bump clears the old, the new-language cache restores it).
            onActivityBlocking(scenario) { it.reconcileBilingualLanguageForTest(altLang) }
            val after = onActivityBlocking(scenario) { it.bilingualDecorationCountForTest() }
            assertEquals("the current resource reconciled to the new language (finding b)", blocks.size, after)
            // The VM now reflects the new-language unit translation as well.
            val unit = TranslationUnitId(TranslationUnitId.Kind.epubHref, href)
            var present = false
            for (i in 0 until 60) {
                scenario.onActivity { present = it.bilingualVmTranslationsContainsForTest(unit) }
                if (present) break
                Thread.sleep(50)
            }
            assertTrue("the VM reflects the reconciled EPUB unit", present)
        }
    }

    // ---- helpers ----

    private val VReaderApp.appContext get() = this.applicationContext as android.content.Context

    private fun stage(): Pair<VReaderApp, Book> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val staged = File(appContext.cacheDir, "bili-epub-entry-${System.nanoTime()}.epub")
        instrumentation.context.assets.open("minimal.epub").use { input -> staged.outputStream().use { input.copyTo(it) } }
        val book = runBlocking { app.container.importer.importStream("content://test/minimal.epub", "minimal.epub", staged.inputStream()) }
        runBlocking { runCatching { app.container.perBookBilingualStore.write(book.fingerprintKey, com.vreader.app.bilingual.PerBookBilingualConfig()) } }
        return app to book
    }

    private fun seedCache(app: VReaderApp, book: Book, href: String, language: String, count: Int) {
        val unit = TranslationUnitId(TranslationUnitId.Kind.epubHref, href)
        runBlocking {
            app.container.chapterTranslationStore.upsert(
                CachedTranslation(
                    bookKey = book.fingerprintKey,
                    unitStorageKey = unit.storageKey,
                    targetLanguage = language,
                    promptVersion = BilingualServices.PROMPT_VERSION_V1,
                    translatedSegments = List(count) { "译文${it + 1}" },
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
        var out: T? = null; var set = false
        scenario.onActivity { out = block(it); set = true }
        assertTrue("onActivity ran", set)
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    private fun <T> onActivityBlocking(scenario: ActivityScenario<ReaderActivity>, block: suspend (ReaderActivity) -> T): T {
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
