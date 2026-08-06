// Purpose: feature #142 WI-3 — the AZW3/foliate ANNOTATION outbound surface: the three pure JS
// builders that paint / erase / dismiss a highlight, plus the one-shot `evalForResult` machinery
// behind the WI-5 selection-anchor probe. Everything here is WebView-free and JVM-testable on purpose;
// FoliateBridge holds the WebView and does nothing but forward.
//
// Security posture (rule 54 / feature #126): every interpolated value is JSON-encoded into a JS string
// literal via the single [foliateJsString] seam — a CFI is minted from book content and a restored one
// came off a backup wire, so both are treated as hostile. Outbound calls go through
// `evaluateJavascript` -> `readerAPI.*`; inbound rides the origin-allow-listed WebMessage channel.
// NEVER `addJavascriptInterface`. The vendored bundle already exposes every member used here
// (foliate-bundle.js readerAPI: addAnnotation / deleteAnnotation / deselect) — no bundle change.
//
// @coordinates-with: FoliateBridge.kt (the WebView holder), Azw3Document.kt (WI-4 setAnnotations),
//   FoliateBundleProvenanceTest.kt (pins these readerAPI member names in the bundle)
package com.vreader.app.reader.foliate

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/** U+2028 LINE SEPARATOR / U+2029 PARAGRAPH SEPARATOR, built from their code points so this source
 *  file contains no `\uXXXX` escape text (a tool-written escape can become a real control character
 *  in the file). These two are the only characters JSON leaves raw that JS once treated as line
 *  terminators. */
private val jsLineTerminators = listOf(
    0x2028.toChar().toString() to "\\" + "u2028",
    0x2029.toChar().toString() to "\\" + "u2029",
)

/**
 * Encode [s] as a JSON string literal — which is also a valid JS string literal, with quotes,
 * backslashes, newlines and control characters neutralized. The SINGLE escaping seam for every value
 * this package interpolates into injected JS (the iOS `FoliateJSEscaper` analog).
 *
 * Two deliberate specifics, both pinned by `FoliateAnnotationJsTest`:
 *
 * - **`/` is left alone**, so a value containing `</script>` passes through verbatim. Safe *here*
 *   because the result is handed to `evaluateJavascript`, never spliced into an HTML `<script>`
 *   element — there is no HTML parser to terminate. It would NOT be safe if a caller ever built an
 *   HTML document with this.
 * - **U+2028 / U+2029 are escaped on top of JSON.** JSON emits them raw, and until ES2019 they were
 *   line terminators inside a JS string literal — i.e. a raw one is a *parse* error, which no
 *   `try{…}catch{}` can rescue because the whole statement fails to compile. Current Chromium accepts
 *   them, so this is a compatibility guarantee rather than a live injection fix; escaping removes the
 *   dependency on which System WebView the device happens to ship.
 */
internal fun foliateJsString(s: String): String {
    var encoded = Json.encodeToString(String.serializer(), s)
    for ((raw, escape) in jsLineTerminators) {
        if (encoded.contains(raw)) encoded = encoded.replace(raw, escape)
    }
    return encoded
}

/**
 * Paint (or re-paint) a highlight over [cfi] in [cssColor].
 *
 * [cfi] is book-derived → escaped. [cssColor] is an `AnnotationColor.dotHex` today, but it is escaped
 * too: the parameter is a `String`, so the next caller may well forward a stored value. The bundle
 * hands `annotation.color` straight to `Overlayer.highlight`, so the hex must survive untouched.
 *
 * `view.addAnnotation` silently no-ops for a section whose overlayer does not exist yet, which is why
 * WI-4 re-applies the recorded decoration set on every `create-overlay` rather than calling this once.
 */
fun foliateAddAnnotationJs(cfi: String, cssColor: String): String =
    "try{readerAPI.addAnnotation&&readerAPI.addAnnotation(" +
        "{value:${foliateJsString(cfi)},color:${foliateJsString(cssColor)}})}catch(e){}"

/** Erase the highlight anchored at [cfi]. `view.deleteAnnotation({value})` needs no colour. */
fun foliateDeleteAnnotationJs(cfi: String): String =
    "try{readerAPI.deleteAnnotation&&readerAPI.deleteAnnotation({value:${foliateJsString(cfi)}})}catch(e){}"

/**
 * Clear the live text selection inside the mounted section document.
 *
 * A builder rather than an inline string (the plan sketched it inline) for one reason: the
 * `readerAPI` member name is a contract with the vendored bundle, and only a pinned pure builder lets
 * a JVM test prove it — a literal buried in a WebView-bound method is unreachable from any JVM test.
 */
fun foliateDeselectJs(): String = "try{readerAPI.deselect&&readerAPI.deselect()}catch(e){}"

/**
 * feature #142 WI-3 — the pure, WebView-free one-shot machinery behind [FoliateBridge.evalForResult].
 *
 * `WebView.evaluateJavascript` hands its `ValueCallback` whatever the page produced, *whenever* the
 * page produces it — and that "whenever" is the whole hazard this class exists to bound:
 *
 * - **The page never answers** (wedged renderer, a probe that throws before returning). Each probe
 *   carries a wall-clock budget; when it elapses the caller is settled with `null` and the entry is
 *   dropped.
 * - **The page answers twice.** Every probe settles at most once; the later answer is discarded.
 * - **The page answers after teardown.** The callback is DROPPED, not settled-with-null: a null would
 *   still drive the caller's "no anchor" branch and touch state belonging to a finished host. This is
 *   the #165 WI-7 defect class (a bounded callback outliving the Activity that owns its target).
 * - **The answer is malformed.** It is passed through verbatim; this class never parses. Shaping the
 *   result belongs to the caller, which knows what it asked for.
 *
 * RETENTION — why probes are keyed by id rather than by the entry object (Gate-4 round 1, H2). A
 * `WebView` holds its `ValueCallback` until the page answers, which for a wedged renderer is *never*.
 * Had the callback closed over the [Pending] entry, dropping that entry from a registry would free
 * nothing: the WebView's own reference would keep it — and with it the caller's `onResult` and
 * everything that lambda captured (in WI-5, the popover VM and through it the host). So the lambda
 * handed to the WebView captures only a `Long` id and this dispatcher (already reachable from the
 * bridge). Once [pending] no longer holds the id, the caller's lambda is unreachable and a late answer
 * resolves to nothing.
 *
 * THREADING: identical confinement to [FoliateGoToDispatcher]. [pending] is confined to ONE dispatcher
 * — in production [FoliateBridge] (`@MainThread`) supplies a `Dispatchers.Main` scope, `eval` is called
 * from the main-thread host, and `evaluateJavascript` delivers its callback on the main thread too.
 * There is no suspension point inside `settle`, so re-entrancy (a nested `eval` from within a callback)
 * is safe. Tests use `runTest`'s single-threaded scheduler — same confinement.
 */
internal class FoliateEvalDispatcher(
    /** Injects [String] JS and parks the result callback. Production: `webView.evaluateJavascript`. */
    private val sendJs: (String, (String?) -> Unit) -> Unit,
    private val scope: CoroutineScope,
) {
    private class Pending(val onResult: (String?) -> Unit, var timeoutJob: Job? = null)

    /** Every probe awaiting an answer, by id. A registry, not a single slot: rapid re-selection fires a
     *  second probe before the first answers, and neither may steal the other's result. Membership IS
     *  the settled flag — a removed id can never be settled again. */
    private val pending = LinkedHashMap<Long, Pending>()

    private var nextId = 0L

    /** Latched by [teardown]. Refuses new probes and drops every late answer, permanently. */
    private var tornDown = false

    /** Run [js] and deliver its result to [onResult] exactly once — or `null` if the page answered
     *  `null`/`undefined` or did not answer within [timeoutMs]. After [teardown] nothing is injected
     *  and [onResult] is never invoked. Main-thread only. */
    fun eval(js: String, timeoutMs: Long = DEFAULT_EVAL_TIMEOUT_MS, onResult: (String?) -> Unit) {
        if (tornDown) return
        val id = nextId++
        val entry = Pending(onResult)
        pending[id] = entry
        entry.timeoutJob = scope.launch {
            delay(timeoutMs)
            settle(id, null)
        }
        // Captures `id` and this dispatcher — deliberately NOT `entry`. See the RETENTION note above.
        sendJs(js) { raw -> settle(id, normalize(raw)) }
    }

    /** Drop every in-flight probe and refuse all later ones. Idempotent. Called from
     *  [FoliateBridge.destroy] before `WebView.destroy()`, and by the WI-5 host on dispose. */
    fun teardown() {
        tornDown = true
        for (entry in pending.values) entry.timeoutJob?.cancel()
        pending.clear()
    }

    /** Test/diagnostic: how many probes are awaiting an answer. Zero on every exit path. */
    fun pendingCount(): Int = pending.size

    private fun settle(id: Long, value: String?) {
        // remove-then-invoke: the id is gone before the callback runs, so a re-entrant eval() from
        // inside it is a fresh probe and a second answer for this id finds nothing.
        val entry = pending.remove(id) ?: return
        entry.timeoutJob?.cancel()
        entry.onResult(value)
    }

    /** `evaluateJavascript` JSON-encodes the JS result, so a JS `null`/`undefined` arrives as the
     *  literal text. Callers should not have to know that; both become a Kotlin null. An empty string
     *  is a real answer and survives. */
    private fun normalize(raw: String?): String? = when (raw) {
        null, "null", "undefined" -> null
        else -> raw
    }

    companion object {
        /** Budget for a one-shot probe. Short: the selection anchor is only useful for the frame it
         *  was measured in, and the documented degradation is a clamped-default popover position. */
        const val DEFAULT_EVAL_TIMEOUT_MS = 1_000L
    }
}
