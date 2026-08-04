package com.vreader.app.reader.nav

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableJob
import kotlinx.coroutines.InternalForInheritanceCoroutinesApi
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.Continuation
import kotlin.coroutines.startCoroutine

/**
 * Feature #139 WI-3 — [MdTocScanner]: ATX + fence parity with iOS `TOCBuilder.forMD`
 * (`vreader/Services/TOCBuilder.swift:107-216`), plus the Android-only setext + YAML
 * front-matter extensions (plan §4.6, divergence D2).
 *
 * The properties this suite exists to protect:
 *
 * - **Every offset is a RAW-SOURCE UTF-16 offset at the heading LINE's start** — never a
 *   rendered/markup-stripped offset, and correct under LF / CRLF / CR. Everything downstream
 *   (the Contents jump, and through it #138's paged `ensureMeasuredThrough` seam) treats it
 *   as a source offset.
 * - **iOS parity where iOS has an opinion**: trim-before-test (so arbitrary leading
 *   indentation is legal), a SPACE — not a tab — after the hashes, and the guarded
 *   closing-hash strip.
 * - **The setext/front-matter extension never fires where it must not**: inside fences, after
 *   a blank line, after an ATX heading, or on a YAML front-matter delimiter.
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class MdTocScannerTest {

    private companion object {
        /** Kept out of the raw strings so a stray edit cannot silently unbalance a fence. */
        const val TICK3 = "```"
        const val TICK4 = "````"
        const val TILDE3 = "~~~"

        /** U+3000 IDEOGRAPHIC SPACE — a Zs, so `trim`-before-test must treat it as indent. */
        val IDEO: String = Char(0x3000).toString()

        /** A budget no semantic fixture can reach; the cap has its own tests. */
        const val NO_CAP: Int = Int.MAX_VALUE

        /** U+00A0 NO-BREAK SPACE — also a Zs, and also NOT the space ATX requires. */
        val NBSP: String = Char(0x00A0).toString()

        /** Two would-be ATX lines whose separator is a Zs rather than U+0020. */
        val NBSP_LINE: String = "\n#" + NBSP + "Nbsp\n#" + IDEO + "Ideographic"
    }

    // ------------------------------------------------------------------ suspend-call harness

    /**
     * Runs [MdTocScanner.scan] with exactly [job] as its context and returns the outcome.
     *
     * Deliberately not `runBlocking` / `runTest`: those install a NEW `Job` in the context, so a
     * cancelled job under test would never be the object `ensureActive()` queries. It also pins a
     * real property — the scanner is pure CPU work and must never actually suspend.
     */
    private fun scanWithJob(job: Job, text: String, limit: Int = NO_CAP): Result<ExtractResult> {
        var outcome: Result<ExtractResult>? = null
        val block: suspend () -> ExtractResult = { MdTocScanner.scan(text, limit) }
        block.startCoroutine(Continuation(job) { outcome = it })
        return requireNotNull(outcome) { "MdTocScanner must not suspend — it is pure CPU work" }
    }

    /** The plain-result path every semantic test uses; the cap gets its own dedicated tests. */
    private fun scan(text: String): List<DetectedHeading> =
        scanWithJob(Job(), text).getOrThrow().headings

    /**
     * A [Job] that reports `isActive` for the first [activeChecks] queries and cancels itself on
     * the next one — a deterministic stand-in for "the reader was closed mid-scan", with no
     * sleeps, no threads, and no dependence on how fast the machine runs.
     *
     * Same shape as `TxtTocRuleEngineTest.CancelAfter`, including the `get` override: `Job by
     * delegate` forwards EVERY interface member — `CoroutineContext.get` included — so without it
     * `coroutineContext[Job]` hands back the delegate, [isActive] is never called, the job never
     * cancels, and every assertion built on it passes vacuously.
     */
    @OptIn(InternalForInheritanceCoroutinesApi::class)
    private class CancelAfter(
        private val activeChecks: Int,
        private val delegate: CompletableJob = Job(),
    ) : Job by delegate {
        private var checks: Int = 0

        override val isActive: Boolean
            get() {
                if (checks++ >= activeChecks) delegate.cancel()
                return delegate.isActive
            }

        @Suppress("UNCHECKED_CAST")
        override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? =
            if (key == Job) this as E else null
    }

    /** `title|depth@offset` — one readable string per heading, so a diff names what moved. */
    private fun List<DetectedHeading>.rendered(): List<String> =
        map { "${it.title}|${it.depth}@${it.sourceOffsetUtf16}" }

    private fun titles(text: String): List<String> = scan(text).map { it.title }

    /** The offset the heading LINE starts at in the raw source — the assertion's own oracle. */
    private fun offsetOfLineContaining(text: String, needle: String): Int {
        val at = text.indexOf(needle)
        assertTrue("fixture does not contain '$needle'", at >= 0)
        val nl = text.lastIndexOfAny(charArrayOf('\n', '\r'), at)
        return nl + 1
    }

    // ------------------------------------------------------------------ ATX

    @Test
    fun atx_levels1To6_mapToDepth0To5() {
        val text = """
            # H1
            ## H2
            ### H3
            #### H4
            ##### H5
            ###### H6
        """.trimIndent()

        val headings = scan(text)

        assertEquals(listOf("H1", "H2", "H3", "H4", "H5", "H6"), headings.map { it.title })
        assertEquals(listOf(0, 1, 2, 3, 4, 5), headings.map { it.depth })
        assertEquals(
            listOf("H1", "H2", "H3", "H4", "H5", "H6").map { offsetOfLineContaining(text, "# $it") },
            headings.map { it.sourceOffsetUtf16 },
        )
    }

    @Test
    fun atx_sevenHashes_isNotAHeading() {
        val text = "####### Seven\n# Six or fewer\n"

        assertEquals(listOf("Six or fewer"), titles(text))
    }

    @Test
    fun atx_requiresSpaceAfterHashes_tabDoesNotQualify() {
        val text = "#\tTabbed\n#NoSpace" + NBSP_LINE + "\n# Nbsp\n# Real\n"

        // iOS: `afterHashes.hasPrefix(" ")` — literally U+0020, nothing else. A tab, an NBSP and
        // an ideographic space are all whitespace and none of them qualifies. The trailing
        // U+0020 line is the positive control: the rejections are about the separator, not the
        // fixture. (Two of the four rejected lines carry a NBSP — deliberate belt and braces.)
        assertEquals(listOf("Real"), titles(text))
    }

    @Test
    fun atx_arbitraryLeadingIndentation_isAllowed() {
        // 6 spaces is past CommonMark's 3-space limit; iOS trims first, so it is a heading.
        val text = "      # Deep\n\t\t# Tabbed\n$IDEO# Ideographic\n"

        val headings = scan(text)

        assertEquals(listOf("Deep", "Tabbed", "Ideographic"), headings.map { it.title })
        // The offset is the LINE start — the indent is INCLUDED, exactly as WI-2's TXT offsets are.
        assertEquals(0, headings[0].sourceOffsetUtf16)
        assertEquals(text.indexOf("\t\t#"), headings[1].sourceOffsetUtf16)
        assertEquals(text.indexOf(IDEO), headings[2].sourceOffsetUtf16)
    }

    @Test
    fun atx_closingHashRun_isStripped_unlessResultWouldBeEmpty() {
        val text = """
            # Closed #
            ## Bare ###
            ### ###
            #### Hash # Middle #
        """.trimIndent()

        // "### ###" would strip to "", so the run is KEPT as the title (iOS guard).
        assertEquals(listOf("Closed", "Bare", "###", "Hash # Middle"), titles(text))
    }

    @Test
    fun atx_offsetIsSourceOffset_notRenderedOffset() {
        val text = "Some **bold** and `code` and [link](http://example.com) here.\n\n## Target\n"

        val heading = scan(text).single()

        val sourceOffset = text.indexOf("## Target")
        assertEquals(sourceOffset, heading.sourceOffsetUtf16)

        // A RENDERED offset would sit far earlier: the markup above collapses substantially.
        val rendered = "Some bold and code and link here.\n\nTarget\n"
        val renderedOffset = rendered.indexOf("Target")
        assertNotEquals(
            "fixture is too weak to distinguish source from rendered offsets",
            renderedOffset,
            sourceOffset,
        )
    }

    @Test
    fun atx_cjkAndSurrogateTitles_arePreserved_withCodeUnitOffsets() {
        val emoji = "📘" // U+1F4D8 BLUE BOOK — a surrogate PAIR, 2 UTF-16 units
        val text = "$emoji intro\n# 第一章 太阳消失\n## $emoji Ends\n"

        val headings = scan(text)

        assertEquals(listOf("第一章 太阳消失", "$emoji Ends"), headings.map { it.title })
        assertEquals(text.indexOf("# 第"), headings[0].sourceOffsetUtf16)
        assertEquals(text.indexOf("## "), headings[1].sourceOffsetUtf16)
        // Offsets are UTF-16 CODE UNITS and never land inside a pair.
        headings.forEach { assertTrue(!text[it.sourceOffsetUtf16].isLowSurrogate()) }
    }

    @Test
    fun headingTitles_neverContainALineTerminator() {
        val text = "Setext title\n===\n# Atx title\n"

        val headings = scan(text)

        // Both kinds must actually be present, or the loop below asserts nothing.
        assertEquals(listOf("Setext title", "Atx title"), headings.map { it.title })
        headings.forEach { assertTrue(it.title.none { c -> c == '\n' || c == '\r' }) }
    }

    // ------------------------------------------------------------------ fences

    @Test
    fun fence_backtickFencedAtxHeading_isExcluded() {
        val text = "$TICK3\n# Inside the fence\n$TICK3\n# Outside\n"

        assertEquals(listOf("Outside"), titles(text))
    }

    @Test
    fun fence_tildeFencedAtxHeading_isExcluded() {
        val text = "$TILDE3\n# Inside the fence\n$TILDE3\n# Outside\n"

        assertEquals(listOf("Outside"), titles(text))
    }

    @Test
    fun fence_backtickRunWithTrailingBacktick_isNotAFence() {
        // An info string containing a backtick disqualifies the line (iOS parseFenceLine).
        val text = "${TICK3}kotlin`\n# Still scanned\n"

        assertEquals(listOf("Still scanned"), titles(text))
    }

    @Test
    fun fence_closingRunShorterThanOpening_doesNotClose() {
        val text = "$TICK4\n# Inside\n$TICK3\n# Still inside\n$TICK4\n# Outside\n"

        assertEquals(listOf("Outside"), titles(text))
    }

    @Test
    fun fence_unterminatedFence_swallowsRestOfDocument() {
        val text = "# Before\n$TICK3\n# After\n## Later\n"

        assertEquals(listOf("Before"), titles(text))
    }

    @Test
    fun fence_mismatchedCharDoesNotCloseTheOtherFence() {
        val text = "$TICK3\n$TILDE3\n# Inside\n$TICK3\n# Outside\n"

        assertEquals(listOf("Outside"), titles(text))
    }

    // ------------------------------------------------------------------ setext (D2)

    @Test
    fun setext_equalsUnderline_yieldsDepth0() {
        val text = "Document Title\n==============\n\nbody\n"

        val heading = scan(text).single()

        assertEquals("Document Title", heading.title)
        assertEquals(0, heading.depth)
        // The heading's position is its TITLE line, not the underline.
        assertEquals(0, heading.sourceOffsetUtf16)
    }

    @Test
    fun setext_dashUnderline_yieldsDepth1() {
        val text = "intro\n\nSection Title\n-------------\n"

        val heading = scan(text).single()

        assertEquals("Section Title", heading.title)
        assertEquals(1, heading.depth)
        assertEquals(text.indexOf("Section Title"), heading.sourceOffsetUtf16)
    }

    @Test
    fun setext_singleCharUnderline_isValid() {
        val text = "Equals One\n=\nblank\n\nDash One\n-\n"

        assertEquals(
            listOf("Equals One|0@${text.indexOf("Equals One")}", "Dash One|1@${text.indexOf("Dash One")}"),
            scan(text).rendered(),
        )
    }

    @Test
    fun setext_underlineAfterBlankLine_isNotAHeading() {
        val text = "Not a title\n\n---\n\nAlso not\n\n===\n"

        assertEquals(emptyList<String>(), titles(text))

        // Positive control: delete the blank lines and the SAME underlines do fire, so an
        // always-empty scanner cannot pass this test by accident.
        assertEquals(listOf("Not a title", "Also not"), titles(text.replace("\n\n", "\n")))
    }

    @Test
    fun setext_underlineInsideFence_isNotAHeading() {
        val text = "$TICK3\nTitle\n=====\n$TICK3\n# After\n"

        assertEquals(listOf("After"), titles(text))
    }

    @Test
    fun setext_underlineAfterAtxHeading_isNotAHeading() {
        val text = "# Atx Title\n---\n"

        val heading = scan(text).single()

        assertEquals("Atx Title", heading.title)
        assertEquals(0, heading.depth)
    }

    @Test
    fun setext_underlineWithInteriorSpaces_isNotAHeading() {
        // "- - -" is a thematic break, not an underline: the run must be contiguous.
        val text = "Paragraph\n- - -\nOther paragraph\n= =\n"

        assertEquals(emptyList<String>(), titles(text))

        // Positive control: close the runs up and the same two lines DO underline.
        assertEquals(
            listOf("Paragraph", "Other paragraph"),
            titles(text.replace("- - -", "---").replace("= =", "==")),
        )
    }

    @Test
    fun setext_underlineIsNotItselfAParagraphForTheNextUnderline() {
        val text = "Title\n===\n===\n"

        assertEquals(listOf("Title|0@0"), scan(text).rendered())
    }

    // ------------------------------------------------------------------ YAML front matter

    @Test
    fun frontMatter_closingDelimiter_doesNotEmitHeading() {
        val text = "---\ntitle: My Document\n---\n# Real\n"

        // Without the guard the closing `---` reads as a setext underline for "title: My Document".
        assertEquals(listOf("Real"), titles(text))
    }

    @Test
    fun frontMatter_onlyRecognizedWhenFirstLine() {
        val text = "\n---\ntitle: My Document\n---\n# Real\n"

        // Line 1 is blank, so this is NOT front matter — the delimiter is a setext underline.
        assertEquals(listOf("title: My Document", "Real"), titles(text))
    }

    @Test
    fun frontMatter_unterminated_isTreatedAsAbsent() {
        val text = "---\ntitle: My Document\n# Real\n## Also real\n"

        // A lone leading `---` is just a thematic break; nothing is swallowed.
        assertEquals(listOf("Real", "Also real"), titles(text))
    }

    @Test
    fun frontMatter_contents_yieldNoHeadings() {
        val text = "---\ntitle: X\nblurb: |\n  # Looks like a heading\n" +
            "Setext bait\n===\n---\n# Real\n"

        assertEquals(listOf("Real"), titles(text))
    }

    @Test
    fun frontMatter_requiresYamlLikeLine_proseBlockIsNotFrontMatter() {
        val text = "---\nJust prose with no key here\n---\n# Real\n"

        assertEquals(listOf("Just prose with no key here", "Real"), titles(text))
    }

    @Test
    fun frontMatter_leadingThematicBreak_laterDelimiter_headingsBetweenSurvive() {
        val text = "---\nChapter one begins here\n\n# Between A\n## Between B\n\n---\ntail\n"

        assertEquals(listOf("Between A", "Between B"), titles(text))
    }

    @Test
    fun frontMatter_closingBeyond100Lines_isTreatedAsAbsent() {
        val body = (0 until 100).joinToString("") { "key" + it + ": v\n" }
        val text = "---\n" + body + "---\n# Real\n"

        // The closing delimiter sits at line index 101 — past MAX_FRONT_MATTER_LINES, so the
        // block is scanned as ordinary Markdown and the last key line becomes a setext heading.
        assertEquals(listOf("key99: v", "Real"), titles(text))
    }

    @Test
    fun frontMatter_closingAtExactly100thLine_isRecognized() {
        val body = (0 until 98).joinToString("") { "key" + it + ": v\n" }
        val text = "---\n" + body + "---\n# Real\n"

        // `---` at index 0, 98 keys at 1..98, closing at index 99 — the last accepted position.
        assertEquals(listOf("Real"), titles(text))
    }

    @Test
    fun frontMatter_sequenceMapping_dashTitleColon_isRecognized() {
        val text = "---\n- title: Foo\n---\n# Real\n"

        assertEquals(listOf("Real"), titles(text))
    }

    @Test
    fun frontMatter_bareBulletList_isNotFrontMatter_headingsSurvive() {
        val text = "---\n- item one\n- item two\n---\n# Real Heading\n"

        // A bare sequence item is NOT a mapping, so this is a bullet list under a thematic
        // break, not metadata: the real heading below it must survive. The line-based scanner
        // also reads the trailing `---` as a setext underline for "- item two" (documented
        // limitation — see MdTocScanner's header).
        assertEquals(listOf("- item two", "Real Heading"), titles(text))
    }

    // ------------------------------------------------------------------ line endings + edges

    @Test
    fun md_crlf_cr_lf_allProduceSameSourceOffsets() {
        val logical = listOf("# One", "body text", "## Two", "Setext", "======")
        val lf = logical.joinToString("\n")
        val crlf = logical.joinToString("\r\n")
        val cr = logical.joinToString("\r")

        val byLf = scan(lf)
        val byCrlf = scan(crlf)
        val byCr = scan(cr)

        // Same headings, same order, same depths under all three conventions...
        listOf(byLf, byCrlf, byCr).forEach {
            assertEquals(listOf("One", "Two", "Setext"), it.map { h -> h.title })
            assertEquals(listOf(0, 1, 0), it.map { h -> h.depth })
        }
        // ...and every offset is that variant's own RAW-SOURCE line start.
        listOf(lf to byLf, crlf to byCrlf, cr to byCr).forEach { (text, headings) ->
            assertEquals(
                listOf("# One", "## Two", "Setext").map { offsetOfLineContaining(text, it) },
                headings.map { it.sourceOffsetUtf16 },
            )
        }
        // Source offsets, so the two-unit CRLF terminator genuinely shifts them — this test
        // would be vacuous if the scanner normalized line endings before measuring.
        assertNotEquals(
            byLf.map { it.sourceOffsetUtf16 },
            byCrlf.map { it.sourceOffsetUtf16 },
        )
        assertEquals(byLf.map { it.sourceOffsetUtf16 }, byCr.map { it.sourceOffsetUtf16 })
    }

    @Test
    fun md_headingAsFinalLine_noTrailingNewline_isFound() {
        val atx = "intro\n# Final"
        assertEquals(listOf("Final|0@${atx.indexOf("# Final")}"), scan(atx).rendered())

        val setext = "intro\n\nFinal Title\n==="
        assertEquals(
            listOf("Final Title|0@${setext.indexOf("Final Title")}"),
            scan(setext).rendered(),
        )
    }

    @Test
    fun md_documentEndingWithATerminator_doesNotShiftOffsets() {
        // The final terminator creates a trailing empty line; the two-line-ending bookkeeping
        // must survive it under all three conventions (Gate-4 r1 LOW).
        listOf("\n", "\r\n", "\r").forEach { eol ->
            val text = "# A" + eol + "body" + eol + "## B" + eol

            assertEquals(
                listOf(
                    "A|0@0",
                    "B|1@" + text.indexOf("## B"),
                ),
                scan(text).rendered(),
            )
        }
    }

    @Test
    fun emptyDocument_yieldsNoHeadings() {
        assertEquals(emptyList<DetectedHeading>(), scan(""))
        assertEquals(emptyList<DetectedHeading>(), scan("   \n\t\n\n"))
        assertEquals(emptyList<DetectedHeading>(), scan("just prose, no headings at all\n"))

        // Positive control: the same prose WITH a heading is not empty, so this test cannot pass
        // against a scanner that simply never scans (Gate-4 r1 LOW).
        assertEquals(listOf("Real"), titles("just prose, no headings at all\n# Real\n"))
    }

    // ------------------------------------------------------------------ bounded extraction

    @Test
    fun scan_stopsAtLimit_doesNotMaterializeBeyondIt() {
        // Long enough that a scanner which walks the whole document MUST reach the periodic
        // cancellation check; the three headings are all in the first three lines.
        val text = (1..3).joinToString("") { "# H" + it + "\n" } +
            "filler\n".repeat(MdTocScanner.CANCELLATION_CHECK_INTERVAL * 3)

        // A job that goes inactive on its SECOND query. `scan`'s entry check is the first, so a
        // walk that keeps going past the limit trips the in-loop check and throws — while a walk
        // that genuinely stops at the third heading never queries again. That makes the early
        // stop OBSERVABLE, rather than merely asserting the returned list was truncated.
        val stopped = scanWithJob(CancelAfter(1), text, limit = 3)

        val result = stopped.getOrThrow()
        assertTrue(result.hitLimit)
        assertEquals(listOf("H1", "H2", "H3"), result.headings.map { it.title })

        // The control: same document, same job shape, a limit it cannot reach — now the walk DOES
        // continue and the pending cancellation is observed. If this did not throw, the assertion
        // above would prove nothing.
        assertTrue(
            scanWithJob(CancelAfter(1), text, limit = NO_CAP).exceptionOrNull()
                is CancellationException,
        )
    }

    @Test
    fun scan_isCancellationCooperative_evenInsideOneEnormousLine() {
        // One line, no terminator, longer than the intra-line check interval — the case a
        // whole-line scan would have deferred cancellation for (Gate-4 r2 MEDIUM).
        val text = "x".repeat(MdTocScanner.CANCELLATION_CHECK_UNITS * 4)

        val outcome = scanWithJob(CancelAfter(1), text, limit = NO_CAP)

        assertTrue(outcome.exceptionOrNull() is CancellationException)
    }

    @Test
    fun scan_isCancellationCooperative_insideALongClassifierRun() {
        // Gate-4 r3 MEDIUM: the terminator scan was checked but the CLASSIFIERS were not, so a
        // line that is one enormous marker run could still defer a cancel. Query accounting for
        // this fixture: 1 at scan's entry, then 4 while the terminator scan crosses the 32 768-unit
        // line (one per 8 192 units) = 5. Letting exactly those 5 pass means the SIXTH query — the
        // first one raised inside the setext underline run — is the one that cancels.
        val units = MdTocScanner.CANCELLATION_CHECK_UNITS
        val text = "Title\n" + "=".repeat(units * 4)

        val outcome = scanWithJob(CancelAfter(5), text, limit = NO_CAP)

        assertTrue(outcome.exceptionOrNull() is CancellationException)

        // ...and with nothing cancelling, the same fixture is an ordinary setext heading, so the
        // assertion above is about cancellation and not about a malformed document.
        assertEquals(listOf("Title|0@0"), scan(text).rendered())
    }

    @Test
    fun scan_setextHeadingAlsoCountsAgainstLimit() {
        val text = "One\n===\nTwo\n---\nThree\n===\n"

        val result = scanWithJob(Job(), text, limit = 2).getOrThrow()

        assertTrue(result.hitLimit)
        assertEquals(listOf("One", "Two"), result.headings.map { it.title })
    }

    @Test
    fun scan_underTheLimit_reportsNoHitLimit() {
        val text = "# One\n# Two\n"

        val result = scanWithJob(Job(), text, limit = 3).getOrThrow()

        assertFalse(result.hitLimit)
        assertEquals(2, result.headings.size)
    }

    @Test
    fun scan_atExactlyTheLimit_reportsHitLimit() {
        // `limit` is a collection budget, not a cap on the document: a caller that passes
        // `cap + 1` reads `hitLimit` as "more than `cap` headings exist".
        val text = "# One\n# Two\n"

        val result = scanWithJob(Job(), text, limit = 2).getOrThrow()

        assertTrue(result.hitLimit)
        assertEquals(2, result.headings.size)
    }

    @Test
    fun scan_nonPositiveLimit_isRejected() {
        listOf(0, -1).forEach { bad ->
            val outcome = scanWithJob(Job(), "# H\n", limit = bad)
            assertTrue(outcome.exceptionOrNull() is IllegalArgumentException)
        }
    }

    @Test
    fun scan_cancelledBeforeStart_throwsCancellation() {
        val cancelled = Job().apply { cancel() }

        val outcome = scanWithJob(cancelled, "# Heading\n")

        assertTrue(outcome.exceptionOrNull() is CancellationException)
    }
}
