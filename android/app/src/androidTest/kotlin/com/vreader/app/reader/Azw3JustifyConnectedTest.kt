// Purpose: feature #156 WI-3 — AZW3 justification, verified by COMPUTED STYLE + LINE GEOMETRY in the live
// foliate/Chromium DOM, through the production entry point (open the book; the CSS is injected
// unconditionally at Azw3ReaderActivity.kt, so no Display control is involved — AC-7 / plan §9.1 P1).
//
// Every claim here is a with-rule / without-rule DIFFERENTIAL against the SAME document, because a single
// reading cannot discriminate: the book's own publisher stylesheet may already compute `justify` on `<p>`
// (WI-2 hit exactly that on the CJK EPUB), and `assertEquals(css.contains("justify"))` passes while zero
// glyphs move. The subject arm is the UNTOUCHED production state at open; the control arm is the
// production CSS with its one justify rule removed, injected through the production `setStyles` seam.
//
// This also answers the feature's open CJK question with a number: the only real AZW3 is CJK, and unlike
// EPUB — where ReadiumCSS's cjk-horizontal sheet carries no USER__textAlign rule at all — AZW3 renders
// through Chromium with OUR OWN CSS, so CSS justification is expected to reach CJK here.
package com.vreader.app.reader

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.settings.ReaderSettings
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class Azw3JustifyConnectedTest {

    // NO ComposeTestRule here, deliberately. This class drives the reader through the WebView bridge and
    // polls on the test thread; with a Compose rule installed, the Compose clock only advances while the
    // test framework is pumping (inside waitForIdle / waitUntil), so a `Thread.sleep` polling loop
    // STARVES composition — the host never runs its LaunchedEffects, the book never renders, and every
    // measurement times out against a blank shell. Observed exactly that. Without the rule the app runs
    // on the real frame clock, which is what these measurements need.
    private val tag = "Azw3Justify"

    /** Long Latin prose for the positive control — enough to wrap to several lines at reader width. */
    private val latinProbeText =
        "The measurement must be able to fail. A control paragraph of ordinary Latin prose, set in the " +
            "same document, at the same width, under the same injected stylesheet, gives the negative " +
            "result somewhere to stand: if justification moves nothing here either, the harness is " +
            "broken rather than the engine being incapable, and no conclusion about the book's own " +
            "script may be drawn from it at all."

    // ---- fixtures -------------------------------------------------------------------------------

    /**
     * Import the REAL AZW3 (the only one in the repo; it is CJK). Deliberately **asserts** rather than
     * `assumeTrue` — a skipped connected test exits 0 exactly like a pass, which is how bug #369 hid a
     * failing test. If the local-only fixture is missing, this WI's evidence does not exist and the run
     * must say so.
     */
    private fun importRealAzw3(): Book {
        val inst = InstrumentationRegistry.getInstrumentation()
        val present = inst.context.assets.list("foliate-spike")?.contains("book.azw3") == true
        assertTrue(
            "the real AZW3 fixture androidTest/assets/foliate-spike/book.azw3 is absent — this WI's " +
                "acceptance is measured on the real book and cannot be satisfied without it",
            present,
        )
        val app = inst.targetContext.applicationContext as VReaderApp
        val staged = File(inst.targetContext.cacheDir, "azw3-justify-${System.nanoTime()}")
        inst.context.assets.open("foliate-spike/book.azw3").use { input ->
            staged.outputStream().use { input.copyTo(it) }
        }
        assertEquals("the staged AZW3 must be the real 6,288,371-byte book", 6_288_371L, staged.length())
        return runBlocking {
            app.container.importer.importStream("content://test/book.azw3", "Bei Tao Yan.azw3", staged.inputStream())
        }
    }

    private fun launch(book: Book): ActivityScenario<Azw3ReaderActivity> =
        ActivityScenario.launch(
            Azw3ReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        )

    /**
     * Wait for the reader pipeline to have genuinely run before any probing: a persisted relocate means
     * the bundle opened the book, rendered, and reported back. Probing before that would be measuring a
     * blank shell, and every "unchanged" comparison in this class would be trivially satisfiable.
     */
    private fun awaitBookReady(book: Book) {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
        for (i in 0 until 120) {
            if (runBlocking { app.container.repository.loadPosition(book.fingerprintKey) } != null) return
            Thread.sleep(500)
        }
        throw AssertionError("the AZW3 reader never persisted a relocate — the book did not render")
    }

    /**
     * The LIVE production CSS with its ONE justify rule removed — a faithful pre-#156 reconstruction of
     * whatever is actually injected in this document, so the two arms differ by exactly that rule and
     * nothing else. The exact-count check makes a renamed/relocated rule a loud failure rather than a
     * silently vacuous control.
     *
     * Gate-4 round 1 (High) replaced the previous source: it rebuilt the blob from
     * `ReaderSettings().foliateDisplayCss()`, which equals production only when the persisted display
     * settings are the defaults. Under any other settings the control would also have changed font size,
     * margin, line-height and family — and those change LINE BREAKING, so the index-wise line comparison
     * would have been differencing two different layouts while reporting it as a justification delta.
     */
    private fun legacyCss(production: String): String {
        val lines = production.lines()
        val kept = lines.filterNot { it.contains("text-align: justify") }
        assertEquals(
            "expected exactly ONE justify rule line in the production foliate CSS — the control arm is " +
                "only meaningful if it removes precisely the rule under test",
            lines.size - 1,
            kept.size,
        )
        return kept.joinToString("\n")
    }

    // ---- AC-7 (a): prose justifies, and the ragged right edge actually collapses -----------------

    @Test
    fun a_prose_computesJustifyInTheLiveDom_andRaggedRightEdgeCollapses() {
        val book = importRealAzw3()
        launch(book).use { scenario ->
            val probe = Azw3DomProbe(scenario, tag)
            awaitBookReady(book)
            probe.awaitRender()

            // SUBJECT = the untouched production state at open. No test injection has happened yet, so
            // this reading is the production path's own output (plan §9.1 P1).
            val subject = probe.settled("production CSS live") { it.optBoolean("styleHasJustify") }
            probe.logState("core", "subject(production)", subject)

            // The subject paragraph must not itself be guard-exempt, or the whole comparison is vacuous.
            assertTrue(
                "the measured paragraph carries an inline text-align / align / center|right class, so the " +
                    "justify rule deliberately does NOT target it — it cannot be the subject",
                subject.optString("pInlineStyle").isEmpty() &&
                    subject.optString("pAlignAttr").isEmpty() &&
                    !subject.optString("pClass").contains("center") &&
                    !subject.optString("pClass").contains("right"),
            )

            // CONTROL = the same document with the justify rule removed, derived from the LIVE blob.
            val production = liveVreaderCss(subject)
            probe.setStyles(legacyCss(production))
            val control = probe.settled("pre-#156 CSS live") { !it.optBoolean("styleHasJustify") }
            probe.logState("core", "control(pre-#156)", control)

            // RETURN LEG: re-injecting production CSS restores the effect (so the difference is the rule,
            // not an artefact of the injection order).
            probe.setStyles(production)
            val restored = probe.settled("production CSS re-injected") { it.optBoolean("styleHasJustify") }
            probe.logState("core", "restored(production)", restored)

            assertSameElement(subject, control, restored)

            // (1) computed style — the proxy.
            assertEquals(
                "AC-7: body prose must compute text-align: justify under the production CSS",
                "justify", subject.optString("pTextAlign"),
            )
            assertEquals(
                "the effect must return when the production CSS is re-injected",
                "justify", restored.optString("pTextAlign"),
            )
            assertTrue(
                "the control arm computes '${control.optString("pTextAlign")}' — identical to the subject, " +
                    "so this book's publisher stylesheet already justifies and the reading proves nothing " +
                    "about OUR rule. The pixel differential below is then the only evidence.",
                control.optString("pTextAlign") != "justify",
            )

            // (2) line geometry — the pixel fact the computed value is only a proxy for.
            val subjectLines = lineBoxes(subject)
            val controlLines = lineBoxes(control)
            android.util.Log.i(
                tag,
                "GEOMETRY subject=${subjectLines.map { it.right }} control=${controlLines.map { it.right }} " +
                    "lefts.subject=${subjectLines.map { it.left }} lefts.control=${controlLines.map { it.left }}",
            )
            assertTrue(
                "the subject paragraph produced only ${subjectLines.size} line box(es) — a collapse claim " +
                    "needs several justifiable lines to rest on",
                subjectLines.size >= 4,
            )
            assertEquals(
                "justification must not change line BREAKING — a different line count means the " +
                    "comparison is not index-aligned and every delta below is meaningless",
                controlLines.size, subjectLines.size,
            )

            // Document order is preserved by lineBoxes, so the LAST line box is the paragraph's final
            // line — the one no engine justifies.
            val justifiable = subjectLines.size - 1
            val moved = (0 until justifiable).count { subjectLines[it].right - controlLines[it].right > 0.5 }
            val movedLeft = (0 until justifiable).count { controlLines[it].right - subjectLines[it].right > 0.5 }
            val columns = columnIndices(subjectLines)
            android.util.Log.i(
                tag,
                "COLLAPSE justifiable=$justifiable moved=$moved movedLeft=$movedLeft " +
                    "columns=$columns docWidth=${subject.optInt("docWidth")}",
            )

            // Per COLUMN, because foliate paginates with CSS multi-column: a spread taken across columns
            // measures the column pitch (~775px here) and is ~identical in both arms, so it would report
            // "no collapse" no matter what the engine did.
            var columnsChecked = 0
            for (col in columns.distinct()) {
                val idx = (0 until justifiable).filter { columns[it] == col }
                if (idx.size < 3) continue
                val controlSpread = spread(idx.map { controlLines[it].right })
                val subjectSpread = spread(idx.map { subjectLines[it].right })
                android.util.Log.i(
                    tag,
                    "COLLAPSE col=$col lines=${idx.size} controlSpread=$controlSpread subjectSpread=$subjectSpread " +
                        "control=${idx.map { controlLines[it].right }} subject=${idx.map { subjectLines[it].right }}",
                )
                assertTrue(
                    "column $col was not ragged enough unjustified (spread=$controlSpread) for a collapse " +
                        "claim to mean anything — a fixture too uniform to justify must fail here rather " +
                        "than pass vacuously",
                    controlSpread > 3.0,
                )
                assertTrue(
                    "column $col did not collapse onto one right edge under justification " +
                        "(subjectSpread=$subjectSpread, controlSpread=$controlSpread)",
                    subjectSpread <= 1.0 && subjectSpread <= controlSpread / 3.0,
                )
                columnsChecked++
            }
            assertTrue("no column carried >= 3 justifiable lines — nothing was actually measured", columnsChecked >= 1)

            // Allow up to two lines not to move: a line that already happened to end within a glyph of
            // the measure has nowhere to go (observed: 1881.93 -> 1882.33, a 0.40px move).
            assertTrue(
                "justification must move the right edge of essentially every justifiable line " +
                    "(moved=$moved of $justifiable)",
                moved >= justifiable - 2,
            )
            assertEquals("no justifiable line may move LEFT under justification", 0, movedLeft)

            // The paragraph's final line must NOT be stretched — the no-stretched-last-line property the
            // plan relies on coming free from the engine's `text-align-last: auto` default.
            val finalDelta = kotlin.math.abs(subjectLines.last().right - controlLines.last().right)
            android.util.Log.i(tag, "FINAL-LINE delta=$finalDelta subject=${subjectLines.last().right}")
            assertTrue(
                "the paragraph's final line must stay unjustified, but it moved ${finalDelta}px",
                finalDelta <= 0.5,
            )
        }
    }

    // ---- AC-7 (b): headings are NOT justified; the rule is p-scoped ------------------------------

    @Test
    fun b_headingsAndBody_areNotJustified_whileProseIs() {
        val book = importRealAzw3()
        launch(book).use { scenario ->
            val probe = Azw3DomProbe(scenario, tag)
            awaitBookReady(book)
            probe.awaitRender()
            val subject = probe.settled("production CSS live") { it.optBoolean("styleHasJustify") }
            probe.logState("scope", "subject(production)", subject)

            assertEquals("prose must justify for the scope claim to mean anything", "justify", subject.optString("pTextAlign"))

            // `body` is NOT a target of our rule (it is `p`-scoped, unlike ReadiumCSS's :root rule which
            // made EPUB headings inherit justification — WI-2's E1c). So body must NOT read justify:
            // that is the evidence the blast radius is confined to paragraphs.
            assertTrue(
                "the rule is p-scoped, so document.body must NOT compute justify (got " +
                    "'${subject.optString("bodyTextAlign")}') — a justified body would mean every " +
                    "element inherits it, including headings",
                subject.optString("bodyTextAlign") != "justify",
            )

            val headings = subject.optJSONArray("headings")
            var checked = 0
            for (i in 0 until (headings?.length() ?: 0)) {
                val h = headings!!.optJSONObject(i) ?: continue
                assertTrue(
                    "AC-7: heading ${h.optString("tag")} must not be justified, got '${h.optString("align")}'",
                    h.optString("align") != "justify",
                )
                checked++
            }
            android.util.Log.i(tag, "SCOPE headingsChecked=$checked headings=$headings body=${subject.optString("bodyTextAlign")}")
            // Gate-4 round 1 (Medium): iterating an EMPTY heading list would satisfy AC-7's "headings do
            // not justify" half without reading a single heading's computed style.
            assertTrue(
                "no heading was measured in this section, so the heading half of AC-7 would pass " +
                    "vacuously — the measured section must contain at least one h1..h6",
                checked >= 1,
            )
        }
    }

    // ---- measurement validity + the guard heuristics ---------------------------------------------

    /**
     * Two things at once, both on the SAME engine and the SAME document as the book measurement:
     *  • a **Latin positive control** — the repo has no real Latin AZW3, so a negative CJK result would
     *    otherwise be indistinguishable from a broken measurement;
     *  • the plan's **guard heuristics** (R7) — an inline `text-align`, an `align` attribute, or a
     *    `center`/`right` class must exempt a paragraph from the override.
     */
    @Test
    fun c_latinControlMoves_andGuardedParagraphsAreExempt() {
        val book = importRealAzw3()
        launch(book).use { scenario ->
            val probe = Azw3DomProbe(scenario, tag)
            awaitBookReady(book)
            probe.awaitRender()
            probe.settled("production CSS live") { it.optBoolean("styleHasJustify") }

            val production = liveVreaderCss(probe.settled("live blob") { it.optBoolean("styleHasJustify") })
            val install = probeElementsJs(latinProbeText)

            val subject = requireNotNull(probe.evalJson(install)) { "probe-element install/measure failed (subject)" }
            android.util.Log.i(tag, "PROBE subject=$subject")

            probe.setStyles(legacyCss(production))
            probe.settled("pre-#156 CSS live") { !it.optBoolean("styleHasJustify") }
            val control = requireNotNull(probe.evalJson(install)) { "probe-element install/measure failed (control)" }
            android.util.Log.i(tag, "PROBE control=$control")

            probe.setStyles(production)
            probe.settled("production CSS re-injected") { it.optBoolean("styleHasJustify") }

            // A failed install/measure would report empty strings, and "" != "justify" would satisfy every
            // exemption assertion below without measuring anything. Reject that state outright.
            for ((label, reading) in listOf("subject" to subject, "control" to control)) {
                assertTrue("the probe-element $label arm reported failure: $reading", reading.optBoolean("ok"))
                for (key in listOf("plainAlign", "inlineAlign", "attrAlign", "classAlign")) {
                    assertTrue(
                        "the $label arm read no computed value for $key — an empty reading would pass the " +
                            "exemption assertions vacuously",
                        reading.optString(key).isNotEmpty(),
                    )
                }
            }

            // Latin positive control: plain probe paragraph must justify and its lines must move.
            assertEquals("Latin control must compute justify under production CSS", "justify", subject.optString("plainAlign"))
            assertTrue(
                "Latin control must NOT already be justify without the rule (got '${control.optString("plainAlign")}')",
                control.optString("plainAlign") != "justify",
            )
            val sLines = lineBoxes(subject.getJSONObject("plain"))
            val cLines = lineBoxes(control.getJSONObject("plain"))
            assertEquals("Latin control line count must match across arms", cLines.size, sLines.size)
            assertTrue("Latin control needs >=3 lines to be a meaningful control, got ${sLines.size}", sLines.size >= 3)
            val n = sLines.size - 1
            val movedLatin = (0 until n).count { sLines[it].right - cLines[it].right > 0.5 }
            android.util.Log.i(
                tag,
                "LATIN control moved=$movedLatin of $n subject=${sLines.map { it.right }} control=${cLines.map { it.right }}",
            )
            assertEquals(
                "the Latin control must move under justification — if it does not, the measurement is " +
                    "broken and NO conclusion may be drawn about the book's own script",
                n, movedLatin,
            )

            // Guards: each exempt shape keeps its own alignment under the production CSS.
            assertTrue(
                "an inline text-align must be exempt, got '${subject.optString("inlineAlign")}'",
                subject.optString("inlineAlign") != "justify",
            )
            assertTrue(
                "an align= attribute must be exempt, got '${subject.optString("attrAlign")}'",
                subject.optString("attrAlign") != "justify",
            )
            assertTrue(
                "a center class must be exempt, got '${subject.optString("classAlign")}'",
                subject.optString("classAlign") != "justify",
            )
        }
    }

    // ---- helpers ---------------------------------------------------------------------------------

    private fun assertSameElement(vararg readings: JSONObject) {
        val heads = readings.map { it.optString("textHead") }.distinct()
        val tags = readings.map { it.optString("tag") }.distinct()
        val docs = readings.map { it.optInt("docIndex") }.distinct()
        val lens = readings.map { it.optInt("textLen") }.distinct()
        assertTrue(
            "every arm must measure the SAME element in the SAME section — heads=$heads tags=$tags " +
                "docIndexes=$docs textLens=$lens",
            heads.size == 1 && tags.size == 1 && docs.size == 1 && lens.size == 1,
        )
    }

    private fun spread(values: List<Double>): Double =
        if (values.isEmpty()) 0.0 else (values.max() - values.min())

    /**
     * Install (once) four probe paragraphs into the live section document and measure them. Marked
     * `data-vreader-probe` so the main probe's prose picker skips them, and so a re-run reuses the same
     * elements instead of stacking duplicates. This DOES mutate the document — deliberately, and only in
     * this test: it is measuring the CSS RULE's selector semantics in the real engine, not the book's own
     * rendering, and the book-rendering measurements live in their own Activity launches above.
     */
    private fun probeElementsJs(latin: String): String {
        val text = Json.encodeToString(String.serializer(), latin)
        return """
            (function(){
              try{
                var v=document.getElementById('view');
                var r=v&&v.renderer;
                var cs=(r&&r.getContents)?r.getContents():null;
                if(!cs||!cs.length) return JSON.stringify({ok:false,reason:'no-mounted-view'});
                var d=cs[0].doc;
                var host=d.getElementById('vreader-probe-host');
                if(!host){
                  host=d.createElement('div');
                  host.id='vreader-probe-host';
                  host.setAttribute('data-vreader-probe','1');
                  function mk(id,attr,val){
                    var el=d.createElement('p');
                    el.setAttribute('data-vreader-probe','1');
                    el.id=id;
                    if(attr) el.setAttribute(attr,val);
                    el.textContent=$text;
                    host.appendChild(el);
                  }
                  mk('vreader-probe-plain',null,null);
                  mk('vreader-probe-inline','style','text-align:left');
                  mk('vreader-probe-attr','align','center');
                  mk('vreader-probe-class','class','center');
                  d.body.appendChild(host);
                }
                function el(id){return d.getElementById(id);}
                function align(id){var e=el(id); return e?(getComputedStyle(e).textAlign||''):'';}
                function rects(id){
                  var e=el(id); if(!e) return [];
                  var rg=d.createRange(); rg.selectNodeContents(e);
                  var rs=rg.getClientRects(), out=[];
                  for(var i=0;i<rs.length;i++){
                    if(!(rs[i].width>0.5)) continue;
                    out.push([Math.round(rs[i].left*100)/100,Math.round(rs[i].right*100)/100,
                              Math.round(rs[i].top*100)/100]);
                  }
                  return out;
                }
                return JSON.stringify({ok:true,
                  plainAlign:align('vreader-probe-plain'),
                  inlineAlign:align('vreader-probe-inline'),
                  attrAlign:align('vreader-probe-attr'),
                  classAlign:align('vreader-probe-class'),
                  plain:{rects:rects('vreader-probe-plain')}});
              }catch(e){return JSON.stringify({ok:false,error:String(e)});}
            })()
        """
    }
}
