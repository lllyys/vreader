package com.vreader.app.reader

import android.util.Log
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.style.TextAlign
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.FixMethodOrder
import org.junit.runners.MethodSorters
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.bodyTextStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.abs

/**
 * Feature #156 WI-0 — the **measurement spike** for the TXT/MD (Compose) engine. No production code.
 *
 * The plan (§4.3(a), W16) predicts Compose maps `TextAlign.Justify` to `StaticLayout`'s
 * `JUSTIFICATION_MODE_INTER_WORD`, which distributes slack into SPACE RUNS — so space-free CJK prose
 * should not move a single glyph. §7.1 makes WI-0's acceptance explicitly exclude the evidence class
 * that would make it worthless: asserting a `ReaderSettings` / `TextStyle` value proves the request was
 * made, never that a glyph moved. Every number here is therefore read back AFTER layout.
 *
 *  • **M1 (`m1_cjkRealBook_...`)** — the REAL `test-books/books/txt/黑暗血时代.txt` paragraph, rendered
 *    through the production [TxtBody], measured under `Start` vs `Justify`. Characterisation, not a
 *    promise (plan AC-1b): it PINS whatever the engine does, so a future Compose/AGP upgrade that starts
 *    justifying CJK fails this test and forces §4.3(a) to be revisited instead of rotting.
 *  • **M2 (`m2_latinSynthetic_...`)** — the POSITIVE CONTROL and a GATE ON M1: the identical helper, the
 *    identical [TxtBody] call, the identical metrics, on Latin prose. If M2 shows no movement the
 *    HARNESS is broken and M1 is uninterpretable — that is a spike failure, not a CJK finding. An EPUB
 *    cannot serve as this control (Chromium, a different engine — plan §4.1/§10 exception 3), hence the
 *    synthetic Latin TXT asset.
 *
 * Post-layout signals per run. TWO are load-bearing; the third is recorded and explicitly is NOT
 * evidence, because the control PROVED it blind:
 *   1. **`TextLayoutResult.getLineRight(i)`** per NON-FINAL line (the last line is never justified by
 *      any engine — plan §4.2 — so it is excluded). VALIDATED by M2: ragged → flush at the layout width.
 *   2. **A raw PIXEL diff** of the rendered node between the two alignments — the ground truth for
 *      "did a glyph move". VALIDATED by M2 (191 965 pixels differ). Recorded when `captureToImage` is
 *      available on the device.
 *   3. `getBoundingBox(offset).left` for a MID-LINE glyph — intended as a third independent path, but
 *      **M2 measured it INERT while 191 965 pixels demonstrably moved**, so Compose's
 *      `getBoundingBox`/`getHorizontalPosition` do NOT reflect justification (unlike `getLineRight`,
 *      which resolves through `Layout.getLineExtent` → `TextLine.justify`). It is therefore logged for
 *      the record and PINNED by M2 as a known-blind API — never used as evidence that nothing moved.
 *      This is exactly what a positive control is for: it invalidated a signal before that signal could
 *      manufacture a false "CJK is inert" result.
 *
 * Real-books-first: M1 reads the genuine 14 059 220-byte CJK book pushed to the app's scoped external
 * files dir as `perf-cjk.txt` (the #137/#138 `TxtPaginatorPerfBenchmark` convention — the connected task
 * wipes that dir at run end, so re-push every run). A byte-size identity check refuses to label a
 * truncated/stale file "real". Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)   // `controlM2…` sorts before `measurementM1…` — see [controlPassed]
class JustificationMeasurementSpikeTest {

    @get:Rule val compose = createComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private companion object {
        const val TAG = "WI0-JUSTIFY"
        const val REAL_BOOK_BYTES = 14_059_220L
        const val REAL_BOOK_BYTES_TOLERANCE = 1_000L
        /** Long enough to wrap to several lines at 18sp, short enough to stay ONE TxtDocument chunk. */
        const val MIN_PARAGRAPH_CHARS = 350
        const val MAX_PARAGRAPH_CHARS = 1_500
        /** Float noise floor for "these two x-coordinates are the same pixel position". */
        const val EPSILON_PX = 0.5f
        /** A CJK paragraph must be overwhelmingly CJK — a mislabelled fixture must not be measured as one. */
        const val MIN_CJK_FRACTION = 0.8

        /**
         * Set by the M2 positive control when it passes. M1 REQUIRES it, so the control cannot be skipped
         * — a filtered invocation that runs M1 alone fails loudly instead of publishing an uninterpretable
         * "CJK does not move" number. Method order is pinned so the control always runs first.
         */
        @JvmStatic var controlPassed = false
    }

    /** Chinese/Japanese/Korean ideographs + CJK punctuation + fullwidth forms. */
    private fun isCjk(c: Char): Boolean = c.code in 0x3000..0x303F ||
        c.code in 0x3400..0x4DBF || c.code in 0x4E00..0x9FFF ||
        c.code in 0xF900..0xFAFF || c.code in 0xFF00..0xFFEF

    // ---------------------------------------------------------------- fixtures

    /** The real 14 MB CJK book from the app's scoped external files dir; null if absent or NOT the genuine
     *  book (never label a truncated/unrelated file `real` — the #137 WI-11 Gate-4 M3 lesson). */
    private fun readRealCjkBookOrNull(): String? {
        val dir = instrumentation.targetContext.getExternalFilesDir(null) ?: return null
        val f = File(dir, "perf-cjk.txt")
        if (!f.exists() || !f.canRead()) return null
        if (abs(f.length() - REAL_BOOK_BYTES) > REAL_BOOK_BYTES_TOLERANCE) {
            Log.w(TAG, "perf-cjk.txt size ${f.length()} != $REAL_BOOK_BYTES → NOT the real book")
            return null
        }
        return runCatching { TxtDecoder.decode(f).text }.getOrNull()
    }

    private fun readLatinAsset(): String =
        instrumentation.context.assets.open("latin-justify-sample.txt").use { it.readBytes().toString(Charsets.UTF_8) }

    /**
     * The first line of [text] that is a wrappable single-chunk paragraph. [asciiLettersAllowed] = false
     * selects space-free CJK prose (the M1 case); true accepts the Latin control. Deterministic — the
     * same book always yields the same paragraph, so the recorded numbers are reproducible.
     */
    private fun pickParagraph(text: String, asciiLettersAllowed: Boolean): String {
        for (line in text.lineSequence()) {
            val t = line.trim()
            if (t.length !in MIN_PARAGRAPH_CHARS..MAX_PARAGRAPH_CHARS) continue
            if (!asciiLettersAllowed && t.any { it.code < 128 && it.isLetter() }) continue
            if (asciiLettersAllowed && !t.contains(' ')) continue
            return t
        }
        throw AssertionError("no paragraph of $MIN_PARAGRAPH_CHARS..$MAX_PARAGRAPH_CHARS chars found")
    }

    // ---------------------------------------------------------------- measurement

    /** One post-layout reading of the rendered paragraph under a single alignment. */
    private data class Metrics(
        val align: TextAlign?,
        val lineCount: Int,
        val layoutWidthPx: Int,
        /** `getLineRight(i)` for every line (index i). */
        val lineRights: List<Float>,
        /** `getBoundingBox(mid-of-line).left` for every line (a second, independent API path). */
        val midGlyphLefts: List<Float>,
        /** ARGB pixels of the rendered node, or null when capture is unavailable on this device. */
        val pixels: IntArray?,
        val pixelDims: Pair<Int, Int>?,
    )

    private fun layoutFor(anchor: String): TextLayoutResult? = runCatching {
        val out = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(anchor, substring = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(out) }
        out.firstOrNull()
    }.getOrNull()

    private fun capturePixels(anchor: String): Pair<IntArray, Pair<Int, Int>>? = runCatching {
        val map = compose.onNodeWithText(anchor, substring = true).captureToImage().toPixelMap()
        val px = IntArray(map.width * map.height)
        for (y in 0 until map.height) for (x in 0 until map.width) px[y * map.width + x] = map[x, y].toArgb()
        px to (map.width to map.height)
    }.getOrNull()

    private fun readMetrics(anchor: String): Metrics {
        // Exactly one node may match the anchor, or the two readings could be of different Texts.
        assertEquals(
            "the anchor must identify exactly one rendered Text node",
            1, compose.onAllNodesWithText(anchor, substring = true).fetchSemanticsNodes().size,
        )
        val layout = requireNotNull(layoutFor(anchor)) { "no TextLayoutResult for the rendered paragraph" }
        val lines = layout.lineCount
        val rights = (0 until lines).map { layout.getLineRight(it) }
        val mids = (0 until lines).map { line ->
            val start = layout.getLineStart(line)
            val end = layout.getLineEnd(line, visibleEnd = true)
            val mid = ((start + end) / 2).coerceIn(start, (end - 1).coerceAtLeast(start))
            layout.getBoundingBox(mid).left
        }
        val cap = capturePixels(anchor)
        return Metrics(
            align = layout.layoutInput.style.textAlign,
            lineCount = lines,
            layoutWidthPx = layout.size.width,
            lineRights = rights,
            midGlyphLefts = mids,
            pixels = cap?.first,
            pixelDims = cap?.second,
        )
    }

    /**
     * Render [paragraph] through the PRODUCTION [TxtBody] once, read it under `Start`, flip the alignment
     * state to `Justify` (one recomposition — `setContent` is called exactly ONCE per test, MEMORY #134),
     * read it again, and return both readings. M1 and M2 call this identically; that is what makes M2 a
     * valid gate on M1.
     */
    private fun measureBothAlignments(paragraph: String): Pair<Metrics, Metrics> {
        val doc = TxtDocument.of(paragraph)
        assertEquals("the measured paragraph must be exactly one chunk", 1, doc.chunkCount)
        val mapper = IdentityChunkTextMapper(doc)
        val settings = ReaderSettings()
        val alignState = mutableStateOf(TextAlign.Start)

        compose.setContent {
            TxtBody(
                document = doc,
                listState = rememberLazyListState(),
                format = vreader.contracts.BookFormat.txt,
                mapper = mapper,
                textStyle = settings.bodyTextStyle().copy(textAlign = alignState.value),
                marginDp = settings.marginDp,
            )
        }

        val anchor = paragraph.take(8)
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText(anchor, substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitUntil(15_000) { layoutFor(anchor)?.layoutInput?.style?.textAlign == TextAlign.Start }
        val start = readMetrics(anchor)

        compose.runOnUiThread { alignState.value = TextAlign.Justify }
        // The style reaching layout is NECESSARY but NOT sufficient — it is only the gate that says the
        // second reading is of the justified request; the movement question is answered by the numbers.
        compose.waitUntil(15_000) { layoutFor(anchor)?.layoutInput?.style?.textAlign == TextAlign.Justify }
        val justify = readMetrics(anchor)

        assertEquals("both readings must lay out the same line count", start.lineCount, justify.lineCount)
        assertTrue(
            "the paragraph must wrap (≥2 lines) or there are no NON-FINAL lines to measure",
            start.lineCount >= 2,
        )
        return start to justify
    }

    /** Count of non-final lines whose x-coordinate moved by more than the noise floor. */
    private fun movedLines(a: List<Float>, b: List<Float>, lineCount: Int): Int =
        (0 until lineCount - 1).count { abs(a[it] - b[it]) > EPSILON_PX }

    private fun report(label: String, book: String, para: String, start: Metrics, justify: Metrics): Int {
        val n = start.lineCount
        val rightMoves = movedLines(start.lineRights, justify.lineRights, n)
        val midMoves = movedLines(start.midGlyphLefts, justify.midGlyphLefts, n)
        val pxDiff = if (start.pixels != null && justify.pixels != null && start.pixelDims == justify.pixelDims) {
            start.pixels.indices.count { start.pixels[it] != justify.pixels[it] }
        } else {
            -1
        }
        Log.i(
            TAG,
            "$label book=$book chars=${para.length} lines=$n layout_width_px=${justify.layoutWidthPx} " +
                "start_align=${start.align} justify_align=${justify.align} " +
                "nonfinal_lines=${n - 1} lineRight_moved=$rightMoves midGlyph_moved=$midMoves " +
                "pixel_diff=$pxDiff pixel_dims=${justify.pixelDims} " +
                "start_lineRights=${start.lineRights.map { it.toInt() }} " +
                "justify_lineRights=${justify.lineRights.map { it.toInt() }} " +
                "start_midGlyphLefts=${start.midGlyphLefts.map { it.toInt() }} " +
                "justify_midGlyphLefts=${justify.midGlyphLefts.map { it.toInt() }}",
        )
        return rightMoves
    }

    // ---------------------------------------------------------------- M2 (the gate)

    /**
     * **M2 — the positive control.** Latin prose on the SAME Compose path. `Justify` must move non-final
     * lines' `getLineRight` and drive them flush to the layout width. A failure here means the harness or
     * the wiring is broken and M1 is uninterpretable — a WI-0 FAILURE, not a finding about CJK.
     */
    @Test
    fun controlM2_latinSynthetic_justifyMovesGlyphs_positiveControl() {
        val para = pickParagraph(readLatinAsset(), asciiLettersAllowed = true)
        val (start, justify) = measureBothAlignments(para)
        val moved = report("M2", "synthetic:latin-justify-sample.txt", para, start, justify)
        val n = justify.lineCount

        assertTrue(
            "M2 (positive control) FAILED: Justify moved 0 of ${n - 1} non-final lines on LATIN prose → " +
                "the measurement or the wiring is broken, so M1 is uninterpretable",
            moved > 0,
        )
        // Justified non-final lines must reach the content-box right edge (plan §7.1 M2), which the ragged
        // Start run does not — this is the "flush right" half of the criterion, not just "something moved".
        val flush = (0 until n - 1).count { abs(justify.lineRights[it] - justify.layoutWidthPx) <= 1.5f }
        assertTrue(
            "M2: justified non-final lines must reach the layout width (${justify.layoutWidthPx}px); " +
                "flush=$flush of ${n - 1} — rights=${justify.lineRights}",
            flush == n - 1,
        )
        // Pixel capture is MANDATORY, not best-effort: it is the ground-truth signal that makes M1's
        // negative credible. If it silently became unavailable, the run must fail rather than quietly
        // degrade to a single signal.
        assertTrue(
            "M2: captureToImage must work on this device — the pixel ground truth is required evidence",
            start.pixels != null && justify.pixels != null && start.pixelDims == justify.pixelDims,
        )
        val pxDiff = start.pixels!!.indices.count { start.pixels[it] != justify.pixels!![it] }
        assertTrue("M2: the rendered pixels must differ between Start and Justify", pxDiff > 0)
        // The control also CHARACTERISES a Compose API as justification-blind: while the pixels above
        // demonstrably moved, `getBoundingBox().left` reported ZERO movement on every non-final line.
        // Pinning it here is what stops a future reader from treating that API's silence on the CJK run
        // (M1) as evidence — and fails loudly if Compose ever makes it justification-aware.
        assertEquals(
            "M2 characterisation: getBoundingBox/getHorizontalPosition do NOT reflect justification " +
                "in this Compose version — so they are not evidence in M1 either",
            0, movedLines(start.midGlyphLefts, justify.midGlyphLefts, n),
        )
        controlPassed = true   // unblocks M1 — see [controlPassed]
    }

    // ---------------------------------------------------------------- M1 (the question)

    /**
     * **M1 — the real CJK book.** Characterisation of what the Compose engine actually does to space-free
     * CJK prose under `TextAlign.Justify`. The assertion PINS the measured outcome (see the WI-0 record in
     * the HANDOFF / evidence): zero non-final lines move on any of the three signals, i.e. Compose's
     * inter-word justification is INERT on CJK. If a future toolchain makes CJK justify, this fails and
     * forces plan §4.3(a) + AC-1b to be revisited rather than rotting.
     */
    @Test
    fun measurementM1_cjkRealBook_justifyIsInert_characterisation() {
        // The control gates the measurement MECHANICALLY, not by convention: without a passing M2 in this
        // same run, a "nothing moved" result is indistinguishable from a broken harness.
        assertTrue(
            "M1 is uninterpretable without the M2 positive control passing in the SAME run — run the whole " +
                "class, not a filtered single method",
            controlPassed,
        )
        val text = requireNotNull(readRealCjkBookOrNull()) {
            "M1 requires the REAL CJK book (test-books/books/txt/黑暗血时代.txt, $REAL_BOOK_BYTES bytes) " +
                "pushed to the app's external files dir as perf-cjk.txt — a synthetic stand-in would make " +
                "the CJK finding hollow"
        }
        val para = pickParagraph(text, asciiLettersAllowed = false)
        assertTrue("the CJK paragraph must contain no spaces to stretch", !para.contains(' '))
        // Prove the measured text really is CJK script — a mislabelled fixture must not silently become
        // "the CJK result".
        val cjkFraction = para.count { isCjk(it) }.toDouble() / para.length
        assertTrue(
            "the measured paragraph must be predominantly CJK script (was ${"%.2f".format(cjkFraction)})",
            cjkFraction >= MIN_CJK_FRACTION,
        )
        val (start, justify) = measureBothAlignments(para)
        val moved = report("M1", "real:黑暗血时代.txt", para, start, justify)
        val n = justify.lineCount

        assertEquals(
            "M1 characterisation: Compose inter-word justification moved ${moved} of ${n - 1} non-final " +
                "CJK lines. 0 = the plan's §4.3(a) prediction holds. A non-zero value means the engine " +
                "CHANGED — strike the prediction and upgrade AC-1b to an assertion.",
            0, moved,
        )
        // NO assertion on midGlyphLefts here: M2 proved that API is justification-blind, so asserting it
        // unchanged would be a test that CANNOT fail — worse than no test. Its values are logged only.
        assertTrue(
            "M1: the pixel ground truth is REQUIRED — a missing capture would reduce the negative result " +
                "to a single signal without anyone noticing",
            start.pixels != null && justify.pixels != null && start.pixelDims == justify.pixelDims,
        )
        assertEquals(
            "M1: not a single rendered pixel may differ if no glyph moved (the ground truth)",
            0, start.pixels!!.indices.count { start.pixels[it] != justify.pixels!![it] },
        )
    }
}
