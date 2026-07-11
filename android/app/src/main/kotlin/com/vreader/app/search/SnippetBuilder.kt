// Purpose: Build a token-aware search snippet with wash-highlight ranges over the RAW section text —
// feature #128 WI-3. Pure JVM. Because normalization (case / width / diacritic / ß→ss fold) means a
// valid FTS match frequently has NO literal raw-query substring, the builder locates matches by
// normalizing each RAW word-run and testing it against the query's normalized tokens, then
// highlights the whole matched word run in the RAW casing. Centers a window on the first match;
// collapses control/whitespace runs to single spaces; falls back to the section head (no highlight)
// when no token can be located.
package com.vreader.app.search

/** A snippet's display text + the wash-highlight ranges (inclusive-exclusive as `IntRange`) within it. */
data class Snippet(val text: String, val matchRanges: List<IntRange>)

object SnippetBuilder {

    private const val DEFAULT_WINDOW = 60

    /**
     * Builds a snippet for [sectionText] against [built], centering a [window]-char window on the
     * first matched word run. Returns null only for empty text.
     */
    fun build(sectionText: String, built: BuiltQuery, window: Int = DEFAULT_WINDOW): Snippet? {
        if (sectionText.isEmpty()) return null
        // 1. Collapse control/whitespace runs to single spaces → the display string.
        val display = collapseWhitespace(sectionText)
        if (display.isEmpty()) return null

        // 2. Tokenize the display string into word runs with their [start,end) offsets.
        val words = wordRuns(display)
        // A word run matches when its normalized form CONTAINS any query token (post-fold).
        val tokens = built.tokens
        val firstMatchIdx = words.indexOfFirst { w ->
            val norm = SearchTextNormalizer.normalize(display.substring(w.start, w.end))
            tokens.any { t -> norm.contains(t) }
        }

        if (firstMatchIdx < 0) {
            // 3. No token locatable → head fallback, no highlight.
            val head = display.take(window * 2).trim()
            return Snippet(head, emptyList())
        }

        // 4. Center the window on the first matched word run.
        val match = words[firstMatchIdx]
        val matchCenter = (match.start + match.end) / 2
        val half = window
        var lo = (matchCenter - half).coerceAtLeast(0)
        var hi = (matchCenter + half).coerceAtMost(display.length)
        // Snap the window to word boundaries so we don't slice mid-word.
        lo = snapToWordStart(display, lo)
        hi = snapToWordEnd(display, hi)
        val snippetText = display.substring(lo, hi).trim()
        val trimShift = display.substring(lo, hi).indexOfFirst { !it.isWhitespace() }.coerceAtLeast(0)

        // 5. Compute highlight ranges for every matched word run inside the window.
        val ranges = mutableListOf<IntRange>()
        for (w in words) {
            if (w.start >= lo && w.end <= hi) {
                val norm = SearchTextNormalizer.normalize(display.substring(w.start, w.end))
                if (tokens.any { t -> norm.contains(t) }) {
                    val s = w.start - lo - trimShift
                    val e = w.end - lo - trimShift
                    if (s in 0..snippetText.length && e in 0..snippetText.length && s < e) {
                        ranges.add(IntRange(s, e - 1))
                    }
                }
            }
        }
        return Snippet(snippetText, ranges)
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

    private data class WordRun(val start: Int, val end: Int)

    /** Word runs of the display string, split on ASCII space (display is already whitespace-collapsed). */
    private fun wordRuns(display: String): List<WordRun> {
        val runs = mutableListOf<WordRun>()
        var i = 0
        val n = display.length
        while (i < n) {
            while (i < n && display[i] == ' ') i++
            if (i >= n) break
            val start = i
            while (i < n && display[i] != ' ') i++
            runs.add(WordRun(start, i))
        }
        return runs
    }

    private fun snapToWordStart(display: String, idx: Int): Int {
        var i = idx.coerceIn(0, display.length)
        while (i > 0 && display[i - 1] != ' ') i--
        return i
    }

    private fun snapToWordEnd(display: String, idx: Int): Int {
        var i = idx.coerceIn(0, display.length)
        while (i < display.length && display[i] != ' ') i++
        return i
    }
}
