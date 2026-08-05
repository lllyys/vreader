// Purpose: feature #156 WI-3 — the **computed-style + line-geometry** harness for the AZW3 (foliate-js /
// Chromium) engine, used by Azw3JustifyConnectedTest. A read-only window onto ONE open
// Azw3ReaderActivity's foliate WebView, plus the ability to re-inject a CSS blob through the EXACT
// production seam (`foliateSetStylesJs` — the string FoliateBridge.setStyles evaluates), so a
// with-rule / without-rule differential runs against the same document, same width, same fonts.
//
// Why a differential rather than a single reading: a book's own publisher stylesheet can already compute
// `justify` on `<p>` (WI-2 hit exactly that on the CJK EPUB), so "computed text-align == justify" can be
// green for entirely the wrong reason. Comparing the SAME paragraph under the production CSS and under a
// faithful pre-#156 reconstruction is what isolates OUR rule's effect.
//
// Foliate renders each book section into a `blob:` SUBFRAME (sandbox=allow-same-origin), so the section
// document is reached through the renderer the same way foliate's own setStyles reaches it:
// `document.getElementById('view').renderer.getContents()[0].doc`.
//
// @coordinates-with: Azw3ReaderActivity.kt (the host under measurement), Azw3DisplayCss.kt (the CSS blob
//   being verified), foliate/FoliateBridge.kt (`foliateSetStylesJs`, the injection seam).
package com.vreader.app.reader

import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import com.vreader.app.reader.foliate.foliateSetStylesJs
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** One merged line box of a measured element: its horizontal extent in the section document. */
data class LineBox(val left: Double, val right: Double, val top: Double)

class Azw3DomProbe(
    private val scenario: ActivityScenario<Azw3ReaderActivity>,
    private val tag: String,
) {

    companion object {
        /**
         * The minimum text length that makes an element "prose" rather than a heading / running head.
         * Set high enough that the subject paragraph reliably wraps to several lines — a two-line
         * paragraph has exactly one justifiable line, which is too thin a base for a collapse claim.
         */
        const val MIN_PROSE_CHARS = 200

        /**
         * Reads the DOM the user is actually looking at — the mounted section document.
         *
         * Returns, per sample: the concatenated text of the injected `<style>` elements (so a reading can
         * be tied to the arm that produced it — this is the settling discriminator, not a guess about
         * timing); the longest prose element and its computed `text-align`, inline `style`/`class` (so a
         * guard-exempt paragraph is never silently used as the subject) and its per-line client rects;
         * `document.body`'s computed alignment (our rule is `p`-scoped, so body is expected NOT to move —
         * that is evidence, not an oversight); a census of every substantial `<p>`'s computed alignment;
         * and every heading's computed alignment (AC-7's "headings do not justify" half).
         */
        const val PROBE_JS = """
            (function(){
              try{
                var v=document.getElementById('view');
                var r=v&&v.renderer;
                var cs=(r&&r.getContents)?r.getContents():null;
                if(!cs||!cs.length) return JSON.stringify({found:false,reason:'no-mounted-view'});
                var d=cs[0].doc;
                if(!d||!d.body) return JSON.stringify({found:false,reason:'no-document'});
                var styleText='';
                var ss=d.querySelectorAll('style');
                for(var i=0;i<ss.length;i++){styleText+=(ss[i].textContent||'');}
                // The subject must be WRAPPED prose. A Kindle front-matter page (copyright, title,
                // colophon) is one <p> whose "lines" are separated by <br>, and EVERY such line is the
                // last line of its own run — which no engine justifies. Measuring one would report
                // computed `justify` with zero glyphs moved and look exactly like a CJK no-op. So a
                // <br>-bearing element is never the subject; the walk pages on until real prose appears.
                function pick(sel){
                  var els=d.querySelectorAll(sel),best=null,bl=-1;
                  for(var i=0;i<els.length;i++){
                    var e=els[i];
                    if(e.getAttribute&&e.getAttribute('data-vreader-probe')) continue;
                    if(e.querySelector&&e.querySelector('br')) continue;
                    var t=(e.textContent||'').length; if(t>bl){bl=t;best=e;}
                  }
                  return best?{el:best,len:bl}:null;
                }
                var p=pick('p');
                if(!p||p.len<20){var q=pick('div,li,section'); if(q&&(!p||q.len>p.len)) p=q;}
                function rectsOf(el){
                  var rg=d.createRange(); rg.selectNodeContents(el);
                  var rs=rg.getClientRects(), out=[];
                  for(var i=0;i<rs.length;i++){
                    if(!(rs[i].width>0.5)) continue;
                    out.push([Math.round(rs[i].left*100)/100,Math.round(rs[i].right*100)/100,
                              Math.round(rs[i].top*100)/100]);
                  }
                  return out;
                }
                var census={},sampled=0;
                var ps=d.querySelectorAll('p');
                for(var k=0;k<ps.length;k++){
                  var el=ps[k]; if((el.textContent||'').length<40) continue;
                  var a=getComputedStyle(el).textAlign||''; census[a]=(census[a]||0)+1; sampled++;
                }
                var heads=[],hs=d.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for(var m=0;m<hs.length&&m<8;m++){
                  heads.push({tag:hs[m].tagName,align:getComputedStyle(hs[m]).textAlign||'',
                              len:(hs[m].textContent||'').length});
                }
                var bcs=getComputedStyle(d.body),rcs=getComputedStyle(d.documentElement);
                var o={found:!!p,docIndex:(cs[0].index==null?-1:cs[0].index),mounted:cs.length,
                       styleHasJustify:/text-align:\s*justify/.test(styleText),styleLen:styleText.length,
                       bodyTextAlign:bcs.textAlign,bodyFontSize:bcs.fontSize,bodyLineHeight:bcs.lineHeight,
                       rootFontSize:rcs.fontSize,docWidth:(d.documentElement.clientWidth||0),
                       census:census,censusSampled:sampled,headings:heads,
                       pCount:d.querySelectorAll('p').length};
                if(p){
                  var pcs=getComputedStyle(p.el);
                  o.tag=p.el.tagName; o.textLen=p.len;
                  o.textHead=(p.el.textContent||'').replace(/\s+/g,' ').trim().substring(0,40);
                  o.pTextAlign=pcs.textAlign; o.pTextIndent=pcs.textIndent;
                  o.pInlineStyle=(p.el.getAttribute('style')||'');
                  o.pClass=(p.el.getAttribute('class')||'');
                  o.pAlignAttr=(p.el.getAttribute('align')||'');
                  o.rects=rectsOf(p.el);
                }
                return JSON.stringify(o);
              }catch(e){return JSON.stringify({found:false,error:String(e)});}
            })()
        """
    }

    /** The production WebView, found by walking the Activity's view tree (no production test hook). */
    private fun webView(): WebView? {
        var found: WebView? = null
        scenario.onActivity { act -> found = firstWebView(act.window.decorView) }
        return found
    }

    private fun firstWebView(v: View): WebView? {
        if (v is WebView) return v
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) firstWebView(v.getChildAt(i))?.let { return it }
        }
        return null
    }

    /**
     * Evaluate [js] in the foliate WebView ON THE MAIN THREAD and block the test thread for the result.
     * A per-call holder: on timeout we must NOT read a value a late callback may write afterwards, or a
     * slow evaluation would surface as a stale reading in a later poll.
     */
    private fun evalJs(js: String): String? {
        val holder = AtomicReference<String?>(null)
        val done = CountDownLatch(1)
        scenario.onActivity { act ->
            val wv = firstWebView(act.window.decorView)
            if (wv == null) {
                // Distinguishable from "the page returned nothing" — a probe that silently loops on a
                // missing WebView would look identical to a book that never rendered.
                Log.w(tag, "evalJs: NO WebView in the Activity view tree")
                done.countDown(); return@onActivity
            }
            wv.evaluateJavascript(js) { value -> holder.set(value); done.countDown() }
        }
        if (!done.await(20, TimeUnit.SECONDS)) {
            Log.w(tag, "evalJs timed out after 20s — discarding this sample")
            return null
        }
        return holder.get()
    }

    fun evalJson(js: String): JSONObject? {
        val raw = evalJs(js) ?: return null
        if (raw == "null") return null
        val decoded = runCatching { JSONTokener(raw).nextValue() }.getOrNull() ?: return null
        return if (decoded is String) runCatching { JSONObject(decoded) }.getOrNull() else decoded as? JSONObject
    }

    fun probeOnce(): JSONObject? = evalJson(PROBE_JS)

    /** A structural read of the shell, for diagnosing a probe that finds nothing. Never throws. */
    fun structure(): String? = evalJs(
        """
        (function(){
          try{
            var v=document.getElementById('view');
            var r=v&&v.renderer;
            var cs=(r&&r.getContents)?r.getContents():null;
            var d=(cs&&cs.length)?cs[0].doc:null;
            return JSON.stringify({
              hasView:!!v, hasRenderer:!!r, rendererTag:(r?r.tagName:''),
              hasGetContents:!!(r&&r.getContents), mounted:(cs?cs.length:-1),
              frames:window.frames.length,
              hasDoc:!!d, bodyLen:(d&&d.body?(d.body.textContent||'').length:-1),
              pCount:(d?d.querySelectorAll('p').length:-1),
              readerAPI:!!window.readerAPI
            });
          }catch(e){return JSON.stringify({error:String(e)});}
        })()
        """,
    )

    /** Advance one page through the production `readerAPI.next()` (the same call the tap zones make). */
    private fun nextPage() { evalJs("try{readerAPI.next&&readerAPI.next()}catch(e){}") }

    /**
     * Wait for the reader to mount a section document, then page forward until it actually contains
     * prose. A real Kindle book opens on a cover / title / TOC resource that can carry no `<p>` at all —
     * measuring alignment there would prove nothing. Fails loudly (never skips) if prose is unreachable,
     * and reports the shell's structure so a null probe is distinguishable from a text-free page.
     */
    fun awaitRender() {
        var raw: String? = null
        for (attempt in 0 until 40) {
            val p = probeOnce()
            raw = p?.toString()
            if (p != null && p.optBoolean("found") && p.optInt("textLen") >= MIN_PROSE_CHARS) {
                Log.i(tag, "awaitRender: prose reached after $attempt step(s) — ${p.optString("tag")} len=${p.optInt("textLen")}")
                return
            }
            if (attempt % 4 == 3) {
                Log.i(tag, "awaitRender step=$attempt still no prose; last=$raw structure=${structure()}")
                nextPage()
            }
            Thread.sleep(900)
        }
        throw AssertionError(
            "the AZW3 reader never presented a section document with >= $MIN_PROSE_CHARS chars of prose " +
                "— nothing to measure. last probe=$raw structure=${structure()}",
        )
    }

    /**
     * Poll until the DOM is settled **in the state we asked for**. Several readings here are
     * comparisons where "no change" is a legal outcome, so a sampler that returns the OLD state would be
     * a silent false-confirmation machine: [require] states what MUST be live before a reading counts,
     * and a state that never arrives is an explicit failure rather than a quietly stale sample.
     */
    fun settled(description: String, require: (JSONObject) -> Boolean): JSONObject {
        var previous: String? = null
        var stable = 0
        var last: JSONObject? = null
        for (i in 0 until 60) {
            val json = probeOnce()
            if (json != null && json.optBoolean("found") && !json.has("error")) {
                last = json
                val signature = "${json.optBoolean("styleHasJustify")}|${json.optInt("styleLen")}|" +
                    "${json.optString("pTextAlign")}|${json.optString("textHead")}"
                stable = if (previous == signature) stable + 1 else 0
                previous = signature
                if (stable >= 1 && require(json)) return json
            }
            Thread.sleep(250)
        }
        throw AssertionError(
            "the AZW3 DOM never settled into the required state [$description] — refusing to report a " +
                "stale or invalid reading. last: styleHasJustify=${last?.optBoolean("styleHasJustify")} " +
                "pTextAlign=${last?.optString("pTextAlign")} found=${last?.optBoolean("found")}",
        )
    }

    /**
     * Inject [css] through the EXACT production seam — `foliateSetStylesJs` is the string
     * `FoliateBridge.setStyles` hands to `evaluateJavascript`, so the control arm is driven by production
     * code, not a test reimplementation of it. A missing WebView is a hard failure: injecting nothing and
     * then measuring "unchanged" would manufacture the very result this harness exists to test.
     */
    fun setStyles(css: String) {
        assertTrue("the foliate WebView must exist for a style injection to mean anything", webView() != null)
        evalJs(foliateSetStylesJs(css))
    }

    fun logState(label: String, arm: String, p: JSONObject) {
        Log.i(
            tag,
            "$label arm=$arm hasJustifyRule=${p.optBoolean("styleHasJustify")} tag=${p.optString("tag")} " +
                "pTextAlign=${p.optString("pTextAlign")} bodyTextAlign=${p.optString("bodyTextAlign")} " +
                "bodyFontSize=${p.optString("bodyFontSize")} rootFontSize=${p.optString("rootFontSize")} " +
                "pTextIndent=${p.optString("pTextIndent")} pInlineStyle='${p.optString("pInlineStyle")}' " +
                "pClass='${p.optString("pClass")}' pAlignAttr='${p.optString("pAlignAttr")}' " +
                "census=${p.optJSONObject("census")} sampled=${p.optInt("censusSampled")} " +
                "headings=${p.optJSONArray("headings")} docIndex=${p.optInt("docIndex")} " +
                "mounted=${p.optInt("mounted")} docWidth=${p.optInt("docWidth")} " +
                "pCount=${p.optInt("pCount")} textLen=${p.optInt("textLen")} " +
                "textHead='${p.optString("textHead")}' rects=${rectSummary(p)}",
        )
    }

    private fun rectSummary(p: JSONObject): String {
        val lines = lineBoxes(p)
        return "n=${lines.size} " + lines.joinToString(" ") { "[${it.left},${it.right}]" }
    }
}

/**
 * Merge a probe's raw client rects into LINE BOXES, **in document order**.
 *
 * `Range.getClientRects()` emits one rect per inline fragment, so a line containing an `<em>` yields
 * several. Consecutive rects on the SAME rounded `top` whose left continues the previous right (within
 * 2px) belong to one line. The 2px tolerance deliberately cannot bridge a COLUMN gap — foliate paginates
 * with multi-column layout, and column gaps are tens of px — so lines in different columns stay distinct
 * rather than being fused into one absurdly wide "line".
 *
 * **Document order is preserved on purpose; do NOT sort by (top, left).** In a multi-column layout every
 * column restarts at the same `top`, so a positional sort INTERLEAVES the columns — which silently makes
 * "the last element" some mid-paragraph line instead of the paragraph's final one. That matters because
 * the final line is precisely the line justification must leave alone, and an earlier revision of this
 * helper sorted, then excluded the wrong line from the justifiable set.
 */
fun lineBoxes(p: JSONObject): List<LineBox> {
    val raw: JSONArray = p.optJSONArray("rects") ?: return emptyList()
    val rects = (0 until raw.length()).mapNotNull { i ->
        raw.optJSONArray(i)?.let { Triple(it.optDouble(0), it.optDouble(1), it.optDouble(2)) }
    }
    val out = mutableListOf<LineBox>()
    for ((left, right, top) in rects) {
        val prev = out.lastOrNull()
        if (prev != null && Math.round(prev.top) == Math.round(top) && left <= prev.right + 2.0) {
            out[out.size - 1] = prev.copy(right = maxOf(prev.right, right))
        } else {
            out.add(LineBox(left, right, top))
        }
    }
    return out
}

/**
 * Assign each line box a COLUMN index by clustering their left edges.
 *
 * Foliate paginates with CSS multi-column, so a single paragraph's lines are spread across two or three
 * columns whose right edges are hundreds of px apart. A raggedness/collapse figure computed across all
 * of them measures the column pitch, not the alignment — the spread stays ~775px whether the text is
 * justified or not. Columns are separated by hundreds of px while a first-line `text-indent` shifts a
 * left edge by only tens, so a 60px tolerance splits columns without splitting an indented first line
 * off its own column.
 */
fun columnIndices(lines: List<LineBox>, tolerancePx: Double = 60.0): List<Int> {
    val lefts = lines.map { it.left }.distinct().sorted()
    val clusters = mutableListOf<MutableList<Double>>()
    for (l in lefts) {
        val last = clusters.lastOrNull()
        if (last != null && l - last.last() <= tolerancePx) last.add(l) else clusters.add(mutableListOf(l))
    }
    return lines.map { line -> clusters.indexOfFirst { c -> c.any { it == line.left } } }
}
