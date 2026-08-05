package com.vreader.app.reader

import android.util.Log
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Feature #156 — the shared **computed-style** harness for the EPUB (Readium / Chromium) engine, used by
 * [JustificationEpubStyleSpikeTest] (WI-0's mechanism measurement) and [EpubJustifyConnectedTest]
 * (WI-2's production verification + bug #367 regression). Fixtures live in [EpubFixtures].
 *
 * Every number it returns is read out of the live DOM with `getComputedStyle`. That is the whole point:
 * `assertEquals(JUSTIFY, prefs.textAlign)` passes while ReadiumCSS emits a variable no rule consumes, and
 * `<p>` can already compute `justify` from the PUBLISHER's own stylesheet — so a preference assertion, and
 * even a `<p>`-only assertion, can both be green while zero pixels moved. `body` is the discriminating
 * element for our override because ReadiumCSS names it directly and publishers rarely style it.
 *
 * A read-only window onto one open [ReaderActivity]'s Readium WebView DOM.
 *
 * The probe is deliberately **read-only** — it never mints ids or attributes, because mutating the DOM
 * under measurement is exactly how a rendering assertion starts proving something other than what it
 * claims. Element identity across states is therefore the resource path plus a 40-char text prefix, which
 * is unambiguous for these fixtures.
 */
class EpubDomProbe(private val scenario: ActivityScenario<ReaderActivity>, private val tag: String) {

    companion object {
        const val READER_TAG = "reader-navigator" // ReaderActivity's fragment tag

        /** The minimum text length that makes a resource "prose" rather than a cover / nav page. */
        const val MIN_PROSE_CHARS = 200

        /**
         * Reads the DOM the user is actually looking at.
         *
         * Measures more than one element on purpose: a real EPUB's opening resource can have **zero**
         * `<p>` (a bare cover), and a running head could otherwise stand in for body prose. So it returns
         *  • the longest `<p>` (falling back to the longest block element when a book wraps prose in divs);
         *  • `document.body`, named directly in ReadiumCSS's override selector, hence the element that
         *    isolates OUR effect from the publisher's;
         *  • a census of every substantial `<p>`'s computed `text-align`, split by whether it sits inside a
         *    `blockquote`/`figcaption` (those containers are NOT in the override list, so their prose keeps
         *    inheriting the publisher's alignment);
         *  • the first heading and the root font size, for the advanced type-scale effects.
         */
        const val PROBE_JS = """
            (function(){
              try{
                function pick(sel){
                  var els=document.querySelectorAll(sel), best=null, bl=-1;
                  for(var i=0;i<els.length;i++){var t=(els[i].textContent||'').length; if(t>bl){bl=t;best=els[i];}}
                  return best?{el:best,len:bl}:null;
                }
                function tal(cs){return cs.textAlignLast||cs.webkitTextAlignLast||'';}
                var r=pick('p');
                if(!r||r.len<20){var r2=pick('div,li,blockquote,section'); if(r2&&(!r||r2.len>r.len)) r=r2;}
                var root=document.documentElement, sheets=[];
                var links=document.querySelectorAll('link[rel~=stylesheet]');
                for(var j=0;j<links.length;j++){sheets.push(links[j].getAttribute('href'));}
                var bcs=getComputedStyle(document.body), rcs=getComputedStyle(root);
                var census={}, exempt={}, sampled=0, exemptCount=0;
                var ps=document.querySelectorAll('p');
                for(var k=0;k<ps.length;k++){
                  var el=ps[k]; if((el.textContent||'').length<40) continue;
                  var a=getComputedStyle(el).textAlign||'';
                  if(el.closest&&el.closest('blockquote,figcaption')){exempt[a]=(exempt[a]||0)+1;exemptCount++;}
                  else{census[a]=(census[a]||0)+1;sampled++;}
                }
                var o={found:!!r, pCount:document.querySelectorAll('p').length,
                       textLen:(r?r.len:-1), sheets:sheets.join('|'),
                       lang:(root.getAttribute('lang')||root.getAttribute('xml:lang')||''),
                       rootStyle:(root.getAttribute('style')||''), docHref:location.pathname,
                       textHead:(r?(r.el.textContent||'').replace(/\s+/g,' ').trim().substring(0,40):''),
                       rootFontSize:rcs.fontSize,
                       bodyTextAlign:bcs.textAlign, bodyLineHeight:bcs.lineHeight, bodyFontSize:bcs.fontSize,
                       bodyHyphens:(bcs.hyphens||bcs.webkitHyphens||''), bodyTextAlignLast:tal(bcs),
                       census:census, censusSampled:sampled, exempt:exempt, exemptSampled:exemptCount};
                var h=document.querySelector('h1,h2,h3,h4,h5,h6');
                if(h){var hcs=getComputedStyle(h); o.headingTag=h.tagName; o.headingFontSize=hcs.fontSize;}
                if(r){var cs=getComputedStyle(r.el);
                  o.textAlign=cs.textAlign; o.lineHeight=cs.lineHeight; o.fontSize=cs.fontSize;
                  o.hyphens=(cs.hyphens||cs.webkitHyphens||''); o.textAlignLast=tal(cs); o.tag=r.el.tagName;}
                return JSON.stringify(o);
              }catch(e){return JSON.stringify({found:false,error:String(e)});}
            })()
        """
    }

    fun awaitNavigator() {
        for (i in 0 until 150) {
            if (onActivityValue { it.currentHref() } != null) return
            Thread.sleep(200)
        }
        throw AssertionError("the Readium navigator never rendered a resource")
    }

    private fun <T> onActivityValue(block: (ReaderActivity) -> T): T {
        var out: T? = null
        var set = false
        scenario.onActivity { out = block(it); set = true }
        assertTrue("onActivity ran", set)
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    /** Evaluate [js] against the live navigator ON THE MAIN THREAD (R2BasicWebView.checkThread throws
     *  off-main) and block the test thread for the result. */
    private fun evalJs(js: String): String? {
        // A per-call holder: on timeout we must NOT read a value a still-running coroutine may write
        // later, or a slow evaluation would surface as a stale reading in a subsequent poll.
        val holder = java.util.concurrent.atomic.AtomicReference<String?>(null)
        val done = CountDownLatch(1)
        scenario.onActivity { act ->
            val nav = act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment
            if (nav == null) { done.countDown(); return@onActivity }
            act.lifecycleScope.launch(Dispatchers.Main.immediate) {
                holder.set(runCatching { nav.evaluateJavascript(js) }.getOrNull())
                done.countDown()
            }
        }
        if (!done.await(20, TimeUnit.SECONDS)) {
            Log.w(tag, "evalJs timed out after 20s — discarding this sample")
            return null
        }
        return holder.get()
    }

    /** One evaluation of [PROBE_JS], parsed; null when the evaluation failed or timed out. */
    fun probeOnce(): JSONObject? = evalJson(PROBE_JS)

    /**
     * Evaluate a caller-supplied JSON-returning expression against the same DOM. For readings the generic
     * probe cannot express (specific selectors); always paired with a [settled] call so the state it reads
     * is known to be live and stable.
     */
    fun evalJson(js: String): JSONObject? {
        val raw = evalJs(js) ?: return null
        val decoded = JSONTokener(raw).nextValue()
        return if (decoded is String) JSONObject(decoded) else decoded as? JSONObject
    }

    /**
     * Poll the DOM until it is SETTLED **in the state we asked for**.
     *
     * Waiting only for the `<html>` inline style to stop changing would return the OLD state before a
     * submission had been applied at all — and several conclusions here are *negatives* ("the computed
     * value did not change"), so that would be a silent false-confirmation machine. [require] states the
     * CSS variables that MUST be live before a reading counts; a state that never arrives is an explicit
     * failure, not a quietly stale sample.
     */
    fun settled(description: String, require: (JSONObject) -> Boolean = { true }): JSONObject {
        var previous: String? = null
        var stableCount = 0
        var last: JSONObject? = null
        for (i in 0 until 60) {
            val json = probeOnce()
            if (json != null) {
                last = json
                // An error object or a document with no measurable text is NEVER a valid reading.
                if (json.optBoolean("found") && !json.has("error")) {
                    val style = json.optString("rootStyle")
                    stableCount = if (previous == style) stableCount + 1 else 0
                    previous = style
                    if (stableCount >= 1 && require(json)) return json
                }
            }
            Thread.sleep(250)
        }
        throw AssertionError(
            "the DOM never settled into the required state [$description] — refusing to report a stale or " +
                "invalid reading. last=${last?.optString("rootStyle")} found=${last?.optBoolean("found")}",
        )
    }

    /**
     * Poll until the `<html>` inline style stops changing and return whatever the DOM says — INCLUDING a
     * resource with no text element at all. Used only while paging towards prose: a real EPUB's opening
     * resource can be a bare cover, a legitimate intermediate state, not a measurement. Measurements
     * always go through the strict [settled].
     */
    private fun settledRaw(): JSONObject? {
        var previous: String? = null
        var last: JSONObject? = null
        for (i in 0 until 12) {
            val json = probeOnce()
            if (json != null) {
                last = json
                val style = json.optString("rootStyle")
                if (previous == style && i >= 1) return json
                previous = style
            }
            Thread.sleep(250)
        }
        return last
    }

    /**
     * Page forward until the visible resource actually contains prose, using the navigator's own
     * `goForward` — the same motion a reading user makes. A real EPUB opens on a cover / title resource
     * that can have ZERO `<p>`; WI-0's first run measured exactly that and produced empty computed values.
     */
    fun advanceToProse(label: String, require: (JSONObject) -> Boolean = { true }): JSONObject {
        var probe = settledRaw()
        for (step in 0 until 30) {
            if (probe != null && probe.optBoolean("found") && !probe.has("error") &&
                probe.optInt("textLen") >= MIN_PROSE_CHARS && require(probe)
            ) {
                Log.i(tag, "advanceToProse $label steps=$step tag=${probe.optString("tag")} textLen=${probe.optInt("textLen")}")
                // The permissive sampler above is ONLY a navigation aid — it may return a transitional
                // sample. The BASELINE that later comparisons are measured against must be as strict as
                // every other measurement, or a mid-reflow baseline could coincidentally equal the
                // post-change value and manufacture a "nothing changed" result.
                return settled("$label: settled baseline on prose") {
                    it.optInt("textLen") >= MIN_PROSE_CHARS && require(it)
                }
            }
            var moved = false
            scenario.onActivity { act ->
                moved = (act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment)
                    ?.goForward(false) ?: false
            }
            if (!moved) Log.w(tag, "advanceToProse $label goForward returned false at step $step")
            Thread.sleep(400)
            probe = settledRaw()
        }
        throw AssertionError(
            "$label: never reached a resource satisfying the measurement precondition (>= $MIN_PROSE_CHARS " +
                "chars of prose) — a measurement taken on a cover/nav page would prove nothing",
        )
    }

    /**
     * `submitPreferences` REPLACES the whole preference set rather than merging, so every submission pins
     * `scroll = true` — the production default for a Scroll-layout install (the host opens with
     * `scroll = layout == Scroll`). Without it a run can flip to `readium-paged-on` midway, an
     * uncontrolled second variable in a before/after comparison.
     *
     * A MISSING navigator is a hard failure, not a silent no-op: submitting nothing and then measuring
     * "no change" would manufacture exactly the negative results these tests report.
     */
    @OptIn(ExperimentalReadiumApi::class)
    fun submit(prefs: EpubPreferences) {
        var submitted = false
        scenario.onActivity { act ->
            val nav = act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment
            if (nav != null) { nav.submitPreferences(EpubPreferences(scroll = true) + prefs); submitted = true }
        }
        assertTrue("the Readium navigator must exist for a preference submission to mean anything", submitted)
    }

    fun logState(label: String, book: String, state: String, p: JSONObject) {
        Log.i(
            tag,
            "$label book=$book state=$state tag=${p.optString("tag")} bodyTextAlign=${p.optString("bodyTextAlign")} " +
                "bodyLineHeight=${p.optString("bodyLineHeight")} bodyFontSize=${p.optString("bodyFontSize")} " +
                "bodyHyphens=${p.optString("bodyHyphens")} bodyTextAlignLast=${p.optString("bodyTextAlignLast")} " +
                "pTextAlign=${p.optString("textAlign")} pLineHeight=${p.optString("lineHeight")} " +
                "pFontSize=${p.optString("fontSize")} rootFontSize=${p.optString("rootFontSize")} " +
                "heading=${p.optString("headingTag")}/${p.optString("headingFontSize")} " +
                "census=${p.optJSONObject("census")} exempt=${p.optJSONObject("exempt")} " +
                "lang=${p.optString("lang")} pCount=${p.optInt("pCount")} textLen=${p.optInt("textLen")} " +
                "sheets=${p.optString("sheets")} rootStyle=${p.optString("rootStyle")}",
        )
    }
}
