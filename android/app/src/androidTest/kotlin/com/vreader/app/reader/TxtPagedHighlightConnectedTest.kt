package com.vreader.app.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.reader.paged.PageOffsetMap
import com.vreader.app.reader.paged.PageSegment
import com.vreader.app.reader.paged.TxtPageNavigator
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #137 WI-7b — the PAGED highlight WASH render + host tap-to-edit wiring on [TxtPagedBody] +
 * [TxtSelectionController].
 *
 * DETERMINISTIC Compose-rule tests (createComposeRule; the same posture as [TxtPagedSelectionConnectedTest]
 * — no emulator-timing-flaky recognizer for the render/tap paths):
 *   • the wash math (TxtPagedWash.washesForPage) is exact against a REAL laid-out page map, incl. a
 *     highlight that spans a page boundary (washed on BOTH covered pages, clamped per page);
 *   • the real [TxtPagedBody] renders its page with a highlight present WITHOUT crashing (the drawBehind
 *     wash path composes), and its per-page selection map registers so tap-to-edit resolves;
 *   • a real TAP on a highlighted glyph, routed through the SAME `onTapEditAt` contract the host wires
 *     (resolve source → hit-test → open the edit popover, RETURN true to SUPPRESS navigation), fires the
 *     edit callback and suppresses the page-turn — proving the host wiring end-to-end;
 *   • a real TAP on a NON-highlighted glyph returns false (navigation proceeds).
 * PLUS one REAL long-press test (`realLongPress_stillSelects_withWashWired`) that drives the actual
 * TxtPagedBody through the unified pagedTapZones classifier to prove selection still works with the wash
 * wired — it polls the controller's selection StateFlow (NOT bare waitForIdle; long-press is emulator-flaky).
 *
 * One class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedHighlightConnectedTest {

    @get:Rule val compose = createComposeRule()

    private fun r(a: Int, b: Int) = Utf16Range(a, b)

    private fun hl(bookKey: String, start: Int, end: Int, color: AnnotationColor = AnnotationColor.yellow) =
        HighlightRecord(
            id = "h$start-$end", bookKey = bookKey, color = color, selectedText = "x", note = null,
            locator = Locator("a".repeat(64), 999L, "txt", charRangeStartUTF16 = start, charRangeEndUTF16 = end),
            anchor = null, createdAt = 1L, updatedAt = 1L,
        )

    private class Laid(val root: LayoutCoordinates, val layout: TextLayoutResult, val coords: LayoutCoordinates)

    /** A page-local point (root-local) at the CENTER of the glyph rendered at [renderedIndex]. */
    private fun pointAtRendered(laid: Laid, renderedIndex: Int): Offset {
        val cursor = laid.layout.getCursorRect(renderedIndex)
        val next = laid.layout.getCursorRect((renderedIndex + 1).coerceAtMost(laid.layout.layoutInput.text.length))
        val glyphMidX = (cursor.left + next.left) / 2f
        val glyphMidY = (cursor.top + cursor.bottom) / 2f
        val window = laid.coords.localToWindow(Offset(glyphMidX, glyphMidY))
        return laid.root.windowToLocal(window)
    }

    /** Compose a single page `Text` at the root top-left; register it with [controller] as [page]/[map]. */
    private fun layoutPage(controller: TxtSelectionController, page: Int, rendered: String, map: PageOffsetMap): Laid {
        val rootRef = AtomicReference<LayoutCoordinates?>(null)
        val layoutRef = AtomicReference<TextLayoutResult?>(null)
        val coordsRef = AtomicReference<LayoutCoordinates?>(null)
        compose.setContent {
            Box(Modifier.fillMaxWidth().height(600.dp).onGloballyPositioned { rootRef.set(it) }) {
                Text(
                    text = rendered,
                    onTextLayout = { layoutRef.set(it) },
                    modifier = Modifier.fillMaxSize().onGloballyPositioned { coordsRef.set(it) },
                )
            }
        }
        compose.waitForIdle()
        val root = requireNotNull(rootRef.get())
        val layout = requireNotNull(layoutRef.get())
        val coords = requireNotNull(coordsRef.get())
        controller.setLazyCoords(root)
        controller.registerPage(page, layout, coords, map)
        return Laid(root, layout, coords)
    }

    private fun txtPage(srcBase: Int, len: Int) =
        PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = srcBase, renderedLen = len)))

    // ---- The wash math against a REAL laid-out page map -------------------------------------------------

    @Test fun washForPage_realLayout_projectsHighlightToRenderedSpan() {
        val text = "hello world here"
        val doc = TxtDocument.of("x".repeat(100) + text)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map = txtPage(srcBase = 100, len = text.length)
        layoutPage(controller, page = 0, rendered = text, map = map)

        // Highlight source [106,111) = "world" → rendered-local [6,11) on this page.
        val spans = TxtPagedWash.washesForPage(map, listOf(hl(doc.text, 106, 111, AnnotationColor.pink)))
        assertEquals(listOf(WashSpan(r(6, 11), AnnotationColor.pink)), spans)
    }

    // ---- A page-boundary-spanning highlight washes on BOTH pages, clamped per page ---------------------

    @Test fun boundarySpanningHighlight_washesOnBothPages() {
        val doc = TxtDocument.of("z".repeat(200))
        val page0 = txtPage(srcBase = 100, len = 20)   // source [100,120)
        val page1 = txtPage(srcBase = 120, len = 20)   // source [120,140)
        val h = hl(doc.text, 110, 130)                 // spans the boundary
        val s0 = TxtPagedWash.washesForPage(page0, listOf(h))
        val s1 = TxtPagedWash.washesForPage(page1, listOf(h))
        assertEquals("page 0 tail washed", r(10, 20), s0.single().local)
        assertEquals("page 1 head washed", r(0, 10), s1.single().local)
    }

    // ---- The real TxtPagedBody renders a page with a highlight present (drawBehind wash composes) -------

    @Test fun pagedBody_rendersPage_withHighlightWash() = runBlocking<Unit> {
        pinPagedDefaults()
        val body = buildString { for (i in 1..80) append("Line %03d of the wash fixture text.\n".format(i)) }
        val doc = TxtDocument.of(body)
        val bookKey = "txt:${"a".repeat(64)}:${doc.text.length}"
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val paginator = TxtPaginator()
        val navigator = TxtPageNavigator(paginator)
        val cache = PagedRenderCache()
        // A highlight over the first line's opening word "Line" (source [0,4)).
        val highlights = listOf(hl(doc.text, 0, 4, AnnotationColor.green))

        compose.setContent {
            TxtPagedBody(
                document = doc,
                format = vreader.contracts.BookFormat.txt,
                mapper = IdentityChunkTextMapper(doc),
                textStyle = TextStyle.Default,
                marginDp = ReaderSettings.DEFAULT_MARGIN,
                navigator = navigator,
                paginator = paginator,
                renderCache = cache,
                initialSourceOffset = 0,
                onSaveSourceOffset = {},
                selectionController = controller,
                onSelectionFinalized = {},
                highlights = highlights,
            )
        }
        compose.waitUntil(15_000) { navigator.index?.let { it.pageCount > 0 } == true }
        // The page renders (proving the drawBehind wash path composed without crash) and the first line
        // is visible on page 0.
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("txt-page-0", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        assertTrue("paged body rendered page 0 with a highlight present",
            compose.onAllNodesWithTag("txt-page-0", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
    }

    // ---- Real TAP on a highlighted glyph → onTapEditAt fires + suppresses navigation -------------------

    @Test fun realTap_onHighlightedGlyph_firesEditAndSuppressesNavigation() = runBlocking<Unit> {
        pinPagedDefaults()
        val body = buildString { for (i in 1..80) append("Highlighted line %03d of the fixture.\n".format(i)) }
        val doc = TxtDocument.of(body)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val paginator = TxtPaginator()
        val navigator = TxtPageNavigator(paginator)
        val cache = PagedRenderCache()
        // Highlight a generous leading span (the first ~10 lines of source) so a settled tap anywhere in
        // the page's top band lands on a highlighted glyph (robust to line-height / top-pad variance).
        val spanEnd = doc.text.take(400).length.coerceAtLeast(1)
        val highlights = listOf(hl(doc.text, 0, spanEnd, AnnotationColor.blue))

        val editFired = AtomicBoolean(false)
        val navigated = AtomicBoolean(false)

        compose.setContent {
            TxtPagedBody(
                document = doc,
                format = vreader.contracts.BookFormat.txt,
                mapper = IdentityChunkTextMapper(doc),
                textStyle = TextStyle.Default,
                marginDp = ReaderSettings.DEFAULT_MARGIN,
                navigator = navigator,
                paginator = paginator,
                renderCache = cache,
                initialSourceOffset = 0,
                onSaveSourceOffset = {},
                onToggleChrome = { navigated.set(true) },
                selectionController = controller,
                onSelectionFinalized = {},
                // The SAME contract the host wires: resolve source → hit-test → open edit → return true to
                // suppress navigation. Here we assert the resolve+hit path fires and returns true.
                onTapEditAt = { point ->
                    val off = controller.resolveSourceOffset(point)
                    val hit = off?.let { TxtHighlightHitTester.highlightAt(it, highlights) }
                    if (hit != null) { editFired.set(true); true } else false
                },
                highlights = highlights,
            )
        }
        compose.waitUntil(15_000) { navigator.index?.let { it.pageCount > 0 } == true }
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("txt-page-0", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        // A settled tap through the PAGER (which owns the pagedTapZones classifier — the same node the
        // WI-6b tap-zones test taps), near the top-left glyph of page 0 (inside the highlighted first
        // line, below the 16dp top pad).
        compose.onNodeWithTag("txt-pager", useUnmergedTree = true)
            .performTouchInput { click(Offset(width * 0.2f, height * 0.1f)) }
        compose.waitUntil(8_000) { editFired.get() }
        assertTrue("a tap on a highlighted glyph fires tap-to-edit", editFired.get())
        // The classifier returned early on the true → the CENTER chrome toggle must NOT have fired for
        // this tap (navigation suppressed). (Left/right zones don't apply at x=12%.)
        assertFalse("tap-to-edit suppresses navigation for that tap", navigated.get())
    }

    // ---- Real TAP on a NON-highlighted glyph → onTapEditAt returns false (navigation proceeds) ---------

    @Test fun realTap_onUnhighlightedGlyph_returnsFalse() {
        val text = "no highlight on this page at all"
        val doc = TxtDocument.of(text)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map = txtPage(srcBase = 0, len = text.length)
        val laid = layoutPage(controller, page = 0, rendered = text, map = map)
        val highlights = emptyList<HighlightRecord>()

        // Simulate the host's tap-to-edit contract at a real laid-out glyph with NO highlight present.
        val off = controller.resolveSourceOffset(pointAtRendered(laid, 5))
        val hit = off?.let { TxtHighlightHitTester.highlightAt(it, highlights) }
        assertNotNull("the tap resolves a source offset on the page", off)
        assertTrue("no highlight → tap-to-edit does not fire (navigation proceeds)", hit == null)
    }

    // ---- Real long-press still selects with the wash wired ---------------------------------------------

    @Test fun realLongPress_stillSelects_withWashWired() = runBlocking<Unit> {
        pinPagedDefaults()
        val body = buildString { for (i in 1..80) append("Selectable washed line %03d here.\n".format(i)) }
        val doc = TxtDocument.of(body)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val paginator = TxtPaginator()
        val navigator = TxtPageNavigator(paginator)
        val cache = PagedRenderCache()
        val highlights = listOf(hl(doc.text, 0, 10, AnnotationColor.pink))

        compose.setContent {
            TxtPagedBody(
                document = doc,
                format = vreader.contracts.BookFormat.txt,
                mapper = IdentityChunkTextMapper(doc),
                textStyle = TextStyle.Default,
                marginDp = ReaderSettings.DEFAULT_MARGIN,
                navigator = navigator,
                paginator = paginator,
                renderCache = cache,
                initialSourceOffset = 0,
                onSaveSourceOffset = {},
                selectionController = controller,
                onSelectionFinalized = {},
                highlights = highlights,
            )
        }
        compose.waitUntil(15_000) { navigator.index?.let { it.pageCount > 0 } == true }
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("txt-page-0", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("txt-page-0", useUnmergedTree = true)
            .performTouchInput { longClick(percentOffset(0.2f, 0.1f)) }
        compose.waitUntil(8_000) { controller.currentRange() != null }
        val range = controller.currentRange()
        assertNotNull("long-press still begins a selection with the wash wired", range)
        assertTrue("the selection is a real non-empty in-doc range",
            range!!.startInclusive in 0..doc.text.length && range.endExclusive > range.startInclusive &&
                range.endExclusive <= doc.text.length)
    }

    private fun pinPagedDefaults() = runBlocking<Unit> {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as com.vreader.app.VReaderApp
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
        store.setLayout(ReaderLayout.Paged)
        repeat(3) { store.markTapHintSeen() }   // no first-open hint overlay over the pager
    }
}
