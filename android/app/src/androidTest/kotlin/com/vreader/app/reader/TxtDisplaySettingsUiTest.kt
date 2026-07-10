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
import com.vreader.app.ui.theme.VReaderFonts
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #129 WI-4 — connected re-render-on-change proof: a ReaderSettingsStore change while the
 * TXT/MD reader is open re-renders the body with the new style (every setting: size / spacing /
 * family / theme ink / margin), the MD host inherits the size base (em headings pinned at the JVM
 * tier), and the ReaderBottomChrome Display slot opens the Display sheet from the TXT/MD host.
 */
@RunWith(AndroidJUnit4::class)
class TxtDisplaySettingsUiTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    /** The real on-disk DataStore is shared across test classes — pin the defaults BEFORE each test
     *  (a prior interrupted run could have leaked values) and restore them after. */
    @Before
    fun pinDefaults() = resetDisplaySettings()

    @After
    fun resetDisplaySettings() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
    }

    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "display-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        return book.fingerprintKey
    }

    /** The body Text's applied layout style at [anchor], re-queried per call (null while recomposing). */
    private fun bodyLayoutResult(anchor: String): TextLayoutResult? = runCatching {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(anchor, substring = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        results.firstOrNull()
    }.getOrNull()

    @Test
    fun changingEverySetting_reRendersTheTxtBody() {
        val key = importAsset("sample.txt")
        val anchor = "quick brown fox"
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            compose.waitUntil(10_000) {
                compose.onAllNodesWithText(anchor, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // the default style applied (18sp / 27sp = 18×1.5 / Paper ink / serif)
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.fontSize?.value == 18f }
            val defaultStyle = bodyLayoutResult(anchor)!!.layoutInput.style
            assertEquals(27f, defaultStyle.lineHeight.value, 1e-4f)
            assertEquals(ReaderTheme.Paper.ink, defaultStyle.color)
            assertEquals(VReaderFonts.Serif, defaultStyle.fontFamily)

            // change EACH setting while the reader is open → the body re-renders with the new style
            runBlocking { app.container.readerSettingsStore.setFontSize(26f) }
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.fontSize?.value == 26f }

            runBlocking { app.container.readerSettingsStore.setLineSpacing(2.0f) }
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.lineHeight?.value == 52f }   // 26 × 2.0

            runBlocking { app.container.readerSettingsStore.setFontFamily(ReaderFontFamily.Sans) }
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.fontFamily == VReaderFonts.Sans }

            runBlocking { app.container.readerSettingsStore.setTheme(ReaderTheme.Dark) }
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.color == ReaderTheme.Dark.ink }

            // margin: widening it pushes the body text right (the LazyColumn contentPadding).
            val leftAt20 = compose.onNodeWithText(anchor, substring = true).fetchSemanticsNode().positionInRoot.x
            runBlocking { app.container.readerSettingsStore.setMargin(48f) }
            compose.waitUntil(10_000) {
                runCatching {
                    compose.onNodeWithText(anchor, substring = true).fetchSemanticsNode().positionInRoot.x
                }.getOrDefault(leftAt20) > leftAt20 + 1f
            }
        }
    }

    @Test
    fun mdBody_inheritsTheFontSizeSetting() {
        val key = importAsset("sample-note.md")
        val anchor = "This is bold and italic"   // rendered (markers stripped) — proves the MD path
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            compose.waitUntil(10_000) {
                compose.onAllNodesWithText(anchor, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.fontSize?.value == 18f }
            // change the base size → the MD body re-renders at the new base; headings scale with it
            // via the em-relative spans (ratios pinned by the JVM TxtDisplaySettingsTest).
            runBlocking { app.container.readerSettingsStore.setFontSize(24f) }
            compose.waitUntil(10_000) { bodyLayoutResult(anchor)?.layoutInput?.style?.fontSize?.value == 24f }
        }
    }

    @Test
    fun chromeDisplaySlot_opensTheDisplaySheet_andReadAloudSlotPresent() {
        val key = importAsset("sample.txt")
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
