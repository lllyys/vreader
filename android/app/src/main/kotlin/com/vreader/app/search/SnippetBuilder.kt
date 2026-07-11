// Purpose: Build a token-aware search snippet with wash-highlight ranges over the RAW section text —
// feature #128 WI-3. Pure JVM. Because normalization (case / width / diacritic / ß→ss fold) means a
// valid FTS match frequently has NO literal raw-query substring, the builder locates matches by
// normalizing raw windows and testing them against the query's normalized tokens, then highlights the
// TIGHT raw span that folds to the token — code-point precise, so an unspaced CJK run (关于编程的书)
// queried with 编程 washes only 编程, not the whole run. Centers a window on the first match; collapses
// control/whitespace runs to single spaces; falls back to the section head (no highlight) when no
// token can be located.
package com.vreader.app.search

/** A snippet's display text + the wash-highlight ranges (inclusive `IntRange`) within it. */
data class Snippet(val text: String, val matchRanges: List<IntRange>)

object SnippetBuilder {

    private const val DEFAULT_WINDOW = 60

    /**
     * Builds a snippet for [sectionText] against [built], centering a [window]-char window on the
     * first matched span. Returns null only for empty text.
     */
    fun build(sectionText: String, built: BuiltQuery, window: Int = DEFAULT_WINDOW): Snippet? {
        if (sectionText.isEmpty()) return null
        // 1. Collapse control/whitespace runs to single spaces → the display string.
        val display = collapseWhitespace(sectionText)
        if (display.isEmpty()) return null

        // 2. Find every tight raw span (in `display`) that folds to a query token.
        val matches = findMatches(display, built.tokens)
        if (matches.isEmpty()) {
            // 3. No token locatable → head fallback, no highlight.
            val head = display.take(window * 2).trim()
            return Snippet(head, emptyList())
        }

        // 4. Center a window on the FIRST match.
        val first = matches.first()
        val matchCenter = (first.first + first.last + 1) / 2
        var lo = (matchCenter - window).coerceAtLeast(0)
        var hi = (matchCenter + window).coerceAtMost(display.length)
        // Snap the window to word/space boundaries so we don't slice mid-word (spaces only — CJK has
        // no spaces, so a CJK window just clamps to the raw bounds).
        lo = snapToSpaceStart(display, lo)
        hi = snapToSpaceEnd(display, hi)
        val windowText = display.substring(lo, hi)
        val leadingWs = windowText.indexOfFirst { !it.isWhitespace() }.coerceAtLeast(0)
        val snippetText = windowText.trim()

        // 5. Shift match ranges into snippet-local coordinates; drop those outside the window.
        val ranges = mutableListOf<IntRange>()
        for (m in matches) {
            if (m.first >= lo && m.last < hi) {
                val s = m.first - lo - leadingWs
                val e = m.last - lo - leadingWs
                if (s in 0..snippetText.length && e in 0 until snippetText.length && s <= e) {
                    ranges.add(IntRange(s, e))
                }
            }
        }
        return Snippet(snippetText, ranges)
    }

    /**
     * Every tight raw span in [display] whose normalized form STARTS WITH a query [tokens] entry —
     * scanned by code point so CJK matches only the ideograph subsequence. Spans are non-overlapping
     * and returned in start order.
     */
    private fun findMatches(display: String, tokens: List<String>): List<IntRange> {
        if (tokens.isEmpty()) return emptyList()
        val ranges = mutableListOf<IntRange>()
        var i = 0
        val n = display.length
        while (i < n) {
            val end = matchAt(display, i, tokens)
            if (end > i) {
                ranges.add(IntRange(i, end - 1))
                i = end
            } else {
                i += Character.charCount(display.codePointAt(i))
            }
        }
        ranges.sortBy { it.first }
        return ranges
    }

    /**
     * If any [tokens] entry is a prefix of the normalized raw text starting at [start] (matched at a
     * code-point boundary), returns the exclusive raw end index of the SHORTEST such span; else [start].
     * Grows the raw window code point by code point, normalizing each, until it covers the token.
     */
    private fun matchAt(display: String, start: Int, tokens: List<String>): Int {
        val n = display.length
        // A token cannot start inside whitespace.
        if (display[start] == ' ') return start
        var end = start
        // Bound the growth: a raw span rarely exceeds ~4x the longest token after folding
        // (ß→ss halves; NFKC can expand a little). Cap generously to keep it O(token length).
        val maxTokenLen = tokens.maxOf { it.length }
        val cap = (start + maxTokenLen * 4 + 4).coerceAtMost(n)
        while (end < cap) {
            end += Character.charCount(display.codePointAt(end))
            // Do not let a raw span cross a space (word boundary) for Latin matching.
            val norm = SearchTextNormalizer.normalize(display.substring(start, end))
            for (t in tokens) {
                if (norm == t || norm.startsWith(t)) return end
            }
            // Stop growing at a space boundary — a token never spans a space.
            if (end < n && display[end] == ' ') break
        }
        return start
    }

    /** Collapses every run of whitespace/control chars into a single ASCII space. */
    private fun collapseWhitespace(text: String): String {
        val sb = StringBuilder(text.length)
        var prevSpace = false
        for (ch in text) {
            val isSpace = ch.isWhitespace() || ch.isISOControl()
            if (isSpace) {
                if (!prevSpace && sb.isNotEmpty()) sb.append(' ')
                prevSpace = true
            } else {
                sb.append(ch)
                prevSpace = false
            }
        }
        return sb.toString().trim()
    }

    private fun snapToSpaceStart(display: String, idx: Int): Int {
        var i = idx.coerceIn(0, display.length)
        while (i > 0 && display[i - 1] != ' ') i--
        return i
    }

    private fun snapToSpaceEnd(display: String, idx: Int): Int {
        var i = idx.coerceIn(0, display.length)
        while (i < display.length && display[i] != ' ') i++
        return i
    }
}
