package com.vreader.app.reader.foliate

import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Feature #126 WI-0 — go/no-go spike (THROWAWAY).
 *
 * Answers, on a real Android emulator, before any shippable reader code:
 *   1. Does the iOS-vendored foliate-js bundle — WITH `allow-scripts` stripped from every
 *      section iframe (the security patch) — actually OPEN + render an AZW3/MOBI/KF8 book in
 *      Android System WebView, and does the `window.webkit.messageHandlers` shim deliver
 *      foliate's events to the native `addWebMessageListener` bridge?
 *   2. Does stripping `allow-scripts` break foliate's rendering/eventing on Chromium WebView
 *      (the source comment says it's "needed for events because of a WebKit bug" — which
 *      should not apply to Chromium)?
 *   3. Can hostile book content reach the native bridge? (security)
 *
 * Assets (test APK, local-only): `foliate-spike/reader.html`, `foliate-spike/foliate-bundle.js`
 * (patched), and `foliate-spike/book.azw3` (a real 6 MB CJK Kindle book, copied in locally — NOT
 * committed). Verdict is appended to dev-docs/plans/20260629-feature-126-android-azw3-reader.md.
 */
@RunWith(AndroidJUnit4::class)
class FoliateSpikeHarnessTest {

    private val shellOrigin = "https://appassets.androidplatform.net"
    // AssetsPathHandler strips the registered prefix and maps the remainder to the assets ROOT,
    // so the prefix must be `/assets/` and the file lives at assets/foliate-spike/*.
    private val shellUrl = "$shellOrigin/assets/foliate-spike/reader.html"
    private val bookUrl = "$shellOrigin/assets/foliate-spike/book.azw3"

    /** name -> {name, detail}; bridgeFrame records (origin,isMainFrame) of every native call. */
    private val messages = LinkedBlockingQueue<JSONObject>()
    private val bridgeCalls = LinkedBlockingQueue<JSONObject>()
    /** every relocate, tracked independently of the await queue (initial layout relocate proves eventing). */
    private val relocateCount = java.util.concurrent.atomic.AtomicInteger(0)

    private fun buildWebView(): WebView {
        val inst = InstrumentationRegistry.getInstrumentation()
        lateinit var wv: WebView
        inst.runOnMainSync {
            WebView.setWebContentsDebuggingEnabled(true)
            val w = WebView(inst.targetContext)
            // AssetsPathHandler reads the TEST APK's assets (where foliate-spike/ lives).
            val loader = WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(inst.context))
                .build()
            // Surface JS console + CSP violations into instrumentation stdout for diagnosis.
            w.webChromeClient = object : android.webkit.WebChromeClient() {
                override fun onConsoleMessage(m: android.webkit.ConsoleMessage): Boolean {
                    System.out.println("foliate-spike console[${m.messageLevel()}]: ${m.message()} @${m.sourceId()}:${m.lineNumber()}")
                    return true
                }
            }
            w.settings.javaScriptEnabled = true
            w.settings.allowFileAccess = false
            w.settings.allowContentAccess = false
            @Suppress("DEPRECATION")
            run {
                w.settings.allowFileAccessFromFileURLs = false
                w.settings.allowUniversalAccessFromFileURLs = false
            }
            w.webViewClient = object : WebViewClientCompat() {
                override fun shouldInterceptRequest(view: WebView, request: android.webkit.WebResourceRequest) =
                    loader.shouldInterceptRequest(request.url)
                override fun onRenderProcessGone(
                    view: WebView?,
                    detail: android.webkit.RenderProcessGoneDetail?,
                ): Boolean = true // survive renderer death; real recovery is WI-6
            }
            if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
                WebViewCompat.addWebMessageListener(
                    w, "vreaderHost", setOf(shellOrigin),
                ) { _, message, sourceOrigin, isMainFrame, _ ->
                    val call = JSONObject()
                        .put("raw", message.data ?: "")
                        .put("origin", sourceOrigin.toString())
                        .put("isMainFrame", isMainFrame)
                    bridgeCalls.add(call)
                    // Only main-frame, shell-origin messages are trusted application events.
                    if (isMainFrame && sourceOrigin.toString() == shellOrigin) {
                        runCatching {
                            val obj = JSONObject(message.data ?: "{}")
                            if (obj.optString("name") == "relocate") relocateCount.incrementAndGet()
                            messages.add(obj)
                        }
                    }
                }
            } else {
                fail("WEB_MESSAGE_LISTENER unsupported on this WebView — see plan R3")
            }
            // A detached WebView has 0x0 size → foliate can't paginate → no relocate. Force a real
            // viewport so the paginator can measure pages. (WI-6 hosts it in a sized Compose AndroidView.)
            val px = inst.targetContext.resources.displayMetrics
            val ww = if (px.widthPixels > 0) px.widthPixels else 1080
            val hh = if (px.heightPixels > 0) px.heightPixels else 1920
            w.measure(
                android.view.View.MeasureSpec.makeMeasureSpec(ww, android.view.View.MeasureSpec.EXACTLY),
                android.view.View.MeasureSpec.makeMeasureSpec(hh, android.view.View.MeasureSpec.EXACTLY),
            )
            w.layout(0, 0, ww, hh)
            wv = w
            w.loadUrl(shellUrl)
        }
        return wv
    }

    private fun await(name: String, timeoutMs: Long): JSONObject? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val msg = messages.poll(250, TimeUnit.MILLISECONDS) ?: continue
            if (msg.optString("name") == name) return msg
            if (msg.optString("name") == "error") {
                System.err.println("foliate-spike JS error: ${msg.optJSONObject("detail")}")
            }
        }
        return null
    }

    private fun eval(wv: WebView, js: String) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync { wv.evaluateJavascript(js, null) }
    }

    @Test
    fun patchedBundle_opensAzw3_rendersSections_andBridgeWorks() {
        // The real CJK AZW3 fixture is local-only (gitignored, not in CI). Skip gracefully if absent;
        // the security test below is self-contained and always runs.
        val hasBook = InstrumentationRegistry.getInstrumentation().context.assets
            .list("foliate-spike")?.contains("book.azw3") == true
        org.junit.Assume.assumeTrue("local-only foliate-spike/book.azw3 absent — skipping render check", hasBook)

        val wv = buildWebView()

        // Q1a: the bundle loads + the shim delivers `bridge-ready`.
        val ready = await("bridge-ready", 20_000)
            ?: fail("no bridge-ready — bundle failed to load or the webkit.messageHandlers shim is broken").let { return }

        // Q1b/Q2: open a real AZW3 by fetching it as a File (mirrors iOS) and rendering it.
        eval(
            wv,
            """
            (async () => {
              try {
                const r = await fetch('$bookUrl');
                const b = await r.blob();
                const f = new File([b], 'book.azw3', { type: 'application/octet-stream' });
                await readerAPI.open(f);
              } catch (e) { window.__vreaderPost('error', { message: 'open failed: ' + e, type: 'open' }); }
            })();
            """.trimIndent(),
        )

        // book-ready proves mobi.js decoded the AZW3 AND foliate rendered it with allow-scripts stripped.
        val bookReady = await("book-ready", 30_000)
            ?: fail("no book-ready — patched bundle did not open/render the AZW3 in Android WebView (go/no-go FAIL)").let { return }
        val detail = bookReady.optJSONObject("detail") ?: JSONObject()
        val sections = detail.optInt("sections", detail.optInt("sectionTotal", 0))
        assertTrue("book-ready reported 0 sections — render produced nothing: $detail", sections > 0)

        // book-ready = parse done. init() renders the first page (mirrors the iOS host calling
        // readerAPI.init after book-ready) and fires the INITIAL relocate.
        eval(wv, "try { readerAPI.init({}); } catch(e){ window.__vreaderPost('error',{message:'init: '+e}); }")
        val firstRelocate = await("relocate", 12_000)
        assertTrue(
            "no relocate after init() — foliate did not render/locate the first page (got ${relocateCount.get()})",
            firstRelocate != null,
        )

        // Q2: navigation must fire MORE relocates even with `allow-scripts` stripped (events come from
        // the parent, not in-frame script — the WebKit-bug workaround should not be needed on Chromium).
        val afterInit = relocateCount.get()
        eval(wv, "try { readerAPI.next && readerAPI.next(); } catch(e) {}")
        Thread.sleep(2500)
        val total = relocateCount.get()
        assertTrue("navigation fired no relocate (init=$afterInit, total=$total) — eventing did not survive nav", total > afterInit)
        System.out.println(
            "foliate-spike VERDICT: GO — sections=$sections, relocates=$total (init=$afterInit, +nav=${total - afterInit}); " +
                "patched bundle (allow-scripts stripped) renders the real AZW3 + eventing intact on Android WebView",
        )
    }

    /**
     * Security verdict: a hostile book section (a blob-URL iframe — same shape foliate creates for
     * MOBI/KF8 sections) must NOT reach the native bridge. Proves the mitigation (strip `allow-scripts`)
     * AND that the test is real (the SAME payload DOES reach native when `allow-scripts` is present).
     */
    @Test
    fun hostileSection_blockedWithoutAllowScripts_butReachesNativeWithIt() {
        val wv = buildWebView()
        await("bridge-ready", 20_000) ?: fail("no bridge-ready").let { return }

        // The payload a malicious section would run: reach the bridge via every known path.
        val attack = """
            try { parent.vreaderHost.postMessage(JSON.stringify({name:'relocate',detail:{PWNED:'parent.vreaderHost'}})); } catch(e){}
            try { top.vreaderHost.postMessage(JSON.stringify({name:'relocate',detail:{PWNED:'top.vreaderHost'}})); } catch(e){}
            try { parent.webkit.messageHandlers.relocate.postMessage({PWNED:'parent.webkit'}); } catch(e){}
        """.trimIndent()

        fun injectHostileFrame(sandbox: String) = eval(
            wv,
            """
            (function(){
              var f = document.createElement('iframe');
              f.setAttribute('sandbox', '$sandbox');
              var html = '<html><body><scr'+'ipt>${attack.replace("\n", " ").replace("'", "\\'")}<\/scr'+'ipt></body></html>';
              var blob = new Blob([html], { type: 'text/html' });
              f.src = URL.createObjectURL(blob);
              document.body.appendChild(f);
            })();
            """.trimIndent(),
        )

        // Distinct PWNED markers (which escape path reached native) + the isMainFrame each call reported.
        fun pwnedMarkers(): List<Pair<String, Boolean>> = bridgeCalls.toList()
            .filter { it.optString("raw").contains("PWNED") }
            .mapNotNull { c ->
                Regex(""""PWNED":"([^"]+)"""").find(c.optString("raw"))?.groupValues?.get(1)
                    ?.let { it to c.optBoolean("isMainFrame") }
            }

        // 1) PATCHED posture — sandbox WITHOUT allow-scripts: the section script must never run, so
        //    NONE of the escape paths reach native.
        injectHostileFrame("allow-same-origin")
        Thread.sleep(2500)
        val blocked = pwnedMarkers()
        assertTrue("SECURITY FAIL: hostile section reached native without allow-scripts: $blocked", blocked.isEmpty())

        // 2) CONTROL — sandbox WITH allow-scripts: the SAME payload SHOULD reach native via ALL THREE
        //    paths, proving the escape is real (and recording how each call's isMainFrame is reported —
        //    the empirical answer to "can a same-origin section reach parent.vreaderHost as main-frame").
        injectHostileFrame("allow-same-origin allow-scripts")
        Thread.sleep(2500)
        val control = pwnedMarkers()
        val markers = control.map { it.first }.toSet()
        System.out.println("foliate-spike SECURITY: blocked=${blocked.size}, control=$control")
        assertTrue(
            "CONTROL inconclusive: expected the 3 escape paths to reach native, got $markers",
            markers.containsAll(listOf("parent.vreaderHost", "top.vreaderHost", "parent.webkit")),
        )
    }

    /**
     * Proves the patched bundle stripped `allow-scripts` from EVERY section-iframe sandbox (both the
     * reflowable `paginator` path and the `fixed-layout` path), not just one — guards against partial
     * patching / bundle drift (Gate-4 finding). The synthetic-iframe security test above shows the
     * MECHANISM works; this asserts the shipped bundle actually applies it everywhere.
     */
    @Test
    fun patchedBundle_hasNoAllowScriptsInAnySectionIframe() {
        val bundle = InstrumentationRegistry.getInstrumentation().context.assets
            .open("foliate-spike/foliate-bundle.js").bufferedReader().use { it.readText() }
        val remaining = Regex("allow-scripts").findAll(bundle).count()
        assertTrue("patched bundle still has $remaining 'allow-scripts' — not every section iframe patched", remaining == 0)
        assertTrue("bundle does not look like foliate (no 'allow-same-origin' sandbox)", bundle.contains("allow-same-origin"))
    }
}
