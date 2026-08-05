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
                       rootStyle:(root.getAttribute('style')||''),
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
        var result: String? = null
        val done = CountDownLatch(1)
        scenario.onActivity { act ->
            val nav = act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment
            if (nav == null) { done.countDown(); return@onActivity }
            act.lifecycleScope.launch(Dispatchers.Main.immediate) {
                result = runCatching { nav.evaluateJavascript(js) }.getOrNull()
                done.countDown()
            }
        }
        done.await(20, TimeUnit.SECONDS)
        return result
    }

    /**
     * Poll the DOM until it is SETTLED — a `<p>` is present and the `<html>` inline style stops changing
     * between consecutive samples. A `submitPreferences` reflow rewrites that style attribute and
     * re-renders, so sampling on a fixed sleep could read a half-applied DOM.
     */
    private fun settledProbe(scenario: ActivityScenario<ReaderActivity>): JSONObject {
        var previous: String? = null
        var last: JSONObject? = null
        for (i in 0 until 40) {
            val raw = evalJs(scenario, PROBE_JS)
            if (raw != null) {
                val decoded = JSONTokener(raw).nextValue()
                val json = if (decoded is String) JSONObject(decoded) else decoded as JSONObject
                last = json
                if (json.optBoolean("found")) {
                    val style = json.optString("rootStyle")
                    if (previous == style && i >= 2) return json
                    previous = style
                }
            }
            Thread.sleep(250)
        }
        return requireNotNull(last) { "the DOM probe never returned a result" }
    }

    /**
     * `submitPreferences` REPLACES the whole preference set rather than merging, so every submission here
     * pins `scroll = true` — the production default (the host opens with `scroll = layout == Scroll`).
     * Without it the first run flipped the reader to `readium-paged-on` midway, which would have been an
     * uncontrolled second variable in the before/after comparison.
     */
    @OptIn(ExperimentalReadiumApi::class)
    private fun submit(scenario: ActivityScenario<ReaderActivity>, prefs: EpubPreferences) {
        scenario.onActivity { act ->
            (act.supportFragmentManager.findFragmentByTag(READER_TAG) as? EpubNavigatorFragment)
                ?.submitPreferences(EpubPreferences(scroll = true) + prefs)
        }
    }

    /**
     * Page forward until the visible resource actually contains prose. A real EPUB opens on a cover /
     * title resource that can have ZERO `<p>` — the first run measured exactly that and produced empty
     * computed values, so this is not a hypothetical. Uses the navigator's own `goForward`, i.e. the same
     * motion a reading user makes.
     */
    private fun advanceToProse(scenario: ActivityScenario<ReaderActivity>, label: String): JSONObject {
        var probe = settledProbe(scenario)
        for (step in 0 until 30) {
            if (probe.optBoolean("found") && probe.optInt("textLen") >= MIN_PROSE_CHARS) {
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
            probe = settledProbe(scenario)
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

    @OptIn(ExperimentalReadiumApi::class)
    private fun measureTextAlign(file: String, bytes: Long, label: String): Triple<AlignReading, AlignReading, AlignReading> {
        val book = importRealEpub(file, bytes)
        var out: Triple<AlignReading, AlignReading, AlignReading>? = null
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

            submit(scenario, EpubPreferences(textAlign = ReadiumTextAlign.JUSTIFY))
            val justifyOnly = settledProbe(scenario)
            log("M3", label, "textAlign=JUSTIFY,publisherStyles-unset", justifyOnly)

            submit(scenario, EpubPreferences(textAlign = ReadiumTextAlign.JUSTIFY, publisherStyles = false))
            val withFlag = settledProbe(scenario)
            log("M3", label, "textAlign=JUSTIFY,publisherStyles=false", withFlag)

            fun read(p: JSONObject) =
                AlignReading(p.optString("textAlign"), p.optString("bodyTextAlign"), p.optString("tag"))
            out = Triple(read(default), read(justifyOnly), read(withFlag))
        }
        return out!!
    }

    /**
     * **M3 (Latin `en`)** — the W10 proof: `textAlign = JUSTIFY` is INERT while `publisherStyles` is
     * unset, and takes effect only once the flag gates `readium-advanced-on` on. This pair is what makes
     * WI-2's two properties inseparable (plan §7.2).
     */
    @Test fun m3_enEpub_justifyRequiresPublisherStylesFalse() {
        val (default, justifyOnly, withFlag) = measureTextAlign(EN_FILE, EN_BYTES, "real:The Half Second(en)")
        Log.i(TAG, "M3-SUMMARY book=en default=$default justifyOnly=$justifyOnly withFlag=$withFlag")
        assertEquals(
            "M3/en: computed text-align on body with publisherStyles=false must be justify " +
                "(body is named directly in ReadiumCSS's override selector)",
            "justify", withFlag.body,
        )
        assertNotEquals(
            "M3/en: textAlign=JUSTIFY alone must NOT reach the DOM (W10 — the variable is emitted but no " +
                "rule consumes it without readium-advanced-on). If this ever equals 'justify', W10 is " +
                "wrong and publisherStyles=false is not load-bearing.",
            "justify", justifyOnly.body,
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
        val (default, justifyOnly, withFlag) = measureTextAlign(ZH_FILE, ZH_BYTES, "real:道诡异仙(zh-CN)")
        Log.i(TAG, "M3-SUMMARY book=zh default=$default justifyOnly=$justifyOnly withFlag=$withFlag")
        assertNotEquals(
            "M3/zh characterisation: the CJK publication must NOT compute text-align:justify on body even " +
                "with publisherStyles=false (W12 — cjk-horizontal/ReadiumCSS-after.css has no " +
                "USER__textAlign rule). A 'justify' here STRIKES plan §4.3(b) and upgrades AC-5 for EPUB.",
            "justify", withFlag.body,
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

            // The REAL user action: move the Display sheet's line-spacing slider to its maximum. The host's
            // observeDisplaySettings collector re-submits toEpubPreferences() — publisherStyles unset.
            runBlocking { store.setLineSpacing(ReaderSettings.MAX_LINE_SPACING) }
            val after = settledProbe(scenario)
            log("M4", "real:The Half Second(en)", "lineSpacing=2.0 (production, publisherStyles-unset)", after)
            val lh1 = after.optString("lineHeight")
            val bh1 = after.optString("bodyLineHeight")

            // Same line height, now WITH the flag — the WI-2 fix.
            @OptIn(ExperimentalReadiumApi::class)
            submit(scenario, EpubPreferences(lineHeight = 2.0, publisherStyles = false))
            val fixed = settledProbe(scenario)
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
            // true. The values must be real CSS lengths before they can be evidence either way.
            assertTrue("M4: computed line-height readings must be non-empty", lh0.isNotEmpty() && bh0.isNotEmpty())
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
