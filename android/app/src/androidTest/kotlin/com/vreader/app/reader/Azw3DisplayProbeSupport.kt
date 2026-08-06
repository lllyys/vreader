// Purpose: bug #368 — the reader-stack and live-stylesheet helpers used by
// Azw3DisplayControlConnectedTest. Split out of that class to keep both files near the repo's ~300-line
// guidance (Gate-4 round 1, Low), and so the "what CSS is ACTUALLY live in the mounted section document"
// probe is a named, reusable thing rather than a local implementation detail.
//
// It is deliberately NOT merged into Azw3DomProbe: that probe is constructed from an
// `ActivityScenario<Azw3ReaderActivity>`, which a PRODUCTION-path test does not have — it launches
// MainActivity and finds the reader the Library tap opened through the lifecycle monitor. The JS itself
// reaches the section document exactly the way Azw3DomProbe and foliate's own `setStyles` do.
//
// @coordinates-with: Azw3DisplayControlConnectedTest.kt (the only caller), Azw3DisplayCss.kt
//   (VREADER_CSS_SENTINEL — the ownership marker the blob is selected by), Azw3DomProbe.kt (the
//   scenario-based sibling probe this mirrors).
package com.vreader.app.reader

import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import org.json.JSONObject
import org.json.JSONTokener
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

private const val TAG = "B368-DISPLAY"
private const val POLL_MS = 250L

/**
 * Foliate renders each book section into a `blob:` SUBFRAME (sandbox=allow-same-origin), so the section
 * document is reached the same way foliate's own `setStyles` reaches it:
 * `document.getElementById('view').renderer.getContents()[0].doc`. Returns every `<style>` element's
 * text; the caller picks OUR blob out by the production sentinel.
 */
private const val STYLES_JS = """
    (function(){
      try{
        var v=document.getElementById('view');
        var r=v&&v.renderer;
        var cs=(r&&r.getContents)?r.getContents():null;
        if(!cs||!cs.length) return JSON.stringify({styles:[],reason:'no-mounted-view'});
        var d=cs[0].doc;
        if(!d) return JSON.stringify({styles:[],reason:'no-document'});
        var out=[];
        var ss=d.querySelectorAll('style');
        for(var i=0;i<ss.length;i++) out.push(ss[i].textContent||'');
        return JSON.stringify({styles:out});
      }catch(e){return JSON.stringify({styles:[],error:String(e)});}
    })()
"""

private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

private fun <T> readOnMain(block: () -> T): T {
    var value: Any? = null
    instrumentation.runOnMainSync { value = block() }
    @Suppress("UNCHECKED_CAST")
    return value as T
}

// ---- the reader stack ------------------------------------------------------------------------------

/** The resumed AZW3 reader, if any — the Activity a Library tap has just brought to the front. */
fun resumedAzw3Reader(): Azw3ReaderActivity? = readOnMain {
    ActivityLifecycleMonitorRegistry.getInstance()
        .getActivitiesInStage(Stage.RESUMED)
        .filterIsInstance<Azw3ReaderActivity>()
        .firstOrNull()
}

/** Every AZW3 reader that is not yet DESTROYED — one parked in CREATED or STOPPED is still on the
 *  stack and would still be found by a later lookup, so a test that ignored it could bind to the
 *  survivor of an earlier method instead of the reader its own tap opened. */
private fun liveAzw3Readers(): List<Azw3ReaderActivity> = readOnMain {
    val monitor = ActivityLifecycleMonitorRegistry.getInstance()
    listOf(
        Stage.PRE_ON_CREATE, Stage.CREATED, Stage.STARTED,
        Stage.RESUMED, Stage.PAUSED, Stage.STOPPED, Stage.RESTARTED,
    ).flatMap { monitor.getActivitiesInStage(it) }.filterIsInstance<Azw3ReaderActivity>().distinct()
}

/** Finish every live AZW3 reader and wait for the stack to drain; returns whether it fully drained. */
fun finishAnyAzw3Reader(timeoutMs: Long = 20_000): Boolean {
    val readers = liveAzw3Readers()
    if (readers.isEmpty()) return true
    instrumentation.runOnMainSync { readers.forEach { it.finish() } }
    val deadline = System.currentTimeMillis() + timeoutMs
    while (liveAzw3Readers().isNotEmpty() && System.currentTimeMillis() < deadline) Thread.sleep(POLL_MS)
    return liveAzw3Readers().isEmpty()
}

// ---- the live stylesheet ---------------------------------------------------------------------------

/**
 * The vreader display-CSS blob as it is ACTUALLY live in the mounted section document, selected by the
 * production ownership sentinel [VREADER_CSS_SENTINEL] rather than by a rule's text — a content
 * signature is guessable, and a publisher stylesheet could carry the same shape.
 *
 * Null while the section is not mounted, while the blob has not been injected yet, or — deliberately —
 * if MORE than one sentinel-bearing blob is present: reporting one arbitrarily would be reporting a
 * possibly stale sample as the live one.
 */
fun liveVreaderCssOrNull(reader: Azw3ReaderActivity): String? {
    val raw = evalJs(reader, STYLES_JS) ?: return null
    if (raw == "null") return null
    // `evaluateJavascript` hands back the JS value JSON-ENCODED, and the JS itself returns a JSON
    // string — so the payload arrives double-encoded and has to be unwrapped twice (the
    // Azw3DomProbe.evalJson precedent).
    val outer = runCatching { JSONTokener(raw).nextValue() }.getOrNull() ?: return null
    val decoded = when (outer) {
        is String -> runCatching { JSONObject(outer) }.getOrNull()
        is JSONObject -> outer
        else -> null
    } ?: return null
    val styles = decoded.optJSONArray("styles") ?: return null
    return (0 until styles.length()).map { styles.optString(it) }
        .filter { it.contains(VREADER_CSS_SENTINEL) }
        .singleOrNull()
}

/**
 * Poll until the blob live in the section document equals [expected]. A state that never arrives is an
 * explicit failure carrying the last reading — never a quietly stale sample reported as a pass.
 */
fun awaitLiveVreaderCss(reader: Azw3ReaderActivity, what: String, expected: String, timeoutMs: Long) {
    val deadline = System.currentTimeMillis() + timeoutMs
    var last: String? = null
    while (System.currentTimeMillis() < deadline) {
        last = liveVreaderCssOrNull(reader)
        if (last == expected) {
            Log.i(TAG, "LIVE CSS is $what (${expected.length} chars)")
            return
        }
        Thread.sleep(POLL_MS)
    }
    throw AssertionError(
        "the AZW3 body's live stylesheet never became $what within ${timeoutMs}ms. " +
            "expected=${expected.take(160)}… actual=${last?.take(160) ?: "<no vreader blob in the document>"}…",
    )
}

/**
 * Evaluate [js] in the production foliate WebView ON THE MAIN THREAD and block the caller for the
 * result. A per-call holder: on timeout the value a late callback writes must NOT be read, or a slow
 * evaluation would surface as a stale reading in a later poll.
 */
private fun evalJs(reader: Azw3ReaderActivity, js: String): String? {
    val holder = AtomicReference<String?>(null)
    val done = CountDownLatch(1)
    instrumentation.runOnMainSync {
        val webView = firstWebView(reader.window.decorView)
        if (webView == null) {
            // Distinguishable from "the page returned nothing" — a probe that silently polled on a
            // missing WebView would look identical to a book that never rendered.
            Log.w(TAG, "evalJs: NO WebView in the reader's view tree")
            done.countDown()
            return@runOnMainSync
        }
        webView.evaluateJavascript(js) { value -> holder.set(value); done.countDown() }
    }
    if (!done.await(20, TimeUnit.SECONDS)) {
        Log.w(TAG, "evalJs timed out after 20s — discarding this sample")
        return null
    }
    return holder.get()
}

private fun firstWebView(view: View): WebView? {
    if (view is WebView) return view
    if (view is ViewGroup) {
        for (i in 0 until view.childCount) firstWebView(view.getChildAt(i))?.let { return it }
    }
    return null
}
