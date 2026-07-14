package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.bilingual.PerBookBilingualConfig
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #137 WI-10 — connected proof of the BILINGUAL routing gate in paged mode:
 *   • with bilingual ON, a Paged-layout book renders in SCROLL (the paged body is NOT mounted) — the v1
 *     documented limitation (the #131 interlinear contract has no paged analog; usePaged is gated on
 *     `!bilingualState.enabled`);
 *   • with bilingual OFF, the SAME Paged-layout book mounts the paged body;
 *   • the layout preference is retained across the bilingual toggle (turning bilingual off restores paged).
 *
 * Bilingual is persisted via the per-book config store BEFORE the open (the TxtReaderBilingualConnectedTest
 * precedent), so the reader hydrates enabled without needing an AI provider. createEmptyComposeRule +
 * ActivityScenario + compose.waitUntil polling. One class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedBilingualGateConnectedTest {
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
    }

    @After
    fun restoreScroll() = runBlocking<Unit> {
        app.container.readerSettingsStore.setLayout(ReaderLayout.Scroll)
    }

    private fun setLayoutAndConfirm(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        for (i in 0 until 50) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    /** Import + set the persisted bilingual config (enabled/disabled) BEFORE launching. */
    private fun importAsset(asset: String, bilingualEnabled: Boolean): String {
        val staged = File(instrumentation.targetContext.cacheDir, "pgbi-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        app.container.cacheOffset(book.fingerprintKey, 0)
        runBlocking {
            app.container.perBookBilingualStore.write(
                book.fingerprintKey,
                if (bilingualEnabled) PerBookBilingualConfig(enabled = true, targetLanguage = "Chinese")
                else PerBookBilingualConfig(enabled = false),
            )
        }
        return book.fingerprintKey
    }

    /** True once the reader body has rendered (the read-aloud entry is a format-agnostic "reader up" signal). */
    private fun awaitBody() {
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("tts-read-aloud-entry").fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun bilingualOn_pagedLayout_rendersScroll_notPaged() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt", bilingualEnabled = true)
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitBody()
            // Wait for the persisted bilingual state to hydrate ON.
            compose.waitUntil(10_000) {
                var on = false
                scenario.onActivity { on = it.bilingualStateForTest()?.enabled == true }
                on
            }
            // The scroll body renders (line 001 visible); the PAGED body is NOT mounted despite layout=Paged.
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            var pagedMounted: Boolean? = null
            scenario.onActivity { pagedMounted = it.pagedBodyMountedForTest() }
            assertNotNull(pagedMounted)
            assertTrue("bilingual ON at layout=Paged must render SCROLL (paged body NOT mounted)", pagedMounted == false)
        }
    }

    @Test
    fun bilingualOff_pagedLayout_mountsPagedBody() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt", bilingualEnabled = false)
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitBody()
            // The paged body mounts + phase-1 publishes an index (proof it paginated, not scroll-fell-back).
            compose.waitUntil(15_000) {
                var mounted = false
                scenario.onActivity { mounted = it.pagedBodyMountedForTest() == true }
                mounted
            }
            var pagedMounted: Boolean? = null
            var pageCount = 0
            scenario.onActivity {
                pagedMounted = it.pagedBodyMountedForTest()
                pageCount = it.pagedPageCountForTest() ?: 0
            }
            assertTrue("bilingual OFF at layout=Paged mounts the paged body", pagedMounted == true)
            compose.waitUntil(15_000) {
                var c = 0
                scenario.onActivity { c = it.pagedPageCountForTest() ?: 0 }
                c > 1
            }
            scenario.onActivity { pageCount = it.pagedPageCountForTest() ?: 0 }
            assertTrue("100-line file paginated into > 1 page", pageCount > 1)
        }
    }

    @Test
    fun togglingBilingualOff_restoresPaged_layoutPreferenceRetained() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        // Open with bilingual ON → scroll; then disable bilingual and confirm the paged body mounts (the
        // layout preference was retained and re-applies once bilingual is off).
        val key = importAsset("resume-sample.txt", bilingualEnabled = true)
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitBody()
            compose.waitUntil(10_000) {
                var on = false
                scenario.onActivity { on = it.bilingualStateForTest()?.enabled == true }
                on
            }
            var pagedMounted: Boolean? = null
            scenario.onActivity { pagedMounted = it.pagedBodyMountedForTest() }
            assertEquals("starts SCROLL (bilingual on)", false, pagedMounted)

            // Disable bilingual via the same VM seam the More-menu toggle uses.
            runBlocking { scenario.onActivity { } }
            disableBilingual(scenario)
            // Once bilingual is off, usePaged flips true → the paged body mounts (layout pref retained).
            compose.waitUntil(15_000) {
                var mounted = false
                scenario.onActivity { mounted = it.pagedBodyMountedForTest() == true }
                mounted
            }
            scenario.onActivity { pagedMounted = it.pagedBodyMountedForTest() }
            assertTrue("bilingual OFF → paged re-applies (layout preference retained)", pagedMounted == true)
        }
    }

    /** Disable bilingual on the Activity's scope (the SAME VM path the More-menu toggle drives). */
    private fun disableBilingual(scenario: ActivityScenario<TxtReaderActivity>) {
        val latch = java.util.concurrent.CountDownLatch(1)
        val error = arrayOfNulls<Throwable>(1)
        scenario.onActivity { activity ->
            activity.lifecycleScope.launch {
                try { activity.disableBilingualForTest() } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(30, java.util.concurrent.TimeUnit.SECONDS)) throw AssertionError("disable bilingual timed out")
        error[0]?.let { throw it }
    }
}
