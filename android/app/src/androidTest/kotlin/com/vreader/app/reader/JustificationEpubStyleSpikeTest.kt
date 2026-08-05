package com.vreader.app.reader

import android.util.Log
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.settings.ReaderSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.readium.r2.navigator.preferences.TextAlign as ReadiumTextAlign

/**
 * Feature #156 WI-0 — the **measurement spike** for the EPUB (Readium / Chromium) engine. No production
 * code. Every number is read out of the live **DOM** with `getComputedStyle`, never off an
 * `EpubPreferences` object: plan §7.1 and §8 both name `assertEquals(JUSTIFY, prefs.textAlign)` as THE
 * trap — it passes while ReadiumCSS emits a variable no rule consumes (W10) and while the CJK stylesheet
 * contains no such rule at all (W12).
 *
 *  • **M3** — `getComputedStyle(p).textAlign` on the real `en` and `zh-CN` EPUBs, each under three
 *    preference states: production default (`publisherStyles` unset), `textAlign = JUSTIFY` alone
 *    (still unset), and `textAlign = JUSTIFY` + `publisherStyles = false`. The `en` book returning
 *    `justify` ONLY in the third state is the W10 proof that the flag is load-bearing; the `zh-CN` book's
 *    result settles the §4.3(b) CJK-stylesheet prediction (W12–W14).
 *  • **M4** — **bug #367 / GH #2074**. Computed `line-height` before/after a real line-spacing change
 *    made through the production store (which re-submits `toEpubPreferences()`, `publisherStyles` unset).
 *    Unchanged ⇒ #129's EPUB line-spacing slider is inert ⇒ bug confirmed. The same measurement is then
 *    repeated with `publisherStyles = false` to show that flag is the fix (WI-2).
 *
 * The probe also returns the `<html>` inline style and the injected stylesheet hrefs, so the run captures
 * DIRECT on-device evidence of `readium-advanced-on` / `--USER__*` presence and of which ReadiumCSS
 * stylesheet (default vs `cjk-horizontal`) the publication resolved to — W10/W12/W13/W14 read off the
 * shipped artifacts at runtime rather than inferred.
 *
 * Real-books-first: both EPUBs are the genuine gitignored fixtures pushed to the app's scoped external
 * files dir (the connected task wipes that dir at run END — re-push every run). Byte-size identity checks
 * refuse to label a truncated/stale file "real". Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class JustificationEpubStyleSpikeTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    private companion object {
        const val TAG = "WI0-JUSTIFY"
        const val READER_TAG = "reader-navigator"          // ReaderActivity's fragment tag
        const val EN_FILE = "m3-en.epub"
        const val EN_BYTES = 1_302_140L
        const val ZH_FILE = "m3-zh.epub"
        const val ZH_BYTES = 19_381_838L

        /** The minimum text length that makes a resource "prose" rather than a cover / nav page. */
        const val MIN_PROSE_CHARS = 200

        /**
         * Reads the DOM the user is actually looking at. Returns a JSON string (an expression, so
         * `evaluateJavascript` yields it as a JSON-encoded value).
         *
         * Measures TWO elements, because the first run showed the opening resource of a real EPUB can have
         * **zero** `<p>` (a cover page), which would have silently produced empty readings:
         *  • the LONGEST `<p>` (falling back to the longest block element when a book wraps prose in
         *    `div`s) — so a running head / page number can never stand in for body prose; and
         *  • `document.body` itself, which is named DIRECTLY in ReadiumCSS's override selector
         *    (`:not(blockquote):not(figcaption) p, body, li`), so it is the one element guaranteed to
         *    exist and to be in scope of the rule under test.
         */
        const val PROBE_JS = """
            (function(){
              try{
                function pick(sel){
                  var els=document.querySelectorAll(sel), best=null, bl=-1;
                  for(var i=0;i<els.length;i++){var t=(els[i].textContent||'').length; if(t>bl){bl=t;best=els[i];}}
                  return best?{el:best,len:bl}:null;
                }
                var r=pick('p');
                if(!r||r.len<20){var r2=pick('div,li,blockquote,section'); if(r2&&(!r||r2.len>r.len)) r=r2;}
                var root=document.documentElement, sheets=[];
                var links=document.querySelectorAll('link[rel~=stylesheet]');
                for(var j=0;j<links.length;j++){sheets.push(links[j].getAttribute('href'));}
                var bcs=getComputedStyle(document.body);
                var o={found:!!r, pCount:document.querySelectorAll('p').length,
                       textLen:(r?r.len:-1), sheets:sheets.join('|'),
                       lang:(root.getAttribute('lang')||root.getAttribute('xml:lang')||''),
                       rootStyle:(root.getAttribute('style')||''), docHref:location.pathname,
                       textHead:(r?(r.el.textContent||'').replace(/\s+/g,' ').trim().substring(0,40):''),
                       bodyTextAlign:bcs.textAlign, bodyLineHeight:bcs.lineHeight, bodyFontSize:bcs.fontSize};
                if(r){var cs=getComputedStyle(r.el);
                  o.textAlign=cs.textAlign; o.lineHeight=cs.lineHeight; o.fontSize=cs.fontSize;
                  o.hyphens=(cs.hyphens||cs.webkitHyphens||''); o.tag=r.el.tagName;}
                return JSON.stringify(o);
              }catch(e){return JSON.stringify({found:false,error:String(e)});}
            })()
        """
    }

    /** Restore the pre-test display settings so this class leaves no residue for later classes. */
    private lateinit var original: ReaderSettings

    @Before fun captureSettings() = runBlocking<Unit> {
        original = app.container.readerSettingsStore.current()
        app.container.readerSettingsStore.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
    }

    @After fun restoreSettings() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(original.theme)
        store.setFontFamily(original.fontFamily)
        store.setFontSize(original.fontSizeSp)
        store.setLineSpacing(original.lineSpacing)
        store.setMargin(original.marginDp)
    }

    // ---------------------------------------------------------------- fixtures

    /** Import the genuine pushed EPUB; fails loudly (never silently substitutes) if it is absent or the
     *  wrong size — a synthetic stand-in would make the CJK / publisher-styles findings hollow. */
    private fun importRealEpub(file: String, expectedBytes: Long): Book {
        val dir = requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)) { "no external files dir" }
        val f = File(dir, file)
        assertTrue(
            "M3/M4 require the REAL EPUB at ${f.absolutePath} — push it before the run " +
                "(the connected task wipes this dir at run end)",
            f.exists() && f.canRead(),
        )
        assertEquals("$file must be the genuine real book, not a truncated/stale copy", expectedBytes, f.length())
        return runBlocking { app.container.importer.importStream("content://test/$file", file, f.inputStream()) }
    }

    // ---------------------------------------------------------------- probes

    private fun <T> onActivityValue(scenario: ActivityScenario<ReaderActivity>, block: (ReaderActivity) -> T): T {
        var out: T? = null
        var set = false
        scenario.onActivity { out = block(it); set = true }
        assertTrue("onActivity ran", set)
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    private fun awaitNavigator(scenario: ActivityScenario<ReaderActivity>) {
        for (i in 0 until 150) {
            if (onActivityValue(scenario) { it.currentHref() } != null) return
            Thread.sleep(200)
        }
        throw AssertionError("the Readium navigator never rendered a resource")
    }

    /** Evaluate [js] against the live navigator ON THE MAIN THREAD (R2BasicWebView.checkThread throws
     *  off-main) and block the test thread for the result. */
    private fun evalJs(scenario: ActivityScenario<ReaderActivity>, js: String): String? {
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
            Log.w(TAG, "evalJs timed out after 20s — discarding this sample")
            return null
        }
        return holder.get()
    }

    /**
     * Poll the DOM until it is SETTLED **in the state we asked for**.
     *
     * The first version of this helper only waited for the `<html>` inline style to stop changing, which
     * meant it could return the OLD state before a `submitPreferences` / store emission had been applied
     * at all — and every one of this class's conclusions is a *negative* ("the computed value did not
     * change"), so that would have been a silent false-confirmation machine. [require] therefore states
     * the CSS variables that MUST be present before a reading counts, and a state that never arrives is
     * an explicit failure rather than a quietly stale sample.
     */
    private fun settledProbe(
        scenario: ActivityScenario<ReaderActivity>,
        description: String,
        require: (JSONObject) -> Boolean = { true },
    ): JSONObject {
        var previous: String? = null
        var stableCount = 0
        var last: JSONObject? = null
        for (i in 0 until 60) {
            val json = probeOnce(scenario)
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

    /** One evaluation of [PROBE_JS], parsed; null when the evaluation failed or timed out. */
    private fun probeOnce(scenario: ActivityScenario<ReaderActivity>): JSONObject? {
        val raw = evalJs(scenario, PROBE_JS) ?: return null
        val decoded = JSONTokener(raw).nextValue()
        return if (decoded is String) JSONObject(decoded) else decoded as? JSONObject
    }

    /**
     * Poll until the `<html>` inline style stops changing and return whatever the DOM says — INCLUDING a
     * resource with no text element at all. Used only while paging towards prose: a real EPUB's opening
     * resource can be a bare cover (`<body><img/></body>`), which is a legitimate intermediate state, not
     * a measurement. Measurements always go through the strict [settledProbe].
     */
    private fun settledRaw(scenario: ActivityScenario<ReaderActivity>): JSONObject? {
        var previous: String? = null
        var last: JSONObject? = null
        for (i in 0 until 12) {
            val json = probeOnce(scenario)
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

    /** True when ReadiumCSS's advanced-settings gate (`publisherStyles = false`) is on in the live DOM. */
    private fun advancedOn(p: JSONObject) = p.optString("rootStyle").contains("readium-advanced-on")

    /** True when [decl] (e.g. `--USER__textAlign: justify`) is present in the live `<html>` inline style. */
    private fun hasDecl(p: JSONObject, decl: String) = p.optString("rootStyle").contains(decl)

    /**
     * `submitPreferences` REPLACES the whole preference set rather than merging, so every submission here
     * pins `scroll = true` — the production default (the host opens with `scroll = layout == Scroll`).
     * Without it the first run flipped the reader to `readium-paged-on` midway, which would have been an
     * uncontrolled second variable in the before/after comparison.
     *
     * A MISSING navigator is a hard failure, not a silent no-op: submitting nothing and then measuring
     * "no change" would manufacture exactly the negative results this class reports.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun submit(scenario: ActivityScenario<ReaderActivity>, prefs: EpubPreferences) {
        var submitted = false
        scenario.onActivity { act ->
            val nav = act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment
            if (nav != null) { nav.submitPreferences(EpubPreferences(scroll = true) + prefs); submitted = true }
        }
        assertTrue("the Readium navigator must exist for a preference submission to mean anything", submitted)
    }

    /**
     * Page forward until the visible resource actually contains prose. A real EPUB opens on a cover /
     * title resource that can have ZERO `<p>` — the first run measured exactly that and produced empty
     * computed values, so this is not a hypothetical. Uses the navigator's own `goForward`, i.e. the same
     * motion a reading user makes.
     */
    private fun advanceToProse(scenario: ActivityScenario<ReaderActivity>, label: String): JSONObject {
        var probe = settledRaw(scenario)
        for (step in 0 until 30) {
            if (probe != null && probe.optBoolean("found") && !probe.has("error") &&
                probe.optInt("textLen") >= MIN_PROSE_CHARS
            ) {
                Log.i(TAG, "advanceToProse $label steps=$step tag=${probe.optString("tag")} textLen=${probe.optInt("textLen")}")
                return probe
            }
            var moved = false
            scenario.onActivity { act ->
                moved = (act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment)
                    ?.goForward(false) ?: false
            }
            if (!moved) Log.w(TAG, "advanceToProse $label goForward returned false at step $step")
            Thread.sleep(400)
            probe = settledRaw(scenario)
        }
        throw AssertionError(
            "$label: never reached a resource with >= $MIN_PROSE_CHARS chars of prose — the measurement " +
                "would be taken on a cover/nav page and would prove nothing",
        )
    }

    private fun log(label: String, book: String, state: String, p: JSONObject) {
        Log.i(
            TAG,
            "$label book=$book state=$state tag=${p.optString("tag")} textAlign=${p.optString("textAlign")} " +
                "lineHeight=${p.optString("lineHeight")} fontSize=${p.optString("fontSize")} " +
                "hyphens=${p.optString("hyphens")} bodyTextAlign=${p.optString("bodyTextAlign")} " +
                "bodyLineHeight=${p.optString("bodyLineHeight")} lang=${p.optString("lang")} " +
                "pCount=${p.optInt("pCount")} textLen=${p.optInt("textLen")} " +
                "sheets=${p.optString("sheets")} rootStyle=${p.optString("rootStyle")}",
        )
    }

    // ---------------------------------------------------------------- M3

    /** The computed `text-align` of the prose element and of `body`, under one preference state. */
    private data class AlignReading(val element: String, val body: String, val tag: String)

    /** The three readings plus the invariants that prove all three measured the SAME content. */
    private data class AlignRun(
        val default: AlignReading,
        val justifyOnly: AlignReading,
        val withFlag: AlignReading,
        val lang: String,
        val sheets: String,
        val docHref: String,
        val textHead: String,
        val sameContentThroughout: Boolean,
    )

    @OptIn(ExperimentalReadiumApi::class)
    private fun measureTextAlign(file: String, bytes: Long, label: String): AlignRun {
        val book = importRealEpub(file, bytes)
        var out: AlignRun? = null
        ActivityScenario.launch<ReaderActivity>(
            ReaderActivity.intent(instrumentation.targetContext, book.fingerprintKey),
        ).use { scenario ->
            awaitNavigator(scenario)
            val default = advanceToProse(scenario, label)
            log("M3", label, "production-default(publisherStyles-unset)", default)
            assertTrue(
                "$label: the probe must be measuring real prose (>= $MIN_PROSE_CHARS chars), not a cover page",
                default.optInt("textLen") >= MIN_PROSE_CHARS,
            )
            assertTrue(
                "$label: the production default must NOT already have the advanced gate on " +
                    "(publisherStyles is never set in production — W9)",
                !advancedOn(default),
            )

            // Each submission is followed by a probe that REQUIRES the requested variables to be live in
            // the DOM, so a reading can never be of the previous state.
            submit(scenario, EpubPreferences(textAlign = ReadiumTextAlign.JUSTIFY))
            val justifyOnly = settledProbe(scenario, "$label: --USER__textAlign live, advanced gate OFF") {
                hasDecl(it, "--USER__textAlign: justify") && !advancedOn(it)
            }
            log("M3", label, "textAlign=JUSTIFY,publisherStyles-unset", justifyOnly)

            submit(scenario, EpubPreferences(textAlign = ReadiumTextAlign.JUSTIFY, publisherStyles = false))
            val withFlag = settledProbe(scenario, "$label: --USER__textAlign live, advanced gate ON") {
                hasDecl(it, "--USER__textAlign: justify") && advancedOn(it)
            }
            log("M3", label, "textAlign=JUSTIFY,publisherStyles=false", withFlag)

            fun read(p: JSONObject) =
                AlignReading(p.optString("textAlign"), p.optString("bodyTextAlign"), p.optString("tag"))
            val states = listOf(default, justifyOnly, withFlag)
            out = AlignRun(
                default = read(default), justifyOnly = read(justifyOnly), withFlag = read(withFlag),
                lang = default.optString("lang"),
                sheets = default.optString("sheets"),
                docHref = default.optString("docHref"),
                textHead = default.optString("textHead"),
                // All three readings must come from the same resource AND the same element, or a
                // "nothing changed" verdict could just be two different paragraphs.
                sameContentThroughout = states.map { it.optString("docHref") }.distinct().size == 1 &&
                    states.map { it.optString("textHead") }.distinct().size == 1,
            )
        }
        return out!!
    }

    /**
     * **M3 (Latin `en`)** — the W10 proof: `textAlign = JUSTIFY` is INERT while `publisherStyles` is
     * unset, and takes effect only once the flag gates `readium-advanced-on` on. This pair is what makes
     * WI-2's two properties inseparable (plan §7.2).
     */
    @Test fun m3_enEpub_justifyRequiresPublisherStylesFalse() {
        val run = measureTextAlign(EN_FILE, EN_BYTES, "real:The Half Second(en)")
        Log.i(TAG, "M3-SUMMARY book=en $run")
        assertTrue("M3/en: all three readings must be of the same resource + element", run.sameContentThroughout)
        assertEquals("M3/en: the Latin book must declare English", "en", run.lang)
        assertTrue(
            "M3/en: the Latin book must resolve the DEFAULT ReadiumCSS, not the CJK one (the contrast that " +
                "makes the zh-CN result meaningful) — sheets=${run.sheets}",
            run.sheets.contains("readium-css/ReadiumCSS-after.css") && !run.sheets.contains("cjk-horizontal"),
        )
        assertEquals(
            "M3/en: computed text-align on body with publisherStyles=false must be justify " +
                "(body is named directly in ReadiumCSS's override selector)",
            "justify", run.withFlag.body,
        )
        // Positive, not merely "not justify": the un-gated states must be a real start/left value, so an
        // empty or error reading cannot masquerade as "the override did not apply".
        assertTrue(
            "M3/en: WITHOUT the advanced gate the computed body text-align must be a real start/left " +
                "value (was '${run.justifyOnly.body}') — W10: the variable is emitted but no rule consumes it",
            run.justifyOnly.body in setOf("start", "left"),
        )
        assertTrue(
            "M3/en: the production default must likewise be start/left (was '${run.default.body}')",
            run.default.body in setOf("start", "left"),
        )
    }

    /**
     * **M3 (CJK `zh-CN`)** — settles §4.3(b): ReadiumCSS's `cjk-horizontal` stylesheet contains no
     * `--USER__textAlign` rule (W12), and the publication declares `zh-CN` so Readium selects it
     * (W13/W14). Characterisation: it PINS the measured result so a future Readium upgrade that starts
     * honouring `text-align` for CJK fails here and forces the plan's prediction to be revisited.
     *
     * **`body` is the discriminating element here, and the reason is a finding in itself.** The measured
     * run showed this book's `<p>` computing `text-align: justify` in ALL THREE states — including the
     * production default, before we submit anything. That is the PUBLISHER's own stylesheets
     * (`../Styles/main.css` etc., visible in the probe's `sheets`), not our preference: the book ships
     * justified. Asserting on `<p>` would therefore have "passed" for entirely the wrong reason and
     * looked like #156 working on CJK. `body` is only ever styled by ReadiumCSS's override selector, so
     * it isolates OUR effect — and it stays `start` in all three states, which is W12 confirmed.
     */
    @Test fun m3_zhEpub_cjkStylesheet_characterisation() {
        val run = measureTextAlign(ZH_FILE, ZH_BYTES, "real:道诡异仙(zh-CN)")
        Log.i(TAG, "M3-SUMMARY book=zh $run")
        // Every precondition of the characterisation is asserted, so the test cannot "pass" by measuring
        // an error object, a stale DOM, the wrong resource, or a non-CJK stylesheet.
        assertTrue("M3/zh: all three readings must be of the same resource + element", run.sameContentThroughout)
        assertTrue("M3/zh: the publication must declare a zh language (was '${run.lang}') — W14", run.lang.startsWith("zh"))
        assertTrue(
            "M3/zh: Readium must have resolved the cjk-horizontal stylesheet — W12/W13 — sheets=${run.sheets}",
            run.sheets.contains("cjk-horizontal/ReadiumCSS-after.css"),
        )
        assertTrue(
            "M3/zh characterisation: body computed text-align must stay a real start/left value even WITH " +
                "publisherStyles=false (was '${run.withFlag.body}') — W12: cjk-horizontal/ReadiumCSS-after.css " +
                "has no USER__textAlign rule, so our override never applies. A 'justify' here STRIKES plan " +
                "§4.3(b) and upgrades AC-5 for EPUB.",
            run.withFlag.body in setOf("start", "left"),
        )
        assertTrue(
            "M3/zh: body must be start/left in the un-gated states too (default='${run.default.body}', " +
                "justifyOnly='${run.justifyOnly.body}')",
            run.default.body in setOf("start", "left") && run.justifyOnly.body in setOf("start", "left"),
        )
    }

    // ---------------------------------------------------------------- M4 (bug #367)

    /**
     * **M4 — bug #367 / GH #2074.** Drives the line-spacing change through the PRODUCTION path (the
     * settings store → `observeDisplaySettings` → `toEpubPreferences()`, `publisherStyles` unset) and
     * measures the computed `line-height` in the DOM. Unchanged ⇒ the #129 slider is inert on EPUB.
     * Then submits the same line height WITH `publisherStyles = false` to show that is the fix (WI-2).
     */
    @Test fun m4_epubLineSpacingSlider_isInertWithoutPublisherStyles_bug367() {
        val book = importRealEpub(EN_FILE, EN_BYTES)
        val store = app.container.readerSettingsStore
        runBlocking { store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING) }

        ActivityScenario.launch<ReaderActivity>(
            ReaderActivity.intent(instrumentation.targetContext, book.fingerprintKey),
        ).use { scenario ->
            awaitNavigator(scenario)
            val before = advanceToProse(scenario, "real:The Half Second(en)")
            log("M4", "real:The Half Second(en)", "lineSpacing=1.5 (production, publisherStyles-unset)", before)
            val lh0 = before.optString("lineHeight")
            val bh0 = before.optString("bodyLineHeight")
            assertTrue(
                "M4 must measure real prose, not a cover page",
                before.optInt("textLen") >= MIN_PROSE_CHARS,
            )
            assertTrue(
                "M4 baseline must be the genuine production state: --USER__lineHeight 1.5 live and the " +
                    "advanced gate OFF (W9 — publisherStyles is never set in production)",
                hasDecl(before, "--USER__lineHeight: 1.5") && !advancedOn(before),
            )

            // The REAL user action: move the Display sheet's line-spacing slider to its maximum. The host's
            // observeDisplaySettings collector re-submits toEpubPreferences() — publisherStyles unset.
            // The probe REQUIRES --USER__lineHeight to actually read 2.0 before it counts, so "the computed
            // value did not change" can never be an artifact of reading before the change landed.
            runBlocking { store.setLineSpacing(ReaderSettings.MAX_LINE_SPACING) }
            val after = settledProbe(scenario, "--USER__lineHeight: 2.0 live, advanced gate OFF") {
                hasDecl(it, "--USER__lineHeight: 2.0") && !advancedOn(it)
            }
            log("M4", "real:The Half Second(en)", "lineSpacing=2.0 (production, publisherStyles-unset)", after)
            val lh1 = after.optString("lineHeight")
            val bh1 = after.optString("bodyLineHeight")

            // Same line height, now WITH the flag — the WI-2 fix.
            @OptIn(ExperimentalReadiumApi::class)
            submit(scenario, EpubPreferences(lineHeight = 2.0, publisherStyles = false))
            val fixed = settledProbe(scenario, "--USER__lineHeight: 2.0 live, advanced gate ON") {
                hasDecl(it, "--USER__lineHeight: 2.0") && advancedOn(it)
            }
            log("M4", "real:The Half Second(en)", "lineHeight=2.0,publisherStyles=false", fixed)
            val lh2 = fixed.optString("lineHeight")
            val bh2 = fixed.optString("bodyLineHeight")

            Log.i(
                TAG,
                "M4-SUMMARY bug367 elem[1.5=$lh0 2.0_production=$lh1 2.0_flagOn=$lh2] " +
                    "body[1.5=$bh0 2.0_production=$bh1 2.0_flagOn=$bh2] " +
                    "slider_inert=${lh0 == lh1 && bh0 == bh1} flag_fixes_it=${lh2 != lh0 || bh2 != bh0} " +
                    "rootVar_moved=${before.optString("rootStyle") != after.optString("rootStyle")}",
            )
            // Guard against a vacuous pass: an empty reading would make every comparison below trivially
            // true. Every value must be a real CSS pixel length before it can be evidence either way —
            // including lh2/bh2, whose "changed" assertion would otherwise pass on an empty string.
            for ((name, v) in listOf("lh0" to lh0, "lh1" to lh1, "lh2" to lh2, "bh0" to bh0, "bh1" to bh1, "bh2" to bh2)) {
                assertTrue("M4: computed $name must be a real px length, was '$v'", v.endsWith("px") && v.length > 2)
            }
            assertTrue(
                "M4: the three readings must be of the same resource + element",
                listOf(before, after, fixed).map { it.optString("docHref") }.distinct().size == 1 &&
                    listOf(before, after, fixed).map { it.optString("textHead") }.distinct().size == 1,
            )
            assertEquals(
                "M4 / bug #367 CONFIRMED: the production line-spacing slider must leave computed " +
                    "line-height UNCHANGED while publisherStyles is unset ($lh0 → $lh1). If these ever " +
                    "differ, bug #367 is REFUTED and the row must be closed as not-a-bug.",
                lh0, lh1,
            )
            assertEquals("M4: body computed line-height must be unchanged too ($bh0 → $bh1)", bh0, bh1)
            assertNotEquals(
                "M4: submitting the SAME line height with publisherStyles=false must change computed " +
                    "body line-height — that is what makes WI-2 the fix for #367",
                bh0, bh2,
            )
        }
    }
}
