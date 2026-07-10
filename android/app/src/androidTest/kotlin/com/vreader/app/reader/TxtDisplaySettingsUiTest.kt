package com.vreader.app.reader

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #129 WI-4 — connected re-render-on-change proof: a ReaderSettingsStore change while the
 * TXT reader is open re-renders the body with the new style (fontSize / theme ink), and the
 * ReaderBottomChrome Display slot opens the Display sheet from the TXT/MD host.
 */
@RunWith(AndroidJUnit4::class)
class TxtDisplaySettingsUiTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    /** The real on-disk DataStore is shared across test classes — restore the defaults. */
    @After
    fun resetDisplaySettings() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
    }

    private fun importSampleTxt(): String {
        val staged = File(instrumentation.targetContext.cacheDir, "display-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream())
        }
        return book.fingerprintKey
    }

    /** The body Text's applied layout style, re-queried per call (null while recomposing). */
    private fun bodyLayoutResult(): TextLayoutResult? = runCatching {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("quick brown fox", substring = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        results.firstOrNull()
    }.getOrNull()

    @Test
    fun changingFontSizeAndTheme_reRendersTheBody() {
        val key = importSampleTxt()
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            compose.waitUntil(10_000) {
                compose.onAllNodesWithText("quick brown fox", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // the default style applied (18sp, Paper ink)
            compose.waitUntil(10_000) { bodyLayoutResult()?.layoutInput?.style?.fontSize?.value == 18f }
            assertEquals(ReaderTheme.Paper.ink, bodyLayoutResult()!!.layoutInput.style.color)

            // change the store while the reader is open → the body re-renders with the new style
            runBlocking { app.container.readerSettingsStore.setFontSize(26f) }
            compose.waitUntil(10_000) { bodyLayoutResult()?.layoutInput?.style?.fontSize?.value == 26f }

            runBlocking { app.container.readerSettingsStore.setTheme(ReaderTheme.Dark) }
            compose.waitUntil(10_000) { bodyLayoutResult()?.layoutInput?.style?.color == ReaderTheme.Dark.ink }
        }
    }

    @Test
    fun chromeDisplaySlot_opensTheDisplaySheet_andReadAloudSlotPresent() {
        val key = importSampleTxt()
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            compose.waitUntil(10_000) {
                compose.onAllNodesWithText("quick brown fox", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("reader-bottom-chrome").assertIsDisplayed()
            compose.onNodeWithTag("tts-read-aloud-entry").assertIsDisplayed()   // the reconciled TTS entry
            compose.onNodeWithTag("chrome-display").performClick()
            compose.waitUntil(10_000) {
                compose.onAllNodesWithTag("display-sheet-content").fetchSemanticsNodes().isNotEmpty()
            }
        }
    }
}
