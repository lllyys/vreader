// Purpose: feature #137 WI-6a (#110 Phase 3, box E) — the TXT/MD reader BODY composables, extracted
// out of the (already ~1380-line) TxtReaderActivity so the host stays under budget and the paged path is
// isolated. Two bodies:
//
//   • [TxtBody] — the pre-#137 continuous-scroll LazyColumn, moved here UNCHANGED (byte-identical
//     behavior: #124/#125 selection + washes, #131 WI-8 bilingual interlinear, #121 TTS span wash). The
//     host renders it when layout == Scroll (the default) and always for bilingual-on (WI-10 gate).
//
//   • [TxtPagedBody] — the feature-#137 PAGED renderer: a HorizontalPager over WI-4's TxtPageIndex.
//     Phase-1 pagination (TxtPaginator.index) runs OFF-MAIN (Dispatchers.Default, generation-cancellable)
//     via WI-5's TxtPageNavigator, driven by a real Compose ComposeLineMeasurer built from the SAME
//     resolver/density/direction the render uses (deterministic breaks). Each visible page renders LAZILY
//     via TxtPaginator.renderPage through the UI mapper, held only for a small window (an LRU keyed by
//     page → the rendered AnnotatedString) so the whole book is never rendered at once. A load state
//     shows while phase-1 is in flight (or the degenerate-box degrade-to-scroll fallback renders the
//     scroll body). Page-start save/restore: the pager's current page's START source offset is what the
//     host persists (via [onSaveSourceOffset]); a saved offset restores by pageContaining. A
//     display-settings / rotation change re-paginates via the navigator's reflow reconciliation, which
//     clamps the pager to the page containing the captured source offset.
//
// Selection / highlights / bookmarks / TTS / find are NOT re-integrated into the paged body yet — those
// are WI-7a/7b/8/9 (the paged mode leaves them inert; the scroll path keeps them). Tap-zones + the
// first-open hint are WI-6b (this WI uses HorizontalPager's native horizontal swipe as the page-turn).
//
// @coordinates-with: TxtReaderActivity.kt (the host — branches layout==Paged→TxtPagedBody else TxtBody,
//   owns the TxtPageNavigator + save seam), paged/TxtPaginator.kt + TxtPageIndex.kt + TxtPageNavigator.kt
//   + PageOffsetMap.kt (WI-4/WI-5 engine), paged/ComposeLineMeasurer.kt (the production measurer),
//   ChunkTextMapper.kt (the UI render+cache seam), TxtDocument.kt (the chunk source),
//   settings/ReaderTextStyles.kt (bodyTextStyle both paths apply).
package com.vreader.app.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.vreader.app.reader.paged.ComposeLineMeasurer
import com.vreader.app.reader.paged.PageContentBox
import com.vreader.app.reader.paged.PageOffsetMap
import com.vreader.app.reader.paged.TxtPageNavigator
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.ui.theme.VReaderColors
import kotlinx.coroutines.flow.flowOf
import vreader.contracts.BookFormat

/**
 * The paged TXT/MD reader body — feature #137 WI-6a. Renders the document one page at a time through a
 * [HorizontalPager] over the off-main [TxtPageNavigator]'s page index, each page rendered lazily via
 * [TxtPaginator.renderPage] and held for a small window ([PagedRenderCache]). While phase-1 pagination
 * is in flight a load indicator shows; a degenerate content box (no usable layout area) degrades to the
 * scroll [TxtBody] (the plan's bounded, logged fallback).
 *
 * The host OWNS the [navigator], the [paginator], and the [renderCache] (so its test seams + the
 * save/restore path can read them), and supplies:
 *   • [initialSourceOffset] — the resume anchor (a source-UTF-16 offset); the first pagination restores
 *     the pager to `pageContaining(initialSourceOffset)`.
 *   • [onSaveSourceOffset] — invoked (debounced by the host) with the CURRENT page's START source offset
 *     whenever the visible page changes, so the host persists the page-start offset (R1 Medium-8).
 *   • [onContentBoxReady] — reports the measured chrome-aware content box (px) so the host can trigger a
 *     reflow on a settings change with the same box.
 *
 * [textStyle] + [marginDp] are the #129 Display settings (the SAME the scroll body applies), so a page's
 * measured line breaks (phase-1) match its rendered text (phase-2) — the [ComposeLineMeasurer] is built
 * from the composition's font-family resolver / density / layout direction for determinism.
 */
@Composable
internal fun TxtPagedBody(
    document: TxtDocument,
    format: BookFormat,
    mapper: ChunkTextMapper,
    textStyle: TextStyle,
    marginDp: Float,
    navigator: TxtPageNavigator,
    paginator: TxtPaginator,
    renderCache: PagedRenderCache,
    initialSourceOffset: Int,
    onSaveSourceOffset: (Int) -> Unit,
    // An external programmatic page jump (the test-seam page turn; future bookmark/search jumps). The host
    // raises it to a target PAGE; the body scrolls, persists, then calls [onJumpConsumed] to clear it.
    jumpRequest: Int? = null,
    onJumpConsumed: () -> Unit = {},
    onContentBoxReady: (PageContentBox) -> Unit = {},
) {
    val isMarkdown = format == BookFormat.md
    val density = LocalDensity.current
    val fontResolver = LocalFontFamilyResolver.current
    val layoutDirection = LocalLayoutDirection.current
    // The EFFECTIVE style — the exact same style the page `Text` renders with: the Material
    // LocalTextStyle merged with [textStyle] (bodyTextStyle leaves layout-affecting fields like
    // letterSpacing unset, and the Material default fills them). BOTH phase-1 measurement AND phase-2
    // render MUST use this identical style, or measured line breaks diverge from rendered ones (Gate-4
    // High: a bare `textStyle` measure vs a merged render is non-deterministic).
    val effectiveStyle = LocalTextStyle.current.merge(textStyle)
    // ONE measurer per (resolver/density/direction) — the SAME shaping inputs the page Text renders with,
    // so phase-1 line breaks == phase-2 render (deterministic; Gate-2 R3). Rebuilt only when a shaping
    // input changes (a config change swaps density/direction), which is exactly when a reflow is due.
    val measurer = remember(fontResolver, density, layoutDirection) {
        ComposeLineMeasurer(TextMeasurer(fontResolver, density, layoutDirection))
    }
    // Chrome-aware content box: the paged Box's laid-out size minus the horizontal margin padding + the
    // vertical page padding (matches the scroll body's contentPadding: horizontal = marginDp, vertical
    // = 16dp). Zero until the first layout pass; a zero/degenerate box → a degenerate index → the
    // scroll fallback.
    var contentBox by remember { mutableStateOf(PageContentBox(0f, 0f)) }
    val marginPx = with(density) { marginDp.dp.toPx() }
    val vPadPx = with(density) { 16.dp.toPx() }

    // The published boundary index as COMPOSE STATE (null before phase-1 completes) — the pagination
    // runs off-main in a LaunchedEffect and publishes here so the pager recomposes. The `navigator`
    // mirrors currentPage + the offset↔page math (so the host's test seams + future bookmark/search jumps
    // read it); this Compose-state mirror is what drives recomposition (the navigator's plain fields
    // don't). NO frame-poll loop — every programmatic scroll flows through a Compose-observable target
    // (localScrollTarget for the reflow clamp, [jumpRequest] for an external jump), so the compose-test
    // idling resource can settle (a busy while-loop would keep it perpetually not-idle).
    var index by remember(document) { mutableStateOf<com.vreader.app.reader.paged.TxtPageIndex?>(null) }
    // The reflow clamp's one-shot programmatic scroll target (a Compose State the pager consumes).
    var localScrollTarget by remember(document) { mutableStateOf<Int?>(null) }
    // Whether the FIRST pagination has restored to the resume anchor yet (so a later reflow captures the
    // live page offset, not initialSourceOffset again).
    var restored by remember(document) { mutableStateOf(false) }
    // The in-flight phase-1 token, held across recompositions so a superseded pass is explicitly
    // token-CANCELLED (Gate-4 Medium). Coroutine-cancelling the old LaunchedEffect alone does NOT stop
    // TxtPaginator's tight CPU loop — it only aborts at `checkCancelled(token)` (TxtPaginator.kt:119), so
    // the whole-book measure would run to completion on Dispatchers.Default without this cancel.
    val activeToken = remember(document) { androidx.compose.runtime.mutableStateOf<com.vreader.app.reader.paged.PaginationToken?>(null) }

    // Drive phase-1 pagination OFF-MAIN whenever a reflow trigger changes (content box, EFFECTIVE style,
    // margin). Captures the resume anchor: initialSourceOffset on the FIRST pass, else the current page's
    // start (so font/rotation reflow preserves progression). Cancellable: the prior token is flipped BEFORE
    // the new pass so a superseded whole-book measure aborts at its next chunk-boundary check. Clamps the
    // pager to pageContaining(captured). Uses [effectiveStyle] — the SAME style the page renders with.
    LaunchedEffect(contentBox, effectiveStyle, marginDp, document) {
        if (contentBox.widthPx <= 0f || contentBox.heightPx <= 0f) return@LaunchedEffect
        onContentBoxReady(contentBox)
        val captured = if (!restored) initialSourceOffset else navigator.currentSourceOffset()
        activeToken.value?.cancel()                              // supersede any in-flight measure pass
        val token = com.vreader.app.reader.paged.PaginationToken()
        activeToken.value = token
        val newIndex = paginator.index(document, effectiveStyle, contentBox, measurer, token, isMarkdown)
        if (activeToken.value === token) activeToken.value = null
        // The renderPage cache is keyed by page NUMBER; a reflow renumbers pages → invalidate it.
        renderCache.clear()
        navigator.setIndex(newIndex)                             // install into the navigator (offset↔page math)
        val target = newIndex.pageContaining(captured)
        navigator.onPagerPageChanged(target)                     // keep navigator.currentPage in sync
        index = newIndex                                         // publish → pager recomposes
        localScrollTarget = target                               // scroll the (already-composed) pager to it
        restored = true
    }

    Box(
        Modifier
            .fillMaxSize()
            .testTag("txt-paged-body")
            .onGloballyPositioned {
                val s: IntSize = it.size
                val w = (s.width - 2 * marginPx).coerceAtLeast(0f)
                val h = (s.height - 2 * vPadPx).coerceAtLeast(0f)
                val next = PageContentBox(w, h)
                if (next != contentBox) contentBox = next
            },
    ) {
        val idx = index
        when {
            // Phase-1 not done yet → a bare (non-animating) load surface. The reader's own open/load
            // gate already showed the settings/document loading scaffold; phase-1 on a decoded document
            // is sub-frame for typical books, so a static placeholder (NOT an infinite spinner — that
            // would wedge the compose-test idling resource) is the right transient. No invented reader
            // chrome (rule 51); the pager replaces it the instant the index publishes.
            idx == null -> {
                Box(Modifier.fillMaxSize().testTag("txt-paged-loading"))
            }
            // Degenerate content box (no usable layout area) or an empty document → degrade to scroll
            // rendering for this open (bounded, logged failure state; the reader stays usable). Re-attempts
            // when a valid box arrives (the LaunchedEffect re-runs on the next non-degenerate contentBox).
            idx.isDegenerate || idx.isEmpty -> {
                TxtScrollFallback(document, format, mapper, textStyle, marginDp)
            }
            else -> {
                val pageCount = idx.pageCount
                val pagerState = rememberPagerState(
                    initialPage = navigator.currentPage.coerceIn(0, (pageCount - 1).coerceAtLeast(0)),
                    pageCount = { pageCount },
                )
                // A user swipe reports the settled page back to the navigator (so the save seam + a later
                // reflow see the right anchor). Only settled pages (not a mid-drag target) update state.
                // Skip the SAVE while a programmatic scroll is still pending (a reflow just published a new
                // index and is about to clamp the pager to the reconciled page): saving the pre-clamp
                // settled page would briefly persist the wrong page under the new index (Gate-4 Low). The
                // clamp's own scroll settles and saves the correct page immediately after.
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { pagerState.settledPage }.collect { settled ->
                        navigator.onPagerPageChanged(settled)
                        // localScrollTarget is Compose state — re-read live per emission; non-null means a
                        // reflow clamp is queued and this settled page is the stale pre-clamp one.
                        if (localScrollTarget == null) onSaveSourceOffset(navigator.currentSourceOffset())
                    }
                }
                // The reflow clamp's programmatic scroll: a one-shot Compose-observable target → scroll +
                // clear (so a user swipe afterwards is never overridden). No busy loop → idling settles.
                // Clear localScrollTarget AFTER scrollToPage settles (not before) so the settled-page save
                // guard stays true for the whole scroll — otherwise a stale pre-clamp settledPage emission
                // could land a wrong save in the clear→settle window (Gate-4 R2 Low).
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { localScrollTarget }.collect { t ->
                        if (t == null) return@collect
                        val clamped = t.coerceIn(0, (pageCount - 1).coerceAtLeast(0))
                        navigator.onPagerPageChanged(clamped)
                        if (clamped != pagerState.currentPage) runCatching { pagerState.scrollToPage(clamped) }
                        localScrollTarget = null
                        // After the clamp settles, persist the reconciled page's start offset (the save was
                        // suppressed while the target was pending).
                        onSaveSourceOffset(navigator.currentSourceOffset())
                    }
                }
                // An EXTERNAL jump (the test-seam page turn / future bookmark-search jump): the host raises
                // [jumpRequest] (a target PAGE), we scroll the pager + sync the navigator + persist the new
                // page-start offset, then clear the request via [onJumpConsumed]. `jumpRequest` is a plain
                // parameter — read it through rememberUpdatedState so the snapshotFlow reacts to a NEW value
                // even though this LaunchedEffect (keyed pagerState/idx) never restarts (a bare
                // `snapshotFlow { jumpRequest }` would capture the stale first value).
                val liveJumpRequest by rememberUpdatedState(jumpRequest)
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { liveJumpRequest }.collect { req ->
                        if (req == null) return@collect
                        val clamped = req.coerceIn(0, (pageCount - 1).coerceAtLeast(0))
                        navigator.onPagerPageChanged(clamped)
                        if (clamped != pagerState.currentPage) runCatching { pagerState.scrollToPage(clamped) }
                        onSaveSourceOffset(navigator.currentSourceOffset())
                        onJumpConsumed()
                    }
                }

                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize().testTag("txt-pager"),
                    // Bound the rendered window: HorizontalPager keeps ± beyondViewportPageCount pages
                    // COMPOSED; combined with the LRU render cache the whole book is never rendered.
                    beyondViewportPageCount = 1,
                ) { page ->
                    // Lazily render THIS page through the UI mapper; hold it in the small LRU cache so an
                    // off-screen page's AnnotatedString is evicted (memory-bounded — the scroll body's LRU
                    // posture, page-scoped). Only the AnnotatedString is cached (the PageOffsetMap is
                    // WI-7a's concern and not retained here).
                    val rendered: AnnotatedString = remember(page, idx, mapper) {
                        renderCache.getOrRender(page) {
                            val (text: AnnotatedString, _: PageOffsetMap) =
                                paginator.renderPage(document, idx, page, mapper, effectiveStyle, isMarkdown)
                            text
                        }
                    }
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(horizontal = marginDp.dp, vertical = 16.dp),
                    ) {
                        Text(
                            text = rendered,
                            // The SAME effective style phase-1 measured against (deterministic breaks).
                            style = effectiveStyle,
                            modifier = Modifier.fillMaxSize().testTag("txt-page-$page"),
                        )
                    }
                }
            }
        }
    }
}

/**
 * The scroll degrade-to-scroll fallback for a degenerate/empty paged index (feature #137 WI-6a). Renders
 * the SAME [TxtBody] the scroll path uses, but WITHOUT the selection/wash/TTS/bilingual wiring (those
 * are the scroll host's concern; the fallback only needs to keep the reader usable when pagination can't
 * proceed). A bounded, logged failure state — the plan's degrade-to-scroll.
 */
@Composable
private fun TxtScrollFallback(
    document: TxtDocument,
    format: BookFormat,
    mapper: ChunkTextMapper,
    textStyle: TextStyle,
    marginDp: Float,
) {
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    TxtBody(document, listState, format, mapper, textStyle = textStyle, marginDp = marginDp)
}

/**
 * A tiny page → rendered-AnnotatedString LRU (feature #137 WI-6a) so the paged body holds only a small
 * window of rendered pages (the current ± a couple that HorizontalPager composes), never the whole book.
 * NOT thread-safe — accessed only on the main thread (the page-render composables run there). [maxCached]
 * bounds the retained pages (default 6 — a couple beyond the pager's composed window).
 */
class PagedRenderCache(private val maxCached: Int = 6) {
    private val cache = object : LinkedHashMap<Int, AnnotatedString>(maxCached.coerceAtLeast(1), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Int, AnnotatedString>): Boolean = size > maxCached
    }

    /** The rendered text for [page], rendering + caching it (LRU) on a miss. */
    fun getOrRender(page: Int, render: () -> AnnotatedString): AnnotatedString =
        cache.getOrPut(page, render)

    /** Test/host visibility into the retained-page count (proves the window stays bounded). */
    val size: Int get() = cache.size

    /** Drop every cached page (a reflow invalidates page numbers → their rendered text must be rebuilt). */
    fun clear() = cache.clear()
}

/**
 * The continuous-scroll TXT/MD reader body — moved UNCHANGED from TxtReaderActivity (feature #137 WI-6a
 * light extraction; behavior byte-identical). A LazyColumn over the document's chunk ranges. For
 * BookFormat.md each chunk renders through the mapper (styled AnnotatedString); else verbatim. [textStyle]
 * + [marginDp] come from the #129 Display settings.
 *
 * feature #125 — [mapper] is the single render owner (MD chunks render via mapper.renderedText so the
 * body's TextLayoutResult matches the controller/wash offset map exactly — no double render, no drift).
 * feature #124 — per-chunk annotation washes + custom selection (TXT + MD). feature #121 — the spoken
 * sentence span wash (TXT). feature #131 WI-8 — the interlinear translation slot(s) per chunk.
 */
@Composable
internal fun TxtBody(
    document: TxtDocument, listState: LazyListState, format: BookFormat,
    mapper: ChunkTextMapper,
    textStyle: TextStyle, marginDp: Float,
    highlightSpan: (chunkIndex: Int) -> IntRange? = { null },
    washesForChunk: (chunkIndex: Int) -> List<WashSpan> = { emptyList() },
    selectionController: TxtSelectionController? = null,
    onSelectionFinalized: () -> Unit = {},
    onTapAt: (Offset) -> Unit = {},
    bilingualRenderStates: (chunkIndex: Int) -> List<com.vreader.app.bilingual.BilingualRenderState> = { emptyList() },
    bilingualLanguage: com.vreader.app.bilingual.BilingualLanguage = com.vreader.app.bilingual.BilingualLanguages.ALL.first(),
    bilingualTheme: com.vreader.app.reader.settings.ReaderTheme? = null,
    bilingualSourceFontSizeSp: Float = 17f,
    onBilingualSlotBounds: (List<androidx.compose.ui.geometry.Rect>) -> Unit = {},
) {
    val isMarkdown = format == BookFormat.md
    val wash = VReaderColors.Accent.copy(alpha = 0.18f)
    val selectionAccent = androidx.compose.ui.graphics.Color(0x575C8FC4)   // design selection bg rgba(92,143,196,0.34)
    val selection by (selectionController?.selection ?: flowOf(null)).collectAsState(null)
    // the pointerInput block keys on selectionController (stable), so without this it would capture the
    // INITIAL onTapAt/onSelectionFinalized closures (stale highlightsList → tap-to-edit never hits).
    val currentOnTap by rememberUpdatedState(onTapAt)
    val currentOnFinalize by rememberUpdatedState(onSelectionFinalized)
    // feature #131 WI-8 — the WINDOW-space bounds of EACH laid-out translation slot, keyed by
    // (chunkIndex, slotIndex) so EVERY rendered slot reports its own rect (round-4 audit Medium-1 — a
    // chunk may anchor several units; the first slot's rect does not cover its siblings). Each slot owns
    // its entry + disposal, and a source-only/empty slot removes its stale rect. The flattened list is
    // pushed to the host (→ selection controller's excluded bounds) so a long-press on translation is
    // never selectable — and never keeps a phantom rect over source content that scrolled into its place.
    val translationSlotBounds = remember { androidx.compose.runtime.mutableStateMapOf<Pair<Int, Int>, androidx.compose.ui.geometry.Rect>() }
    LaunchedEffect(translationSlotBounds.entries.toList()) {
        onBilingualSlotBounds(translationSlotBounds.values.toList())
    }
    LazyColumn(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { selectionController?.setLazyCoords(it) }
            .then(
                if (selectionController != null) {
                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
                    Modifier.pointerInput(selectionController) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val longPress = awaitLongPressOrCancellation(down.id)
                            if (longPress != null) {
                                // long-press → selection; finalize only on a COMPLETED drag/up (not a cancel).
                                selectionController.beginAt(longPress.position)
                                val completed = drag(longPress.id) { change -> selectionController.extendTo(change.position); change.consume() }
                                if (completed) currentOnFinalize() else selectionController.clear()
                            } else if (!down.isConsumed) {
                                // null also means cancel (e.g. a scroll won) — only a TAP leaves the down
                                // unconsumed; a scroll consumes it, so it won't be misread as tap-to-edit.
                                currentOnTap(down.position)
                            }
                        }
                    }
                } else {
                    Modifier
                },
            ),
        state = listState,
        contentPadding = PaddingValues(horizontal = marginDp.dp, vertical = 16.dp),
    ) {
        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
        // ONE lazy item per chunk (loop + keys UNCHANGED → lazy-index == chunk-index preserved, round-4
        // H2). Inside each item a Column holds the byte-unchanged source Text (below) then the muted,
        // NON-registered interlinear translation slot(s) anchored to this chunk (feature #131 WI-8).
        items(count = document.chunkCount, key = { it }) { i ->
          Column {
            val raw = document.textForChunk(i).toString()
            // .md → styled markdown spans (no read-aloud span wash — markers shift offsets, plan §OOS).
            // .txt → raw verbatim, with the spoken-sentence span washed when read-aloud is active.
            val span = if (isMarkdown) null else highlightSpan(i)
            val text = when {
                isMarkdown -> mapper.renderedText(i)   // #125: the mapper is the single render owner
                span != null -> buildAnnotatedString {
                    append(raw)
                    val a = span.first.coerceIn(0, raw.length); val b = (span.last + 1).coerceIn(a, raw.length)
                    if (b > a) addStyle(SpanStyle(background = wash), a, b)
                }
                else -> AnnotatedString(raw)
            }
            // annotation washes drawn BEHIND the text (getPathForRange) — separate from the read-aloud span.
            val washes = washesForChunk(i)
            var layout by remember(i) { mutableStateOf<TextLayoutResult?>(null) }
            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
            if (selectionController != null) {
                LaunchedEffect(i, layout, coords) {
                    val l = layout; val c = coords
                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
                }
                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
            }
            // read `selection` (a State) so a selection change recomposes + redraws the accent.
            val selRange = if (selection != null) selectionController?.selectionForChunk(i) else null
            Text(
                text = text,
                // merge over the material default (the pre-#129 explicit-param behavior) so platform
                // text defaults (letterSpacing etc.) are kept — only the Display settings change.
                style = LocalTextStyle.current.merge(textStyle),
                onTextLayout = { layout = it },
                modifier = Modifier
                    .onGloballyPositioned { coords = it }
                    .drawBehind {
                        layout?.let { l ->
                            drawWashes(l, washes)
                            selRange?.let { drawRangeFill(l, it, selectionAccent) }
                        }
                    },
            )
            // feature #131 WI-8 — the interlinear translation slot(s) for the unit(s) anchored to chunk `i`,
            // as muted NON-registered `Text` children inside the SAME lazy item's Column. Never registered
            // with the selection controller; EACH reports its own window bounds (keyed by (i, slotIdx)) so a
            // long-press on ANY of them is excluded (round-4 audit Medium-1).
            val renderStates = bilingualRenderStates(i)
            val slotTheme = bilingualTheme
            renderStates.forEachIndexed { slotIdx, renderState ->
                val boundsKey = i to slotIdx
                // A source-only/empty slot draws NOTHING (no node → no onGloballyPositioned) — so proactively
                // drop any prior rect for this key, and each slot removes its rect on dispose (recycle /
                // language change) so no phantom exclusion survives over source content (round-4 audit Medium-1).
                val drawsSlot = renderState.phase != com.vreader.app.bilingual.BilingualRenderPhase.SourceOnly &&
                    !(renderState.phase == com.vreader.app.bilingual.BilingualRenderPhase.Loaded &&
                        renderState.segments.orEmpty().none { it.isNotBlank() })
                if (slotTheme != null && drawsSlot) {
                    com.vreader.app.bilingual.BilingualTranslationSlot(
                        state = renderState,
                        theme = slotTheme,
                        language = bilingualLanguage,
                        sourceFontSizeSp = bilingualSourceFontSizeSp,
                        modifier = Modifier.onGloballyPositioned { c ->
                            if (c.isAttached) translationSlotBounds[boundsKey] = c.boundsInWindow()
                            else translationSlotBounds.remove(boundsKey)
                        },
                    )
                    DisposableEffect(boundsKey) { onDispose { translationSlotBounds.remove(boundsKey) } }
                } else {
                    // Nothing drawn for this slot → ensure no stale rect lingers.
                    DisposableEffect(boundsKey, drawsSlot) { translationSlotBounds.remove(boundsKey); onDispose { translationSlotBounds.remove(boundsKey) } }
                }
            }
          }
        }
    }
}
