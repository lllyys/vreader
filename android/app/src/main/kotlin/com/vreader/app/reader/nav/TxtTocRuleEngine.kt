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
//   title swallow the rest of the document (the bounded `.{0,30}$` tail is what confines a match
//   to one line) and `IGNORE_CASE` would reintroduce the Unicode case-folding divergence the rules
//   avoid by spelling both cases. See TxtTocRules' header for the D1/D1b class repairs.
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
// - Both entry points are cancellation-cooperative (`ensureActive()` at entry, then every
//   [CANCELLATION_CHECK_INTERVAL] matches and between detection rules), so closing the reader
//   mid-scan stops promptly instead of burning a background thread on a 14 MB book.
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
     * Matches examined between cancellation checks. Small enough that a cancelled scan of a 14 MB
     * book stops in well under a frame; large enough that the check is not the inner loop's cost.
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

        return if (bestCount >= MIN_MATCHES) bestRule else null
    }

    /**
     * Extracts every heading [rule] finds in [text], in document order, stopping early at [limit].
     *
     * Each heading's title is the whole matched LINE trimmed; matches that trim to nothing are
     * dropped (iOS parity) and cost nothing against [limit]. Each offset is the match start — the
     * line start, leading indent included — as a UTF-16 offset into [text].
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

        return ExtractResult(headings, hitLimit = false)
    }

    /**
     * The leading [SAMPLE_SIZE_UTF16] code units of [text], never splitting a surrogate pair.
     *
     * Swift's `String.Index(utf16Offset:in:)` rounds to a Character boundary; a bare Kotlin
     * `substring` would leave a lone high surrogate at the end, which is not a character in either
     * engine's sense and would only ever confuse a `.{0,30}` count.
     */
    private fun sampleOf(text: String): String {
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
