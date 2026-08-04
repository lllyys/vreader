package com.vreader.app.reader.nav

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableJob
import kotlinx.coroutines.InternalForInheritanceCoroutinesApi
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.Continuation
import kotlin.coroutines.startCoroutine

/**
 * Feature #139 WI-2 — [TxtTocRuleEngine]: the Kotlin port of iOS `TXTTocRuleEngine`
 * (`vreader/Services/TXT/TXTTocRuleEngine.swift:38-132`).
 *
 * Two properties this suite exists to protect, because everything downstream (the Contents
 * sheet's jump target, and through it #138's paged `ensureMeasuredThrough` seam) is built on
 * them:
 *
 * - **Offsets are SOURCE UTF-16 offsets at the LINE START**, leading ideographic space
 *   included, identical under LF / CRLF / CR, and never landing inside a surrogate pair.
 * - **Extraction is bounded BEFORE materialization** (plan §4.4 / Gate-2 R2 MEDIUM): a
 *   pathological all-match document must stop at `limit`, not build the full match list and
 *   then truncate.
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class TxtTocRuleEngineTest {

    private companion object {
        /** U+3000 IDEOGRAPHIC SPACE, built from its code point so re-encoding cannot mangle it. */
        val IDEO: String = Char(0x3000).toString()

        /** A rule that only ever matches a whitespace-only line, so its title trims to "". */
        val BLANK_TITLE_RULE = TxtTocRule(
            id = 900, enabled = true, name = "blank", pattern = "^[ ]{1,4}$",
            example = "  ", serialNumber = 900,
        )

        /** A pattern `java.util.regex` cannot compile — iOS's `try?` skips these silently. */
        val UNCOMPILABLE_RULE = TxtTocRule(
            id = 901, enabled = true, name = "broken", pattern = "^[unclosed",
            example = "n/a", serialNumber = 901,
        )
    }

    private val defaults get() = TxtTocRules.defaults
    private fun rule(id: Int) = defaults.first { it.id == id }

    /** A generous per-call cap; the cap semantics get their own dedicated tests. */
    private val noCap = Int.MAX_VALUE

    // ------------------------------------------------------------------ suspend-call harness

    /**
     * Runs a suspend block with EXACTLY [job] as its coroutine context and returns the outcome.
     *
     * Deliberately not `runBlocking(job)` / `runTest`: those wrap the call in a NEW coroutine
     * whose own `Job` element replaces the one under test, so a counting/self-cancelling job
     * would never be the object `ensureActive()` queries. `startCoroutine` with a hand-built
     * [Continuation] hands the engine the context verbatim.
     *
     * It also pins a real property: the engine is CPU-bound and must never actually suspend —
     * if it did, `outcome` would still be null when this returns.
     */
    private fun <T> runWithJob(job: Job, block: suspend () -> T): Result<T> {
        var outcome: Result<T>? = null
        block.startCoroutine(Continuation(job) { outcome = it })
        return requireNotNull(outcome) { "TxtTocRuleEngine must not suspend — it is pure CPU work" }
    }

    private fun <T> run(block: suspend () -> T): T = runWithJob(Job(), block).getOrThrow()

    /**
     * A [Job] that reports `isActive` for the first [activeChecks] queries and cancels itself on
     * the next one — a deterministic stand-in for "the reader was closed mid-scan", with no
     * sleeps, no threads, and no dependence on how fast the machine runs the regex.
     *
     * The delegate is cancelled (not merely reported inactive) so `ensureActive()` can obtain a
     * real `CancellationException` from it.
     */
    @OptIn(InternalForInheritanceCoroutinesApi::class)
    private class CancelAfter(
        private val activeChecks: Int,
        private val delegate: CompletableJob = Job(),
    ) : Job by delegate {
        var checks: Int = 0
            private set

        override val isActive: Boolean
            get() {
                if (checks++ >= activeChecks) delegate.cancel()
                return delegate.isActive
            }

        /**
         * MUST be overridden. `Job by delegate` forwards EVERY interface member — including
         * `CoroutineContext.get` — so without this, `coroutineContext[Job]` hands back the
         * delegate and [isActive] above is never called: the job never cancels and every
         * assertion built on [checks] passes vacuously. (Observed exactly that, first run.)
         */
        @Suppress("UNCHECKED_CAST")
        override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? =
            if (key == Job) this as E else null
    }

    // ------------------------------------------------------------------ detectBestRule

    @Test
    fun detectBestRule_emptyText_returnsNull() {
        assertNull(run { TxtTocRuleEngine.detectBestRule("", defaults) })
    }

    @Test
    fun detectBestRule_noEnabledRules_returnsNull() {
        val text = "第一章 甲\n第二章 乙\n"
        assertNull(run { TxtTocRuleEngine.detectBestRule(text, emptyList()) })
        assertNull(run { TxtTocRuleEngine.detectBestRule(text, defaults.map { it.copy(enabled = false) }) })
    }

    @Test
    fun detectBestRule_belowTwoMatches_returnsNull() {
        // iOS requires >= 2 matches for confidence (TXTTocRuleEngine.swift:77).
        assertNull(run { TxtTocRuleEngine.detectBestRule("prose\n第一章 甲\nprose\n", defaults) })
    }

    @Test
    fun detectBestRule_exactlyTwoMatches_returnsRule() {
        val detected = run { TxtTocRuleEngine.detectBestRule("第一章 甲\nprose\n第二章 乙\n", defaults) }
        assertNotNull("two matches is exactly the threshold, not one above it", detected)
    }

    @Test
    fun detectBestRule_tie_firstRuleInOrderWins() {
        // Strictly-greater comparison (`count > bestCount`) is what makes ties resolve toward the
        // rule that appears FIRST in the list — iOS's serialNumber ordering. Two rules with the
        // SAME pattern isolate the tie-break from any difference in matching power, and swapping
        // the list order proves LIST ORDER decides, not the id.
        val a = TxtTocRule(101, true, "a", rule(1).pattern, rule(1).example, 101)
        val b = TxtTocRule(102, true, "b", rule(1).pattern, rule(1).example, 102)
        val text = "第一章 甲\n第二章 乙\n"

        assertEquals(101, run { TxtTocRuleEngine.detectBestRule(text, listOf(a, b)) }?.id)
        assertEquals(102, run { TxtTocRuleEngine.detectBestRule(text, listOf(b, a)) }?.id)
    }

    @Test
    fun detectBestRule_picksTheRuleWithTheMostMatches_notTheFirstThatMatches() {
        val few = TxtTocRule(101, true, "few", "^ONLY-ONCE.*$", "ONLY-ONCE", 101)
        val many = TxtTocRule(102, true, "many", "^第.*章.*$", "第一章", 102)
        val text = "ONLY-ONCE x\n第一章 甲\n第二章 乙\n第三章 丙\n"

        assertEquals(102, run { TxtTocRuleEngine.detectBestRule(text, listOf(few, many)) }?.id)
    }

    @Test
    fun detectBestRule_ignoresDisabledRules() {
        // Rule 18 (圆圈数字) ships disabled, and no ENABLED rule matches a circled-numeral line.
        val text = "① 甲\n② 乙\n③ 丙\n"
        assertNull("a disabled rule must not win", run { TxtTocRuleEngine.detectBestRule(text, defaults) })

        // Control: the same text with that one rule enabled DOES detect — proving the null above
        // is the enabled-filter, not a pattern that simply cannot match.
        val enabled = defaults.map { if (it.id == 18) it.copy(enabled = true) else it }
        assertEquals(18, run { TxtTocRuleEngine.detectBestRule(text, enabled) }?.id)
    }

    @Test
    fun detectBestRule_samplesOnlyFirst512KUtf16Units() {
        val filler = "x".repeat(TxtTocRuleEngine.SAMPLE_SIZE_UTF16)
        val headings = "\n第一章 甲\n第二章 乙\n第三章 丙\n"

        assertNull(
            "headings beyond the 512K sampling window must not be counted",
            run { TxtTocRuleEngine.detectBestRule(filler + headings, defaults) },
        )
        assertNotNull(
            "control: the same headings INSIDE the window are counted",
            run { TxtTocRuleEngine.detectBestRule(headings + filler, defaults) },
        )
    }

    // ------------------------------------------------------------------ the sampling window edge

    @Test
    fun sampleOf_shorterThanTheWindow_returnsTheTextUntouched() {
        val text = "第一章 甲\n"
        assertSame(text, TxtTocRuleEngine.sampleOf(text))
    }

    @Test
    fun sampleOf_exactlyTheWindow_returnsTheTextUntouched() {
        // The `<=` boundary: one code unit longer and the truncation branch runs instead.
        val text = "x".repeat(TxtTocRuleEngine.SAMPLE_SIZE_UTF16)
        assertEquals(TxtTocRuleEngine.SAMPLE_SIZE_UTF16, TxtTocRuleEngine.sampleOf(text).length)
        assertSame(text, TxtTocRuleEngine.sampleOf(text))
    }

    @Test
    fun sampleOf_surrogatePairStraddlingTheBoundary_stepsBackOverIt() {
        // High surrogate at SAMPLE - 1, low surrogate at SAMPLE: a bare substring would leave a
        // lone high surrogate as the sample's last code unit.
        val text = "x".repeat(TxtTocRuleEngine.SAMPLE_SIZE_UTF16 - 1) + "😀" + "x".repeat(10)
        val sample = TxtTocRuleEngine.sampleOf(text)

        assertEquals(TxtTocRuleEngine.SAMPLE_SIZE_UTF16 - 1, sample.length)
        assertFalse("the sample must not end on a lone high surrogate", sample.last().isHighSurrogate())
        assertEquals("x", sample.takeLast(1))
    }

    @Test
    fun sampleOf_surrogatePairEndingExactlyAtTheBoundary_isKeptWhole() {
        // Low surrogate at SAMPLE - 1: the pair is fully inside the window, so no back-off.
        val text = "x".repeat(TxtTocRuleEngine.SAMPLE_SIZE_UTF16 - 2) + "😀" + "x".repeat(10)
        val sample = TxtTocRuleEngine.sampleOf(text)

        assertEquals(TxtTocRuleEngine.SAMPLE_SIZE_UTF16, sample.length)
        assertTrue("the whole pair survives", sample.endsWith("😀"))
    }

    @Test
    fun sampleOf_loneSurrogateAtTheBoundary_isPreserved_notSteppedOver() {
        // Malformed input: an unpaired high surrogate is a code point of its own. Stepping back
        // over it would drop a real code unit for no reason, so the back-off must require a PAIR.
        val loneHigh = Char(0xD83D).toString()
        val text = "x".repeat(TxtTocRuleEngine.SAMPLE_SIZE_UTF16 - 1) + loneHigh + "x".repeat(10)

        assertEquals(TxtTocRuleEngine.SAMPLE_SIZE_UTF16, TxtTocRuleEngine.sampleOf(text).length)
    }

    @Test
    fun detectBestRule_returnsTheRuleInstanceFromTheSuppliedList() {
        val supplied = defaults.map { it.copy(name = it.name + " (tagged)") }
        val detected = run { TxtTocRuleEngine.detectBestRule("第一章 甲\n第二章 乙\n", supplied) }
        assertNotNull(detected)
        assertSame("the winner must be the caller's own rule object", supplied.first { it.id == detected!!.id }, detected)
    }

    @Test
    fun detectBestRule_skipsUncompilableRules_ratherThanThrowing() {
        // iOS uses `try?` and `continue`s past a rule that will not compile.
        val text = "第一章 甲\n第二章 乙\n"
        val withBroken = listOf(UNCOMPILABLE_RULE) + defaults
        assertNotNull(run { TxtTocRuleEngine.detectBestRule(text, withBroken) })
    }

    // ------------------------------------------------------------------ extractHeadings: titles

    @Test
    fun extractHeadings_emptyText_returnsNothing() {
        val result = run { TxtTocRuleEngine.extractHeadings("", rule(1), noCap) }
        assertEquals(emptyList<DetectedHeading>(), result.headings)
        assertFalse(result.hitLimit)
    }

    @Test
    fun extractHeadings_titleIsWholeMatchedLineTrimmed() {
        val text = "prose\n   第一章 太阳消失   \nprose\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(1, headings.size)
        assertEquals("第一章 太阳消失", headings[0].title)
        assertEquals("TXT depth is flat (plan §4.3 / D5)", 0, headings[0].depth)
    }

    @Test
    fun extractHeadings_offsetIsLineStart_includingLeadingIdeographicSpace() {
        // The indent is PART of the match on iOS, so the offset is the line start, not the first
        // non-space glyph. This is the property the whole navigation path rests on.
        // Braced: a CJK letter is a valid Kotlin identifier character, so an unbraced
        // `$IDEO第一章` would parse as the identifier `IDEO第一章` (the WI-1 gotcha).
        val text = "prose\n$IDEO${IDEO}第一章 太阳消失\nprose\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(1, headings.size)
        assertEquals("offset is the LINE start", text.indexOf(IDEO), headings[0].sourceOffsetUtf16)
        assertEquals("but the title is trimmed", "第一章 太阳消失", headings[0].title)
    }

    @Test
    fun extractHeadings_headingAfterBlankLines_offsetIsTheHeadingLine_notTheBlankLine() {
        // WI-1's reverted indent-widening bug, asserted where it would actually have hurt: as an
        // off-by-one-LINE navigation offset. See TxtTocRules.INDENT's KDoc.
        val text = "prose\n\n\n第一章 太阳消失\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(1, headings.size)
        assertEquals(text.indexOf("第一章"), headings[0].sourceOffsetUtf16)
    }

    @Test
    fun extractHeadings_skipsBlankTitles() {
        // A match whose whole line trims to "" yields no entry — iOS's `guard !title.isEmpty`.
        val text = "prose\n   \nprose\n  \n"
        val result = run { TxtTocRuleEngine.extractHeadings(text, BLANK_TITLE_RULE, noCap) }

        assertEquals(emptyList<DetectedHeading>(), result.headings)
        assertFalse("skipped entries are not 'hit the limit'", result.hitLimit)
    }

    @Test
    fun extractHeadings_skippedBlankTitles_doNotConsumeTheLimit() {
        // Two blank-title lines then one real one, with limit = 1: the real heading must still be
        // reached, i.e. skipped matches cannot silently spend the budget.
        val mixed = TxtTocRule(902, true, "mixed", "^[ 第].{0,30}$", "第一章", 902)
        val text = "  \n  \n第一章 甲\n"
        val result = run { TxtTocRuleEngine.extractHeadings(text, mixed, limit = 1) }

        assertEquals(listOf("第一章 甲"), result.headings.map { it.title })
    }

    @Test
    fun extractHeadings_uncompilableRule_returnsEmpty_ratherThanThrowing() {
        // iOS's `try?` returns []. A malformed rule must degrade to "no Contents", never crash a
        // reader that is otherwise working.
        val result = run { TxtTocRuleEngine.extractHeadings("第一章 甲\n", UNCOMPILABLE_RULE, noCap) }
        assertEquals(emptyList<DetectedHeading>(), result.headings)
        assertFalse(result.hitLimit)
    }

    // ------------------------------------------------------------------ extractHeadings: offsets

    @Test
    fun extractHeadings_headingAtOffsetZero_yieldsOffsetZero() {
        val text = "第一章 甲\nprose\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(1, headings.size)
        assertEquals(0, headings[0].sourceOffsetUtf16)
    }

    @Test
    fun extractHeadings_headingAsFinalLine_noTrailingNewline_isFound() {
        val text = "prose\n第一章 甲"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(listOf("第一章 甲"), headings.map { it.title })
        assertEquals(text.indexOf("第一章"), headings[0].sourceOffsetUtf16)
    }

    @Test
    fun extractHeadings_crlf_cr_lf_allProduceSameOffsets() {
        // "Same offsets" means each offset is the LINE START within its own text. LF and CR are
        // one code unit, so their offset LISTS are byte-identical; CRLF shifts by one per
        // preceding break, and the assertion that matters is that every offset still indexes the
        // exact heading line in that text (in particular, never the preceding "\r").
        val lines = listOf("prose", "第一章 甲", "prose", "第二章 乙", "prose")
        val perEol = listOf("\n", "\r", "\r\n").associateWith { eol ->
            val text = lines.joinToString(eol)
            val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

            assertEquals("titles under ${eol.map { it.code }}", listOf("第一章 甲", "第二章 乙"), headings.map { it.title })
            headings.forEach { h ->
                assertEquals(
                    "offset must index the heading's own first character",
                    h.title, text.substring(h.sourceOffsetUtf16, h.sourceOffsetUtf16 + h.title.length),
                )
            }
            headings.map { it.sourceOffsetUtf16 }
        }

        assertEquals("LF and CR are both one code unit", perEol["\n"], perEol["\r"])
        // The headings sit on line indices 1 and 3, so CRLF adds exactly that many extra units —
        // i.e. the offset tracks the SOURCE, and the extra "\r"s are counted, never skipped.
        val breaksBeforeEachHeading = listOf(1, 3)
        assertEquals(
            "CRLF shifts by exactly one unit per preceding line break",
            perEol.getValue("\n").zip(breaksBeforeEachHeading) { off, breaks -> off + breaks },
            perEol["\r\n"],
        )
    }

    @Test
    fun extractHeadings_surrogatePairInTitle_offsetsAreUtf16Consistent() {
        val emoji = "😀" // U+1F600, two UTF-16 code units
        val text = "第一章 $emoji 甲\nprose\n第二章 乙\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(2, headings.size)
        assertEquals("第一章 $emoji 甲", headings[0].title)
        // The second heading's offset must account for BOTH code units of the pair.
        assertEquals(text.indexOf("第二章"), headings[1].sourceOffsetUtf16)
        assertEquals("第二章 乙", text.substring(headings[1].sourceOffsetUtf16).substringBefore("\n"))
    }

    @Test
    fun extractHeadings_offsetNeverLandsMidSurrogatePair() {
        val emoji = "😀"
        val text = buildString {
            repeat(50) { i -> append("$emoji prose $i\n第").append(i).append("章 $emoji 标题\n") }
        }
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(2), noCap) }.headings

        assertTrue("the fixture must actually produce headings", headings.isNotEmpty())
        headings.forEach { h ->
            val at = h.sourceOffsetUtf16
            assertTrue("offset $at is in bounds", at in text.indices)
            assertFalse(
                "offset $at landed on a LOW surrogate — it is inside a pair",
                text[at].isLowSurrogate(),
            )
            assertEquals(
                "the code point at the offset round-trips",
                text.codePointAt(at), text.substring(at).codePointAt(0),
            )
        }
    }

    @Test
    fun extractHeadings_rtlTitle_isPreservedByteForByte() {
        val hebrew = "שלום עולם"
        val arabic = "الفصل الأول"
        val text = "1. $hebrew\nprose\n2. $arabic\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(14), noCap) }.headings

        assertEquals(listOf("1. $hebrew", "2. $arabic"), headings.map { it.title })
        headings.forEach { h ->
            assertEquals(
                "no reordering, no normalization, no bidi marks added",
                h.title, text.substring(h.sourceOffsetUtf16, h.sourceOffsetUtf16 + h.title.length),
            )
        }
    }

    @Test
    fun extractHeadings_returnsEntriesInDocumentOrder() {
        val text = (1..20).joinToString("\n") { "第${it}章 标题$it\nprose $it" }
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(2), noCap) }.headings

        assertEquals(20, headings.size)
        assertEquals(
            headings.map { it.sourceOffsetUtf16 }.sorted(), headings.map { it.sourceOffsetUtf16 },
        )
    }

    // ------------------------------------------------------------------ the bounded `limit`

    @Test
    fun extractHeadings_underTheLimit_reportsNoHit() {
        val text = (1..10).joinToString("\n") { "第${it}章 标题" }
        val result = run { TxtTocRuleEngine.extractHeadings(text, rule(2), limit = 11) }

        assertEquals(10, result.headings.size)
        assertFalse(result.hitLimit)
    }

    @Test
    fun extractHeadings_stopsAtLimit_doesNotMaterializeBeyondIt() {
        // The Gate-2 R2 MEDIUM: the cap must bound the SCAN, not just the returned list.
        //
        // Proof is structural, not timing-based: the engine checks cancellation every
        // CANCELLATION_CHECK_INTERVAL matches EXAMINED, so a scan that walked all 200 000 matches
        // before truncating would query `isActive` hundreds of times. An early-stopping scan
        // queries it only at entry. The counting Job makes that observable exactly.
        val text = (1..200_000).joinToString("\n") { "第${it}章 标题" }
        val job = CancelAfter(activeChecks = Int.MAX_VALUE)
        val result = runWithJob(job) { TxtTocRuleEngine.extractHeadings(text, rule(2), limit = 10) }.getOrThrow()

        assertEquals(10, result.headings.size)
        assertTrue("reaching the limit is reported", result.hitLimit)
        assertEquals("第1章 标题", result.headings.first().title)
        assertEquals("第10章 标题", result.headings.last().title)

        val checksIfFullScanned = 200_000 / TxtTocRuleEngine.CANCELLATION_CHECK_INTERVAL
        assertTrue(
            "anti-vacuity: the counting job must actually be the one the engine queries " +
                "(a `Job by delegate` that forwards `get` would report 0 and pass trivially)",
            job.checks >= 1,
        )
        assertTrue(
            "the scan must stop at the limit, not walk all 200 000 matches " +
                "(${job.checks} cancellation checks; a full scan would be ~$checksIfFullScanned)",
            job.checks < checksIfFullScanned,
        )
    }

    @Test
    fun extractHeadings_limitOfOne_returnsExactlyTheFirstHeading() {
        val text = "第一章 甲\n第二章 乙\n第三章 丙\n"
        val result = run { TxtTocRuleEngine.extractHeadings(text, rule(1), limit = 1) }

        assertEquals(listOf("第一章 甲"), result.headings.map { it.title })
        assertTrue(result.hitLimit)
    }

    @Test
    fun extractHeadings_exactlyLimitManyHeadings_reportsHitLimit() {
        // Deliberate, documented semantics: `hitLimit` means "collection stopped because the
        // budget was reached", so a document with EXACTLY `limit` headings reports it too. WI-4
        // passes MAX_TOC_ENTRIES + 1, which turns this into the precise predicate "the document
        // has MORE than MAX_TOC_ENTRIES headings".
        val text = (1..5).joinToString("\n") { "第${it}章 标题" }
        assertTrue(run { TxtTocRuleEngine.extractHeadings(text, rule(2), limit = 5) }.hitLimit)
        assertFalse(run { TxtTocRuleEngine.extractHeadings(text, rule(2), limit = 6) }.hitLimit)
    }

    @Test
    fun extractHeadings_nonPositiveLimit_isRejected() {
        listOf(0, -1, Int.MIN_VALUE).forEach { bad ->
            assertThrows(IllegalArgumentException::class.java) {
                run { TxtTocRuleEngine.extractHeadings("第一章 甲\n", rule(1), limit = bad) }
            }
        }
    }

    @Test
    fun extractHeadings_pathologicalAllMatchDocument_isTimeAndAllocationBounded() {
        // Every one of 300 000 lines matches rule 14 ("1." style). Allocation is bounded by the
        // returned list never exceeding `limit`; time is bounded by the early stop.
        val text = (1..300_000).joinToString("\n") { "$it. 标题" }
        val limit = 50_001
        val startedNs = System.nanoTime()
        val result = run { TxtTocRuleEngine.extractHeadings(text, rule(14), limit) }
        val elapsedMs = (System.nanoTime() - startedNs) / 1_000_000

        assertEquals("never more than `limit` entries are allocated", limit, result.headings.size)
        assertTrue(result.hitLimit)
        assertTrue("bounded in time (took ${elapsedMs}ms)", elapsedMs < 10_000)
    }

    @Test
    fun extractHeadings_singleEnormousLine_terminatesQuickly() {
        // R4 (ReDoS): one 2 000 000-character line whose prefix is rule 1's lazy-numeral trap and
        // which never supplies a unit character. The bounded `.{0,30}$` tail is what keeps the
        // search space small.
        val text = "第" + "一".repeat(2_000_000) + "的故事没有章字"
        val startedNs = System.nanoTime()
        val result = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }
        val elapsedMs = (System.nanoTime() - startedNs) / 1_000_000

        assertEquals(emptyList<DetectedHeading>(), result.headings)
        assertTrue("must not backtrack catastrophically (took ${elapsedMs}ms)", elapsedMs < 10_000)
    }

    @Test
    fun extractHeadings_largeNoMatchDocument_isACatastrophicRegressionSmokeTest() {
        // The worst-case UNINTERRUPTIBLE window: `find()` is one non-suspending java.util.regex
        // call, so a document with NO match at all is walked in a single uncancellable step.
        //
        // Stated honestly (Gate-4 round 2): one input size against a loose ceiling is a
        // CATASTROPHIC-regression smoke test — it does not measure the ~100 ms the plan reports
        // (§5 / Appendix A.1) and does not establish linearity. A precise budget belongs to WI-8's
        // measured evidence on the real device, not to a JVM unit test on a shared machine.
        // Fixture size is ~14M UTF-16 code units — about twice the real book's 7 029 609.
        val text = "没有任何章节标记的正文段落。".repeat(1_000_000)
        val startedNs = System.nanoTime()
        val result = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }
        val elapsedMs = (System.nanoTime() - startedNs) / 1_000_000

        assertEquals(emptyList<DetectedHeading>(), result.headings)
        assertTrue(
            "a full no-match pass must not blow up (took ${elapsedMs}ms over ${text.length} units)",
            elapsedMs < 10_000,
        )
    }

    // ------------------------------------------------------------------ cancellation

    @Test
    fun extractHeadings_alreadyCancelledScope_throwsCancellationException() {
        // A NON-cooperative loop would return a full result here; only an `ensureActive()` makes
        // this throw. That is what makes the assertion load-bearing rather than vacuous.
        val cancelled = Job().apply { cancel() }
        val outcome = runWithJob(cancelled) {
            TxtTocRuleEngine.extractHeadings("第一章 甲\n第二章 乙\n", rule(1), noCap)
        }

        assertTrue("cancellation must propagate, never be swallowed", outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
    }

    @Test
    fun extractHeadings_isCancellationCooperative() {
        // Cancelled MID-scan (after the 2nd check), deterministically: no sleeps, no threads.
        val text = (1..200_000).joinToString("\n") { "第${it}章 标题" }
        val job = CancelAfter(activeChecks = 2)
        val outcome = runWithJob(job) { TxtTocRuleEngine.extractHeadings(text, rule(2), noCap) }

        assertTrue("cancellation must propagate out of extraction", outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
        assertTrue(
            "the engine must check cancellation repeatedly DURING the scan, not once at entry",
            job.checks > 2,
        )
    }

    @Test
    fun detectBestRule_isCancellationCooperative_betweenRules() {
        val text = (1..50_000).joinToString("\n") { "第${it}章 标题" }
        val job = CancelAfter(activeChecks = 1)
        val outcome = runWithJob(job) { TxtTocRuleEngine.detectBestRule(text, defaults) }

        assertTrue("cancellation must propagate out of detection", outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
    }

    @Test
    fun detectBestRule_isCancellationCooperative_whileCountingOneRulesMatches() {
        // The between-rules test above would still pass if match COUNTING never checked at all:
        // with one enabled rule, the checks are entry (0) and the rule boundary (1), and counting
        // is where all the time actually goes. Cancelling only after those two forces the third
        // check to come from INSIDE countMatches — so this fails if that check is removed.
        val single = listOf(rule(2))
        val matchesPerRule = TxtTocRuleEngine.CANCELLATION_CHECK_INTERVAL * 4
        val text = (1..matchesPerRule).joinToString("\n") { "第${it}章 标题" }
        val job = CancelAfter(activeChecks = 2)
        val outcome = runWithJob(job) { TxtTocRuleEngine.detectBestRule(text, single) }

        assertTrue("cancellation must propagate out of match counting", outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
        assertTrue("the third check must come from inside countMatches", job.checks > 2)
    }

    @Test
    fun extractHeadings_cancelDuringTheFinalScanStep_isNotSwallowed() {
        // Gate-4 round 2 LOW: a cancel landing during the LAST `next()` — the long walk to
        // end-of-text — used to be lost, because the loop exits on null and returned a normal
        // result. Reproduced exactly: too few matches for any in-loop interval check to fire, so
        // the ONLY query after entry is the post-loop one.
        val text = "第一章 甲\n第二章 乙\n"
        val job = CancelAfter(activeChecks = 1) // entry check passes; the next query cancels
        val outcome = runWithJob(job) { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }

        assertTrue("a cancel during the final scan step must not be swallowed", outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
        assertEquals("exactly the entry check plus the post-loop check", 2, job.checks)
    }

    @Test
    fun detectBestRule_cancelAfterTheLastRule_isNotSwallowed() {
        // The detection-side twin: exhaust the entry check and every per-rule check, so the only
        // query left is the post-loop one. The document is small enough that countMatches never
        // reaches its interval, making the query count exact rather than approximate.
        val text = "第一章 甲\n第二章 乙\n"
        val checksBeforeTheEnd = 1 + defaults.count { it.enabled }
        val job = CancelAfter(activeChecks = checksBeforeTheEnd)
        val outcome = runWithJob(job) { TxtTocRuleEngine.detectBestRule(text, defaults) }

        assertTrue("a cancel after the last rule must not be swallowed", outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
        assertEquals(checksBeforeTheEnd + 1, job.checks)
    }

    @Test
    fun detectBestRule_alreadyCancelledScope_throwsCancellationException() {
        val cancelled = Job().apply { cancel() }
        val outcome = runWithJob(cancelled) {
            TxtTocRuleEngine.detectBestRule("第一章 甲\n第二章 乙\n", defaults)
        }

        assertTrue(outcome.isFailure)
        assertTrue(outcome.exceptionOrNull() is CancellationException)
    }

    // ------------------------------------------------------------------ detect → extract, joined

    @Test
    fun extractHeadings_aRuleCanMatchAcrossALineTerminator_soTheScanIsNotLineSplittable() {
        // Load-bearing for the engine header's REJECTION of line-region chunking (Gate-4 round 1
        // proposed it to tighten cancellation latency). TxtTocRules.WS widens whitespace to ICU's
        // `\s`, which CONTAINS line terminators — so a heading split across lines still matches,
        // exactly as it does on iOS's ICU. Any future "scan line by line" optimization would
        // silently drop this match; this test is what makes that a failure instead of a shrug.
        val text = "第\n一\n章 标题\n"
        val headings = run { TxtTocRuleEngine.extractHeadings(text, rule(1), noCap) }.headings

        assertEquals(1, headings.size)
        assertEquals(0, headings[0].sourceOffsetUtf16)
        assertTrue("the match spans terminators", headings[0].title.contains("\n"))
    }

    @Test
    fun detectThenExtract_onARealisticCjkDocument_findsEveryChapterAtItsLineStart() {
        val chapters = listOf("第一章${IDEO}太阳消失", "第二章${IDEO}黑暗降临", "第三章${IDEO}血色黎明")
        val text = buildString {
            append("书名：黑暗血时代\n\n")
            chapters.forEach { c -> append(c).append("\n\n").append("正文段落。".repeat(20)).append("\n\n") }
        }

        val detected = run { TxtTocRuleEngine.detectBestRule(text, defaults) }
        assertNotNull(detected)

        val headings = run { TxtTocRuleEngine.extractHeadings(text, detected!!, noCap) }.headings
        assertEquals(chapters, headings.map { it.title })
        headings.forEachIndexed { i, h ->
            assertEquals(text.indexOf(chapters[i]), h.sourceOffsetUtf16)
            assertEquals(0, h.depth)
        }
    }
}
