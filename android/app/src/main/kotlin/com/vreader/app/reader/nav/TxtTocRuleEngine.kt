// Purpose: TXT chapter detection — pick the best-matching rule from [TxtTocRules] by sampling the
// document, then extract every heading with that one rule (feature #139 WI-2). The Kotlin port of
// iOS `TXTTocRuleEngine` (vreader/Services/TXT/TXTTocRuleEngine.swift:38-132).
//
// Pipeline: text ──detectBestRule──► winning rule ──extractHeadings──► List<DetectedHeading>
//
// Key decisions:
// - Detection samples the first [SAMPLE_SIZE_UTF16] code units and requires [MIN_MATCHES] hits,
//   both iOS parity. Ties resolve toward the rule that appears FIRST in the supplied list
//   (strictly-greater comparison), which is [TxtTocRules.defaults]' serialNumber order.
// - Patterns compile with `RegexOption.MULTILINE` and NOTHING else. `DOT_MATCHES_ALL` would let a
//   title swallow the rest of the document (the bounded `.{0,30}$` tail cannot cross a line
//   terminator) and `IGNORE_CASE` would reintroduce the Unicode case-folding divergence the rules
//   avoid by spelling both cases. See TxtTocRules' header for the D1/D1b class repairs.
// - A title is the WHOLE MATCH, trimmed — usually one line, but not necessarily: the `.` tail
//   cannot cross a terminator, yet the marker's own bounded whitespace positions are `WS` =
//   ICU-`\s`, which CONTAINS terminators, so a heading split as "第\n一\n章 标题" matches and its
//   title carries the embedded newline. That is iOS's ICU behavior too, so it is parity, not a
//   defect; it is pinned by test and is what makes the scan non-splittable by line (below).
// - An offset is the match START = the LINE start, leading indent included, in UTF-16 code units
//   over the RAW text. Everything downstream (the Contents jump, #138's paged
//   `ensureMeasuredThrough` seam) treats it as a source offset, so it must never be a rendered
//   offset and never land inside a surrogate pair. `^` under MULTILINE only matches at 0 or just
//   after a line terminator, and no terminator is a surrogate, so the boundary property holds by
//   construction — and is pinned by test.
// - Extraction is BOUNDED BEFORE MATERIALIZATION: it walks matches one at a time via
//   `MatchResult.next()` and returns the moment it has `limit` headings, so a pathological
//   all-match document never builds a full match list to be truncated afterwards (plan §4.4).
// - No Android imports and no logging: this is pure CPU work that must stay JVM-unit-testable
//   (`android.util.Log` throws "not mocked" in a plain unit test). A rule that fails to compile is
//   skipped, mirroring iOS's `try?` — degrading to "no Contents" beats crashing a working reader,
//   and TxtTocRulesTest already pins that all 25 shipped rules compile.
// - Both entry points are cancellation-cooperative, with a PRECISELY BOUNDED granularity: a check
//   at entry, one before each detection rule, and one every [CANCELLATION_CHECK_INTERVAL] matches.
//   A single `find()` / `next()` is a non-suspending `java.util.regex` call that cannot observe
//   cancellation, so the worst case after a cancel is one uninterrupted walk of the gap to the
//   next match — bounded by a full pass over the text (measured at ~100 ms for the real 14 MB CJK
//   book, plan §5 / Appendix A.1). That pass is off the MAIN thread only because
//   `TxtMdTocProvider` (WI-4) owns the `withContext(dispatcher)` hop; this engine does not hop by
//   itself and must not be called on the main thread. Splitting the scan into line-bounded
//   regions to tighten that was REJECTED, not overlooked: `TxtTocRules.WS` widens whitespace to
//   ICU's `\s`, which contains line terminators, so a rule genuinely can match ACROSS a newline
//   (probed: rule 1 matches "第\n一\n章 标题" at offset 0 — and iOS's ICU `\s` behaves the same).
//   Region-splitting would therefore silently drop real matches, trading a bounded ~100 ms
//   background latency for a correctness divergence.
//
// @coordinates-with: TxtTocRules.kt, DetectedHeading.kt, TxtMdTocProvider.kt
package com.vreader.app.reader.nav

import kotlinx.coroutines.ensureActive
import java.util.regex.PatternSyntaxException
import kotlin.coroutines.coroutineContext

/** Detects and applies TXT chapter-heading rules over a whole decoded document. */
object TxtTocRuleEngine {

    /**
     * Auto-detection reads only this many leading UTF-16 code units (iOS parity:
     * `TXTTocRuleEngine.sampleSizeUTF16`). Extraction, by contrast, always scans the full text.
     */
    const val SAMPLE_SIZE_UTF16: Int = 512 * 1024

    /**
     * A rule must match at least this often within the sample to be trusted (iOS parity:
     * `TXTTocRuleEngine.swift:77`). One match is a coincidence, not a chapter scheme.
     */
    const val MIN_MATCHES: Int = 2

    /**
     * Matches EXAMINED between cancellation checks (not headings emitted — a document of dropped
     * blank titles stays interruptible too).
     *
     * This bounds the check frequency in match-space only. The residual latency is the gap between
     * two matches, which one non-suspending regex call walks in a single step; see the file header
     * for why that is accepted rather than chunked away.
     */
    const val CANCELLATION_CHECK_INTERVAL: Int = 1024

    /**
     * Finds the rule that best explains [text], or `null` when none is convincing.
     *
     * Mirrors iOS exactly: sample the first [SAMPLE_SIZE_UTF16] code units, count matches for each
     * ENABLED rule in list order, keep the rule with strictly the most matches (so a tie goes to
     * the earlier rule), and return it only if that count reaches [MIN_MATCHES].
     *
     * @param rules the candidate set; disabled entries are ignored. The returned instance is the
     *              caller's own object, so a customized rule set round-trips.
     * @throws kotlinx.coroutines.CancellationException if the calling coroutine is cancelled.
     */
    suspend fun detectBestRule(
        text: String,
        rules: List<TxtTocRule> = TxtTocRules.defaults,
    ): TxtTocRule? {
        coroutineContext.ensureActive()
        if (text.isEmpty()) return null

        val sample = sampleOf(text)
        var bestRule: TxtTocRule? = null
        var bestCount = 0

        for (rule in rules) {
            if (!rule.enabled) continue
            coroutineContext.ensureActive()
            val regex = compile(rule) ?: continue
            val count = countMatches(regex, sample)
            if (count > bestCount) {
                bestCount = count
                bestRule = rule
            }
        }

        // Same reason as extractHeadings': a cancel during the LAST rule's count must not be
        // swallowed by the loop simply running out of rules.
        coroutineContext.ensureActive()
        return if (bestCount >= MIN_MATCHES) bestRule else null
    }

    /**
     * Extracts every heading [rule] finds in [text], in document order, stopping early at [limit].
     *
     * Each heading's title is the whole MATCH trimmed — one line for every ordinary heading, but
     * see the file header for the legitimate cross-terminator case. Matches that trim to nothing
     * are dropped (iOS parity) and cost nothing against [limit]. Each offset is the match start —
     * the line start, leading indent included — as a UTF-16 offset into [text].
     *
     * @param limit the maximum number of headings to collect; must be positive. Callers pass
     *              `cap + 1` so [ExtractResult.hitLimit] reads as "more than `cap` headings exist"
     *              (plan §4.4). Deliberately has no default: an unbounded extraction of an
     *              adversarial document is exactly the failure this parameter exists to prevent,
     *              so every call site states its own budget.
     * @throws IllegalArgumentException if [limit] is not positive.
     * @throws kotlinx.coroutines.CancellationException if the calling coroutine is cancelled.
     */
    suspend fun extractHeadings(text: String, rule: TxtTocRule, limit: Int): ExtractResult {
        require(limit > 0) { "limit must be positive, was $limit" }
        coroutineContext.ensureActive()
        if (text.isEmpty()) return ExtractResult.EMPTY
        val regex = compile(rule) ?: return ExtractResult.EMPTY

        val headings = ArrayList<DetectedHeading>()
        var sinceCheck = 0
        var match = regex.find(text)

        while (match != null) {
            if (++sinceCheck >= CANCELLATION_CHECK_INTERVAL) {
                sinceCheck = 0
                coroutineContext.ensureActive()
            }
            val title = match.value.trim()
            if (title.isNotEmpty()) {
                headings.add(DetectedHeading(title = title, sourceOffsetUtf16 = match.range.first))
                // Stop the SCAN, not just the returned list: the next match is never even sought.
                if (headings.size == limit) return ExtractResult(headings, hitLimit = true)
            }
            match = match.next()
        }

        // A cancel landing DURING the final `next()` — the long walk to end-of-text — would
        // otherwise be swallowed: the loop exits on null and returns a normal result. Check once
        // more so the outcome is always "cancelled" rather than "a full result for a job nobody
        // is waiting on".
        coroutineContext.ensureActive()
        return ExtractResult(headings, hitLimit = false)
    }

    /**
     * The leading [SAMPLE_SIZE_UTF16] code units of [text], never splitting a surrogate pair.
     *
     * Swift's `String.Index(utf16Offset:in:)` rounds to a Character boundary; a bare Kotlin
     * `substring` would leave a lone high surrogate at the end, which is not a character in either
     * engine's sense and would only ever confuse a `.{0,30}` count. A lone surrogate ALREADY in
     * the text (malformed input) is preserved as-is — only a genuine pair is stepped back over.
     *
     * `internal` so the boundary cases can be asserted directly; they are not observable through
     * [detectBestRule], whose result is the same either way for every realistic rule.
     */
    internal fun sampleOf(text: String): String {
        if (text.length <= SAMPLE_SIZE_UTF16) return text
        var end = SAMPLE_SIZE_UTF16
        if (text[end - 1].isHighSurrogate() && text[end].isLowSurrogate()) end--
        return text.substring(0, end)
    }

    /** Streams over the matches rather than collecting them — the sample is up to 512 KB. */
    private suspend fun countMatches(regex: Regex, sample: String): Int {
        var count = 0
        var sinceCheck = 0
        var match = regex.find(sample)
        while (match != null) {
            count++
            if (++sinceCheck >= CANCELLATION_CHECK_INTERVAL) {
                sinceCheck = 0
                coroutineContext.ensureActive()
            }
            match = match.next()
        }
        return count
    }

    /** `null` for a pattern `java.util.regex` rejects — iOS's `try?` skips the same way. */
    private fun compile(rule: TxtTocRule): Regex? = try {
        Regex(rule.pattern, RegexOption.MULTILINE)
    } catch (_: PatternSyntaxException) {
        null
    }
}
