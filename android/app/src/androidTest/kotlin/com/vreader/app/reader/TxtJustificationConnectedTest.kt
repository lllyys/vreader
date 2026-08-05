package com.vreader.app.reader

import android.util.Log
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.printToLog
import androidx.compose.ui.text.TextLayoutInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.paged.ComposeLineMeasurer
import com.vreader.app.reader.paged.PageContentBox
import com.vreader.app.reader.paged.PaginationToken
import com.vreader.app.reader.paged.TxtPageIndex
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.reader.settings.bodyTextStyle
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File
import kotlin.math.abs

/**
 * Feature #156 WI-1 — the POST-LAYOUT proof that TXT/MD body text is justified, that a wrapping
 * Markdown heading is excluded in scroll mode, and that no page boundary moved.
 *
 * **Why every assertion here is a number read back after layout.** "The setting persisted" and "the
 * composable recomposed" both pass with zero glyphs moved, and so does
 * `assertEquals(Justify, style.textAlign)` — WI-0 measured exactly that shape passing on the real CJK
 * book while 0 of 19 non-final lines and 0 pixels moved. Reading `textAlign` back off the rendered
 * `TextLayoutResult` is only marginally better: it proves the REQUEST reached layout, never that a
 * glyph moved. The discriminating signal is `TextLayoutResult.getLineRight(i)`.
 * `getBoundingBox`/`getHorizontalPosition` are NOT usable — WI-0's positive control measured them
 * reporting zero movement while 191 965 pixels demonstrably moved, so they are justification-blind in
 * this Compose version.
 *
 * **The differential oracle.** Justify-by-default has no toggle (rule 51 — no new control), so there is
 * no production way to render the same book under `Start` for comparison. Instead each test takes the
 * LIVE production `TextLayoutInput` (text, style, constraints, density, resolver, direction, softWrap,
 * overflow, maxLines, placeholders — all of it) and re-measures it with ONLY `textAlign` changed. Two
 * self-checks keep that honest: re-measuring under the production alignment must REPRODUCE the
 * production line-rights (proving the oracle is faithful, not a differently-shaped layout), and the
 * `Start` baseline must be measurably RAGGED over the same lines the justified run collapses.
 *
 * Method order is pinned so the LATIN control (`a…`) runs before the CJK characterisation (`b…`): a
 * "nothing moved" CJK result is uninterpretable without a passing positive control in the same run —
 * exactly the trap WI-0's M2 exists to close. [controlPassed] enforces it mechanically.
 *
 * Entry point: every rendering assertion opens the book through the production reader
 * (`TxtReaderActivity` via `ActivityScenario` on an imported book) — the "Library → tap the book" path;
 * justify-by-default needs no user action beyond opening. Run ONE class per connected invocation
 * (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class TxtJustificationConnectedTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    private companion object {
        const val TAG = "WI1-JUSTIFY"

        /** The real `test-books/books/txt/黑暗血时代.txt`, pushed to the app's scoped external files dir. */
        const val REAL_BOOK_BYTES = 14_059_220L
        const val REAL_BOOK_BYTES_TOLERANCE = 1_000L

        /** Float noise floor for "these two x-coordinates are the same pixel position". */
        const val EPSILON_PX = 0.5f

        /**
         * How far apart justified right edges may sit and still count as ONE common edge. Measured
         * spread on this emulator: 9px across 13 justified lines at a 974px measure (the residual is
         * per-glyph, since the reported edge is the last glyph's advance).
         */
        const val MAX_JUSTIFIED_EDGE_SPREAD_PX = 15f

        /**
         * How close to the measure that common edge must sit. Measured: 932 of 974 = 95.7% in the
         * production reader. The residual is recorded, not assumed — see [logJustifiedEdgeProbe].
         */
        const val MIN_JUSTIFIED_EDGE_FRACTION = 0.90f

        /**
         * How ragged the `Start` baseline must be for "justification collapsed it" to mean anything.
         * Measured: 134–225px of spread on the same lines. A fixture too uniform to justify would fail
         * here rather than silently produce a vacuous pass.
         */
        const val MIN_RAGGED_SPREAD_PX = 40f

        const val JUSTIFIED_EDGE_PROBE = "edge-probe"

        /**
         * A bounded PREFIX of the real CJK book for the pagination-invariance leg. Real bytes from the
         * real file — bounded only so two full indexes plus a control fit the run (the whole 14 MB book
         * measures ~85 s per index; #137 WI-11 evidence). The alignment question is per-line, so a
         * prefix exercises it identically.
         */
        const val CJK_SLICE_CHARS = 400_000

        /** Set by the Latin positive control; the CJK characterisation requires it (see the class doc). */
        @JvmStatic var controlPassed = false
    }

    @Before
    fun pinDefaults() = resetSettings()

    @After
    fun resetSettings() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
        store.setLayout(ReaderLayout.Scroll)
    }

    // ---------------------------------------------------------------- fixtures / harness

    private fun setLayoutAndConfirm(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        for (i in 0 until 50) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "justify-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        // A prior test's page turns leave a saved offset for the same content-addressed fingerprint;
        // zero it so every open starts at the document head regardless of test order.
        app.container.cacheOffset(book.fingerprintKey, 0)
        return book.fingerprintKey
    }

    private fun assetText(asset: String): String =
        instrumentation.context.assets.open(asset).use { it.readBytes().toString(Charsets.UTF_8) }

    /** The real 14 MB CJK book, or null if it is absent / not the genuine file (never label a stale
     *  or truncated file "real" — the #137 WI-11 Gate-4 M3 lesson). */
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

    private fun requireRealCjkBook(): String = requireNotNull(readRealCjkBookOrNull()) {
        "this test needs the REAL CJK book (test-books/books/txt/黑暗血时代.txt, $REAL_BOOK_BYTES bytes) " +
            "pushed to the app's external files dir as perf-cjk.txt — the connected task wipes that dir " +
            "at run end, so re-push before EVERY run. A synthetic stand-in would make the CJK finding hollow."
    }

    private fun layoutFor(anchor: String): TextLayoutResult? = runCatching {
        val out = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(anchor, substring = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(out) }
        out.firstOrNull()
    }.getOrNull()

    /** Block until exactly one node matches [anchor] and it has published a layout, then return it. */
    private fun awaitLayout(anchor: String, timeoutMs: Long = 20_000): TextLayoutResult {
        try {
            compose.waitUntil(timeoutMs) {
                compose.onAllNodesWithText(anchor, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
        } catch (t: Throwable) {
            // A missing anchor is almost always "the chunk is not composed / the reader is on another
            // surface" — dump what IS rendered so the next run diagnoses rather than guesses.
            runCatching { compose.onRoot(useUnmergedTree = true).printToLog(TAG) }
            Log.w(TAG, "anchor '$anchor' never appeared — see the semantics dump above")
            throw t
        }
        compose.waitUntil(timeoutMs) { layoutFor(anchor) != null }
        assertEquals(
            "the anchor must identify exactly one rendered Text node, else two readings could be of " +
                "different Texts",
            1, compose.onAllNodesWithText(anchor, substring = true).fetchSemanticsNodes().size,
        )
        return requireNotNull(layoutFor(anchor))
    }

    /**
     * Re-lay-out the EXACT production input with only [align] changed — the differential oracle. Every
     * shaping input (density, font resolver, layout direction, constraints, softWrap, overflow,
     * maxLines, placeholders) is taken from the production layout, so the only variable is alignment.
     */
    private fun remeasure(input: TextLayoutInput, align: TextAlign): TextLayoutResult =
        TextMeasurer(input.fontFamilyResolver, input.density, input.layoutDirection).measure(
            text = input.text,
            style = input.style.copy(textAlign = align),
            overflow = input.overflow,
            softWrap = input.softWrap,
            maxLines = input.maxLines,
            placeholders = input.placeholders,
            constraints = input.constraints,
            layoutDirection = input.layoutDirection,
            density = input.density,
            fontFamilyResolver = input.fontFamilyResolver,
            skipCache = true,
        )

    private fun lineRights(r: TextLayoutResult): List<Float> = (0 until r.lineCount).map { r.getLineRight(it) }

    /** Per-line char ranges — the direct evidence for "did the line BREAKS move", not just the edges. */
    private fun lineRanges(r: TextLayoutResult): List<Pair<Int, Int>> =
        (0 until r.lineCount).map { r.getLineStart(it) to r.getLineEnd(it, visibleEnd = false) }

    /**
     * The lines an engine is expected to justify: every line that is NOT the last line of its paragraph.
     * This is `Layout.isJustificationRequired` stated in terms of the laid-out result — a line ending at
     * the end of the text, or ending on a `\n`, terminates its paragraph and is left ragged by every
     * engine (plan §4.2). Deriving it (rather than saying "all but the last line") matters because a
     * production chunk retains its trailing EOL, which adds an empty final line AFTER the paragraph's
     * real last line, and because a paged page holds several paragraphs.
     */
    private fun expectedJustifiedLines(r: TextLayoutResult): List<Int> {
        val text = r.layoutInput.text.text
        return (0 until r.lineCount).filter { line ->
            val end = r.getLineEnd(line, visibleEnd = false)
            end < text.length && end > 0 && text[end - 1] != '\n'
        }
    }

    private fun movedLines(a: List<Float>, b: List<Float>): List<Int> =
        a.indices.filter { abs(a[it] - b[it]) > EPSILON_PX }


    /**
     * Assert the oracle reproduces the production layout when handed the production alignment. Without
     * this, a `Start` baseline that differed for some OTHER reason (a different density, a cache hit, a
     * different resolver) would masquerade as "justification moved glyphs".
     */
    private fun assertOracleIsFaithful(label: String, production: TextLayoutResult) {
        val replayed = remeasure(production.layoutInput, production.layoutInput.style.textAlign)
        assertEquals("$label: oracle must reproduce the production line count", production.lineCount, replayed.lineCount)
        val drift = movedLines(lineRights(production), lineRights(replayed))
        assertTrue(
            "$label: the differential oracle must REPRODUCE the production layout under the production " +
                "alignment (drifted on lines $drift) — otherwise its Start baseline is not comparable",
            drift.isEmpty(),
        )
    }

    /**
     * The shared body of the AC-1a proof for one rendered node. Returns the number of lines that moved.
     *
     * **The criterion is raggedness COLLAPSE, not a flush hit on `layout.size.width`, and that is a
     * measured decision.** In the production reader `getLineRight` reports a justified line at ~923–932
     * of a 974px measure — a stable ~4% short, 9px spread — whereas WI-0's spike measured the SAME
     * paragraph at the SAME measure reporting a hard 973–974. [logJustifiedEdgeProbe] settled why, by
     * measurement rather than argument:
     *   • the production chunk's trailing EOL is NOT the cause — stripping it reproduces 923–932;
     *   • laying the same text out under the UNMERGED `bodyTextStyle()` gives 973–974 exactly.
     * The difference is the Material `LocalTextStyle` the production host merges in (WI-0 called
     * `TxtBody` in a bare composition with no app theme). That style is layout-affecting — under it the
     * paragraph even breaks its last line differently — so the absolute right-edge value is a property
     * of the host, not of justification. Pinning "flush == size.width" would pin WI-0's harness rather
     * than the shipped reader.
     *
     * What justification actually does, and what is asserted here: it takes a set of ragged non-final
     * right edges spanning tens or hundreds of px and collapses them onto ONE common edge near the
     * measure. That is strictly HARDER to satisfy than "some line touched the right edge" — it requires
     * every justified line to converge — and it is engine-independent. Removing `textAlign` from
     * `bodyTextStyle()` makes it fail immediately (the spread stays ragged).
     *
     * The set of lines held to that bar is DERIVED from the layout ([expectedJustifiedLines]), so the
     * same helper serves the scroll node (one paragraph, plus the empty line its trailing EOL adds) and
     * the paged node (several paragraphs, each with its own ragged final line).
     */
    private fun assertJustifiedAndMoved(label: String, production: TextLayoutResult): Int {
        val width = production.size.width
        assertTrue("$label: the text must wrap (≥2 lines) or there is nothing to justify", production.lineCount >= 2)
        // NECESSARY but NOT sufficient — the gate that says we are reading the justified request.
        assertEquals("$label: the production render must request Justify", TextAlign.Justify, production.layoutInput.style.textAlign)
        assertOracleIsFaithful(label, production)

        val justifyRights = lineRights(production)
        val startBaseline = remeasure(production.layoutInput, TextAlign.Start)
        assertEquals(
            "$label: alignment must not change the line count (it is applied after line breaking)",
            production.lineCount, startBaseline.lineCount,
        )
        val startRights = lineRights(startBaseline)
        val moved = movedLines(startRights, justifyRights)

        Log.i(
            TAG,
            "$label lines=${production.lineCount} layout_width_px=$width " +
                "constraints_max=${production.layoutInput.constraints.maxWidth} moved=${moved.size} " +
                "start_lineRights=${startRights.map { it.toInt() }} " +
                "justify_lineRights=${justifyRights.map { it.toInt() }} " +
                "start_ranges=${lineRanges(startBaseline)} justify_ranges=${lineRanges(production)}",
        )
        logJustifiedEdgeProbe(label, production)

        // AC-3 at the RENDER level: alignment is applied after line breaking, so not one break moved.
        // (The paginator-level proof over a full page-start array is d1.)
        assertEquals(
            "$label: alignment must not move a single line break — a drift here would move every saved " +
                "reading position in a paged book",
            lineRanges(startBaseline), lineRanges(production),
        )
        assertTrue(
            "$label: Justify moved 0 of ${production.lineCount} lines on LATIN prose — the alignment is " +
                "not reaching the rendered glyphs (rights=$justifyRights)",
            moved.isNotEmpty(),
        )

        // EVERY line the engine is expected to justify — derived, not "all but the last" — must sit on
        // ONE common right edge at the measure. This is the whole criterion; it is strictly stronger
        // than "some line reached the edge" because it admits no straggler.
        val expected = expectedJustifiedLines(production)
        assertTrue("$label: the fixture must contain lines an engine would justify", expected.isNotEmpty())
        val expectedEdges = expected.map { justifyRights[it] }
        val commonEdge = expectedEdges.max()
        val justifiedSpread = commonEdge - expectedEdges.min()
        assertTrue(
            "$label: EVERY justifiable line must converge on one right edge (spread was ${justifiedSpread}px " +
                "over lines $expected, rights=$expectedEdges)",
            justifiedSpread <= MAX_JUSTIFIED_EDGE_SPREAD_PX,
        )
        assertTrue(
            "$label: that common edge (${commonEdge}px) must sit at the measure (${width}px), i.e. within " +
                "${(100 - MIN_JUSTIFIED_EDGE_FRACTION * 100).toInt()}% of it",
            commonEdge >= width * MIN_JUSTIFIED_EDGE_FRACTION,
        )
        // Those same lines were genuinely RAGGED before — otherwise "they converged" is vacuous.
        val startEdges = expected.map { startRights[it] }
        val startSpread = startEdges.max() - startEdges.min()
        assertTrue(
            "$label: the Start baseline must be ragged over the same lines (spread was ${startSpread}px, " +
                "rights=$startEdges) — otherwise there was nothing for justification to collapse",
            startSpread >= MIN_RAGGED_SPREAD_PX,
        )
        assertTrue(
            "$label: justification must COLLAPSE the raggedness (start spread ${startSpread}px vs " +
                "justified ${justifiedSpread}px)",
            justifiedSpread * 3 < startSpread,
        )
        // And nothing OUTSIDE that set moved: a paragraph-final line must never be stretched (§4.2).
        val strayMoves = moved.filterNot { it in expected }
        assertTrue(
            "$label: a paragraph-final line must not be justified, but lines $strayMoves moved " +
                "(start=${strayMoves.map { startRights[it] }}, justify=${strayMoves.map { justifyRights[it] }})",
            strayMoves.isEmpty(),
        )
        return moved.size
    }

    /**
     * Records — never asserts — where the justified right edge lands under two variations of the
     * production input, so the ~4% offset between this suite's numbers and WI-0's stays an OBSERVED
     * quantity rather than an unexplained discrepancy between two measurements of the same feature.
     *
     * WI-0's spike measured the same paragraph at the same 974px measure and reported a hard flush at
     * 973–974; the production reader reports ~923–932. Two candidate causes, both probed here:
     *   • `no_eol` — the production chunk retains its trailing line terminator, WI-0's did not.
     *   • `bare_style` — WI-0 called `TxtBody` in a bare `setContent` with no app theme, so
     *     `LocalTextStyle.current` was `TextStyle.Default`; the production host merges the Material
     *     typography (letter spacing, platform style, line-break policy), all of which reach shaping.
     */
    private fun logJustifiedEdgeProbe(label: String, production: TextLayoutResult) {
        val input = production.layoutInput
        val measurer = TextMeasurer(input.fontFamilyResolver, input.density, input.layoutDirection)
        fun measure(text: androidx.compose.ui.text.AnnotatedString, style: androidx.compose.ui.text.TextStyle) =
            measurer.measure(
                text = text, style = style, overflow = input.overflow, softWrap = input.softWrap,
                maxLines = input.maxLines, constraints = input.constraints,
                layoutDirection = input.layoutDirection, density = input.density,
                fontFamilyResolver = input.fontFamilyResolver, skipCache = true,
            )
        val justify = input.style.copy(textAlign = TextAlign.Justify)
        val noEol = if (input.text.text.endsWith("\n")) {
            lineRights(measure(input.text.subSequence(0, input.text.length - 1), justify)).map { it.toInt() }
        } else {
            emptyList()
        }
        // The UNMERGED Display style — what WI-0's bare composition laid out with.
        val bare = measure(input.text, ReaderSettings().bodyTextStyle())
        Log.i(
            TAG,
            "$JUSTIFIED_EDGE_PROBE $label width=${bare.size.width} no_eol_rights=$noEol " +
                "bare_style_lines=${bare.lineCount} bare_style_rights=${lineRights(bare).map { it.toInt() }}",
        )
    }

    // ---------------------------------------------------------------- AC-1a (Latin, asserted)

    /**
     * **AC-1a, scroll.** A Latin TXT paragraph opened through the production reader justifies: its
     * non-final lines reach the content-box right edge and differ from the `Start` layout of the same
     * input. This is also the POSITIVE CONTROL that makes the CJK characterisation interpretable.
     *
     * Fixture: the synthetic Latin TXT asset, under the stated AGENTS.md exception — the repository's
     * entire real TXT set is one CJK book, and the only real Latin book is an EPUB (a different engine,
     * so it cannot control a Compose measurement). Its FIRST line is a long body paragraph, because a
     * `LazyColumn` only composes the chunks in the viewport (measured at 1288px tall on this emulator,
     * ≈4 paragraph chunks) — a fixture whose prose starts further down leaves the anchor uncomposed and
     * the test times out on nothing.
     */
    @Test
    fun a1_latinScroll_nonFinalLinesAreFlushRight_andDifferFromStart() {
        setLayoutAndConfirm(ReaderLayout.Scroll)
        val key = importAsset("latin-justify-book.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            // One paragraph == one chunk == one Text in scroll mode, so the strict all-non-final-lines
            // form of AC-1a applies here.
            val layout = awaitLayout("The lamplighter walked")
            assertJustifiedAndMoved("A1/scroll-latin", layout)
            controlPassed = true
        }
    }

    /** **AC-1a, paged.** The same proof in the paged renderer, whose page `Text` is built by
     *  `TxtPaginator.renderPage` and measured by phase-1 against the same style. A page concatenates
     *  several paragraphs into one `Text`, so paragraph-final lines are legitimately ragged and the
     *  criterion is the moved-lines set, each of which must land flush. */
    @Test
    fun a2_latinPaged_nonFinalLinesAreFlushRight_andDifferFromStart() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("latin-justify-book.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            compose.waitUntil(20_000) {
                var ready = false
                scenario.onActivity { ready = it.pagedPageCountForTest()?.let { c -> c > 0 } == true }
                ready
            }
            val layout = awaitLayout("The lamplighter walked")
            val moved = assertJustifiedAndMoved("A2/paged-latin", layout)
            assertTrue(
                "A2: a paged page of Latin prose must justify SEVERAL lines, not one incidental one " +
                    "(moved=$moved)",
                moved >= 3,
            )
        }
    }

    // ---------------------------------------------------------------- AC-1b (CJK, characterised)

    /**
     * **AC-1b — recorded, NOT promised.** On the REAL CJK book, Compose's inter-word justification has
     * nothing to stretch (space-free prose), so WI-0 measured 0 of 19 non-final lines and 0 pixels
     * moving. This PINS that measurement: it does not demand flush-right (which would fail on the
     * plan's own predicted outcome), and it does not assert nothing at all (which would let the
     * prediction rot). If a future Compose/AGP upgrade starts justifying CJK, this fails and forces
     * §4.3(a) + AC-1b to be revisited.
     *
     * The paragraph is rendered by the production reader on the real book; the `Start` comparison comes
     * from the same differential oracle the Latin control validated in the same run.
     */
    @Test
    fun b1_cjkRealBook_justifyIsInert_characterisation() {
        assertTrue(
            "the CJK characterisation is uninterpretable without the Latin positive control passing in " +
                "the SAME run — run the whole class, not a filtered single method",
            controlPassed,
        )
        val text = requireRealCjkBook()
        setLayoutAndConfirm(ReaderLayout.Scroll)
        val key = runBlocking {
            val dir = instrumentation.targetContext.getExternalFilesDir(null)!!
            val book = app.container.importer.importStream(
                "content://test/perf-cjk.txt", "黑暗血时代.txt", File(dir, "perf-cjk.txt").inputStream(),
            )
            app.container.cacheOffset(book.fingerprintKey, 0)
            book.fingerprintKey
        }
        // A deterministic anchor: the first substantial, space-free, predominantly-CJK paragraph of the
        // real book — so the recorded numbers are reproducible run to run. Its chunk index equals its
        // line index (TxtDocument line-chunks the decoded text, and none of the opening lines is long
        // enough to be hard-split), which is what the reader is scrolled to below.
        val chunkIndex = requireNotNull(
            text.lineSequence().take(200).indexOfFirst { line ->
                val t = line.trim()
                t.length in 80..1_500 && !t.contains(' ') && t.none { c -> c.code < 128 && c.isLetter() } &&
                    t.count { c -> isCjk(c) }.toDouble() / t.length >= 0.8
            }.takeIf { it >= 0 },
        ) { "no substantial space-free CJK paragraph in the real book's opening 200 lines" }
        val paragraph = text.lineSequence().elementAt(chunkIndex)

        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            // A LazyColumn only composes the chunks in the viewport, so bring the measured paragraph
            // on-screen the way a reader does — by scrolling the body — before querying its layout.
            compose.waitUntil(40_000) {
                var ready = false
                scenario.onActivity { ready = it.firstVisibleChunkForTest() != null }
                ready
            }
            runScrollTo(scenario, chunkIndex)
            val anchor = paragraph.trim().take(10)
            val production = awaitLayout(anchor, timeoutMs = 40_000)
            assertEquals("the CJK body must still REQUEST Justify", TextAlign.Justify, production.layoutInput.style.textAlign)
            assertTrue("the CJK paragraph must wrap", production.lineCount >= 2)
            assertOracleIsFaithful("B1/cjk", production)

            val justifyRights = lineRights(production)
            val startRights = lineRights(remeasure(production.layoutInput, TextAlign.Start))
            val moved = movedLines(startRights, justifyRights)
            Log.i(
                TAG,
                "B1 book=real:黑暗血时代.txt chars=${paragraph.length} lines=${production.lineCount} " +
                    "layout_width_px=${production.size.width} moved=${moved.size} " +
                    "start_lineRights=${startRights.map { it.toInt() }} " +
                    "justify_lineRights=${justifyRights.map { it.toInt() }}",
            )
            assertEquals(
                "AC-1b characterisation: Compose inter-word justification moved ${moved.size} of " +
                    "${production.lineCount} real-CJK lines (lines $moved). 0 = plan §4.3(a) holds. A " +
                    "non-zero value means the ENGINE CHANGED — strike the prediction and upgrade AC-1b " +
                    "to an assertion.",
                0, moved.size,
            )
        }
    }

    /** Scroll the SCROLL body so [index] is the first visible chunk, on the activity's thread; blocks
     *  until it lands (the #137 `PagedAcceptanceConnectedTest` pattern). */
    private fun runScrollTo(scenario: ActivityScenario<TxtReaderActivity>, index: Int) {
        val latch = java.util.concurrent.CountDownLatch(1)
        val error = arrayOfNulls<Throwable>(1)
        scenario.onActivity { activity ->
            activity.lifecycleScope.launch {
                try { activity.scrollToItemForTest(index) } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(30, java.util.concurrent.TimeUnit.SECONDS)) throw AssertionError("scrollTo timed out")
        error[0]?.let { throw it }
    }

    /** Chinese/Japanese/Korean ideographs + CJK punctuation + fullwidth forms. */
    private fun isCjk(c: Char): Boolean = c.code in 0x3000..0x303F ||
        c.code in 0x3400..0x4DBF || c.code in 0x4E00..0x9FFF ||
        c.code in 0xF900..0xFAFF || c.code in 0xFF00..0xFFEF

    // ---------------------------------------------------------------- AC-2 / AC-2b (MD headings)

    /**
     * **AC-2 — scroll.** A WRAPPING Markdown heading is not justified while the prose after it is. A
     * one-line heading would pass under both the correct and the broken implementation (no engine
     * justifies a paragraph's last line), so the fixture's headings are deliberately long enough to
     * wrap — and the test asserts they actually did.
     */
    @Test
    fun c1_mdWrappingHeading_isNotJustified_whileProseIs_scroll() {
        setLayoutAndConfirm(ReaderLayout.Scroll)
        val key = importAsset("md-justify.md")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            val heading = awaitLayout("A Deliberately Long Markdown Chapter Heading")
            assertTrue(
                "the fixture heading must WRAP (a one-line heading proves nothing — the last-line rule " +
                    "already leaves it alone); lines=${heading.lineCount}",
                heading.lineCount >= 2,
            )
            assertNotEquals(
                "a wrapping MD heading must NOT be justified",
                TextAlign.Justify, heading.layoutInput.style.textAlign,
            )
            // Post-layout, not just the style: the heading's non-final lines must still be RAGGED —
            // the exact mirror of the prose criterion below. Applying justify to the heading collapses
            // this spread and the assertion fails.
            val headingWidth = heading.size.width
            val headingRights = lineRights(heading)
            val nonFinal = expectedJustifiedLines(heading).map { headingRights[it] }
            assertTrue("the heading must have lines an engine would justify", nonFinal.size >= 2)
            val headingSpread = nonFinal.max() - nonFinal.min()
            Log.i(
                TAG,
                "C1 heading lines=${heading.lineCount} width=$headingWidth spread=$headingSpread " +
                    "rights=${headingRights.map { it.toInt() }}",
            )
            assertTrue(
                "a non-justified heading's non-final lines must stay RAGGED (spread was ${headingSpread}px " +
                    "over $nonFinal at width $headingWidth) — a collapsed spread means it was justified",
                headingSpread > MAX_JUSTIFIED_EDGE_SPREAD_PX,
            )

            // ...while the prose chunk right after it justifies, in the SAME document and the SAME open.
            val prose = awaitLayout("Justification is a typographic operation")
            assertJustifiedAndMoved("C1/md-prose", prose)
        }
    }

    /**
     * **AC-2b — paged: the KNOWN LIMITATION, made executable.** `TxtPaginator.renderPage` concatenates a
     * page's chunks into ONE `AnnotatedString` drawn by ONE `Text`, and a Compose `Text` carries exactly
     * one paragraph alignment — so a paged page containing a wrapping heading justifies the heading too.
     * That is scoped out of #156 deliberately (the `ParagraphStyle`-span alternative forces paragraph
     * breaks, which DO affect line breaking, risking page overflow against a per-chunk measurer).
     *
     * Written as a characterisation so the limitation cannot rot in prose: if a future paginator change
     * makes per-paragraph alignment possible, this fails and forces the note to be revisited.
     *
     * Gate-4 round 1 (Medium): asserting only `layoutInput.style.textAlign == Justify` here would leave
     * AC-2b in exactly the false-green class this whole suite exists to avoid — it would stay green if
     * Compose received `Justify` and moved zero heading glyphs, which is precisely what happens on CJK.
     * The limitation is therefore evidenced the same way the feature is: the heading's own wrapped lines
     * are located inside the page, and their `getLineRight` values must MOVE against the `Start` oracle
     * and collapse onto the page's common justified edge.
     */
    @Test
    fun c2_mdPagedHeading_sharesThePageAlignment_knownLimitation() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("md-justify.md")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            compose.waitUntil(20_000) {
                var ready = false
                scenario.onActivity { ready = it.pagedPageCountForTest()?.let { c -> c > 0 } == true }
                ready
            }
            val heading = "A Deliberately Long Markdown Chapter Heading"
            val page = awaitLayout(heading)
            val pageText = page.layoutInput.text.text
            // The heading and the prose after it are the SAME Text — that is the limitation itself.
            assertTrue(
                "the page Text must carry BOTH the heading and the following prose (that shared node is " +
                    "what makes per-paragraph alignment impossible here)",
                pageText.contains("Justification is a typographic operation"),
            )
            assertEquals(
                "KNOWN LIMITATION (plan §5.2b): a paged page renders as ONE Text with ONE alignment. If " +
                    "this ever stops holding, the limitation note and AC-2b must be revisited.",
                TextAlign.Justify, page.layoutInput.style.textAlign,
            )
            assertOracleIsFaithful("C2/paged-md-heading", page)

            // Locate the HEADING's own rendered extent inside the page text (markers are stripped, and
            // the chunk keeps its EOL, so the heading run ends at the next newline).
            val headingStart = pageText.indexOf(heading)
            assertTrue("the heading must be present in the page text", headingStart >= 0)
            val headingEnd = pageText.indexOf('\n', headingStart).let { if (it < 0) pageText.length else it }
            val headingLines = (0 until page.lineCount).filter { line ->
                page.getLineStart(line) < headingEnd && page.getLineEnd(line, visibleEnd = false) > headingStart
            }
            assertTrue(
                "the fixture heading must WRAP inside the page (a one-line heading proves nothing — the " +
                    "last-line rule already leaves it alone); heading lines=$headingLines",
                headingLines.size >= 2,
            )
            val headingJustifiable = expectedJustifiedLines(page).filter { it in headingLines }
            assertTrue("a wrapping heading must have at least one justifiable line", headingJustifiable.isNotEmpty())

            val justifyRights = lineRights(page)
            val startRights = lineRights(remeasure(page.layoutInput, TextAlign.Start))
            val movedHeadingLines = headingJustifiable.filter { abs(startRights[it] - justifyRights[it]) > EPSILON_PX }
            val headingEdges = headingJustifiable.map { justifyRights[it] }
            Log.i(
                TAG,
                "C2 paged heading lines=$headingLines justifiable=$headingJustifiable moved=$movedHeadingLines " +
                    "start=${headingJustifiable.map { startRights[it].toInt() }} " +
                    "justify=${headingEdges.map { it.toInt() }} width=${page.size.width}",
            )
            // The GLYPHS moved — the limitation is measured, not inferred from the requested style.
            assertTrue(
                "AC-2b must be evidenced by glyph movement, not by the requested alignment: the heading's " +
                    "justifiable lines $headingJustifiable did not move (start=" +
                    "${headingJustifiable.map { startRights[it] }}, justify=$headingEdges)",
                movedHeadingLines.isNotEmpty(),
            )
            val pageCommonEdge = expectedJustifiedLines(page).maxOf { justifyRights[it] }
            for (line in headingJustifiable) {
                assertTrue(
                    "heading line $line must sit on the page's common justified edge (${pageCommonEdge}px); " +
                        "was ${justifyRights[line]}",
                    abs(justifyRights[line] - pageCommonEdge) <= MAX_JUSTIFIED_EDGE_SPREAD_PX,
                )
            }
        }
    }

    // ---------------------------------------------------------------- AC-3 (pagination invariance)

    /**
     * **AC-3 — page boundaries are byte-identical under justification**, measured with the REAL
     * production `ComposeLineMeasurer` (a JVM fake measurer cannot answer this: the question is whether
     * the ANDROID text engine breaks lines differently, and a fake by construction does not). Compares
     * the FULL page-start array, not one page — a single-page comparison would be worthless.
     *
     * Carries its own SENSITIVITY control (a larger font size must move the boundaries), so "the arrays
     * match" cannot be confused with "the comparison cannot detect a change". Runs on Latin and on a
     * bounded prefix of the REAL CJK book.
     */
    @Test
    fun d1_pagedBoundaries_areIdenticalUnderStartAndJustify_realMeasurer() {
        setLayoutAndConfirm(ReaderLayout.Scroll)
        val key = importAsset("latin-justify-book.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use {
            // Take the EXACT production shaping inputs from the live reader.
            val production = awaitLayout("The lamplighter walked")
            val input = production.layoutInput
            val measurer = ComposeLineMeasurer(TextMeasurer(input.fontFamilyResolver, input.density, input.layoutDirection))
            // The LAID-OUT width, not `constraints.maxWidth` (which can be Constraints.Infinity and
            // would collapse every document to a single page — silently making the comparison vacuous).
            val widthPx = production.size.width.toFloat()
            assertTrue("a plausible content-box width is required (was $widthPx)", widthPx in 100f..4_000f)
            // A short box so even a modest fixture spans many pages (the comparison needs a real set).
            val box = PageContentBox(widthPx, 260f)
            val paginator = TxtPaginator()

            val cjkSlice = requireRealCjkBook().take(CJK_SLICE_CHARS)
            val cases = listOf(
                Triple("latin", assetText("latin-justify-book.txt"), false),
                Triple("md", assetText("md-justify.md"), true),
                Triple("cjk-real-prefix", cjkSlice, false),
            )

            for ((label, source, isMarkdown) in cases) {
                val doc = TxtDocument.of(source)
                fun indexAt(style: androidx.compose.ui.text.TextStyle): TxtPageIndex = runBlocking {
                    paginator.index(doc, style, box, measurer, PaginationToken(), isMarkdown)
                }
                val startIdx = indexAt(input.style.copy(textAlign = TextAlign.Start))
                val justifyIdx = indexAt(input.style.copy(textAlign = TextAlign.Justify))

                Log.i(
                    TAG,
                    "D1 case=$label md=$isMarkdown chars=${source.length} width_px=${widthPx.toInt()} " +
                        "start_pages=${startIdx.pageCount} justify_pages=${justifyIdx.pageCount}",
                )
                assertTrue("$label: needs several pages to compare (was ${justifyIdx.pageCount})", justifyIdx.pageCount > 3)
                assertEquals("$label: page count must not change under Justify", startIdx.pageCount, justifyIdx.pageCount)
                assertArrayEquals(
                    "$label: EVERY page boundary must be identical under Justify — a drift here moves " +
                        "every saved reading position in a paged book",
                    startIdx.pageStartsUtf16, justifyIdx.pageStartsUtf16,
                )
                assertEquals("$label: doc extent unchanged", startIdx.docEndExclusive, justifyIdx.docEndExclusive)

                // SENSITIVITY CONTROL: a genuinely layout-affecting change MUST move the boundaries.
                val biggerFont = input.style.copy(
                    textAlign = TextAlign.Justify,
                    fontSize = TextUnit(input.style.fontSize.value * 1.4f, TextUnitType.Sp),
                )
                val bigger = indexAt(biggerFont)
                assertFalse(
                    "$label: control — a larger font size must shift the page boundaries, else the " +
                        "invariance assertion above is incapable of failing",
                    bigger.pageStartsUtf16.contentEquals(justifyIdx.pageStartsUtf16),
                )
            }
        }
    }
}
