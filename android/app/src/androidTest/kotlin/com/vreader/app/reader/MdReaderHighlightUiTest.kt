package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.AnnotationAnchor
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import java.io.File

/**
 * Feature #125 WI-4 (final) — acceptance: highlighting a STYLED Markdown line end-to-end through the
 * real reader. `sample-note.md` line "This is **bold** and *italic* and `code` text." renders (markers
 * stripped) to "This is bold and italic and code text.", so a long-press maps RENDERED offsets to the
 * SOURCE coords the highlight persists in (the whole point of #125). Verifies: render (markers gone) →
 * long-press → popover → tap color → persist (md locator) → seeded-wash render → tap → remove.
 */
@RunWith(AndroidJUnit4::class)
class MdReaderHighlightUiTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val mdContent = "# Heading One\n\nThis is **bold** and *italic* and `code` text.\n\n- first bullet\n- second bullet\n"

    private fun importMd(tag: String): Book {
        val inst = InstrumentationRegistry.getInstrumentation()
        val app = inst.targetContext.applicationContext as VReaderApp
        val staged = File(inst.targetContext.cacheDir, "note-$tag-${System.nanoTime()}.md")
        inst.context.assets.open("sample-note.md").use { i -> staged.outputStream().use { o -> i.copyTo(o) } }
        return runBlocking { app.container.importer.importStream("content://test/sample-note.md", "sample-note.md", staged.inputStream()) }
    }

    private fun app() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
    private fun ctx() = InstrumentationRegistry.getInstrumentation().targetContext

    /** The whole styled line's SOURCE range (chunk start..end-newline), for seeding a tappable highlight.
     *  Computed from the IMPORTED asset content (not the hardcoded string) so a fixture edit can't seed
     *  the wrong range; the drift check fails loudly if `sample-note.md` and `mdContent` diverge. */
    private fun styledLineSourceRange(): Pair<Int, Int> {
        val content = InstrumentationRegistry.getInstrumentation().context.assets
            .open("sample-note.md").use { it.readBytes().decodeToString() }
        check(content == mdContent) { "sample-note.md drifted from the test's mdContent — update mdContent" }
        val doc = TxtDocument.of(content)
        val ci = (0 until doc.chunkCount).first { doc.textForChunk(it).contains("bold") }
        val base = doc.offsetForChunk(ci)
        val len = doc.textForChunk(ci).length
        return base to (base + len - 1) // exclude the trailing '\n'
    }

    @Test
    fun mdRenders_markersStripped_andLongPressCreatesMdHighlight() {
        val book = importMd("create")
        val key = book.fingerprintKey
        // clean any prior highlights for this book (shared on-disk Room across methods).
        runBlocking { app().container.annotationsRepository.highlightsForBook(key).forEach { app().container.annotationsRepository.removeHighlight(it.id) } }

        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(ctx(), key)).use {
            // RENDERED text has the markers stripped (proves TxtBody rendered MD via the mapper).
            compose.waitUntil(12_000) {
                compose.onAllNodesWithText("This is bold and italic", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("This is bold and italic", substring = true).assertIsDisplayed()
            // raw markdown must NOT be on screen
            assertEquals("markdown markers must be stripped in the rendered text", 0,
                compose.onAllNodesWithText("**bold**", substring = true).fetchSemanticsNodes().size)

            // long-press the styled line → selection popover.
            compose.onNodeWithText("This is bold and italic", substring = true).performTouchInput { longClick() }
            compose.waitUntil(5_000) { compose.onAllNodesWithTag("popover-color-yellow").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("popover-color-yellow").performClick()

            // the highlight persists with the md locator format (Gate-2 Critical: NOT hardcoded "txt").
            var hl = emptyList<com.vreader.app.annotations.HighlightRecord>()
            repeat(50) {
                hl = runBlocking { app().container.annotationsRepository.highlightsForBook(key) }
                if (hl.isNotEmpty()) return@repeat
                Thread.sleep(150)
            }
            assertTrue("a highlight was created from the MD selection", hl.isNotEmpty())
            assertEquals("the MD highlight locator format is 'md', not 'txt'", "md", hl.first().locator.format)
        }
    }

    @Test
    fun mdSeededHighlight_rendersWashThroughMapper_noCrash() {
        val book = importMd("wash")
        val key = book.fingerprintKey
        val (s, e) = styledLineSourceRange()
        runBlocking {
            app().container.annotationsRepository.highlightsForBook(key).forEach { app().container.annotationsRepository.removeHighlight(it.id) }
            val loc = Locator(book.contentSHA256, book.fileByteCount, "md", charRangeStartUTF16 = s, charRangeEndUTF16 = e, textQuote = "styled")
            app().container.annotationsRepository.addHighlight(key, AnnotationColor.yellow, "styled", loc, AnnotationAnchor.Text("text-document:$key", s, e))
        }
        // PROVE the seeded MD highlight produces a NON-EMPTY rendered wash span (else this test would
        // pass even if washes were disabled — Gate-4 Medium). The activity's drawBehind then paints it.
        val hls = runBlocking { app().container.annotationsRepository.highlightsForBook(key) }
        val washes = TxtWashMapper.washesByChunk(TxtDocument.of(mdContent), hls, MarkdownChunkTextMapper(TxtDocument.of(mdContent)))
        assertTrue("the seeded MD highlight projects to a non-empty rendered wash span", washes.values.any { it.isNotEmpty() })

        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(ctx(), key)).use {
            // render completes WITH the md highlight present → the source→rendered wash projection +
            // getPathForRange drawBehind path executed for the MD chunk without crashing.
            compose.waitUntil(12_000) { compose.onAllNodesWithText("This is bold and italic", substring = true).fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("This is bold and italic", substring = true).assertIsDisplayed()
        }
    }

    @Test
    fun mdTapExistingHighlight_opensEdit_andRemoveDeletes() {
        val book = importMd("edit")
        val key = book.fingerprintKey
        val (s, e) = styledLineSourceRange()
        runBlocking {
            app().container.annotationsRepository.highlightsForBook(key).forEach { app().container.annotationsRepository.removeHighlight(it.id) }
            val loc = Locator(book.contentSHA256, book.fileByteCount, "md", charRangeStartUTF16 = s, charRangeEndUTF16 = e, textQuote = "styled")
            app().container.annotationsRepository.addHighlight(key, AnnotationColor.yellow, "styled", loc, AnnotationAnchor.Text("text-document:$key", s, e))
        }
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(ctx(), key)).use {
            compose.waitUntil(12_000) { compose.onAllNodesWithText("This is bold and italic", substring = true).fetchSemanticsNodes().isNotEmpty() }
            // tap the left part of the styled (highlighted) rendered line → its rendered offset maps to a
            // SOURCE offset inside the seeded range → EDIT popover with Remove.
            compose.onNodeWithText("This is bold and italic", substring = true).performTouchInput { click(percentOffset(0.15f, 0.5f)) }
            compose.waitUntil(5_000) { compose.onAllNodesWithText("Remove").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("Remove").performClick()
            var count = 1
            repeat(50) {
                count = runBlocking { app().container.annotationsRepository.highlightsForBook(key).size }
                if (count == 0) return@repeat
                Thread.sleep(150)
            }
            assertEquals("tap-to-edit → Remove deleted the MD highlight", 0, count)
        }
    }
}
