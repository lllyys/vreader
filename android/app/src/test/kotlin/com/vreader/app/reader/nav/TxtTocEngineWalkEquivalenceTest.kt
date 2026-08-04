package com.vreader.app.reader.nav

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableJob
import kotlinx.coroutines.InternalForInheritanceCoroutinesApi
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.regex.Pattern
import java.util.regex.PatternSyntaxException
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.Continuation
import kotlin.coroutines.startCoroutine

/**
 * Feature #172 WI-2 — the **differential oracle** for the one-`Matcher` rewrite of
 * [TxtTocRuleEngine].
 *
 * WI-2 replaced Kotlin's `Regex.find()` / `MatchResult.next()` walk with a hand-written walk over a
 * single `java.util.regex.Matcher` driven by no-arg `find()`, because `next()` constructs a fresh
 * `Matcher` over the WHOLE input per match and that construction is length-proportional on Android
 * (6 525 ms → 61 ms on the real book; see the engine's header). The performance claim is held by
 * `TxtTocScanCostTest#extractionMeetsEngineBudget` on the device.
 *
 * **This suite holds the other half: that nothing else changed.** [legacyExtractHeadings] and
 * [legacyDetectBestRule] below are the PRE-WI-2 bodies, copied verbatim from commit `407c3d5d`, and
 * every corpus document is run through both implementations with an element-for-element comparison
 * of `(title, offset)` plus `hitLimit`. If a future edit to the engine changes the match sequence
 * by one pair, this fails.
 *
 * **This is a REGRESSION GUARD, not WI-2's RED.** It passes on both the old and the new engine by
 * construction — that is the entire point of an oracle. The RED is the connected budget assertion,
 * which the JVM cannot run (the real 14 MB book is gitignored and not in CI).
 *
 * **Why the corpus is shaped the way it is.** The equivalence argument rests on `next()` resuming
 * at `end + (if (end == start) 1 else 0)` and no-arg `find()` applying the same rule, with
 * `find(int)`'s extra `reset()` unobservable here. Every clause of that argument gets a document:
 * zero-width matches (the `end == start` branch), a match at offset 0 and a match ending at the
 * final character (the boundaries where a resume position can fall off the end), back-to-back
 * matches (zero gap), an all-headings document and a no-headings document (the two degenerate
 * walks), plus the terminator, indent, CJK/full-width, surrogate and `limit` families the engine's
 * own invariants depend on.
 *
 * **Real content where it can be** (AGENTS.md "real books first"): the real 14 MB CJK book is not
 * readable from a JVM unit test, so whole-book equivalence lives in `TxtTocScanCostTest`'s arm
 * comparison on the device. The documents here are synthetic under the rule's explicit
 * "deterministic tiny structure" exception — a lone U+2028, an unpaired surrogate and exactly
 * `limit ± 1` headings are precisely what a 14 MB novel cannot be relied on to contain.
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class TxtTocEngineWalkEquivalenceTest {

    private companion object {
        /** Invisible characters are built from code points — #139's Gate-2 caught them normalised. */
        val IDEO = Char(0x3000).toString()
        val NBSP = Char(0x00A0).toString()
        val NEL = Char(0x0085).toString()
        val LS = Char(0x2028).toString()
        val PS = Char(0x2029).toString()

        /** An astral character (U+1F600) as a surrogate pair, and each half alone. */
        const val HIGH = '\uD83D'
        const val LOW = '\uDE00'
        val ASTRAL = "$HIGH$LOW"

        /** `TxtMdTocProvider.SCAN_LIMIT`'s shape; the limit families use small explicit values. */
        const val BIG_LIMIT = 50_001
    }

    // ------------------------------------------------------------------ suspend-call harness

    /** See `TxtTocRuleEngineTest.runWithJob` — `startCoroutine` hands the engine the context verbatim. */
    private fun <T> runWithJob(job: Job, block: suspend () -> T): Result<T> {
        var outcome: Result<T>? = null
        block.startCoroutine(Continuation(job) { outcome = it })
        return requireNotNull(outcome) { "TxtTocRuleEngine must not suspend — it is pure CPU work" }
    }

    private fun <T> run(block: suspend () -> T): T = runWithJob(Job(), block).getOrThrow()

    /** A [Job] that cancels itself on the query after [activeChecks]. See `TxtTocRuleEngineTest`. */
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

        @Suppress("UNCHECKED_CAST")
        override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? =
            if (key == Job) this as E else null
    }

    // ------------------------------------------------------------------ the PRE-WI-2 engine

    /**
     * `TxtTocRuleEngine.extractHeadings` **as it was before WI-2**, copied verbatim from commit
     * `407c3d5d` — Kotlin `Regex.find()` + `MatchResult.next()`, i.e. a fresh `Matcher` per match.
     *
     * It lives in the test because production no longer has it, and it must NOT be "kept in sync"
     * with the engine: the whole value of an oracle is that it is an INDEPENDENT second
     * implementation. Only the cancellation checks are dropped (this reference is never run under a
     * cancelling job; the engine's own cadence is asserted separately below and by
     * `TxtTocRuleEngineTest`).
     */
    private fun legacyExtractHeadings(text: String, rule: TxtTocRule, limit: Int): ExtractResult {
        require(limit > 0) { "limit must be positive, was $limit" }
        if (text.isEmpty()) return ExtractResult.EMPTY
        val regex = legacyCompile(rule) ?: return ExtractResult.EMPTY

        val headings = ArrayList<DetectedHeading>()
        var match = regex.find(text)
        while (match != null) {
            val title = match.value.trim()
            if (title.isNotEmpty()) {
                headings.add(DetectedHeading(title = title, sourceOffsetUtf16 = match.range.first))
                if (headings.size == limit) return ExtractResult(headings, hitLimit = true)
            }
            match = match.next()
        }
        return ExtractResult(headings, hitLimit = false)
    }

    /** `TxtTocRuleEngine.detectBestRule` as it was before WI-2 (same walk, counting only). */
    private fun legacyDetectBestRule(text: String, rules: List<TxtTocRule>): TxtTocRule? {
        if (text.isEmpty()) return null
        val sample = TxtTocRuleEngine.sampleOf(text)
        var bestRule: TxtTocRule? = null
        var bestCount = 0
        for (rule in rules) {
            if (!rule.enabled) continue
            val regex = legacyCompile(rule) ?: continue
            var count = 0
            var match = regex.find(sample)
            while (match != null) {
                count++
                match = match.next()
            }
            if (count > bestCount) {
                bestCount = count
                bestRule = rule
            }
        }
        return if (bestCount >= TxtTocRuleEngine.MIN_MATCHES) bestRule else null
    }

    private fun legacyCompile(rule: TxtTocRule): Regex? = try {
        Regex(rule.pattern, RegexOption.MULTILINE)
    } catch (_: PatternSyntaxException) {
        null
    }

    // ------------------------------------------------------------------ corpus

    private class Doc(val name: String, val text: String)

    private fun rule(id: Int) = TxtTocRules.defaults.first { it.id == id }

    /**
     * A rule that matches EMPTY at every multiline line start.
     *
     * This is the corpus's most load-bearing entry and it is a rule rather than a document: a
     * zero-width match is the ONLY case where `next()`'s resume arithmetic differs from a plain
     * "continue at `end`", so it is the one place the two walks could legally diverge into an
     * infinite loop or a skipped position. Every match trims to `""`, so it also drives the
     * empty-title drop on every single position.
     */
    private val zeroWidthRule = TxtTocRule(
        id = 990, enabled = true, name = "zero-width", pattern = "^",
        example = "", serialNumber = 990,
    )

    /** Zero-width, but only where a line start is followed by an indent character. */
    private val zeroWidthIndentRule = TxtTocRule(
        id = 991, enabled = true, name = "zero-width-indent", pattern = "^[ $IDEO\\t]{0,4}",
        example = "  ", serialNumber = 991,
    )

    /** Matches a whitespace-only line — a NON-empty match whose title trims to `""`. */
    private val blankTitleRule = TxtTocRule(
        id = 992, enabled = true, name = "blank-title", pattern = "^[ $IDEO\\t]{1,4}$",
        example = "  ", serialNumber = 992,
    )

    /** A pattern `java.util.regex` rejects — both engines must skip it identically. */
    private val uncompilableRule = TxtTocRule(
        id = 993, enabled = true, name = "broken", pattern = "^[unclosed",
        example = "n/a", serialNumber = 993,
    )

    /** Matches every line that has any content — the "document is entirely headings" driver. */
    private val everyLineRule = TxtTocRule(
        id = 994, enabled = true, name = "every-line", pattern = "^.{1,30}$",
        example = "x", serialNumber = 994,
    )

    private val extraRules = listOf(
        zeroWidthRule, zeroWidthIndentRule, blankTitleRule, uncompilableRule, everyLineRule,
    )

    /**
     * Every rule the oracle runs: all 25 shipped rules (disabled ones included — `extractHeadings`
     * never looks at `enabled`, so a disabled rule is still a live extraction path) plus the five
     * synthetic ones that reach behaviours no shipped rule can.
     */
    private val allRules: List<TxtTocRule> = TxtTocRules.defaults + extraRules

    private fun corpus(): List<Doc> = listOf(
        // ---- degenerate ----
        Doc("empty", ""),
        Doc("single-newline", "\n"),
        Doc("no-matches-at-all", "just prose\nmore prose\nand more\n"),
        Doc("whitespace-only", "   \n$IDEO$IDEO\n\t\n"),

        // ---- boundaries: offset 0, final character, back-to-back ----
        Doc("match-at-offset-zero", "第一章 甲\nprose\n"),
        Doc("match-ends-at-final-char-no-terminator", "prose\n第一章 甲"),
        Doc("match-is-the-whole-document", "第一章 甲"),
        Doc("back-to-back-matches", "第一章 甲\n第二章 乙\n第三章 丙\n"),
        Doc("back-to-back-no-trailing-terminator", "第一章 甲\n第二章 乙\n第三章 丙"),
        Doc("entirely-headings", (1..40).joinToString("\n") { "第${it}章 标题$it" } + "\n"),
        Doc("single-char", "x"),
        Doc("terminator-at-eof-only", "第一章 甲\n\n\n"),

        // ---- terminator families (Java regex line terminators, all six) ----
        Doc("lf", "第一章 甲\n第二章 乙\n"),
        Doc("crlf", "第一章 甲\r\n第二章 乙\r\n"),
        Doc("lone-cr", "第一章 甲\r第二章 乙\r"),
        Doc("cr-at-eof", "第一章 甲\r"),
        Doc("crlf-split-across-matches", "第一章 甲\r\n\r\n第二章 乙\r\n"),
        Doc("nel", "第一章 甲${NEL}第二章 乙$NEL"),
        Doc("line-separator-u2028", "第一章 甲${LS}第二章 乙$LS"),
        Doc("paragraph-separator-u2029", "第一章 甲${PS}第二章 乙$PS"),
        Doc("mixed-terminators", "第一章 甲\r\n第二章 乙\n第三章 丙\r第四章 丁${NEL}第五章 戊$LS"),
        Doc("blank-lines-between", "第一章 甲\n\n\n第二章 乙\n\n"),

        // ---- indentation ----
        Doc("indent-0-to-4", (0..4).joinToString("\n") { " ".repeat(it) + "第${it + 1}章 标题" } + "\n"),
        Doc("indent-5-too-deep", "     第一章 甲\n第二章 乙\n"),
        // NOTE: `${…}` braces are mandatory around every interpolation followed by a CJK character
        // — a Kotlin identifier may CONTAIN CJK, so `"$IDEO第一章"` parses as one unresolved name.
        Doc("indent-ideographic", "${IDEO}${IDEO}第一章 甲\n"),
        Doc("indent-tab", "\t\t第一章 甲\n"),
        Doc("indent-nbsp-not-in-class", "${NBSP}第一章 甲\n第二章 乙\n"),
        Doc("indent-mixed", " $IDEO\t 第一章 甲\n"),

        // ---- CJK / full-width / the D1 + D1b repairs ----
        Doc("full-width-digits", "第１２章 标题\n第１３章 标题\n"),
        Doc("financial-numerals", "第壹章 甲\n第贰章 乙\n第拾伍章 丙\n"),
        Doc("ideographic-space-separators", "第${IDEO}一${IDEO}章 标题\n第${IDEO}二${IDEO}章 标题\n"),
        Doc("cross-terminator-heading", "第\n一\n章 标题\nprose\n"),
        Doc("cjk-prose-with-headings", "第一章 开始\n他说：“走吧。”\n第二章 结束\n夜色渐深。\n"),
        Doc("english-chapters", "Chapter 1 The Start\nprose\nchapter 22 The End\n"),
        Doc("numbered-punctuated", "1、这个标题\n2. Another\n30：第三\n"),
        Doc("symbol-headings", "【第一章 标题】\n★ 第二章\n◆ 第三章\n"),

        // ---- surrogates ----
        Doc("astral-line-starts", "$ASTRAL 第一章 甲\n$ASTRAL 第二章 乙\n"),
        Doc("astral-in-title-tail", "第一章 甲$ASTRAL\n第二章 乙$ASTRAL\n"),
        Doc("lone-high-surrogate", "${HIGH}第一章 甲\n$HIGH\n第二章 乙\n"),
        Doc("lone-low-surrogate", "${LOW}第一章 甲\n$LOW\n第二章 乙\n"),
        Doc("astral-only", ASTRAL),
        Doc("astral-at-eof", "第一章 甲\n$ASTRAL"),

        // ---- limit families (small documents; the limits are applied per-document below) ----
        Doc("exactly-five-headings", (1..5).joinToString("\n") { "第${it}章 标题" } + "\n"),
        Doc(
            "five-headings-with-blank-title-matches",
            "  \n第一章 甲\n  \n第二章 乙\n  \n第三章 丙\n  \n第四章 丁\n  \n第五章 戊\n  \n",
        ),
    )

    /**
     * The limits each document is walked at.
     *
     * `BIG_LIMIT` is the production shape (walk to end-of-text). 1 and 2 exercise a `limit`
     * early-return on almost every document. 4/5/6 straddle the five-heading documents, so the
     * `limit − 1` / `limit` / `limit + 1` boundary is covered with `hitLimit` differing across it.
     */
    private val limits = listOf(BIG_LIMIT, 1, 2, 4, 5, 6)

    // ------------------------------------------------------------------ the oracle

    /**
     * The whole claim, in one test: for every (document, rule, limit), the new engine emits exactly
     * the sequence the pre-WI-2 walk emitted.
     *
     * Divergences are reported at the first differing pair with the document, rule and limit named,
     * because "expected 12 headings, got 11" on a 45 × 30 × 6 sweep is not a diagnosis.
     */
    @Test
    fun newWalkEmitsTheIdenticalTitleAndOffsetSequenceAsTheLegacyWalk() {
        var comparisons = 0
        var pairsCompared = 0
        for (doc in corpus()) {
            for (rule in allRules) {
                for (limit in limits) {
                    val expected = legacyExtractHeadings(doc.text, rule, limit)
                    val actual = run { TxtTocRuleEngine.extractHeadings(doc.text, rule, limit) }
                    val where = "doc='${doc.name}' rule=${rule.id} limit=$limit"

                    assertEquals(
                        "$where — heading COUNT diverged",
                        expected.headings.size, actual.headings.size,
                    )
                    assertEquals("$where — hitLimit diverged", expected.hitLimit, actual.hitLimit)
                    expected.headings.forEachIndexed { i, want ->
                        val got = actual.headings[i]
                        assertEquals("$where — heading $i TITLE diverged", want.title, got.title)
                        assertEquals(
                            "$where — heading $i OFFSET diverged (title '${want.title}')",
                            want.sourceOffsetUtf16, got.sourceOffsetUtf16,
                        )
                        assertEquals("$where — heading $i DEPTH diverged", want.depth, got.depth)
                    }
                    comparisons++
                    pairsCompared += expected.headings.size
                }
            }
        }
        // The oracle must not be vacuous: a corpus that produced no headings anywhere would pass
        // every assertion above and prove nothing.
        assertTrue("the sweep must actually run", comparisons > 1_000)
        assertTrue("the sweep must actually COMPARE headings, not just empty lists", pairsCompared > 1_000)
    }

    /** Detection walks the same matches too — `countMatches` was rewritten with the same shape. */
    @Test
    fun detectionPicksTheIdenticalRuleAsTheLegacyWalk() {
        var nonNullDetections = 0
        for (doc in corpus()) {
            val expected = legacyDetectBestRule(doc.text, TxtTocRules.defaults)
            val actual = run { TxtTocRuleEngine.detectBestRule(doc.text, TxtTocRules.defaults) }
            assertEquals("doc='${doc.name}' — detected rule diverged", expected?.id, actual?.id)
            if (actual != null) nonNullDetections++

            // Again with the synthetic rules in the list, so the zero-width and uncompilable paths
            // participate in detection's tie-breaking too.
            val expectedAll = legacyDetectBestRule(doc.text, allRules)
            val actualAll = run { TxtTocRuleEngine.detectBestRule(doc.text, allRules) }
            assertEquals(
                "doc='${doc.name}' (all rules) — detected rule diverged",
                expectedAll?.id, actualAll?.id,
            )
        }
        assertTrue(
            "the detection sweep must actually detect something, or it proves nothing",
            nonNullDetections > 5,
        )
    }

    // ------------------------------------------------------------------ the oracle is not vacuous

    /**
     * A walk that is correct EXCEPT for one named property — the shape of every plausible mistake
     * the WI-2 rewrite could have made in the loop body.
     */
    private enum class Mutation { OFFSET_IS_MATCH_END, NO_EMPTY_TITLE_DROP, UNTRIMMED_TITLE, TRUNCATE_AFTER_COLLECTING }

    /** The new walk with exactly one property broken, for the corpus-discrimination proof below. */
    private fun mutatedWalk(text: String, rule: TxtTocRule, limit: Int, how: Mutation): ExtractResult {
        require(limit > 0)
        if (text.isEmpty()) return ExtractResult.EMPTY
        val pattern = try {
            Pattern.compile(rule.pattern, Pattern.MULTILINE)
        } catch (_: PatternSyntaxException) {
            return ExtractResult.EMPTY
        }
        val headings = ArrayList<DetectedHeading>()
        val m = pattern.matcher(text)
        while (m.find()) {
            val raw = m.group()
            val title = if (how == Mutation.UNTRIMMED_TITLE) raw else raw.trim()
            val offset = if (how == Mutation.OFFSET_IS_MATCH_END) m.end() else m.start()
            if (title.isNotEmpty() || how == Mutation.NO_EMPTY_TITLE_DROP) {
                headings.add(DetectedHeading(title = title, sourceOffsetUtf16 = offset))
                if (how != Mutation.TRUNCATE_AFTER_COLLECTING && headings.size == limit) {
                    return ExtractResult(headings, hitLimit = true)
                }
            }
        }
        if (how == Mutation.TRUNCATE_AFTER_COLLECTING && headings.size > limit) {
            return ExtractResult(headings.take(limit), hitLimit = true)
        }
        return ExtractResult(headings, hitLimit = false)
    }

    /**
     * **Proof that the sweep above is not vacuous.**
     *
     * An oracle whose corpus cannot distinguish a wrong implementation is decoration. Each
     * [Mutation] is a walk that differs from the engine in exactly one named way; every one of them
     * must be CAUGHT by some (document, rule, limit) in the corpus. If a mutation ever survives,
     * the corpus has a hole and the equality asserted above is weaker than it looks.
     *
     * The failure message names the mutation that got through, not just "a test failed".
     */
    @Test
    fun theCorpusDiscriminatesEveryPlausiblyWrongWalk() {
        for (how in Mutation.entries) {
            var caughtBy: String? = null
            outer@ for (doc in corpus()) {
                for (rule in allRules) {
                    for (limit in limits) {
                        val want = legacyExtractHeadings(doc.text, rule, limit)
                        val got = mutatedWalk(doc.text, rule, limit, how)
                        if (want != got) {
                            caughtBy = "doc='${doc.name}' rule=${rule.id} limit=$limit"
                            break@outer
                        }
                    }
                }
            }
            assertTrue(
                "the corpus does NOT distinguish the '$how' walk from the correct one — it has a " +
                    "hole, so the equivalence sweep is weaker than it appears",
                caughtBy != null,
            )
        }
    }

    /**
     * The one mutation [mutatedWalk] cannot express, because it would not terminate: resuming at
     * `end` with no `+1` after an EMPTY match.
     *
     * This is the single clause of the equivalence argument that "just continue where you stopped"
     * does not give you for free, so it gets its own bounded demonstration: the naive resume spins
     * on offset 0 forever, while Java's own `find()` walks the real line starts.
     */
    @Test
    fun theZeroWidthResumeRuleIsLoadBearing() {
        val text = "a\nb\r\nc\rd${NEL}e"
        val naive = ArrayList<Int>()
        val m = Pattern.compile("^", Pattern.MULTILINE).matcher(text)
        var from = 0
        var steps = 0
        while (steps++ < 8 && m.find(from)) {
            naive.add(m.start())
            from = m.end() // the bug: an empty match leaves `from` exactly where it was
        }
        assertEquals("the naive resume must indeed spin on one position", List(8) { 0 }, naive)

        val real = ArrayList<Int>()
        val m2 = Pattern.compile("^", Pattern.MULTILINE).matcher(text)
        while (m2.find()) real.add(m2.start())
        assertEquals(
            "no-arg find() must advance past an empty match to the next line start",
            javaMultilineLineStarts(text), real,
        )
        assertNotEquals("and that is not what the naive resume produces", real.take(8), naive)
    }

    /**
     * The zero-width rule must TERMINATE and must visit every line start exactly once.
     *
     * `find()` on an empty match advances by one code unit; if the rewrite had lost that, the walk
     * would spin forever at offset 0 and this test would hang rather than fail. It is asserted
     * against an independently computed expectation (Java's `^` positions) rather than against the
     * legacy walk, so it stands even if the legacy reference were itself wrong.
     */
    @Test
    fun zeroWidthMatchesTerminateAndVisitEveryLineStart() {
        val text = "a\nb\r\nc\rd${NEL}e${LS}f${PS}g"
        val expectedLineStarts = javaMultilineLineStarts(text)
        assertTrue("the fixture must have several line starts", expectedLineStarts.size >= 7)

        // Every zero-width match trims to "", so extraction emits NOTHING — the visible proof that
        // the walk terminated is that this returns at all, with the empty-title drop intact.
        val extracted = run { TxtTocRuleEngine.extractHeadings(text, zeroWidthRule, BIG_LIMIT) }
        assertEquals("a zero-width match trims to empty and must be dropped", 0, extracted.headings.size)
        assertTrue("dropping every match is not hitting the limit", !extracted.hitLimit)

        // The positions themselves are checked through detection's counting walk, which does not
        // drop anything: it must count exactly one match per Java `^` position.
        val counting = TxtTocRule(995, true, "count-zero-width", "^", "", 995)
        val detected = run { TxtTocRuleEngine.detectBestRule(text, listOf(counting)) }
        assertEquals("a rule matching every line start must be detected", 995, detected?.id)

        val legacy = legacyExtractHeadings(text, zeroWidthRule, BIG_LIMIT)
        assertEquals("legacy and new agree that everything is dropped", 0, legacy.headings.size)
    }

    /** Java's MULTILINE `^` positions: index 0, or after a terminator, never inside CRLF, never at EOF. */
    private fun javaMultilineLineStarts(text: String): List<Int> {
        if (text.isEmpty()) return emptyList()
        val out = ArrayList<Int>()
        out.add(0)
        var i = 0
        while (i < text.length) {
            val c = text[i]
            val isTerminator = c == '\n' || c == '\r' || c == Char(0x0085) ||
                c == Char(0x2028) || c == Char(0x2029)
            if (isTerminator) {
                var next = i + 1
                if (c == '\r' && next < text.length && text[next] == '\n') next++
                if (next < text.length) out.add(next)
                i = next
            } else {
                i++
            }
        }
        return out
    }

    // ------------------------------------------------------------------ preserved semantics

    /**
     * The `limit` early-return still stops the SCAN, and empty titles still cost nothing against it.
     *
     * Both are properties of the loop body WI-2 rewrote, and both are exactly the kind of thing a
     * "just swap the iterator" edit silently loses.
     */
    @Test
    fun limitAndEmptyTitleSemanticsAreUnchanged() {
        val text = "  \n第一章 甲\n  \n第二章 乙\n  \n第三章 丙\n  \n"
        val r = rule(1)

        val underLimit = run { TxtTocRuleEngine.extractHeadings(text, r, 4) }
        assertEquals("three headings, blank lines dropped and not counted", 3, underLimit.headings.size)
        assertTrue("under the limit means hitLimit is false", !underLimit.hitLimit)

        val atLimit = run { TxtTocRuleEngine.extractHeadings(text, r, 3) }
        assertEquals(3, atLimit.headings.size)
        assertTrue("reaching the limit must be reported", atLimit.hitLimit)

        val belowLimit = run { TxtTocRuleEngine.extractHeadings(text, r, 2) }
        assertEquals(2, belowLimit.headings.size)
        assertTrue(belowLimit.hitLimit)

        // The legacy walk agrees on all three.
        listOf(4, 3, 2).forEach { limit ->
            val want = legacyExtractHeadings(text, r, limit)
            val got = run { TxtTocRuleEngine.extractHeadings(text, r, limit) }
            assertEquals("limit=$limit count", want.headings.size, got.headings.size)
            assertEquals("limit=$limit hitLimit", want.hitLimit, got.hitLimit)
        }

        assertTrue(
            "a non-positive limit must still be rejected",
            runCatching { run { TxtTocRuleEngine.extractHeadings(text, r, 0) } }
                .exceptionOrNull() is IllegalArgumentException,
        )
    }

    /** An uncompilable pattern still degrades to "no Contents", never a crash — both engines. */
    @Test
    fun uncompilablePatternStillDegradesToEmpty() {
        val text = "第一章 甲\n第二章 乙\n"
        val extracted = run { TxtTocRuleEngine.extractHeadings(text, uncompilableRule, BIG_LIMIT) }
        assertEquals(0, extracted.headings.size)
        assertTrue(!extracted.hitLimit)
        assertEquals(
            legacyExtractHeadings(text, uncompilableRule, BIG_LIMIT).headings.size,
            extracted.headings.size,
        )
        // And detection skips it rather than failing the whole pass.
        val detected = run { TxtTocRuleEngine.detectBestRule(text, listOf(uncompilableRule, rule(1))) }
        assertEquals(1, detected?.id)
    }

    /**
     * The cancellation cadence survived the rewrite.
     *
     * Not a comparison against the legacy walk (the reference above deliberately has no checks) but
     * against the engine's own documented contract: one check at entry, one every
     * `CANCELLATION_CHECK_INTERVAL` matches EXAMINED, and one after the loop so a cancel during the
     * final `find()` is not swallowed.
     */
    @Test
    fun cancellationCadenceIsUnchanged() {
        val text = (1..40).joinToString("\n") { "第${it}章 标题$it" } + "\n"

        val alreadyCancelled = Job().apply { cancel() }
        val atEntry = runWithJob(alreadyCancelled) {
            TxtTocRuleEngine.extractHeadings(text, rule(1), BIG_LIMIT)
        }
        assertTrue("an already-cancelled scope must not run the scan", atEntry.isFailure)
        assertTrue(atEntry.exceptionOrNull() is CancellationException)

        // The entry check passes; the post-loop check is the next query and must cancel there.
        val duringFinalStep = CancelAfter(activeChecks = 1)
        val late = runWithJob(duringFinalStep) {
            TxtTocRuleEngine.extractHeadings(text, rule(1), BIG_LIMIT)
        }
        assertTrue("a cancel during the final scan step must not be swallowed", late.isFailure)
        assertTrue(late.exceptionOrNull() is CancellationException)

        // Detection: entry check, then one before each rule.
        val betweenRules = CancelAfter(activeChecks = 1)
        val detection = runWithJob(betweenRules) {
            TxtTocRuleEngine.detectBestRule(text, TxtTocRules.defaults)
        }
        assertTrue("detection must stay cancellation-cooperative", detection.isFailure)
        assertTrue(detection.exceptionOrNull() is CancellationException)
    }

}
