package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.bilingual.BilingualServices
import com.vreader.app.bilingual.CachedTranslation
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.bilingual.TxtChapterTextProvider
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #131 WI-9 — the TXT/MD bilingual ENTRY wiring: the top-chrome pill + the More-menu Bilingual
 * row + the setup → AI-providers routing, all reached through the live chrome (NOT the WI-8
 * @VisibleForTesting VM seams). The More button + its rows are render+click surfaces (NOT long-press), so
 * they are NOT emulator-timing-flaky (precedent #132/#134) — the long-press gesture classes stay isolated
 * in TxtReaderBilingualGestureTest.
 *
 * The AiProviderStore is a process singleton, so each test deletes every profile first to control the
 * configured/unconfigured state deterministically.
 */
@RunWith(AndroidJUnit4::class)
class TxtReaderBilingualEntryTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val lang = "Chinese"

    /** unconfigured (no AI provider) → the More-menu Bilingual row is the DISABLED, informational
     *  "Configure AI provider first" row (the design's non-interactive disabled state — no toggle). */
    @Test fun moreMenu_unconfigured_showsDisabledInformationalRow_noToggle() {
        val (app, book) = stage("bili-entry-unconfig")
        clearProviders(app)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            openMore()
            // The design's unconfigured Bilingual row is rendered with the "Configure AI provider first" sub.
            compose.onNodeWithTag("more-row-bilingual").assertIsDisplayed()
            assertTrue(
                "the unconfigured row shows the Configure-AI sub",
                compose.onAllNodesWithText("Configure AI provider first", substring = true).fetchSemanticsNodes().isNotEmpty(),
            )
            // The unconfigured row is DISABLED (informational) — it carries NO toggle switch (rule 51 — the
            // design's `disabled` row is non-interactive), so the setup sheet does NOT auto-open here.
            assertTrue(
                "the unconfigured (disabled) row has no toggle switch",
                compose.onAllNodesWithTag("more-row-toggle-bilingual").fetchSemanticsNodes().isEmpty(),
            )
        }
    }

    /** configured (an active AI provider with a key) → the More-menu Bilingual row is the TOGGLE; toggling
     *  it ON opens the setup sheet, and the "Turn on bilingual mode" CTA confirms + renders interlinear. */
    @Test fun moreMenu_configured_showsToggle_enable_opensSetup_rendersInterlinear() {
        val (app, book) = stage("bili-entry-config")
        seedProvider(app)
        seedWindow0(app, book)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            openMore()
            compose.onNodeWithTag("more-row-bilingual").assertIsDisplayed()
            // A configured row renders a Toggle switch (the design's on/off control).
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("more-row-toggle-bilingual").fetchSemanticsNodes().isNotEmpty() }
            // Toggle ON → the setup sheet opens (first-enable), confirm with the CTA.
            compose.onNodeWithTag("more-row-toggle-bilingual").performClick()
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-turn-on").performClick()
            // The interlinear renders from the seeded cache (zero provider translate) + the pill appears
            // in the top chrome once bilingual settles ON (the setup ModalBottomSheet has dismissed).
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("bilingual-translation-slot").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-translation-slot").assertIsDisplayed()
            // The pill's own tags are merged under its clickable wrapper — the outer slot tag is findable.
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("chrome-bilingual-pill-slot").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("chrome-bilingual-pill-slot").assertExists()
        }
    }

    /** the pill (shown once bilingual is ON) is mounted in the top chrome AND is clickable — tapping it
     *  re-opens the setup sheet. The pill's own tags are merged under its clickable wrapper, so the outer
     *  slot node carries the click action. */
    @Test fun pill_isMounted_whenEnabled_andClickable() {
        val (app, book) = stage("bili-entry-pill")
        seedProvider(app)
        seedWindow0(app, book)
        // Persist ENABLED so the pill mounts on open (the pill shows whenever bilingual is ON — no need to
        // drive the flaky ModalBottomSheet dismiss). The setup sheet only auto-shows on a fresh first-enable,
        // which persisted-enabled is NOT.
        runBlocking {
            app.container.perBookBilingualStore.write(
                book.fingerprintKey,
                com.vreader.app.bilingual.PerBookBilingualConfig(enabled = true, targetLanguage = lang),
            )
        }
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            // Bilingual is ON from open → the pill mounts in the top chrome (its clickable wrapper is a
            // child of the slot node). Tapping the slot lands on the inner clickable → opens the setup sheet.
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("chrome-bilingual-pill-slot").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("chrome-bilingual-pill-slot").assertExists()
            compose.onNodeWithTag("chrome-bilingual-pill-slot").performClick()
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-setup-sheet").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("bilingual-setup-sheet").assertIsDisplayed()
        }
    }

    /** the setup sheet's engine strip "Change…"/"Set up" CTA opens the Variant A AI Providers sheet. */
    @Test fun setupSheet_engineCta_opensAiProvidersSheet() {
        val (app, book) = stage("bili-entry-cta")
        seedProvider(app)
        seedWindow0(app, book)
        // Persist ENABLED so the pill mounts + opens the setup sheet reliably (avoids the ModalBottomSheet
        // first-enable auto-show timing).
        runBlocking {
            app.container.perBookBilingualStore.write(
                book.fingerprintKey,
                com.vreader.app.bilingual.PerBookBilingualConfig(enabled = true, targetLanguage = lang),
            )
        }
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitBody(scenario)
            compose.waitUntil(8_000) { compose.onAllNodesWithTag("chrome-bilingual-pill-slot").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("chrome-bilingual-pill-slot").performClick()
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("bilingual-engine-strip").fetchSemanticsNodes().isNotEmpty() }
            // Tapping the engine strip's CTA ("Change…" when configured) opens the Variant A AI Providers sheet.
            compose.onNodeWithTag("engine-cta").performClick()
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("reader-ai-providers-list").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("reader-ai-providers-list").assertIsDisplayed()
        }
    }

    // ---- helpers ----

    private val VReaderApp.appContext get() = this.applicationContext as android.content.Context

    private fun openMore() {
        compose.waitUntil(8_000) { compose.onAllNodesWithTag("chrome-more").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("chrome-more").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("more-popup").fetchSemanticsNodes().isNotEmpty() }
    }

    private fun stage(tag: String): Pair<VReaderApp, Book> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val staged = File(appContext.cacheDir, "$tag-${System.nanoTime()}-sample.txt")
        instrumentation.context.assets.open("sample.txt").use { input -> staged.outputStream().use { input.copyTo(it) } }
        val book = runBlocking { app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream()) }
        runBlocking { runCatching { app.container.perBookBilingualStore.write(book.fingerprintKey, com.vreader.app.bilingual.PerBookBilingualConfig()) } }
        return app to book
    }

    /** Remove every AI provider so aiConfigured resolves false (the DISABLED-row state). */
    private fun clearProviders(app: VReaderApp) = runBlocking {
        app.container.aiProviderStore.list().forEach { app.container.aiProviderStore.delete(it.id) }
    }

    /** Seed ONE active provider with a non-empty key so BilingualAiReadiness.resolve == true. */
    private fun seedProvider(app: VReaderApp) = runBlocking {
        app.container.aiProviderStore.list().forEach { app.container.aiProviderStore.delete(it.id) }
        val p = app.container.aiProviderStore.upsert(
            id = "test-provider", name = "Test", kind = AiProviderKind.anthropicNative,
            baseUrl = "", model = "claude-3", temperature = 0.7, maxTokens = 2048, apiKey = "sk-test",
        )
        app.container.aiProviderStore.setActive(p.id)
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

    private fun awaitBody(scenario: ActivityScenario<TxtReaderActivity>) {
        compose.waitUntil(8_000) { compose.onAllNodesWithTag("tts-read-aloud-entry").fetchSemanticsNodes().isNotEmpty() }
    }
}
