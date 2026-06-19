package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.File

/**
 * Feature #112 — instrumented proof that .md renders (not literally) AND routes through
 * the real library path, that .txt still renders markdown markers LITERALLY (the Gate-2-r2
 * regression — threading originalFormat into TxtBody must not markdown-render TXT), and
 * that .md resume reuses the legacy charOffset path. The authoritative span/style proof is
 * the JVM MarkdownRendererTest; this test proves the wiring end-to-end on a device.
 */
@RunWith(AndroidJUnit4::class)
class MdReaderRenderTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun importAsset(asset: String, displayName: String): Book {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as VReaderApp
        val staged = File(instrumentation.targetContext.cacheDir, "$asset-${System.nanoTime()}")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        return runBlocking {
            app.container.importer.importStream("content://test/$asset", displayName, staged.inputStream())
        }
    }

    @Test
    fun mdOpensThroughLibraryPath_rendersMarkdown_markersAbsent() {
        // Import BEFORE launching — the library's Room-backed Flow surfaces the row.
        importAsset("sample-note.md", "sample-note.md")

        ActivityScenario.launch(MainActivity::class.java).use {
            // The library row (tappable book title) appears reactively.
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("sample-note", substring = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            // Tap it → routes BookFormat.md → TxtReaderActivity (the md route under test).
            compose.onNodeWithText("sample-note", substring = true).performClick()

            // The heading rendered WITHOUT its '# ' marker; the bold word WITHOUT '**'.
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Heading One", substring = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Heading One", substring = true).assertIsDisplayed()
            compose.onNodeWithText("bold", substring = true).assertIsDisplayed()
            // Raw markdown markers must NOT survive on screen (rendering, not literal).
            assertEquals(
                "no '**' marker rendered for .md",
                0,
                compose.onAllNodesWithText("**", substring = true).fetchSemanticsNodes().size,
            )
            assertEquals(
                "no '# ' heading marker rendered for .md",
                0,
                compose.onAllNodesWithText("# Heading", substring = true).fetchSemanticsNodes().size,
            )
        }
    }

    @Test
    fun txtRendersMarkdownMarkersLiterally() {
        // The regression: a .txt whose content looks like markdown must render verbatim.
        val book = importAsset("literal-markers.txt", "literal-markers.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        ).use {
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("# not heading", substring = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            // Markers are LITERAL for .txt (no markdown rendering).
            compose.onNodeWithText("# not heading **not bold**", substring = true).assertIsDisplayed()
        }
    }

    @Test
    fun mdResumesToSavedCharOffset() {
        val book = importAsset("md-resume.md", "md-resume.md")
        // Seed a saved position at line 080's offset (a legacy md charOffsetUTF16 locator).
        runBlocking {
            val app = InstrumentationRegistry.getInstrumentation().targetContext
                .applicationContext as VReaderApp
            val locator = Locator(
                contentSHA256 = book.contentSHA256, fileByteCount = book.fileByteCount,
                format = "md", charOffsetUTF16 = 2528,
            )
            app.container.repository.savePosition(VReaderLocator.wrapLegacy(locator), 1L)
        }
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        ).use {
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Line 080", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Line 080", substring = true).assertIsDisplayed()
            assertEquals(
                "reopened past the top — line 001 not visible",
                0,
                compose.onAllNodesWithText("Line 001 of", substring = true).fetchSemanticsNodes().size,
            )
        }
    }
}
