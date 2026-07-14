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
import com.vreader.app.reader.paged.PageContentBox
import com.vreader.app.reader.paged.PageOffsetMap
import com.vreader.app.reader.paged.PageSegment
import com.vreader.app.reader.paged.TxtPageNavigator
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #137 WI-7a — the PAGED text-selection path of [TxtSelectionController] + [TxtPagedBody].
 *
 * These are DETERMINISTIC Compose-rule tests (createComposeRule; no emulator-timing-flaky gesture
 * recognizer): each test lays out a REAL page `Text` and registers it with the controller via
 * `registerPage(page, TextLayoutResult, LayoutCoordinates, PageOffsetMap)` — exactly what [TxtPagedBody]
 * does — then drives the controller's `beginAt`/`extendTo`/`resolveSourceOffset` at real laid-out
 * coordinates (pointing at a known glyph via `getCursorRect`). This proves the page-scoped hit path
 * resolves pointer → page-local rendered → GLOBAL source via the page's [PageOffsetMap] (NEVER
 * offsetForChunk), producing the SAME source Utf16Range the scroll path would.
 *
 * Covered (deterministic): word-select on a TXT page (correct GLOBAL source word), drag-extend across the
 * page, a tap resolving a source offset (tap-to-edit), MD dual-affinity (the source word span skips
 * stripped markers), multi-page registration (a hit on page 1 resolves against page 1's map, not page 0),
 * and off-screen page de-registration (an unregistered page is not consulted). PLUS one REAL-gesture test
 * (`realLongPress_onPagedBody_beginsASourceSelection`) that drives the actual [TxtPagedBody] through the
 * UNIFIED pagedTapZones classifier (the same recognizer that owns the pager swipe + tap-zones) to prove the
 * long-press → selection wiring end-to-end. One class per connected invocation (MEMORY #129/#133); the
 * long-press test polls the controller's selection StateFlow (NOT bare waitForIdle) because long-press
 * timing is emulator-flaky under load.
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedSelectionConnectedTest {

    @get:Rule val compose = createComposeRule()

    private fun r(a: Int, b: Int) = Utf16Range(a, b)
    private fun mdMap(chunk: String) = MarkdownOffsetMap(MarkdownRenderer.renderWithMap(chunk))

    /** Lay out [rendered] as a real page `Text` inside a root, register it with [controller] as [page]
     *  carrying [map], and return the root coords + the page `Text`'s layout so a caller can point at a
     *  known glyph. The controller's lazyCoords are the ROOT (the paged body registers the outer box). */
    private class Laid(
        val root: LayoutCoordinates,
        val layout: TextLayoutResult,
        val coords: LayoutCoordinates,
    )

    /** A source-UTF-16 point (root-local) targeting the CENTER of the glyph rendered at page-local
     *  [renderedIndex] in [laid], so a hit resolves deterministically to that glyph (no ambiguity). */
    private fun pointAtRendered(laid: Laid, renderedIndex: Int): Offset {
        val cursor = laid.layout.getCursorRect(renderedIndex)
        // Center of the glyph cell (nudge +half-a-char right of the leading edge so getOffsetForPosition
        // lands ON the glyph, not its left boundary).
        val next = laid.layout.getCursorRect((renderedIndex + 1).coerceAtMost(laid.layout.layoutInput.text.length))
        val glyphMidX = (cursor.left + next.left) / 2f
        val glyphMidY = (cursor.top + cursor.bottom) / 2f
        val inText = Offset(glyphMidX, glyphMidY)
        // Text is at the top-left of the root here (no page padding in these deterministic layouts), so
        // text-local == root-local; convert through window to be robust to any inset.
        val window = laid.coords.localToWindow(inText)
        return laid.root.windowToLocal(window)
    }

    /** Compose a single page `Text` at the root top-left; register it as [page] with [map] on [controller];
     *  return the laid-out handles. */
    private fun layoutPage(
        controller: TxtSelectionController,
        page: Int,
        rendered: String,
        map: PageOffsetMap,
    ): Laid {
        val rootRef = AtomicReference<LayoutCoordinates?>(null)
        val layoutRef = AtomicReference<TextLayoutResult?>(null)
        val coordsRef = AtomicReference<LayoutCoordinates?>(null)
        compose.setContent {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(600.dp)
                    .onGloballyPositioned { rootRef.set(it) },
            ) {
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

    // ---- TXT: word-select resolves the correct GLOBAL source word --------------------------------------

    @Test fun txtPage_longPress_selectsWord_atGlobalSource() {
        // A TXT page whose rendered text is "hello world here" starting at document source offset 100.
        val text = "hello world here"
        val doc = TxtDocument.of("x".repeat(100) + text)   // the page starts at source 100 in a larger doc
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 100, renderedLen = text.length)))
        val laid = layoutPage(controller, page = 0, rendered = text, map = map)

        // Point at the 'w' of "world" (rendered index 6) → the word "world" = source [106,111).
        controller.beginAt(pointAtRendered(laid, 6))
        assertEquals("paged long-press selects the GLOBAL source word", r(106, 111), controller.currentRange())
        assertEquals("selected visible text is the word", "world", controller.selectedVisibleText())
        assertTrue("selection is persist-valid", controller.isCurrentSelectionValid())
    }

    @Test fun txtPage_dragExtend_growsSelectionForward_inSource() {
        val text = "alpha beta gamma"
        val doc = TxtDocument.of("y".repeat(50) + text)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 50, renderedLen = text.length)))
        val laid = layoutPage(controller, page = 0, rendered = text, map = map)

        // Long-press "alpha" (rendered 0) then drag to inside "gamma" (rendered 13 = 'a' of gamma) — the
        // selection extends forward to that source offset.
        controller.beginAt(pointAtRendered(laid, 0))
        val anchor = requireNotNull(controller.currentRange())
        assertEquals("anchor word = alpha", r(50, 55), anchor)
        controller.extendTo(pointAtRendered(laid, 13))
        val extended = requireNotNull(controller.currentRange())
        assertEquals("drag keeps the anchor start", 50, extended.startInclusive)
        assertTrue("drag grew the end into gamma", extended.endExclusive > 55)
        assertEquals("end is the dragged source offset", 50 + 13, extended.endExclusive)
    }

    @Test fun txtPage_tap_resolvesGlobalSourceOffset() {
        val text = "tap target line"
        val doc = TxtDocument.of("z".repeat(20) + text)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 20, renderedLen = text.length)))
        val laid = layoutPage(controller, page = 0, rendered = text, map = map)

        // A tap at rendered index 4 ('t' of "target") → GLOBAL source 24.
        val off = controller.resolveSourceOffset(pointAtRendered(laid, 4))
        assertEquals("tap resolves to the GLOBAL source offset", 24, off)
    }

    // ---- MD: dual-affinity — the source word span skips the stripped markers ---------------------------

    @Test fun mdPage_longPress_selectsWord_dualAffinitySourceSpan() {
        // "**bold**x here\n" renders (markers stripped) to "boldx here\n". The doc IS the single chunk, so
        // GLOBAL source == chunk-local source (srcBase 0) and the controller's MarkdownChunkTextMapper
        // renders chunk 0 identically to `cm` (used by selectedVisibleText/selectedSourceText).
        val chunk = "**bold**x here\n"
        val cm = mdMap(chunk)
        val doc = TxtDocument.of(chunk)
        val controller = TxtSelectionController(doc, MarkdownChunkTextMapper(doc))
        val map = PageOffsetMap(listOf(PageSegment.markdown(cm, renderedBase = 0, srcBase = 0)))
        val laid = layoutPage(controller, page = 0, rendered = cm.renderedText.text, map = map)

        // Rendered "boldx here": 'b'=0. Long-press 'b' → the word "boldx" is rendered [0,5). Its SOURCE span
        // is chunk-local [2,9) (the "**" markers preserved in source) → GLOBAL [2,9) (dual-affinity: the
        // stripped "**" between 'd' and 'x' does NOT collapse their distinct source positions).
        controller.beginAt(pointAtRendered(laid, 0))
        assertEquals("MD paged word maps rendered→SOURCE (dual-affinity)", r(2, 9), controller.currentRange())
        // The VISIBLE text is the marker-stripped rendered word "boldx". The SOURCE span is [2,9): it starts
        // at 'b' (source 2 — the leading "**" is NOT part of the word) and keeps the INNER "**" markers
        // between 'd' and 'x' (dual-affinity → those distinct source positions are preserved) = "bold**x".
        assertEquals("visible = rendered word", "boldx", controller.selectedVisibleText())
        assertEquals("source keeps the inner markers", "bold**x", controller.selectedSourceText())
    }

    // ---- Multi-page registration: a hit on page 1 uses page 1's map, not page 0's ----------------------

    @Test fun secondPage_hit_resolvesAgainstThatPagesMap_notOffsetForChunk() {
        // Two registered pages. Page 0 covers source [0,10); page 1 covers source [500,510). A hit on the
        // page-1 Text must resolve to source ~500+, proving it uses page 1's map (NOT a chunk base).
        val text0 = "first page"
        val text1 = "later page"
        val doc = TxtDocument.of(text0 + "\n" + "w".repeat(500))
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map0 = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 0, renderedLen = text0.length)))
        val map1 = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 500, renderedLen = text1.length)))

        // Lay out BOTH pages stacked in one root so both have real, distinct window bounds.
        val rootRef = AtomicReference<LayoutCoordinates?>(null)
        val l0 = AtomicReference<TextLayoutResult?>(null); val c0 = AtomicReference<LayoutCoordinates?>(null)
        val l1 = AtomicReference<TextLayoutResult?>(null); val c1 = AtomicReference<LayoutCoordinates?>(null)
        compose.setContent {
            androidx.compose.foundation.layout.Column(
                Modifier.fillMaxWidth().height(600.dp).onGloballyPositioned { rootRef.set(it) },
            ) {
                Text(text0, onTextLayout = { l0.set(it) }, modifier = Modifier.fillMaxWidth().height(200.dp).onGloballyPositioned { c0.set(it) })
                Text(text1, onTextLayout = { l1.set(it) }, modifier = Modifier.fillMaxWidth().height(200.dp).onGloballyPositioned { c1.set(it) })
            }
        }
        compose.waitForIdle()
        val root = requireNotNull(rootRef.get())
        controller.setLazyCoords(root)
        controller.registerPage(0, requireNotNull(l0.get()), requireNotNull(c0.get()), map0)
        controller.registerPage(1, requireNotNull(l1.get()), requireNotNull(c1.get()), map1)

        // Point at 'l' of "later" (rendered 0) on PAGE 1's Text → GLOBAL source 500 (page 1's srcBase),
        // NOT 5-ish (which is where a chunk-base or page-0 resolution would land).
        val laid1 = Laid(root, requireNotNull(l1.get()), requireNotNull(c1.get()))
        val off = controller.resolveSourceOffset(pointAtRendered(laid1, 0))
        assertNotNull("page-1 hit resolves", off)
        assertTrue("page-1 hit resolves against page-1 map (source >= 500)", (off ?: -1) >= 500)
    }

    // ---- Off-screen de-registration: an unregistered page is not consulted ----------------------------

    @Test fun unregisteredPage_isNotHit_afterEviction() {
        val text = "evictable page text"
        val doc = TxtDocument.of("k".repeat(30) + text)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val map = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 30, renderedLen = text.length)))
        val laid = layoutPage(controller, page = 0, rendered = text, map = map)

        // With the page registered, a strict tap resolves.
        assertNotNull("registered page resolves a tap", controller.resolveSourceOffset(pointAtRendered(laid, 2)))
        // Evict it (the pager-window eviction analog) → the strict tap no longer resolves (no page owns it).
        controller.unregisterPage(0)
        assertNull("an unregistered (evicted) page is not consulted", controller.resolveSourceOffset(pointAtRendered(laid, 2)))
    }

    // ---- Scroll path is byte-identical when NO page is registered --------------------------------------

    @Test fun scrollPath_unaffected_whenNoPageRegistered() {
        // A controller with only a CHUNK registered (scroll mode) resolves via the chunk path — the paged
        // additions must not change this. (The chunk path adds offsetForChunk; here chunk 0 base is 0.)
        val text = "scroll still works"
        val doc = TxtDocument.of(text)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val rootRef = AtomicReference<LayoutCoordinates?>(null)
        val layoutRef = AtomicReference<TextLayoutResult?>(null)
        val coordsRef = AtomicReference<LayoutCoordinates?>(null)
        compose.setContent {
            Box(Modifier.fillMaxWidth().height(400.dp).onGloballyPositioned { rootRef.set(it) }) {
                Text(text, onTextLayout = { layoutRef.set(it) }, modifier = Modifier.fillMaxSize().onGloballyPositioned { coordsRef.set(it) })
            }
        }
        compose.waitForIdle()
        val root = requireNotNull(rootRef.get())
        val layout = requireNotNull(layoutRef.get())
        val coords = requireNotNull(coordsRef.get())
        controller.setLazyCoords(root)
        controller.registerChunk(0, layout, coords)
        // Point at 'w' of "works" (rendered index 14) via a chunk-path Laid.
        val laid = Laid(root, layout, coords)
        controller.beginAt(pointAtRendered(laid, 14))
        val range = requireNotNull(controller.currentRange())
        assertEquals("scroll-mode word-select still works", "works", controller.selectedVisibleText())
        assertEquals("scroll-mode word covers 'works'", "works", doc.text.substring(range.startInclusive, range.endExclusive))
    }

    // ---- REAL gesture through the unified pagedTapZones classifier on the actual TxtPagedBody -----------

    /**
     * Drives the REAL [TxtPagedBody] with a real [TxtSelectionController]: a LONG-PRESS on the page node
     * (through the unified pagedTapZones classifier, which also owns the pager swipe + tap-zones) begins a
     * SOURCE selection — proving the gesture recognizer is wired end-to-end (not just the resolution math).
     * Long-press connected tests are emulator-timing-flaky (MEMORY #125/#133) so this polls the controller's
     * selection StateFlow via `compose.waitUntil` (NOT bare waitForIdle) and stands alone in the class.
     */
    @Test fun realLongPress_onPagedBody_beginsASourceSelection() = runBlocking<Unit> {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as com.vreader.app.VReaderApp
        // Pin display defaults + Paged + hint-seen so no first-open hint overlay sits over the pager.
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
        store.setLayout(ReaderLayout.Paged)
        // mark the hint seen so the overlay does not render over the page in this test.
        repeat(3) { store.markTapHintSeen() }

        // A multi-line TXT doc so pagination yields >1 page; the first page shows the opening lines.
        val body = buildString { for (i in 1..80) append("Line %03d of the paged selection fixture.\n".format(i)) }
        val doc = TxtDocument.of(body)
        val controller = TxtSelectionController(doc, IdentityChunkTextMapper(doc))
        val paginator = TxtPaginator()
        val navigator = TxtPageNavigator(paginator)
        val cache = PagedRenderCache()

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
            )
        }
        // Wait for phase-1 pagination to publish an index (the first page renders).
        compose.waitUntil(15_000) { navigator.index?.let { it.pageCount > 0 } == true }
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("txt-page-0", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        // Long-press near the top-left glyph of page 0 → a source selection begins (word-select).
        compose.onNodeWithTag("txt-page-0", useUnmergedTree = true)
            .performTouchInput { longClick(percentOffset(0.2f, 0.1f)) }
        // Poll the controller's selection state (long-press timing is flaky under emulator load).
        compose.waitUntil(8_000) { controller.currentRange() != null }
        val range = controller.currentRange()
        assertNotNull("a real long-press on the paged body begins a source selection", range)
        assertTrue("the selection is a real non-empty source range in-doc",
            range!!.startInclusive in 0..doc.text.length && range.endExclusive > range.startInclusive && range.endExclusive <= doc.text.length)
        assertNotNull("the selected text is resolvable", controller.selectedSourceText())
    }
}
