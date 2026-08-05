// Purpose: the secure WebView<->native transport for the AZW3/foliate reader. Wires a WebView with:
// WebViewAssetLoader (virtual https origin, no file://), a WebViewClient that serves same-origin
// assets/book + BLOCKS every remote resource request and off-origin navigation, render-process-death
// passthrough (the host Activity owns recovery — WI-6), and WebViewCompat.addWebMessageListener
// allow-listed to the shell origin (NEVER addJavascriptInterface) feeding FoliateMessageParser. The
// security decisions live in FoliateBridgePolicy (pure, JVM-tested). MAIN-THREAD ONLY. Feature #126 WI-3.
package com.vreader.app.reader.foliate

import android.annotation.SuppressLint
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import androidx.annotation.MainThread
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.vreader.app.diagnostics.DiagnosticsCategory
import com.vreader.app.diagnostics.VLog
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.ByteArrayInputStream
import java.util.UUID

/**
 * Configures [webView] for secure foliate-js hosting and exposes its events as [messages].
 * Construct on the main thread; call [attach] once, then [load]. All methods are main-thread only.
 */
@MainThread
class FoliateBridge(
    private val webView: WebView,
    private val assetLoader: WebViewAssetLoader,
    /** Scope the awaited-goTo ack collector runs on. Defaults to a Main-dispatcher scope (WebView is
     *  main-thread only); tests inject a `runTest` scope so virtual time drives the timeout path. */
    scope: CoroutineScope = CoroutineScope(Dispatchers.Main),
) {
    private val _messages = MutableSharedFlow<FoliateMessage>(extraBufferCapacity = 64)
    val messages: SharedFlow<FoliateMessage> = _messages.asSharedFlow()

    /** feature #135 WI-2 — the awaited AZW3/foliate goTo machinery. Injects the JSON-escaped shim call
     *  and suspends on a request-id-keyed deferred resolved by the matching [FoliateMessage.GoToAck]
     *  (routed through the SAME allow-listed `vreaderHost` channel — never `addJavascriptInterface`). */
    val goToDispatcher = FoliateGoToDispatcher(
        sendJs = ::eval,
        messages = _messages,
        scope = scope,
    )

    /**
     * Await a jump to [target], resolving only after foliate's `view.goTo(...)` relocate settles (or a
     * timeout). The request id + target are JSON-escaped ([jsString]) into the shell shim call. A
     * superseding goTo cancels the prior. Main-thread only (WebView is).
     */
    suspend fun goTo(target: FoliateGoToTarget, timeoutMs: Long = DEFAULT_GOTO_TIMEOUT_MS): Azw3GoToResult =
        goToDispatcher.goTo(target, timeoutMs)

    /** Invoked when this device's WebView is too old for `addWebMessageListener` (→ WebViewUnsupported). */
    var onWebViewUnsupported: (() -> Unit)? = null

    /** Render process died; the host Activity owns recovery (snapshot locator → recreate → reopen).
     *  Return true to keep the app alive. Default false (no recovery) until WI-6 sets it. */
    var onRenderProcessGone: ((RenderProcessGoneDetail?) -> Boolean)? = null

    @SuppressLint("SetJavaScriptEnabled")
    fun attach() {
        webView.settings.apply {
            javaScriptEnabled = true // foliate needs it; book section scripts are disabled via the bundle patch
            allowFileAccess = false
            allowContentAccess = false
            @Suppress("DEPRECATION") allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION") allowUniversalAccessFromFileURLs = false
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
        }
        // Keep the render process bound to the app's priority while the reader is open — without this
        // the OS freezer can suspend it after a few idle seconds, so a page-turn (evaluateJavascript)
        // wouldn't run until it thaws. It still drops with the app when backgrounded (render-death
        // recovery handles a kill). Plan R1.
        webView.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_BOUND, false)
        // Surface JS console warnings/errors to logcat (diagnostics; mirrors the iOS error logging).
        webView.webChromeClient = object : android.webkit.WebChromeClient() {
            override fun onConsoleMessage(m: android.webkit.ConsoleMessage): Boolean {
                if (m.messageLevel() == android.webkit.ConsoleMessage.MessageLevel.ERROR ||
                    m.messageLevel() == android.webkit.ConsoleMessage.MessageLevel.WARNING
                ) {
                    VLog.w(
                        DiagnosticsCategory.READER,
                        "FoliateBridge",
                        "console[${m.messageLevel()}]: ${m.message()} @${m.sourceId()}:${m.lineNumber()}",
                    )
                }
                return true
            }
        }
        webView.webViewClient = object : WebViewClientCompat() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val url = request.url?.toString()
                if (FoliateBridgePolicy.shouldBlockRequest(url)) return blocked(403, "blocked")
                val handled = request.url?.let { assetLoader.shouldInterceptRequest(it) }
                if (handled != null) return handled
                // Same-origin but the loader didn't handle it → FAIL CLOSED (never reach the network).
                if (FoliateBridgePolicy.isSameOrigin(url)) return blocked(404, "not found")
                return null // blob:/data:/etc. — handled internally by the WebView, not via this callback
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                // Only gate TOP-LEVEL navigation. Foliate renders each book section as a `blob:`
                // SUBFRAME — allow those (their remote subresources are still blocked above). A
                // main-frame nav off the shell origin is blocked.
                if (!request.isForMainFrame) return false
                return !FoliateBridgePolicy.isAllowedNavigation(request.url?.toString())
            }

            override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean =
                onRenderProcessGone?.invoke(detail) ?: false
        }

        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(
                webView, BRIDGE_NAME, setOf(FoliateAssetServer.SHELL_ORIGIN),
            ) { _, message, sourceOrigin, isMainFrame, _ ->
                if (FoliateBridgePolicy.isTrustedMessage(sourceOrigin?.toString(), isMainFrame)) {
                    FoliateMessageParser.parse(message.data ?: "")?.let { _messages.tryEmit(it) }
                }
            }
        } else {
            onWebViewUnsupported?.invoke()
        }
    }

    fun load() = webView.loadUrl(FoliateAssetServer.SHELL_URL)

    // --- typed reader API (no raw JS exposed; book-derived strings are JSON-escaped) ------------

    /** Fetch the book bytes from the app-controlled same-origin URL and hand foliate a File to open. */
    fun openBook() = eval(
        "(async()=>{try{const r=await fetch(${jsString(FoliateAssetServer.bookUrl())});" +
            "const b=await r.blob();await readerAPI.open(new File([b],'book',{type:'application/octet-stream'}));}" +
            "catch(e){window.__vreaderPost&&window.__vreaderPost('error',{message:'open: '+e,type:'open'});}})()",
    )

    fun init() = eval("try{readerAPI.init({})}catch(e){}")

    /** Restore by foliate CFI. The CFI is book-derived → JSON-escaped to prevent shell JS injection. */
    fun initAtCfi(cfi: String) = eval("try{readerAPI.init({cfi:${jsString(cfi)}})}catch(e){}")

    fun initAtFraction(fraction: Double) {
        if (fraction.isFinite()) eval("try{readerAPI.init({fraction:$fraction})}catch(e){}")
    }

    fun next() = eval("try{readerAPI.next&&readerAPI.next()}catch(e){}")

    fun prev() = eval("try{readerAPI.prev&&readerAPI.prev()}catch(e){}")

    /** feature #129 WI-6 — apply the "Display" theme+typography CSS to the rendered book. The JS is
     *  built by the SHARED [foliateSetStylesJs] seam — which JSON-encodes the CSS into a valid,
     *  injection-safe JS string literal — so the escaping the unit test pins is the EXACT escaping
     *  `evaluateJavascript` runs (no test-vs-production drift). Mirrors iOS Foliate `setStyles`. */
    fun setStyles(css: String) = eval(foliateSetStylesJs(css))

    fun destroy() = webView.destroy()

    private fun eval(js: String) = webView.evaluateJavascript(js, null)

    /** Encode [s] as a JSON string literal — also a safe JS string literal (quotes/escapes handled). */
    private fun jsString(s: String): String = Json.encodeToString(String.serializer(), s)

    private fun blocked(status: Int, reason: String): WebResourceResponse =
        WebResourceResponse("text/plain", "utf-8", status, reason, emptyMap(), ByteArrayInputStream(ByteArray(0)))

    companion object {
        const val BRIDGE_NAME = "vreaderHost"
        /** Wall-clock budget for an awaited goTo — foliate must relocate + ack within this window. */
        const val DEFAULT_GOTO_TIMEOUT_MS = 3_000L
    }
}

/** feature #135 WI-2 — the outcome of an awaited [FoliateBridge.goTo]. */
sealed interface Azw3GoToResult {
    /** The jump landed; `cfi`/`fraction` are the reached position when the ack reported them. */
    data class Succeeded(val cfi: String?, val fraction: Double?) : Azw3GoToResult
    /** No ack arrived within the timeout window (dead bundle / wedged renderer). */
    data object Timeout : Azw3GoToResult
    /** Foliate acked a FAILED jump (`ok=false`) — an unresolvable target. */
    data object Failed : Azw3GoToResult
    /** A later goTo superseded this one before it acked (the caller should ignore this result). */
    data object Superseded : Azw3GoToResult
}

/** feature #135 WI-2 — the foliate navigation target the shim's `goTo`/`goToFraction` accepts.
 *  feature #140 WI-3 added [Href] — the TOC leg, which foliate resolves via `book.resolveHref`. */
sealed interface FoliateGoToTarget {
    data class Cfi(val cfi: String) : FoliateGoToTarget

    /** A book-relative destination exactly as the TOC emitted it (`text/part0007.html#ch12`, the KF8
     *  `kindle:pos:fid:…:off:…` form, …). Carried BYTE-FOR-BYTE to `readerAPI.goTo` — never trimmed,
     *  normalized or re-encoded: the bundle does its own `decodeURI`, and current-chapter matching is
     *  byte-exact, so two hrefs differing only by fragment must stay distinct. */
    data class Href(val href: String) : FoliateGoToTarget

    data class Fraction(val fraction: Double) : FoliateGoToTarget

    companion object {
        /**
         * Derive a jump target from a canonical [vreader.contracts.Locator]: **cfi → href →
         * progression** (the cfi/progression halves match [Azw3Document.restoreOrInit]'s precedence).
         * Returns null when there is nothing to jump to (no cfi + no href + no finite progression) so
         * the caller degrades without injecting JS.
         *
         * The href leg deliberately outranks progression (feature #140 §5.2 defense 1): an AZW3 TOC
         * row's destination IS its href, and iOS's TOC converter stamps such rows with
         * `progression = 0.0` — harmless on iOS, whose target resolution has no progression leg, but
         * fatal here. Were progression to win, every chapter tap would resolve to `Fraction(0.0)`,
         * jump to the START of the book, and still ack `ok:true` (foliate's `view.goTo` swallows a
         * failed resolution), so the sheet would dismiss on a completely broken jump. Pinned by
         * `FoliateGoToTest.from_prefersHrefOverProgression` /
         * `from_hrefWithProgressionZero_stillYieldsHref`.
         */
        fun from(locator: vreader.contracts.Locator): FoliateGoToTarget? {
            locator.cfi?.takeIf { it.isNotBlank() }?.let { return Cfi(it) }
            locator.href?.takeIf { it.isNotBlank() }?.let { return Href(it) }
            locator.progression?.takeIf { it.isFinite() }?.let { return Fraction(it) }
            return null
        }
    }
}

/**
 * feature #135 WI-2 — the pure, WebView-free await-machinery for an ack'd foliate goTo. Injects the
 * JSON-escaped shell-shim call (`window.__vreaderGoTo(id, target)`), suspends on a request-id-keyed
 * [CompletableDeferred], and resolves it from the matching [FoliateMessage.GoToAck] arriving over
 * [messages]. Fully unit-testable: a fake `sendJs` records the injected JS and a test channel drives
 * acks under `runTest` virtual time. NEVER uses `addJavascriptInterface` — the ack rides the existing
 * allow-listed `vreaderHost` message channel only.
 *
 * THREADING (Gate-4 F3): the single mutable field [pending] is confined to ONE dispatcher. In
 * production the only constructor is [FoliateBridge] (`@MainThread`), which supplies a
 * `Dispatchers.Main` scope, and every entry point — `goTo()` (called from the main-thread host) and
 * the ack collector — runs on that Main scope. The read-then-replace of [pending] in `goTo`/`resolve`
 * has no suspension point between read and write, so single-thread coroutine interleaving is safe. A
 * caller MUST therefore invoke `goTo` on the same single-threaded dispatcher as `scope`; this is why
 * `FoliateBridge`/`Azw3Document.goTo` are `@MainThread`. (Tests use `runTest`'s single-threaded
 * scheduler — the same confinement.)
 */
class FoliateGoToDispatcher(
    private val sendJs: (String) -> Unit,
    messages: SharedFlow<FoliateMessage>,
    scope: CoroutineScope,
) {
    private data class Pending(val id: String, val deferred: CompletableDeferred<Azw3GoToResult>)

    /** At most one in-flight goTo — a superseding goTo cancels the prior. Confined to the dispatcher's
     *  single-threaded scope (see class docs): goTo() and the ack collector both run there. */
    private var pending: Pending? = null

    init {
        // A SharedFlow tolerates multiple collectors (Azw3Document also collects for state/relocate),
        // so this ack collector is independent and never steals the document's messages.
        scope.launch {
            messages.collect { message ->
                if (message is FoliateMessage.GoToAck) resolve(message)
            }
        }
    }

    /** Test/diagnostic: how many goTos are awaiting an ack (0 or 1). */
    fun pendingCount(): Int = if (pending == null) 0 else 1

    suspend fun goTo(target: FoliateGoToTarget, timeoutMs: Long = FoliateBridge.DEFAULT_GOTO_TIMEOUT_MS): Azw3GoToResult {
        // Supersede any in-flight goTo: cancel-resolve it + drop its entry so a late ack can't resolve it.
        pending?.let { prior ->
            pending = null
            prior.deferred.complete(Azw3GoToResult.Superseded)
        }
        val id = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<Azw3GoToResult>()
        pending = Pending(id, deferred)
        sendJs(gotoJs(id, target))
        try {
            // withTimeoutOrNull -> null means the ack never arrived within the window.
            return withTimeoutOrNull(timeoutMs) { deferred.await() } ?: Azw3GoToResult.Timeout
        } finally {
            // ALWAYS drop OUR entry (timeout, or caller-cancellation while suspended in await) so a
            // cancelled/timed-out goTo never leaks a pending request that a late/stale ack could
            // resolve. Only if it is still the entry we minted (a supersede may have replaced it, or an
            // ack already cleared it). complete-the-deferred is a no-op if it already resolved.
            if (pending?.id == id) {
                pending = null
                deferred.complete(Azw3GoToResult.Superseded)
            }
        }
    }

    private fun resolve(ack: FoliateMessage.GoToAck) {
        val current = pending ?: return
        if (current.id != ack.id) return // stale / unknown id — ignore (do not resolve).
        pending = null
        current.deferred.complete(
            if (ack.ok) Azw3GoToResult.Succeeded(ack.cfi, ack.fraction) else Azw3GoToResult.Failed,
        )
    }

    /** The JSON-escaped shell-shim call. The request id + CFI/href are JSON-encoded so a hostile
     *  book-derived CFI or TOC href cannot break out of the injected JS string (the [jsString]
     *  escaping seam — the ONLY escaper on this path; the href gets no separate treatment and is
     *  therefore delivered byte-for-byte). */
    private fun gotoJs(id: String, target: FoliateGoToTarget): String = when (target) {
        is FoliateGoToTarget.Cfi ->
            "try{window.__vreaderGoTo&&window.__vreaderGoTo(${jsString(id)},{cfi:${jsString(target.cfi)}})}catch(e){}"
        is FoliateGoToTarget.Href ->
            "try{window.__vreaderGoTo&&window.__vreaderGoTo(${jsString(id)},{href:${jsString(target.href)}})}catch(e){}"
        is FoliateGoToTarget.Fraction ->
            "try{window.__vreaderGoTo&&window.__vreaderGoTo(${jsString(id)},{fraction:${target.fraction}})}catch(e){}"
    }

    private fun jsString(s: String): String = Json.encodeToString(String.serializer(), s)
}

/**
 * feature #129 WI-6 — the SHARED foliate `setStyles` JS builder. The CSS is JSON-encoded into a JS
 * string literal (the FoliateJSEscaper analog) so ANY value — quotes, backslashes, newlines,
 * `</script>` — is neutralized and cannot break out of the shell JS. This is the SINGLE production
 * seam [FoliateBridge.setStyles] runs through `evaluateJavascript`, so the escaping the unit test pins
 * (`Azw3DisplayCssTest`) is exactly the escaping production applies. Deterministic for a given [css].
 */
fun foliateSetStylesJs(css: String): String =
    "try{readerAPI.setStyles&&readerAPI.setStyles(${Json.encodeToString(String.serializer(), css)})}catch(e){}"
