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
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.ByteArrayInputStream

/**
 * Configures [webView] for secure foliate-js hosting and exposes its events as [messages].
 * Construct on the main thread; call [attach] once, then [load]. All methods are main-thread only.
 */
@MainThread
class FoliateBridge(
    private val webView: WebView,
    private val assetLoader: WebViewAssetLoader,
) {
    private val _messages = MutableSharedFlow<FoliateMessage>(extraBufferCapacity = 64)
    val messages: SharedFlow<FoliateMessage> = _messages.asSharedFlow()

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
                    android.util.Log.w("FoliateBridge", "console[${m.messageLevel()}]: ${m.message()} @${m.sourceId()}:${m.lineNumber()}")
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

    /** feature #129 WI-6 — apply the "Display" theme+typography CSS to the rendered book. The CSS is
     *  JSON-escaped (a valid, injection-safe JS string literal) exactly like [jsString] above, so no
     *  settings/book-derived value can break out of the shell JS. Mirrors iOS Foliate `setStyles`. */
    fun setStyles(css: String) = eval("try{readerAPI.setStyles&&readerAPI.setStyles(${jsString(css)})}catch(e){}")

    fun destroy() = webView.destroy()

    private fun eval(js: String) = webView.evaluateJavascript(js, null)

    /** Encode [s] as a JSON string literal — also a safe JS string literal (quotes/escapes handled). */
    private fun jsString(s: String): String = Json.encodeToString(String.serializer(), s)

    private fun blocked(status: Int, reason: String): WebResourceResponse =
        WebResourceResponse("text/plain", "utf-8", status, reason, emptyMap(), ByteArrayInputStream(ByteArray(0)))

    companion object {
        const val BRIDGE_NAME = "vreaderHost"
    }
}
