// Purpose: the MAIN-THREAD controller for an AZW3/MOBI/KF8 reading session. Owns a WebView + the
// secure FoliateBridge, drives the open → restore → render → navigate flow, and exposes the reading
// state + the latest position (main-thread-owned, so the Activity's onStop can flush synchronously).
// All methods are main-thread only (WebView is). Feature #126 WI-4; feature #140 WI-6 carries the
// book's table of contents out on [Azw3DocState.Loaded] so the host can build its Contents rows.
package com.vreader.app.reader.foliate

import android.content.Context
import android.webkit.WebView
import androidx.annotation.MainThread
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.launch
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.File

/** What the reader UI shows for a Foliate session. */
sealed interface Azw3DocState {
    data object Loading : Azw3DocState
    /** This device's System WebView is too old for the secure bridge (`addWebMessageListener`). */
    data object WebViewUnsupported : Azw3DocState
    /**
     * The book opened + rendered; `sectionTotal` spine items.
     *
     * [toc] is the book's table of contents exactly as `book-ready` delivered it (feature #140 WI-6) —
     * the nested `{label, href, subitems}` tree [FoliateTocParser] already bounded. It rides the STATE
     * rather than a separate callback because it arrives with, and is only meaningful alongside, a
     * loaded book. Empty means "no usable TOC" (absent / malformed / over the entry cap), which the
     * host turns into an empty `tocEntries` and the chrome into a hidden Contents control. Defaulted
     * so every pre-#140 construction site still compiles.
     */
    data class Loaded(val sectionTotal: Int, val toc: List<FoliateTocItem> = emptyList()) : Azw3DocState
    /** The book parsed but had no readable sections. */
    data object Empty : Azw3DocState
    /** The book could not be opened/parsed (corrupt / unsupported / JS error before book-ready). */
    data object Corrupt : Azw3DocState
}

@MainThread
class Azw3Document(
    private val webView: WebView,
    bookFile: File,
    context: Context,
) {
    private val bridge = FoliateBridge(webView, FoliateAssetServer.loader(context, bookFile))

    private val _state = MutableStateFlow<Azw3DocState>(Azw3DocState.Loading)
    val state: StateFlow<Azw3DocState> = _state.asStateFlow()

    /** The latest position foliate reported, main-thread-owned so onStop can flush it synchronously. */
    var latestRelocate: FoliateMessage.Relocate? = null
        private set

    /** Fired on every relocate (main thread) — the host persists the position. */
    var onRelocate: ((FoliateMessage.Relocate) -> Unit)? = null

    /** Fired when the render process dies — the host recreates the WebView + document (resume). */
    var onRenderProcessGone: (() -> Unit)? = null

    private var bookReady = false
    private var restore: VReaderLocator? = null
    /** The latest Display CSS to (re)apply once the book is rendered — set before/after book-ready. */
    private var pendingStylesCss: String? = null

    /** feature #135 WI-2 — the awaited-goTo controller (CFI-first→fraction target + ack mapping). */
    private val goToController = FoliateGoToController(bridge.goToDispatcher)

    /**
     * feature #135 WI-2 — a goTo target awaiting a render (the book isn't ready yet, or the render
     * process died mid-jump). Re-issued EXACTLY ONCE after the next book-ready so a bookmark jump
     * survives a renderer restart without an infinite re-issue loop. Main-thread-owned.
     *
     * IMPORTANT (Gate-4 F2): render-death recovery in the host (`Azw3ReaderActivity`, wired by WI-7)
     * DISPOSES this document and creates a fresh one — so an in-document field alone does NOT survive
     * that path. The host carries the pending target across recreation via [takePendingGoTo] (read on
     * the dying instance) → [run]'s `pendingGoTo` argument (seeded on the replacement), mirroring how
     * `resume`/`restore` already survive. The in-document re-issue at book-ready covers the case where
     * the SAME instance receives a fresh book-ready (e.g. an in-place reopen).
     */
    private var pendingGoTo: Locator? = null

    /** The scope [run] collects on — used to re-issue a render-death-pending goTo. Set in [run]. */
    private var reissueScope: CoroutineScope? = null

    /**
     * feature #135 WI-2 — the host reads + CLEARS the pending goTo target from a dying document during
     * render-death recovery, then seeds it into the replacement via [run]'s `pendingGoTo` argument, so
     * an in-flight bookmark jump survives the document recreation (Gate-4 F2). Main-thread only.
     */
    fun takePendingGoTo(): Locator? = pendingGoTo.also { pendingGoTo = null }

    /**
     * Wire the bridge and load, then SUSPEND collecting messages until cancelled. Call from a
     * HOLDER-SCOPED `LaunchedEffect` on the Main dispatcher (WebView is main-thread-only) so a reload
     * / dispose cancels the collector and never retains the old document/bridge/WebView. The
     * `onSubscription { load() }` guarantees the collector is subscribed BEFORE the bundle emits (no
     * hot-flow race), so `bridge-ready`/`book-ready` are never missed.
     *
     * [pendingGoTo] (feature #135 WI-2) seeds a bookmark jump the host carried across a render-death
     * recreation — it is re-issued EXACTLY ONCE after this instance's book-ready.
     */
    suspend fun run(restore: VReaderLocator?, pendingGoTo: Locator? = null) {
        this.restore = restore
        this.pendingGoTo = pendingGoTo
        reissueScope = CoroutineScope(currentCoroutineContext())
        bridge.onWebViewUnsupported = { _state.value = Azw3DocState.WebViewUnsupported }
        bridge.onRenderProcessGone = { onRenderProcessGone?.invoke(); true } // survive; host recreates
        bridge.attach()
        bridge.messages.onSubscription { bridge.load() }.collect(::handle)
    }

    private fun handle(message: FoliateMessage) {
        when (message) {
            FoliateMessage.BridgeReady -> bridge.openBook()
            is FoliateMessage.BookReady -> {
                bookReady = true
                restoreOrInit()
                // Re-apply the latest Display CSS now the renderer exists (a setStyles issued before
                // book-ready would be a no-op — view.renderer isn't wired yet).
                pendingStylesCss?.let(bridge::setStyles)
                // feature #140 WI-6 — carry the book's TOC out with the Loaded state; the host builds
                // the Contents rows from it. A book with no TOC yields an empty list, never an error.
                _state.value = if (message.sectionTotal > 0) {
                    Azw3DocState.Loaded(message.sectionTotal, message.toc)
                } else {
                    Azw3DocState.Empty
                }
                // Re-issue a goTo that was pending across a render restart, EXACTLY ONCE (clear the
                // field before re-issuing so a second render-death doesn't loop it forever). Fire and
                // forget — the host's own goTo() already returned; this only re-lands the position.
                pendingGoTo?.let { target ->
                    pendingGoTo = null
                    reissueScope?.launch { goToController.goTo(target) }
                }
            }
            is FoliateMessage.Relocate -> {
                latestRelocate = message
                onRelocate?.invoke(message)
            }
            is FoliateMessage.Error -> if (!bookReady) _state.value = Azw3DocState.Corrupt
            // The goTo ack is consumed by the FoliateGoToDispatcher's own collector (feature #135 WI-2);
            // the document ignores it here.
            is FoliateMessage.GoToAck -> Unit
            // feature #142 — the annotation events are TYPED by WI-1 and CONSUMED by WI-4 (which adds
            // onSelection / onAnnotationShow and the per-section decoration re-apply). Listed
            // explicitly rather than folded into an `else` so the exhaustive `when` keeps failing the
            // build on the next new message, instead of silently swallowing it.
            is FoliateMessage.Selection -> Unit
            FoliateMessage.SelectionCleared -> Unit
            is FoliateMessage.AnnotationShow -> Unit
            is FoliateMessage.OverlayCreated -> Unit
            is FoliateMessage.Other -> Unit
        }
    }

    /** Render the first page at the restored CFI (precise, same-platform) → fraction → start. */
    private fun restoreOrInit() {
        val loc = restore?.legacyLocator
        val cfi = loc?.cfi
        val fraction = loc?.progression
        when {
            cfi != null -> bridge.initAtCfi(cfi)
            fraction != null -> bridge.initAtFraction(fraction)
            else -> bridge.init()
        }
    }

    fun next() = bridge.next()
    fun prev() = bridge.prev()
    fun destroy() = bridge.destroy()

    /**
     * feature #135 WI-2 — jump to a persisted bookmark's canonical position (CFI-first→fraction). The
     * awaited result lets the host decide dismiss-vs-stay: [Azw3GoToResult.Succeeded] means the bundle
     * ACKNOWLEDGED the jump — not, on its own, that the reader moved, since foliate's `view.goTo`
     * catches a failed resolution and settles anyway (only a later relocate's reported position proves
     * motion); [Azw3GoToResult.Failed]/[Azw3GoToResult.Timeout] did not (the sheet stays open). If the book
     * isn't ready yet (or a render restart is in flight), the target is HELD and re-issued exactly
     * once after the next book-ready — a jump survives a renderer death mid-flight. Main-thread only.
     */
    suspend fun goTo(canonical: Locator): Azw3GoToResult {
        if (!bookReady) {
            // Nothing to jump into yet — remember the target for the post-book-ready re-issue and
            // report a soft failure so the sheet stays open until the render lands + re-issues.
            pendingGoTo = canonical
            return Azw3GoToResult.Failed
        }
        pendingGoTo = canonical // held so a render death DURING the jump re-issues it once.
        val result = goToController.goTo(canonical)
        // A settled (non-superseded) result means the jump completed its round-trip; drop the pending
        // re-issue so a later unrelated book-ready doesn't replay a stale jump.
        if (result != Azw3GoToResult.Superseded) pendingGoTo = null
        return result
    }

    /**
     * feature #129 WI-6 — apply the "Display" theme+typography CSS. Records it so a fresh render (or a
     * render-death recovery, which recreates the document) re-applies the current look, and — if the
     * book is already rendered — injects it live so a settings change updates the open reader at once.
     * Main-thread only (WebView is).
     */
    fun setStyles(css: String) {
        pendingStylesCss = css
        if (bookReady) bridge.setStyles(css)
    }
}

/**
 * feature #135 WI-2 — maps a canonical [Locator] to a foliate goTo through the awaited
 * [FoliateGoToDispatcher]. Derives the target CFI-FIRST then fraction (matching
 * [Azw3Document.restoreOrInit]'s precedence). When the locator has nothing to jump to (no cfi + no
 * finite progression), returns [Azw3GoToResult.Failed] WITHOUT injecting any JS. Pure enough to
 * unit-test against a fake dispatcher (no WebView).
 */
class FoliateGoToController(private val dispatcher: FoliateGoToDispatcher) {
    suspend fun goTo(
        canonical: Locator,
        timeoutMs: Long = FoliateBridge.DEFAULT_GOTO_TIMEOUT_MS,
    ): Azw3GoToResult {
        val target = FoliateGoToTarget.from(canonical) ?: return Azw3GoToResult.Failed
        return dispatcher.goTo(target, timeoutMs)
    }
}
