package com.vreader.app.reader

import android.util.Log
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File

/**
 * **bug #368** — the AZW3/MOBI/KF8 reader had no Display (Aa) control, so feature #129's reader display
 * settings were unreachable while reading a Kindle book: the CSS was injected live from the store
 * (`Azw3ReaderActivity` → `ReaderSettings.foliateDisplayCss()` → `Azw3Document.setStyles`) but the only
 * way to CHANGE it was to leave the book, open an EPUB or a TXT, adjust there, and come back.
 *
 * ## What this suite proves, through the PRODUCTION path
 *
 * **app launch → `MainActivity` (the manifest LAUNCHER activity) → Library grid → tap the book's tile →
 * `Azw3ReaderActivity` → bottom-chrome "Display" → the designed sheet → tap a theme → the AZW3 body's
 * live stylesheet becomes that theme's.** No `Azw3ReaderActivity.intent(...)`, no `src/debug` launcher,
 * no composable invoked directly. The same posture as `Azw3TocAcceptanceTest`, and the same two stated
 * bounds: `ActivityScenario.launch(MainActivity::class.java)` starts the launcher activity CLASS (that
 * it is the launcher and that `Azw3ReaderActivity` is not exported are static `AndroidManifest.xml`
 * facts), and there is no instrumentable release variant, so this runs on `debug`, which shares
 * `src/main` with release.
 *
 * ## "The control exists" is the weak half; "the change reaches the body" is the point
 *
 * A tap that opens a sheet proves only that a sheet opened. So the closing assertion reads the CSS that
 * is **actually live in the mounted section document** — picked out by the production ownership sentinel
 * [VREADER_CSS_SENTINEL], exactly as `Azw3ProbeSupport.liveVreaderCss` does — and requires it to become,
 * byte for byte, `ReaderSettings(theme = <the tapped theme>).foliateDisplayCss()`. Both arms are pinned
 * expectations rather than re-derivations of whatever the app happened to hold, and
 * [themeChangeIsObservable] asserts the two blobs actually differ, so the wait cannot be satisfied by a
 * reader that ignored the tap.
 *
 * ## The fixture — required, never assumed, never skipped
 *
 * `androidTest/assets/foliate-spike/book.azw3` is gitignored and absent from a fresh worktree. A skip
 * exits 0 exactly like a pass (that is bug **#369**), so a missing or wrong fixture FAILS here. Stage it:
 *
 * ```
 * cp /Users/ll/workspace/vreader/android/app/src/androidTest/assets/foliate-spike/book.azw3 \
 *    <worktree>/android/app/src/androidTest/assets/foliate-spike/
 * ```
 *
 * Run ONE class per connected invocation, and never drive the emulator while it runs (rule 52).
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class Azw3DisplayControlConnectedTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val inst get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = inst.targetContext.applicationContext as VReaderApp

    private companion object {
        const val TAG = "B368-DISPLAY"

        const val FIXTURE_ASSET = "foliate-spike/book.azw3"
        const val DISPLAY_NAME = "Bei Tao Yan De Yong Qi - Zi Wo.azw3"
        /** What the Library tile shows — `BookImporter.titleFromDisplayName` strips the extension. */
        const val BOOK_TITLE = "Bei Tao Yan De Yong Qi - Zi Wo"
        /** Identity by CONTENT DIGEST: a same-sized stand-in passes a byte-count check but not this. */
        const val REAL_BOOK_SHA256 = "39826bfdbcd776ce3a6bc512158f6a5240aefadb188e07b0d86a996489c01c95"
        const val REAL_BOOK_BYTES = 6_288_371L

        /** The theme the sheet tap selects — deliberately NOT the Paper default the run starts from. */
        val TARGET_THEME = ReaderTheme.Dark

        /** A 6 MB import + a WebView + the foliate bundle + first paint on a loaded emulator is slow. */
        const val UI_TIMEOUT_MS = 120_000L
        const val CSS_TIMEOUT_MS = 60_000L
    }

    /** The real on-disk DataStore is shared across test classes AND across the app under test — pin the
     *  defaults BEFORE each test (an interrupted run leaks values) and restore them after. */
    @Before fun pinDefaults() = resetDisplaySettings()

    @After fun tearDown() {
        finishAnyAzw3Reader()
        resetDisplaySettings()
    }

    private fun resetDisplaySettings() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
    }

    // ---- the guard that makes the acceptance assertion able to fail --------------------------------

    /**
     * The two CSS blobs the acceptance test waits on MUST differ, or "the body became the new theme"
     * would be satisfiable by a reader that never received the tap. Pure, and asserted first so a
     * regression in the CSS mapper surfaces as this case rather than as a mysterious timeout.
     */
    @Test fun aThemeChangeIsObservableInTheInjectedCss() {
        assertNotEquals(
            "the default and target themes emit identical foliate CSS — the acceptance wait below " +
                "could not distinguish a working Display control from a dead one",
            ReaderSettings().foliateDisplayCss(),
            ReaderSettings(theme = TARGET_THEME).foliateDisplayCss(),
        )
    }

    // ---- the acceptance pass -----------------------------------------------------------------------

    @Test
    fun productionPath_libraryTapToDisplaySheet_themeChangeReachesTheAzw3Body() {
        val book = importRealBook()
        val expectedBefore = ReaderSettings().foliateDisplayCss()
        val expectedAfter = ReaderSettings(theme = TARGET_THEME).foliateDisplayCss()

        // The fixture is imported once and the store is on-device, so a position from an EARLIER run
        // survives. Clear it, or [awaitBookReady]'s "a relocate round-tripped from the bundle" wait
        // could be satisfied by that stale row — i.e. it would stop being a gate at all.
        runBlocking { app.container.repository.clearPosition(book.fingerprintKey) }

        openThroughLibrary(book) { reader ->
            awaitBookReady(book)

            // The bug, directly: the Display control must be in the AZW3 bottom chrome. `chrome-notes`
            // is the positive control — without it a "Display is present" check could be asserted
            // against a screen where the whole toolbar failed to render.
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("chrome-notes") > 0 }
            assertEquals("the AZW3 bottom chrome did not render", 1, nodeCount("azw3-bottom-chrome"))
            assertTrue(
                "bug #368: the AZW3 reader has no Display (Aa) control, so #129's display settings are " +
                    "unreachable while reading a Kindle book",
                nodeCount("chrome-display") > 0,
            )
            assertTrue("the designed 'Display' label is missing", textExists("Display"))

            // Before the tap the body carries the DEFAULT display CSS — the baseline the change is
            // measured against, read from the live section document rather than assumed.
            awaitLiveVreaderCss(reader, "the default display CSS", expectedBefore, CSS_TIMEOUT_MS)

            // Tap it the way a user does — the same designed sheet EPUB and TXT/MD open.
            compose.onNodeWithTag("chrome-display", useUnmergedTree = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("display-sheet-content") > 0 }

            // Change a setting IN the sheet…
            compose.onNodeWithTag("theme-${TARGET_THEME.name}", useUnmergedTree = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) {
                runBlocking { app.container.readerSettingsStore.current().theme } == TARGET_THEME
            }

            // …and it reaches the AZW3 body: the live stylesheet in the mounted section document IS the
            // production CSS for the tapped theme. This is the claim the bug row's fix has to earn.
            awaitLiveVreaderCss(reader, "the tapped theme's display CSS", expectedAfter, CSS_TIMEOUT_MS)
        }
        Log.i(TAG, "bug #368 acceptance PASSED on the real book through the production path")
    }

    // ---- fixture -----------------------------------------------------------------------------------

    private fun importRealBook(): Book {
        val present = inst.context.assets.list("foliate-spike")?.contains("book.azw3") == true
        assertTrue(
            "this suite is measured on the local-only real AZW3 at androidTest assets `$FIXTURE_ASSET`. " +
                "It is gitignored, so a fresh worktree does NOT have it — stage it before the run: " +
                "cp /Users/ll/workspace/vreader/android/app/src/androidTest/assets/foliate-spike/" +
                "book.azw3 <worktree>/android/app/src/androidTest/assets/foliate-spike/",
            present,
        )
        val staged = File(inst.targetContext.cacheDir, "b368-display.azw3")
        inst.context.assets.open(FIXTURE_ASSET).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$DISPLAY_NAME", DISPLAY_NAME, staged.inputStream())
        }
        assertEquals("the imported artifact is not the real AZW3 (content digest)", REAL_BOOK_SHA256, book.contentSHA256)
        assertEquals("the imported artifact is not the real AZW3 (byte count)", REAL_BOOK_BYTES, book.fileByteCount)
        return book
    }

    // ---- the production entry point ----------------------------------------------------------------

    /** Launch the manifest LAUNCHER activity, find [book] in the Library grid by its visible title, tap
     *  it, and run [block] with the reader that tap opened (identity re-checked on the production
     *  intent extra, after draining any reader an earlier method left on the stack). */
    private fun openThroughLibrary(book: Book, block: (Azw3ReaderActivity) -> Unit) {
        assertTrue("a reader from an earlier test is still on the stack", finishAnyAzw3Reader())
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(BOOK_TITLE, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(BOOK_TITLE, substring = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { resumedAzw3Reader() != null }
            val reader = requireNotNull(resumedAzw3Reader())
            try {
                assertEquals(
                    "the Library tap must have opened THIS book (production intent extra)",
                    book.fingerprintKey,
                    readOnMain { reader.intent.getStringExtra(Azw3ReaderActivity.EXTRA_FINGERPRINT_KEY) },
                )
                block(reader)
            } finally {
                finishAnyAzw3Reader()
            }
        }
    }

    /** Wait until the host is in `Azw3DocState.Loaded` — observed through the page-turn tap zones, which
     *  the host composes ONLY inside that branch — and then until a relocate has round-tripped from the
     *  bundle and been persisted. Existence, never `assertIsDisplayed`: bug #369 is an open pre-existing
     *  failure of that exact displayed-ness assertion, and this suite must not inherit it. */
    private fun awaitBookReady(book: Book) {
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount("azw3-next-zone") > 0 && nodeCount("azw3-prev-zone") > 0 }
        compose.waitUntil(UI_TIMEOUT_MS) {
            runBlocking { app.container.repository.loadPosition(book.fingerprintKey) != null }
        }
        Log.i(TAG, "BOOK READY (Loaded + a persisted relocate) for ${book.fingerprintKey}")
    }

    private fun <T> readOnMain(block: () -> T): T {
        var value: Any? = null
        inst.runOnMainSync { value = block() }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    // ---- compose helpers ---------------------------------------------------------------------------

    private fun nodeCount(tag: String) =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    private fun textExists(text: String) =
        compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
}
