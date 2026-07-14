package com.vreader.app.reader

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #137 WI-3 — the layout toggle exposes Readium's native pagination on the EPUB reader.
 * Instrumented because EpubNavigatorFragment resolves its overflow (scroll↔paginated) against a real
 * WebView (not Robolectric). Drives the REAL navigator through the LIVE ReaderSettingsStore:
 *
 *  - layout == Paged (fresh open) → the navigator resolves paginated overflow, and a horizontal page
 *    turn (`goForward`) advances the position: `currentLocator` (the save/progress feed) advances on the
 *    turn — the Gate-2 High-4 requirement (#281/#258 progress-from-page-turn);
 *  - a seeded highlight's decoration survives across the reflow;
 *  - the LIVE Display-sheet Layout toggle flips overflow both ways (Paged→Scroll→Paged), proving BOTH
 *    the open-time `initialPrefs` flip AND the live `submitPreferences` flip are layout-driven.
 *
 * Uses a bundled multi-page/multi-resource EPUB (androidTest can't read the gitignored test-books/; the
 * one-line minimal.epub fits a single page, so it can't exercise a real page turn) — the synthetic-fixture
 * exception (a deterministic multi-page structure a real book can't give cheaply in CI).
 */
@RunWith(AndroidJUnit4::class)
class EpubPagedToggleConnectedTest {

    @Test
    fun pagedLayout_paginatesEpub_pageTurnAdvancesCurrentLocator_andToggleFlipsBothWays() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val store = app.container.readerSettingsStore

        val original: ReaderSettings = runBlocking { store.current() }
        try {
            // Open FRESH in Paged so the open-time initialPrefs flip is exercised AND Readium computes the
            // paginated columns from the start (a mid-read scroll→paged reflow does not always relayout).
            runBlocking { store.setLayout(ReaderLayout.Paged) }
            val book = stageBook(appContext, instrumentation.context, app)
            // BookImporter preserves a saved position on a duplicate import of the same fixture bytes, and
            // ReaderActivity restores it on open — so clear it, guaranteeing a deterministic start-of-book
            // open (the page-turn assertion needs a page AFTER the current one to advance into).
            runBlocking { app.container.repository.clearPosition(book.fingerprintKey) }

            ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(appContext, book.fingerprintKey)).use { scenario ->
                // The open-time initialPrefs carried scroll = (layout == Scroll) == false → paginated.
                assertNotNull(
                    "the open-time initialPrefs resolved paginated overflow for layout == Paged",
                    pollForActivity(scenario) { it.appliedScroll() == false },
                )
                assertEquals(
                    "layout == Paged → the navigator is paginated (scroll == false)",
                    false,
                    onActivity(scenario) { it.appliedScroll() },
                )

                // Seed a highlight at the rendered href → it applies as a Readium decoration.
                val href = onActivity(scenario) { it.currentHref() }
                assertNotNull("navigator rendered a reading href", href)
                seedHighlight(app, book, href!!)
                assertNotNull(
                    "the seeded highlight applied as a decoration on the live navigator",
                    pollForActivity(scenario) { it.appliedHighlightCount() >= 1 },
                )

                // --- a horizontal page turn advances the position via currentLocator (Gate-2 High-4) ---
                assertNotNull(
                    "a reading position (currentLocator) exists before the page turn",
                    pollForActivity(scenario) { it.currentPositionKeyForTest() != null },
                )
                val before = onActivity(scenario) { it.currentPositionKeyForTest() }
                assertNotNull("a reading position key exists before the page turn", before)
                // Drive a horizontal page turn FIRST, then poll for the change on LATER iterations (past the
                // 200ms settle) — never read the locator in the same tick as the goForward, which would race
                // the async WebView emission; and never accept a change that predates ANY turn (a spurious
                // async settle before we turned). `turnedAtLeastOnce` gates success on a real turn having
                // happened. Crossing a page (progression) OR a chapter (href) is an advance of currentLocator.
                var turnedAtLeastOnce = false
                val advanced = pollForActivity(scenario) { activity ->
                    val now = activity.currentPositionKeyForTest()
                    if (turnedAtLeastOnce && now != null && now != before) return@pollForActivity true
                    activity.goForwardForTest()
                    turnedAtLeastOnce = true
                    false
                }
                val after = onActivity(scenario) { it.currentPositionKeyForTest() }
                assertNotNull(
                    "a horizontal page turn advanced the position/progress via currentLocator (before=$before after=$after)",
                    advanced,
                )
                assertTrue(
                    "currentLocator advanced (position key changed) on the page turn (before=$before after=$after)",
                    after != null && after != before,
                )

                // --- the seeded highlight's decoration survives across the reflow / page turns ---
                assertTrue(
                    "the decoration survived the paginated reflow + page turns",
                    onActivity(scenario) { it.appliedHighlightCount() } >= 1,
                )

                // --- the LIVE Layout toggle flips overflow both ways (proves the live submitPreferences flip) ---
                runBlocking { store.setLayout(ReaderLayout.Scroll) }
                assertNotNull(
                    "a live layout change to Scroll resolved scroll overflow on the navigator",
                    pollForActivity(scenario) { it.appliedScroll() == true },
                )
                runBlocking { store.setLayout(ReaderLayout.Paged) }
                assertNotNull(
                    "a live layout change back to Paged resolved paginated overflow again",
                    pollForActivity(scenario) { it.appliedScroll() == false },
                )
            }
        } finally {
            // Restore the exact pre-test global settings (layout included) so this test leaves no residue.
            runBlocking {
                store.setTheme(original.theme)
                store.setFontFamily(original.fontFamily)
                store.setFontSize(original.fontSizeSp)
                store.setLineSpacing(original.lineSpacing)
                store.setMargin(original.marginDp)
                store.setLayout(original.layout)
            }
        }
    }

    /** Read a value off the activity on its own thread (blocks until the callback ran). */
    private fun <T> onActivity(scenario: ActivityScenario<ReaderActivity>, read: (ReaderActivity) -> T): T {
        var out: T? = null
        scenario.onActivity { out = read(it) }
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    /** Poll the activity until [predicate] holds (max ~15s). Returns Unit on success or null on timeout. */
    private fun pollForActivity(
        scenario: ActivityScenario<ReaderActivity>,
        predicate: (ReaderActivity) -> Boolean,
    ): Unit? {
        repeat(75) {
            var ok = false
            scenario.onActivity { ok = predicate(it) }
            if (ok) return Unit
            Thread.sleep(200)
        }
        return null
    }

    private fun seedHighlight(app: VReaderApp, book: Book, href: String) = runBlocking {
        val sel = org.readium.r2.shared.publication.Locator(
            href = org.readium.r2.shared.util.Url(href)!!,
            mediaType = org.readium.r2.shared.util.mediatype.MediaType.XHTML,
            locations = org.readium.r2.shared.publication.Locator.Locations(progression = 0.01),
            text = org.readium.r2.shared.publication.Locator.Text(highlight = "Ishmael"),
        )
        val inputs = com.vreader.app.annotations.EpubAnnotationMapper.selectionToInputs(sel, book)!!
        app.container.annotationsRepository.addHighlight(
            book.fingerprintKey, com.vreader.app.annotations.AnnotationColor.yellow,
            inputs.selectedText, inputs.locator, inputs.anchor,
        )
    }

    private fun stageBook(appContext: android.content.Context, testContext: android.content.Context, app: VReaderApp): Book =
        runBlocking {
            val staged = File(appContext.cacheDir, "paged-toggle-test-${System.nanoTime()}.epub")
            testContext.assets.open("paged-multipage.epub").use { input ->
                staged.outputStream().use { input.copyTo(it) }
            }
            app.container.importer.importStream("content://test/paged-multipage.epub", "paged-multipage.epub", staged.inputStream())
        }
}
