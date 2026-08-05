// Purpose: feature #137 WI-6a (#110 Phase 3, box E) — the TXT/MD reader BODY composables, extracted
// out of the (already ~1380-line) TxtReaderActivity so the host stays under budget and the paged path is
// isolated. Two bodies:
//
//   • [TxtBody] — the pre-#137 continuous-scroll LazyColumn, moved here UNCHANGED (byte-identical
//     behavior: #124/#125 selection + washes, #131 WI-8 bilingual interlinear, #121 TTS span wash). The
//     host renders it when layout == Scroll (the default) and always for bilingual-on (WI-10 gate).
//
//   • [TxtPagedBody] — the feature-#137 PAGED renderer: a HorizontalPager over WI-4's TxtPageIndex.
//     Each visible page renders LAZILY via TxtPaginator.renderPage through the UI mapper, held only for a
//     small window (an LRU keyed by page → the rendered AnnotatedString) so the whole book is never
//     rendered at once. A load state shows on the FIRST open (or the degenerate-box degrade-to-scroll
//     fallback renders the scroll body). Page-start save/restore: the pager's current page's START source
//     offset is what the host persists (via [onSaveSourceOffset]); a saved offset restores by pageContaining.
//
//     feature #138 WI-5b — the body now drives the WINDOWED pagination lifecycle through a
//     PaginationSession (owned here per document) instead of a single blocking whole-doc
//     TxtPaginator.index pass: session.openFromStart publishes the FIRST sealed window fast (the loading
//     surface clears in < 2 s instead of ~85 s), then background-completes; each republish grows the
//     SEALED pageCount (append-only, never shrinks). The session's callbacks fire off-main, so they publish
//     into thread-safe MutableStateFlows that a MAIN collector marshals into Compose state + the navigator.
//     A far page-turn near the frontier drives an on-demand session.ensureMeasuredThrough (NO busy loop).
//     Deep-RESUME uses a CONDITIONAL reveal (session.onReveal → land the pager on the anchor's page once it
//     seals in the background, by RECREATING the pager keyed on that page — the Gate-2 Medium-4 fallback;
//     robust where a far scrollToPage clamps short under count-lag) — DROPPED without a yank the instant the
//     user takes over. A display-settings / rotation change RE-OPENS the windowed pass from the captured
//     source offset and clamps to it; only a REFLOW clears the page-render cache (a background APPEND never
//     does — it only appends SEALED pages, never renumbers a published page).
//
// feature #137 WI-7a — paged text SELECTION is now integrated into [TxtPagedBody]: each visible page
// registers its rendered layout + coords + PageOffsetMap with the (optional) TxtSelectionController, a
// long-press-drag over a page begins/extends a SOURCE selection (word-select via the page's
// PageOffsetMap, GLOBAL source coords, MD dual-affinity), and a tap resolves a source offset.
//
// feature #137 WI-7b — the persisted-highlight WASH is now rendered per page: each visible page's
// rendered Text gets a translucent background over every stored highlight whose SOURCE range intersects
// that page, projected page-local via TxtPagedWash.washesForPage (the page's PageOffsetMap clamps a
// boundary-spanning highlight per page). Bookmarks / TTS / find remain WI-8/9 (inert in paged mode).
//
// feature #137 WI-6b — the designed page-turn AFFORDANCES on [TxtPagedBody]: the 30/40/30 tap-zones
// (paged/PagedTapZones.pagedTapZones on the pager — LEFT→prev, RIGHT→next via animateScrollToPage, CENTER
// →the host's EXISTING chrome toggle via [onToggleChrome]) alongside the preserved native horizontal
// SWIPE, and the first-open [TapZoneHint] discoverability overlay (shown once, persisted via
// ReaderSettingsStore.tapHintSeen/markTapHintSeen; dismissed on the first interaction). feature #137 WI-7a
// folds the tap-zones AND the paged text-selection long-press-drag into ONE pagedTapZones awaitEachGesture
// classifier on the pager (no two racing recognizers): a long-press starts selection, a fast swipe turns
// the page, a settled tap navigates (or tap-to-edit an existing highlight).
//
// feature #156 WI-1 — the body text is JUSTIFIED by default (the alignment arrives inside [textStyle]
// from settings/ReaderTextStyles.bodyTextStyle, so it reaches the scroll body, the paged phase-2 render,
// AND the paged phase-1 measurement through the one `effectiveStyle` merge — no host edit). Alignment is
// applied AFTER line breaking, so page boundaries are unchanged (proved by TxtPaginatorTest's
// invariance+sensitivity pair and the connected real-measurer comparison). In SCROLL mode a Markdown
// heading chunk renders with a natural-alignment variant of the same style (one Text per chunk makes
// that per-chunk choice possible); PAGED mode cannot do the same — TxtPaginator.renderPage concatenates
// a page's chunks into ONE AnnotatedString drawn by ONE Text, which carries a single paragraph
// alignment, so a paged page containing a WRAPPING heading justifies it (a stated known limitation,
// pinned by a characterisation test rather than left as prose).
//
// @coordinates-with: TxtReaderActivity.kt (the host — branches layout==Paged→TxtPagedBody else TxtBody,
//   owns the TxtPageNavigator + save seam + supplies [onToggleChrome]), paged/TxtPaginator.kt +
//   TxtPageIndex.kt + TxtPageNavigator.kt + PaginationSession.kt (feature #138 — the windowed lifecycle
//   owner this body drives) + PageOffsetMap.kt (WI-4/WI-5 engine), paged/PagedTapZones.kt
//   (WI-6b tap-zones + hint), paged/ComposeLineMeasurer.kt (the production measurer), ChunkTextMapper.kt
//   (the UI render+cache seam), TxtDocument.kt (the chunk source), settings/ReaderTextStyles.kt
//   (bodyTextStyle both paths apply), settings/ReaderSettingsStore.kt (the tap-hint-seen flag).
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
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
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
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.reader.paged.ComposeLineMeasurer
import com.vreader.app.reader.paged.PageContentBox
import com.vreader.app.reader.paged.PageOffsetMap
import com.vreader.app.reader.paged.TapZoneHint
import com.vreader.app.reader.paged.TxtPageNavigator
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.reader.paged.pagedTapZones
import com.vreader.app.reader.settings.chunkTextAlign
import com.vreader.app.ui.theme.VReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import vreader.contracts.BookFormat

/**
 * feature #138 WI-5b — how close to the sealed frontier (in pages) a settled/target page must be before
 * the body arms an on-demand forward extension of the [com.vreader.app.reader.paged.PaginationSession].
 * One page ahead of the last sealed page keeps the successor sealed so a page-turn near the frontier is
 * never a dead-end while the background completion loop catches up.
 */
private const val EXTEND_MARGIN = 1

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
    // feature #137 WI-6b — the CENTER tap-zone chrome toggle. The host passes its EXISTING chrome-visibility
    // toggle (chromeState.copy(chromeVisible = !)) — the SAME mechanism the scaffold's own center-tap uses.
    // detectTapGestures consumes the tap so the scaffold's fall-through won't fire; this callback keeps the
    // single chrome mechanism. Defaulted to a no-op so #129/WI-6a call sites / previews stay valid.
    onToggleChrome: () -> Unit = {},
    // feature #138 WI-5a — an external programmatic jump as a SOURCE OFFSET (the test-seam page turn +
    // the bookmark / annotation / search-hit / scrubber / TTS-follow feeders). The host raises the raw
    // source-UTF-16 offset; the body resolves it to a page SYNCHRONOUSLY via the navigator's
    // `jumpToOffset(offset)` overload (`pageContaining` over the current whole-doc index), scrolls,
    // persists, then calls [onJumpConsumed] to clear it. Retyped from a pre-computed page (WI-5a): the
    // seam no longer converts source→page on the UI thread. The async beyond-frontier EVENTUAL landing on
    // a PARTIAL session index is WI-5b — here the index is complete, so the resolution is exact + immediate.
    jumpToSourceOffset: Int? = null,
    onJumpConsumed: () -> Unit = {},
    onContentBoxReady: (PageContentBox) -> Unit = {},
    // feature #137 WI-7a — paged text selection. When non-null, each visible page registers its rendered
    // layout + coords + PageOffsetMap with the controller (registerPage), and a long-press-drag over the
    // page begins/extends/finalizes a SOURCE selection through the ONE unified pagedTapZones classifier.
    // Defaulted null so #129/WI-6a/6b call sites + previews stay valid (selection inert). The highlight
    // WASH render on the page is WI-7b — this WI only produces the source range.
    selectionController: TxtSelectionController? = null,
    onSelectionFinalized: () -> Unit = {},
    // A settled tap → the host resolves tap-to-edit (open the edit popover if the tap hit an existing
    // highlight) and RETURNS true iff a highlight was hit, so the classifier SUPPRESSES page-turn/chrome
    // navigation for that tap (Gate-4 R1 Critical — no navigate+edit double-fire). Returns false → the tap
    // navigates (the WI-6b tap-zone behavior). Defaulted to a no-op returning false.
    onTapEditAt: (Offset) -> Boolean = { false },
    // feature #137 WI-7b — the persisted highlights whose SOURCE ranges are washed on each visible page.
    // The SAME `highlightsList` the scroll body's `washesForChunk` derives from; each page's rendered
    // `Text` gets a translucent background over every highlight intersecting that page's source extent,
    // via TxtPagedWash.washesForPage(pageMap, highlights) (clamped per page for a boundary-spanning
    // highlight). Defaulted empty so #129/WI-6a/6b/7a call sites + previews stay valid (no wash).
    highlights: List<HighlightRecord> = emptyList(),
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

    // feature #137 WI-6b — the designed page-turn affordances (30/40/30 tap-zones + first-open hint). The
    // hint's THEME + persisted seen flag are read here from the ReaderSettingsStore via the app container
    // (LocalContext) — a device-local read, no host plumbing for the hint. (The only host coupling this WI
    // adds is [onToggleChrome], so the CENTER zone reuses the host's existing chrome-visibility toggle.) The
    // theme drives ONLY the non-interactive hint overlay's colors (the pager text uses [effectiveStyle]); it
    // is NOT a re-render trigger for the page body (that keys on effectiveStyle/marginDp/contentBox).
    val appContext = LocalContext.current.applicationContext
    val appContainer = remember(appContext) {
        (appContext as com.vreader.app.VReaderApp).container
    }
    val settingsStore = appContainer.readerSettingsStore
    // The hint's theme: collected from the store's live settings (the SAME source #129 uses). Default until
    // the first emission; the hint only shows AFTER phase-1 anyway, so the theme is settled by then.
    val hintTheme by settingsStore.settings.collectAsState(null)
    // The persisted first-open gate — read ONCE per document; the hint is eligible only when NOT yet seen.
    val hintSeenInitially by produceState<Boolean?>(null, document) { value = settingsStore.tapHintSeen() }
    // Whether the hint is currently visible for THIS open. Becomes true once phase-1 publishes an index AND
    // the persisted flag says not-seen; lowered (+ persisted) on the first interaction or the auto-dismiss.
    var showHint by remember(document) { mutableStateOf(false) }
    var hintArmed by remember(document) { mutableStateOf(true) }   // guards a re-show after dismissal
    // Persist + hide the hint (idempotent). Called on the first tap OR the auto-dismiss timeline's onDone.
    // The persistence write runs on the APP scope (not a composition scope) so a dismiss-then-leave can't
    // cancel the "seen" write and let the hint reappear next open (Gate-4 R1 Low — the position-save pattern).
    val dismissHint: () -> Unit = {
        if (showHint || hintArmed) {
            showHint = false
            hintArmed = false
            appContainer.appScope.launch { settingsStore.markTapHintSeen() }
        }
    }
    // Chrome-aware content box: the paged Box's laid-out size minus the horizontal margin padding + the
    // vertical page padding (matches the scroll body's contentPadding: horizontal = marginDp, vertical
    // = 16dp). Zero until the first layout pass; a zero/degenerate box → a degenerate index → the
    // scroll fallback.
    var contentBox by remember { mutableStateOf(PageContentBox(0f, 0f)) }
    val marginPx = with(density) { marginDp.dp.toPx() }
    val vPadPx = with(density) { 16.dp.toPx() }

    // The published boundary index as COMPOSE STATE (null before the first sealed window publishes) — the
    // windowed pagination lifecycle runs off-main through the SESSION and is mirrored here so the pager
    // recomposes. The `navigator` mirrors currentPage + the offset↔page math (so the host's test seams +
    // the bookmark/search/scrubber/TTS jumps read it); this Compose-state mirror is what drives
    // recomposition (the navigator's plain fields don't). NO frame-poll loop — every programmatic scroll
    // flows through a Compose-observable target (localScrollTarget for the reflow clamp + on-demand-extend
    // landing, pendingResumeReveal for the deep-resume reveal, [jumpToSourceOffset] for an external jump),
    // so the compose-test idling resource can settle (a busy while-loop would keep it perpetually not-idle).
    var index by remember(document) { mutableStateOf<com.vreader.app.reader.paged.TxtPageIndex?>(null) }
    // The reflow clamp's / on-demand-extend landing's one-shot programmatic scroll target (an ORDINARY
    // in-range scroll — its consumer clamp-and-clears, correct because the page is within pageCount). NOT
    // used for the deep-resume reveal (that is a distinct, index-aware one-shot — pendingResumeReveal).
    var localScrollTarget by remember(document) { mutableStateOf<Int?>(null) }
    // feature #138 WI-5b — the CONDITIONAL deep-resume reveal, a one-shot DISTINCT from localScrollTarget
    // (Gate-2 R2 High 1). `pendingResumeReveal` is the resume SOURCE OFFSET the session's onReveal signalled
    // (fired ONCE when the deep anchor's page first seals in the background). A dedicated collector scrolls
    // to pageContaining(revealOffset) ONLY IF the user has not taken over AND the page is now in range —
    // NEVER clamp-and-cleared while out of range (the hazard localScrollTarget's consumer has). Dropped
    // (cleared, no scroll) once the user pages away.
    var pendingResumeReveal by remember(document) { mutableStateOf<Int?>(null) }
    // feature #138 WI-5b — the deep-resume LANDING page (Gate-2 R2 Medium-4 fallback). When the reveal
    // decides to land a DEEP anchor, it sets this to pageContaining(revealOffset) and the pager is
    // RECREATED with initialPage = resumePage (rememberPagerState keyed on it). Recreating is the robust
    // mechanism a `requestScrollToPage(farPage)` is NOT: the pager's own internal pageCount lags a fresh
    // (grown) republish by a frame, so a scroll-to-a-far-page can clamp SHORT under load (land on an
    // earlier page and never catch up) — the recreated pager is BORN on the resume page with the current
    // count, so it lands EXACTLY. null = no deep-resume landing pending.
    var resumePage by remember(document) { mutableStateOf<Int?>(null) }
    // Set true on the FIRST user-driven settled-page change (a swipe with no programmatic target pending)
    // — the reveal is dropped once the user has taken over so an auto-scroll never yanks them.
    var userInteractedSinceOpen by remember(document) { mutableStateOf(false) }
    // feature #138 WI-5b — the on-demand forward-extension target: a Compose-observable settled/target page
    // near the sealed frontier that drives session.ensureMeasuredThrough (NO busy loop — the #137
    // idling-resource lesson is binding). null = no extension pending.
    var extendThroughPage by remember(document) { mutableStateOf<Int?>(null) }
    // Whether the FIRST windowed open has captured its resume anchor yet (so a later reflow captures the
    // live page offset, not initialSourceOffset again).
    var restored by remember(document) { mutableStateOf(false) }
    // feature #138 WI-4/5b — the SESSION owns the pagination token/cancellation/generation (the body no
    // longer holds an activeToken). Owned per-document here so this WI stays within TxtReaderBody; disposed
    // (superseded) when the body leaves the composition so a background pass never publishes after teardown.
    val session = remember(document) { com.vreader.app.reader.paged.PaginationSession(paginator) }
    DisposableEffect(session) { onDispose { session.supersede() } }
    // feature #138 WI-5b — THREAD-SAFE hand-off flows. The session's onSnapshot/onReveal callbacks fire on
    // whatever coroutine context the completion loop resumes on — OBSERVED to be a Dispatchers.Default
    // worker thread for some republishes — so they must NOT write Compose state directly (a background
    // write throws "multithreaded access to SnapshotStateObserver" during a layout read). Instead they
    // publish here; a MAIN-dispatcher collector below marshals every update into Compose state + the
    // navigator. `openSeq` distinguishes a fresh open / reflow generation so the main collector clamps the
    // FIRST snapshot of the current pass exactly once.
    //
    // snapshotFlowOut is a NON-conflated buffered MutableSharedFlow (Gate-4 R2/R3 High): a StateFlow
    // conflates, so a fast republish burst could drop the true FIRST window and let a later grown snapshot
    // be mistaken for it. A large buffer + DROP_OLDEST make every off-main `tryEmit` succeed WITHOUT
    // suspending (the callback is a plain lambda that cannot suspend, and SUSPEND-overflow tryEmit silently
    // drops), so the collector drains snapshots in order and the FINAL (complete) snapshot always lands. If a
    // burst ever exceeds the buffer, DROP_OLDEST drops an INTERMEDIATE window — harmless: the frontier grows
    // monotonically, so the clamp decision (anchor sealed in the first window the collector sees) stays
    // correct (a shallow anchor is still sealed in a bigger window; a deep anchor still isn't → the reveal
    // owns it), and append-only growth + the complete snapshot are preserved.
    val snapshotFlowOut = remember(document) {
        MutableSharedFlow<com.vreader.app.reader.paged.TxtPageIndex?>(
            replay = 1, extraBufferCapacity = 256, onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )
    }
    val revealFlowOut = remember(document) { MutableStateFlow<Int?>(null) }
    val capturedAnchorFlow = remember(document) { MutableStateFlow(0) }
    var openSeq by remember(document) { mutableStateOf(0) }

    // Drive the WINDOWED pagination lifecycle OFF-MAIN whenever a reflow trigger changes (content box,
    // EFFECTIVE style, margin). The FIRST run is a fresh open (anchor = initialSourceOffset); a later run
    // with the same document but a changed style/margin/box is a REFLOW (anchor = the current page's start,
    // and ONLY a reflow clears the render cache — a background APPEND never does, since it only appends
    // SEALED pages and never renumbers a published page — Gate-2 R1 High 3). The session's openFromStart
    // supersedes any in-flight pass (its generation token), publishes the FIRST sealed window fast (loading
    // clears in < 2 s instead of ~85 s), then background-completes; each republish grows the SEALED
    // pageCount (append-only, never shrinks). The callbacks publish into the thread-safe hand-off flows;
    // the MAIN collector below mirrors them into Compose state + the navigator. Uses [effectiveStyle] — the
    // SAME style the page renders with.
    LaunchedEffect(contentBox, effectiveStyle, marginDp, document) {
        if (contentBox.widthPx <= 0f || contentBox.heightPx <= 0f) return@LaunchedEffect
        onContentBoxReady(contentBox)
        val isReflow = restored
        val captured = if (!isReflow) initialSourceOffset else navigator.currentSourceOffset()
        // A reflow renumbers pages → the page-number-keyed render cache is invalid; clear it (ONLY here).
        // A fresh open starts with an empty cache anyway; the harmless clear keeps the first-open path
        // identical to the reflow path. A background APPEND (in the snapshot collector) NEVER clears it.
        renderCache.clear()
        // Reset the hand-off + reveal + interaction state for this new pass, then bump the sequence so the
        // main collector clamps the FIRST snapshot of THIS pass exactly once (a reflow keeps `index`
        // non-null, so an `index == null` guard could not distinguish a reflow's first snapshot).
        pendingResumeReveal = null
        userInteractedSinceOpen = false
        capturedAnchorFlow.value = captured
        // Reset BOTH hand-off flows to null for the new pass BEFORE bumping openSeq (Gate-4 High-1): the
        // snapshot collector restarts on the openSeq change and re-emits the flow's CURRENT value — without
        // this reset it would replay the PREVIOUS generation's last snapshot, consuming the once-per-pass
        // clamp on stale data. A null is ignored by the collector, so the first NON-null it sees is genuinely
        // this pass's first window.
        snapshotFlowOut.tryEmit(null)
        revealFlowOut.value = null
        openSeq += 1
        // NOTE `restored` is NOT set here. It flips to true only once the FIRST pass's resume anchor has
        // actually LANDED (the main snapshot collector's clamp, the reveal collector's scroll, or index
        // completion) — see below. A spurious contentBox jitter (a second layout pass firing this effect
        // before the deep resume lands) must still re-capture `initialSourceOffset`, NOT the pre-restore
        // page-0 offset — flipping `restored` before the restore lands would lose a deep resume (a WI-5b
        // regression). Setting it after the suspend call is also unsafe (openFromStart may resume off-main).
        session.openFromStart(
            document = document, style = effectiveStyle, contentBox = contentBox, measurer = measurer,
            isMarkdown = isMarkdown, resumeAnchorOffset = captured,
            // Off-main-safe: publish into the thread-safe flows ONLY (no Compose-state write here; the
            // callbacks may fire on a worker thread — the main collector marshals them into Compose state).
            onSnapshot = { snapshot -> snapshotFlowOut.tryEmit(snapshot) },
            onReveal = { revealOffset -> revealFlowOut.value = revealOffset },
        )
    }

    // feature #138 WI-5b — the MAIN-thread snapshot collector: marshal every session republish (published
    // off-main into snapshotFlowOut) into the navigator + Compose `index` state, and clamp the FIRST
    // snapshot of the current open/reflow pass to the resume anchor's page IFF the anchor is already SEALED
    // in that window (the SHALLOW case). A DEEP anchor short of the first window is landed by the reveal
    // collector when its page seals — never a progressive clamp that races the reveal (two competing
    // scrolls to the same growing page settle short — the defect that made a deep resume land on the
    // last-sealed page). `openSeq` gates the once-per-pass clamp.
    var clampedForSeq by remember(document) { mutableStateOf(-1) }
    LaunchedEffect(snapshotFlowOut, openSeq) {
        snapshotFlowOut.collect { snapshot ->
            if (snapshot == null) return@collect
            // Append-only guard (Gate-4 Medium): WITHIN a pass the sealed count only GROWS. An on-demand
            // ensureMeasuredThrough returns a snapshot captured before a concurrent background append may
            // have advanced further, so installing it could transiently SHRINK pageCount. Drop a snapshot
            // that is smaller than the one already installed for THIS pass (never on the pass's FIRST
            // snapshot — a reflow legitimately replaces the index with a possibly-smaller count).
            if (clampedForSeq == openSeq && !snapshot.isComplete) {
                val current = index
                if (current != null && !current.isDegenerate && snapshot.pageCount < current.pageCount) return@collect
            }
            navigator.setIndex(snapshot)
            index = snapshot
            // The clamp decision is made EXACTLY ONCE per pass, on the FIRST published snapshot of that pass
            // (the first window). A SHALLOW anchor (in that first window) is clamped here; a DEEP anchor
            // short of the first window is NOT clamped here — the reveal collector owns it EXCLUSIVELY
            // (Gate-2 R2 High 1). Either way `clampedForSeq` is marked done so a LATER (grown) snapshot never
            // re-runs this and competes with the reveal (the defect that landed a deep resume on a
            // clamped-to-a-wrong-window page). `openSeq` gates it per open/reflow pass.
            if (clampedForSeq != openSeq) {
                clampedForSeq = openSeq
                val captured = capturedAnchorFlow.value
                val anchorSealedInFirstWindow = snapshot.isComplete ||
                    (snapshot.pageCount > 0 && captured.coerceAtLeast(0) < snapshot.frontierSourceOffset)
                if (anchorSealedInFirstWindow) {
                    val target = snapshot.pageContaining(captured)
                    navigator.onPagerPageChanged(target)
                    localScrollTarget = target
                    // A SHALLOW anchor is now clamped → the first pass has RESTORED. A later contentBox change
                    // is now a genuine reflow (it captures the live page, not the anchor). A DEEP anchor's
                    // `restored` flip is owned by the reveal collector (below) so a spurious re-layout before
                    // the deep resume lands does NOT re-capture the pre-restore page-0 offset (WI-5b regression).
                    restored = true
                }
            }
        }
    }
    // feature #138 WI-5b — marshal the session's onReveal signal (off-main → revealFlowOut) into the
    // Compose `pendingResumeReveal` one-shot on the main thread; the dedicated reveal collector consumes it.
    LaunchedEffect(revealFlowOut) {
        revealFlowOut.collect { r -> if (r != null) pendingResumeReveal = r }
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
                // feature #138 WI-5b — the SEALED count GROWS over the life of this open (append-only). The
                // pager must re-read the LIVE count, not the value captured at first composition: a plain
                // `pageCount = { pageCount }` lambda closes over the FIRST recomposition's local val, so page
                // turns near the frontier could clamp to a stale count. rememberUpdatedState feeds the live
                // count into the pager's pageCount lambda so it always returns the current value.
                val livePageCount by rememberUpdatedState(pageCount)
                // feature #138 WI-5b — the pager is RECREATED (keyed on resumePage) when a DEEP resume lands:
                // its initialPage becomes the resume page, so it is BORN on that page with the current grown
                // count (the Gate-2 R2 Medium-4 fallback). This is robust where a requestScrollToPage(farPage)
                // is not — a far scroll clamps to the pager's own (frame-lagged) internal count and can settle
                // SHORT under load. When resumePage is null the pager keys only on the document (stable across
                // the growing count — an append never recreates it, so no yank).
                val pagerState = key(resumePage) {
                    rememberPagerState(
                        initialPage = (resumePage ?: navigator.currentPage).coerceIn(0, (pageCount - 1).coerceAtLeast(0)),
                        pageCount = { livePageCount },
                    )
                }
                // feature #137 WI-6b — the page-turn scope + the tap-zone page-turn helpers. A LEFT/RIGHT
                // zone tap animates the pager one page (the design's pager.animateScrollToPage(current±1)),
                // clamped to the valid range.
                val pagerScope = rememberCoroutineScope()
                val turnPrev: () -> Unit = {
                    val to = (pagerState.currentPage - 1).coerceAtLeast(0)
                    if (to != pagerState.currentPage) pagerScope.launch { runCatching { pagerState.animateScrollToPage(to) } }
                }
                val turnNext: () -> Unit = {
                    val to = (pagerState.currentPage + 1).coerceAtMost((pageCount - 1).coerceAtLeast(0))
                    if (to != pagerState.currentPage) pagerScope.launch { runCatching { pagerState.animateScrollToPage(to) } }
                }
                // The pagedTapZones modifier's pointerInput does NOT restart on recomposition (keyed on
                // isRtl only) — so wrap the turn / toggle / first-interaction callbacks in
                // rememberUpdatedState (the codebase's TxtBody pattern) and hand pagedTapZones STABLE
                // trampolines that always invoke the LIVE closure. Without this, a font/margin/rotation
                // reflow (a new pageCount + new turnNext closure) would leave the gesture calling the stale
                // clamp from the first pagination (Gate-4 R1 Medium).
                val liveTurnPrev by rememberUpdatedState(turnPrev)
                val liveTurnNext by rememberUpdatedState(turnNext)
                val liveToggleChrome by rememberUpdatedState(onToggleChrome)
                val liveDismissHint by rememberUpdatedState(dismissHint)
                // feature #137 WI-7a — live selection closures for the unified pagedTapZones classifier
                // (stable pointerInput → read the live closures through rememberUpdatedState). The
                // tap-to-edit trampoline forwards to [onTapEditAt], which the host implements to (a) open the
                // edit popover when the tap lands on an existing highlight and (b) RETURN true so navigation
                // is suppressed for that tap. Returns false (tap navigates) when no highlight is hit — which
                // is always the case in WI-7a (on-page washes are WI-7b), so taps navigate exactly as WI-6b.
                val liveSelFinalize by rememberUpdatedState(onSelectionFinalized)
                val liveTapForEdit by rememberUpdatedState(onTapEditAt)
                // Arm the first-open hint ONCE the paged surface exists AND the persisted flag says not-seen.
                // (The hint shows over the real pager, never the loading/degenerate surfaces.) Auto-lowered
                // by the hint's own timeline (onDone → dismissHint) or the first tap.
                LaunchedEffect(hintSeenInitially, hintArmed) {
                    if (hintSeenInitially == false && hintArmed) showHint = true
                }
                // A user swipe reports the settled page back to the navigator (so the save seam + a later
                // reflow see the right anchor). Only settled pages (not a mid-drag target) update state.
                // Skip the SAVE while a programmatic scroll is still pending (a reflow just published a new
                // index and is about to clamp the pager to the reconciled page): saving the pre-clamp
                // settled page would briefly persist the wrong page under the new index (Gate-4 Low). The
                // clamp's own scroll settles and saves the correct page immediately after.
                //
                // feature #138 WI-5b — this collector ALSO (a) marks userInteractedSinceOpen on the FIRST
                // user-driven settle so the deep-resume reveal is dropped once the user has taken over
                // (Gate-2 R2 High 1 — a settle with NO pending programmatic target is user-driven; a reflow
                // clamp / on-demand-extend landing sets localScrollTarget, the deep-resume reveal is a
                // separate one-shot), and (b) arms on-demand forward EXTENSION when the settled page nears
                // the sealed frontier of a PARTIAL index (extendThroughPage — a Compose-observable target,
                // NO busy loop; the #137 idling-resource lesson).
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { pagerState.settledPage }.collect { settled ->
                        // A settle is PROGRAMMATIC (not a user swipe) while a reflow clamp / on-demand-extend
                        // scroll is queued (localScrollTarget) OR a deep-resume pager RECREATION is in flight
                        // (resumePage != null — the recreated pager is BORN on that page, so its first settle
                        // there is programmatic, not a swipe). NOTE it is NOT keyed on `pendingResumeReveal`
                        // (Gate-4 High-2): while the reveal is merely ARMED-and-waiting (the anchor not yet
                        // sealed) the pager still sits on page 0, so a REAL user swipe in that window must
                        // register + drop the reveal — suppressing it would let the reveal later yank the user.
                        val recreationSettled = resumePage != null && settled == resumePage
                        val programmaticPending = localScrollTarget != null || (resumePage != null && !recreationSettled)
                        navigator.onPagerPageChanged(settled)
                        if (recreationSettled) {
                            // The deep-resume recreation has LANDED on its page → the first pass is now RESTORED
                            // (Gate-4 R2: restored flips only after the resume lands), clear resumePage so a
                            // later user swipe is no longer masked, and persist the resumed page.
                            resumePage = null
                            restored = true
                            onSaveSourceOffset(navigator.currentSourceOffset())
                        } else if (!programmaticPending) {
                            onSaveSourceOffset(navigator.currentSourceOffset())
                            // A settle with no pending programmatic scroll is a user swipe → the user has taken
                            // over; a still-pending deep-resume reveal is DROPPED by the reveal collector (no
                            // yank) once it sees userInteractedSinceOpen.
                            if (settled > 0) userInteractedSinceOpen = true
                        }
                        // Arm on-demand extension when nearing the frontier of a PARTIAL index (append-only;
                        // a complete index needs none). The collector below coalesces this into the session.
                        val live = index
                        if (live != null && !live.isComplete && settled >= live.pageCount - 1 - EXTEND_MARGIN) {
                            extendThroughPage = settled
                        }
                    }
                }
                // feature #138 WI-5b — the CONDITIONAL deep-resume reveal collector (Gate-2 R2 High 1), a
                // one-shot DISTINCT from localScrollTarget: `pendingResumeReveal` is the resume SOURCE OFFSET
                // the session armed once the deep anchor's page first sealed. This collector re-runs on every
                // index publish (keyed on idx) and:
                //   • DROPS the reveal (no yank) the instant the user has taken over (userInteractedSinceOpen);
                //   • LEAVES it pending while the offset is still beyond the published frontier (never lands on
                //     a clamped last-sealed page — the hazard localScrollTarget's consumer has);
                //   • once the offset is genuinely sealed AND the pager is still on the doc-start page 0, LANDS
                //     the deep resume by RECREATING the pager on pageContaining(offset) (setting `resumePage`
                //     → the pager is reborn there with the current grown count). Recreation is robust where a
                //     far scroll is not: a requestScrollToPage(farPage) clamps to the pager's frame-lagged
                //     internal count and can settle SHORT under load; a pager BORN on the resume page lands
                //     exactly. One-shot (cleared after it acts), so it never fights the user or overshoots.
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { pendingResumeReveal }.collect { reveal ->
                        if (reveal == null) return@collect
                        if (userInteractedSinceOpen) {
                            pendingResumeReveal = null            // dropped — the user has taken over (no yank)
                            restored = true                        // the user drove the page → first pass done
                            return@collect
                        }
                        val live = index ?: return@collect
                        // In range ONLY when the offset is genuinely sealed (within the frontier of a partial
                        // index, or anywhere in a complete one) — never LAND on a clamped page.
                        val sealedThrough = live.isComplete ||
                            (live.pageCount > 0 && reveal.coerceAtLeast(0) < live.frontierSourceOffset)
                        if (!sealedThrough) return@collect            // leave pending; a later grown publish resolves it
                        val target = live.pageContaining(reveal)
                        pendingResumeReveal = null                    // one-shot: consumed (landed or a no-op at 0)
                        // Also DROP the reveal if the user has an IN-PROGRESS drag from page 0 (Gate-4 R3
                        // Medium): userInteractedSinceOpen is only set once a swipe SETTLES on a non-zero
                        // page, so a drag that begins right as the anchor seals — before settledPage changes —
                        // would otherwise be overridden by the recreation. isScrollInProgress catches that.
                        if (target > 0 && pagerState.currentPage == 0 && !pagerState.isScrollInProgress) {
                            // Land the DEEP resume by RECREATING the pager on the resume page (Gate-2 R2
                            // Medium-4) rather than scrolling — a far scroll clamps to the pager's frame-lagged
                            // internal count and can settle short under load. Reflect the page in the navigator
                            // + persist it; the pager is reborn on `resumePage` with the current grown count.
                            // `restored` is NOT flipped here — it flips only when the recreation SETTLES on its
                            // page (the recreationSettled branch of the settled collector — Gate-4 R2), so the
                            // invariant "restored flips only after the resume LANDS" holds and a spurious reflow
                            // in the interim still re-captures the resume offset (via onPagerPageChanged above).
                            navigator.onPagerPageChanged(target)
                            resumePage = target
                            onSaveSourceOffset(navigator.currentSourceOffset())
                        } else {
                            // A no-op reveal (offset resolves to page 0, or the user already left page 0): there
                            // is no recreation to await, so the first pass is RESTORED immediately.
                            restored = true
                        }
                    }
                }
                // feature #138 WI-5b — on-demand forward extension: when the reader nears the sealed frontier
                // (extendThroughPage armed above), extend the session past that page's start offset. NO
                // busy/frame-poll loop (the #137 idling-resource lesson is binding) — a Compose-observable
                // target drives ONE coalesced ensureMeasuredThrough per arming; the growing snapshot flows
                // back through openFromStart's onSnapshot (published via the session), which the pager
                // re-reads. No loading affordance for a far extend (Gate-2 R2 Medium 3): the reader stays on
                // the current page and the pages seal EVENTUALLY.
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { extendThroughPage }.collect { page ->
                        if (page == null) return@collect
                        val live = index
                        if (live != null && !live.isComplete) {
                            // Measure THROUGH one page past the armed page's start so the successor seals too
                            // (the +1-page lookahead the seal discipline needs to advance the frontier).
                            val throughOffset = live.pageEndExclusive(page.coerceIn(0, (live.pageCount - 1).coerceAtLeast(0)))
                            val extended = session.ensureMeasuredThrough(throughOffset)
                            // ensureMeasuredThrough hops to the measure dispatcher internally; publish the
                            // grown snapshot into the THREAD-SAFE hand-off flow so the MAIN collector mirrors
                            // it into Compose state + the navigator (never a background Compose-state write).
                            snapshotFlowOut.tryEmit(extended)
                        }
                        extendThroughPage = null
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
                        if (clamped != pagerState.currentPage) {
                            // feature #138 WI-5b — the WINDOWED lifecycle republishes rapidly (the background
                            // completion loop grows the count every few frames), so this clamp can fire while
                            // the pager is mid-measure — a direct suspend scrollToPage then throws
                            // "performMeasureAndLayout called during measure layout". requestScrollToPage
                            // SCHEDULES the jump for the next layout pass (it never performs layout itself), so
                            // it is safe to call during composition/layout + never re-enters (no busy loop).
                            runCatching { pagerState.requestScrollToPage(clamped) }
                        }
                        localScrollTarget = null
                        // After the clamp settles, persist the reconciled page's start offset (the save was
                        // suppressed while the target was pending).
                        onSaveSourceOffset(navigator.currentSourceOffset())
                    }
                }
                // feature #138 WI-5a/5b — an EXTERNAL jump raised as a SOURCE OFFSET (the test-seam page
                // turn / the bookmark / annotation / search-hit / scrubber / TTS-follow feeders): the host
                // raises [jumpToSourceOffset] (a raw source-UTF-16 offset); we resolve it through the
                // navigator's async `jumpToOffset(offset, session)` overload. Within the SEALED region it is
                // the synchronous path; BEYOND the sealed frontier of a PARTIAL session index it
                // session.ensureMeasuredThrough(offset) FIRST (off-main, coalesced with the background loop),
                // installs the extended snapshot, THEN resolves the page — the landing is EVENTUAL for a
                // beyond-frontier offset (Gate-2 R2 Medium 3); the reader stays on the current page meanwhile
                // and there is NO loading affordance. We then mirror the (possibly-extended) index into
                // Compose state, scroll the pager, persist the new page-start offset, and clear the request.
                // `jumpToSourceOffset` is a plain parameter — read it through rememberUpdatedState so the
                // snapshotFlow reacts to a NEW value even though this LaunchedEffect (keyed pagerState/idx)
                // never restarts (a bare `snapshotFlow { jumpToSourceOffset }` would capture the stale first).
                val liveJumpToSourceOffset by rememberUpdatedState(jumpToSourceOffset)
                LaunchedEffect(pagerState, idx) {
                    snapshotFlow { liveJumpToSourceOffset }.collect { offset ->
                        if (offset == null) return@collect
                        // Extend-then-resolve: BEYOND the sealed frontier of a PARTIAL index, measure through
                        // the offset FIRST (off-main, coalesced with the background loop) — the landing is
                        // EVENTUAL (Gate-2 R2 Medium 3), the reader stays on the current page meanwhile, NO
                        // loading affordance. ensureMeasuredThrough may resume this coroutine off-main, so
                        // marshal ALL the index-install + resolve + scroll onto MAIN (`withContext(Main)`) —
                        // installing the grown snapshot into the navigator + Compose state THERE, then
                        // resolving over it (no background Compose-state write; no race with the async
                        // snapshot collector — this jump owns its own install atomically on main).
                        val live = navigator.index
                        val extended = if (live != null && !live.isComplete && offset >= live.frontierSourceOffset) {
                            session.ensureMeasuredThrough(offset)
                        } else null
                        withContext(Dispatchers.Main) {
                            // Install the extended snapshot only if it does NOT shrink the count (Gate-4
                            // Medium — a concurrent background append may have grown past what
                            // ensureMeasuredThrough returned); the newer (larger) snapshot the background
                            // collector installs still covers this offset, so resolving over `navigator.index`
                            // stays correct either way.
                            if (extended != null) {
                                val cur = navigator.index
                                if (cur == null || cur.isDegenerate || extended.pageCount >= cur.pageCount) {
                                    navigator.setIndex(extended); index = extended
                                }
                            }
                            navigator.jumpToOffset(offset)
                            val target = navigator.consumePendingScrollTarget() ?: navigator.pageContaining(offset)
                            if (target != pagerState.currentPage) {
                                // requestScrollToPage schedules the jump for the next layout (never performs
                                // layout itself) — safe during a growing-count republish's mid-measure window,
                                // where a direct scrollToPage throws "performMeasureAndLayout called during
                                // measure layout".
                                runCatching { pagerState.requestScrollToPage(target) }
                            }
                            onSaveSourceOffset(navigator.currentSourceOffset())
                            onJumpConsumed()
                        }
                    }
                }

                HorizontalPager(
                    state = pagerState,
                    // feature #137 WI-6b + WI-7a — ONE unified pagedTapZones classifier on the pager: a
                    // LONG-PRESS starts a source selection (begin+drag+finalize) and NEVER turns a page; a
                    // horizontal SWIPE is a drag the HorizontalPager handles natively (the classifier bows
                    // out on the cancelled long-press); a SETTLED tap resolves tap-to-edit first, else the
                    // 30/40/30 zones (LEFT→prev, RIGHT→next, CENTER→chrome). ANY down dismisses the hint.
                    // The pager also publishes its LayoutCoordinates as the controller's lazyCoords, so the
                    // classifier's pager-local pointer positions convert to window space correctly.
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("txt-pager")
                        .onGloballyPositioned { selectionController?.setLazyCoords(it) }
                        .pagedTapZones(
                            // Stable trampolines → the LIVE closures (rememberUpdatedState) so a reflow's
                            // new pageCount/callbacks are always used even though the pointerInput never
                            // restarts.
                            onPrevPage = { liveTurnPrev() },
                            onNextPage = { liveTurnNext() },
                            onToggleChrome = { liveToggleChrome() },
                            onFirstInteraction = { liveDismissHint() },
                            isRtl = layoutDirection == androidx.compose.ui.unit.LayoutDirection.Rtl,
                            // feature #137 WI-7a — the selection branch of the unified classifier.
                            onSelectLongPress = { p -> selectionController?.beginAt(p) },
                            onSelectDragTo = { p -> selectionController?.extendTo(p) },
                            onSelectFinalize = { liveSelFinalize() },
                            onSelectCancel = { selectionController?.clear() },
                            onTapForEdit = { p -> liveTapForEdit(p) },
                        ),
                    // Bound the rendered window: HorizontalPager keeps ± beyondViewportPageCount pages
                    // COMPOSED; combined with the LRU render cache the whole book is never rendered.
                    beyondViewportPageCount = 1,
                ) { page ->
                    // Lazily render THIS page through the UI mapper; hold BOTH the rendered text and its
                    // per-page PageOffsetMap in the small LRU cache so an off-screen page is evicted
                    // (memory-bounded — the scroll body's LRU posture, page-scoped). The map is WI-7a's
                    // selection bridge (page-local rendered ↔ GLOBAL source); it is rendered + evicted with
                    // the text so a visible page's map always matches its rendered text.
                    val (rendered: AnnotatedString, pageMap: PageOffsetMap) = remember(page, idx, mapper) {
                        renderCache.getOrRenderPage(page) {
                            paginator.renderPage(document, idx, page, mapper, effectiveStyle, isMarkdown)
                        }
                    }
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(horizontal = marginDp.dp, vertical = 16.dp),
                    ) {
                        // feature #137 WI-7a — register THIS page's rendered layout + coords + map with the
                        // selection controller so a long-press-drag over it resolves to a SOURCE range; the
                        // registration replaces on re-render and is DISPOSED when the page leaves the pager
                        // window (beyondViewportPageCount eviction) so a stale off-screen TextLayoutResult is
                        // never consulted. Inert when there is no controller (WI-6a/6b call sites).
                        var pageLayout by remember(page, idx) { mutableStateOf<TextLayoutResult?>(null) }
                        var pageCoords by remember(page, idx) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
                        if (selectionController != null) {
                            // Key registration on the controller TOO (Gate-4 Medium): if the controller
                            // instance changes while the same page/layout/map stays composed, the old
                            // controller is unregistered (below) and the new one MUST re-register.
                            LaunchedEffect(selectionController, page, pageLayout, pageCoords, pageMap) {
                                val l = pageLayout; val c = pageCoords
                                if (l != null && c != null) selectionController.registerPage(page, l, c, pageMap)
                            }
                            DisposableEffect(selectionController, page) { onDispose { selectionController.unregisterPage(page) } }
                        }
                        // feature #137 WI-7b — the persisted-highlight WASH for THIS page: project every
                        // highlight whose SOURCE range intersects the page onto page-local rendered spans via
                        // the page's map (boundary-spanning highlights clamp per page). Recomputed only when
                        // the map or the highlight set changes, then painted BEHIND the page Text through
                        // drawBehind (getPathForRange, the same mechanism the scroll body uses) — a live
                        // redraw when a highlight is added/edited/removed (highlights is Compose state upstream).
                        val pageWashes = remember(pageMap, highlights) {
                            TxtPagedWash.washesForPage(pageMap, highlights)
                        }
                        // Capture the layout whenever it is needed downstream (selection OR wash) so the wash
                        // has a TextLayoutResult to paint against even on a non-annotatable (no-controller) open.
                        val needsLayout = selectionController != null || pageWashes.isNotEmpty()
                        Text(
                            text = rendered,
                            // The SAME effective style phase-1 measured against (deterministic breaks).
                            style = effectiveStyle,
                            onTextLayout = { if (needsLayout) pageLayout = it },
                            modifier = Modifier
                                .fillMaxSize()
                                .testTag("txt-page-$page")
                                .onGloballyPositioned { if (selectionController != null) pageCoords = it }
                                .drawBehind {
                                    if (pageWashes.isNotEmpty()) pageLayout?.let { drawWashes(it, pageWashes) }
                                },
                        )
                    }
                }
                // feature #137 WI-6b — the first-open discoverability hint, overlaid on the pager (a
                // NON-interactive overlay — see TapZoneHint; it never steals a tap). Rendered only while
                // showHint; its own timeline (or the first tap) lowers it + persists the seen flag. The
                // theme comes from the live Display settings (settled by the time phase-1 finishes); until
                // the first emission the hint waits (showHint is only armed after the index publishes).
                val theme = hintTheme?.theme
                if (showHint && theme != null) {
                    TapZoneHint(theme = theme, visible = showHint, onDone = dismissHint)
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
 * Feature #137 WI-7b — the PAGE-scoped analog of [TxtWashMapper.washesByChunk]. Projects each stored
 * highlight's SOURCE range onto ONE rendered page as page-LOCAL rendered [WashSpan]s via the page's
 * [PageOffsetMap.sourceRangeToRendered]. The map clamps a highlight that starts before / ends after the
 * page to the page's rendered extent, so a highlight spanning a page boundary washes correctly on each
 * covered page (each call sees only that page's map). A highlight without a TXT char range, or an
 * empty/inverted range, is skipped; an MD marker-only source slice maps to an EMPTY rendered range and
 * draws nothing (parity with the scroll [TxtWashMapper]). Pure — no Compose; the JVM `TxtPagedWashTest`
 * covers the range math.
 */
object TxtPagedWash {
    fun washesForPage(map: PageOffsetMap, highlights: List<HighlightRecord>): List<WashSpan> {
        val out = ArrayList<WashSpan>(highlights.size)
        for (h in highlights) {
            val s = h.locator.charRangeStartUTF16 ?: continue
            val e = h.locator.charRangeEndUTF16 ?: continue
            if (e <= s) continue
            val rendered = map.sourceRangeToRendered(Utf16Range(s, e)) ?: continue
            if (rendered.isEmpty) continue
            out.add(WashSpan(rendered, h.color))
        }
        return out
    }
}

/**
 * A tiny page → rendered (AnnotatedString + PageOffsetMap) LRU (feature #137 WI-6a; the map added WI-7a)
 * so the paged body holds only a small window of rendered pages (the current ± a couple that
 * HorizontalPager composes), never the whole book. The text AND its per-page PageOffsetMap are rendered
 * together (one renderPage call) and evicted together, so a visible page's selection map is always the one
 * matching its rendered text (no drift). NOT thread-safe — accessed only on the main thread (the
 * page-render composables run there). [maxCached] bounds the retained pages (default 6 — a couple beyond
 * the pager's composed window).
 */
class PagedRenderCache(private val maxCached: Int = 6) {
    private val cache = object : LinkedHashMap<Int, Pair<AnnotatedString, PageOffsetMap>>(maxCached.coerceAtLeast(1), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Int, Pair<AnnotatedString, PageOffsetMap>>): Boolean = size > maxCached
    }

    /** The rendered (text, map) for [page], rendering + caching it (LRU) on a miss. */
    fun getOrRenderPage(page: Int, render: () -> Pair<AnnotatedString, PageOffsetMap>): Pair<AnnotatedString, PageOffsetMap> =
        cache.getOrPut(page, render)

    /** Test/host visibility into the retained-page count (proves the window stays bounded). */
    val size: Int get() = cache.size

    /** Drop every cached page (a reflow invalidates page numbers → their rendered text + map must be rebuilt). */
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
    // The EFFECTIVE style — the material default merged with the Display settings' [textStyle] (the
    // pre-#129 explicit-param behavior, so platform text defaults like letterSpacing are kept). Hoisted
    // out of the item loop so the #156 heading variant below is derived once, not per chunk.
    val effectiveStyle = LocalTextStyle.current.merge(textStyle)
    // feature #156 WI-1 — the SCROLL-mode Markdown heading variant. Scroll renders ONE Text per chunk,
    // so a chunk that is an ATX heading can carry its own paragraph alignment; a WRAPPING heading would
    // otherwise be stretched flush on both edges and read as body prose. Derived once per style (a
    // per-item `copy()` would allocate on every chunk). Paged mode has no equivalent seam — a page
    // slice spanning several chunks renders as ONE Text with ONE alignment (plan §5.2b).
    val headingStyle = remember(effectiveStyle) { effectiveStyle.copy(textAlign = chunkTextAlign(isHeadingChunk = true)) }
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
                // feature #156 WI-1 — an MD heading chunk renders with the natural-alignment variant;
                // every other chunk uses the justified body style. `isHeadingChunk` is the SAME ATX
                // predicate MarkdownRenderer took the heading branch on, so alignment and rendering
                // cannot disagree about what a heading is.
                style = if (isMarkdown && MarkdownRenderer.isHeadingChunk(raw)) headingStyle else effectiveStyle,
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
