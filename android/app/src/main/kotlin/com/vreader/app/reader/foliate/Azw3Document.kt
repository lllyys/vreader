// Purpose: the MAIN-THREAD controller for an AZW3/MOBI/KF8 reading session. Owns a WebView + the
// secure FoliateBridge, drives the open → restore → render → navigate flow, and exposes the reading
// state + the latest position (main-thread-owned, so the Activity's onStop can flush synchronously).
// All methods are main-thread only (WebView is). Feature #126 WI-4.
package com.vreader.app.reader.foliate

import android.content.Context
import android.webkit.WebView
import androidx.annotation.MainThread
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.onSubscription
import vreader.contracts.VReaderLocator
import java.io.File

/** What the reader UI shows for a Foliate session. */
sealed interface Azw3DocState {
    data object Loading : Azw3DocState
    /** This device's System WebView is too old for the secure bridge (`addWebMessageListener`). */
    data object WebViewUnsupported : Azw3DocState
    /** The book opened + rendered; `sectionTotal` spine items. */
    data class Loaded(val sectionTotal: Int) : Azw3DocState
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

    /**
     * Wire the bridge and load, then SUSPEND collecting messages until cancelled. Call from a
     * HOLDER-SCOPED `LaunchedEffect` on the Main dispatcher (WebView is main-thread-only) so a reload
     * / dispose cancels the collector and never retains the old document/bridge/WebView. The
     * `onSubscription { load() }` guarantees the collector is subscribed BEFORE the bundle emits (no
     * hot-flow race), so `bridge-ready`/`book-ready` are never missed.
     */
    suspend fun run(restore: VReaderLocator?) {
        this.restore = restore
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
                _state.value = if (message.sectionTotal > 0) Azw3DocState.Loaded(message.sectionTotal) else Azw3DocState.Empty
            }
            is FoliateMessage.Relocate -> {
                latestRelocate = message
                onRelocate?.invoke(message)
            }
            is FoliateMessage.Error -> if (!bookReady) _state.value = Azw3DocState.Corrupt
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
