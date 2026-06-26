// Purpose: feature #121 WI-1 (#110 Phase 3) — pure sentence segmentation for read-aloud. Splits a
// decoded book String into speakable sentences, each carrying its RAW-text [charStart,charEnd) so the
// spoken span maps back to a TxtDocument chunk for highlight. Mirrors the iOS TTSTextSource. Pure JVM.
package com.vreader.app.tts

object TtsChunker {

    // Full-width CJK terminators ALWAYS end a sentence (CJK doesn't separate sentences with spaces).
    private val CJK_TERMINATORS = setOf('。', '！', '？')
    // Latin terminators end a sentence only when followed by whitespace or end-of-text.
    private val WS_TERMINATORS = setOf('.', '!', '?', '…')
    // Closing marks that belong to the sentence when they trail a terminator.
    private val CLOSERS = setOf('"', '\'', '”', '’', ')', ']', '』', '」', '）')
    // Title abbreviations whose trailing period is never a sentence end (always followed by a name).
    // Dotted-internal forms (e.g./p.m.) are deliberately NOT here — they legitimately end sentences.
    private val ABBREVIATIONS = setOf(
        "mr", "mrs", "ms", "dr", "prof", "st", "sr", "jr", "vs", "etc", "no", "vol", "fig",
    )

    /**
     * Split [text] into sentences. Each sentence spans `[charStart, charEnd)` of the RAW [text]
     * (`text.substring(charStart, charEnd) == sentence.text`). A sentence longer than
     * [maxUtteranceChars] (the engine's `getMaxSpeechInputLength`) is hard-split on a word boundary,
     * never between a surrogate pair. Whitespace-only runs are skipped.
     */
    fun chunk(text: String, maxUtteranceChars: Int): List<TtsSentence> {
        if (text.isBlank()) return emptyList()
        // Defensive floor: a tiny/non-positive cap would otherwise stall capSpan; real callers pass
        // getMaxSpeechInputLength (~4000).
        val maxChars = maxUtteranceChars.coerceAtLeast(MIN_UTTERANCE_CHARS)
        val raw = ArrayList<IntRange>()           // [start, end) spans before capping
        var i = 0
        val n = text.length
        while (i < n) {
            // skip leading whitespace
            while (i < n && text[i].isWhitespace()) i++
            if (i >= n) break
            val start = i
            var end = -1
            var j = i
            while (j < n) {
                val c = text[j]
                if (c in CJK_TERMINATORS) {
                    var k = j + 1
                    while (k < n && text[k] in CLOSERS) k++          // pull trailing quotes/brackets in
                    end = k; break                                   // CJK terminator always ends
                } else if (c in WS_TERMINATORS && !isAbbreviation(text, j)) {
                    var k = j + 1
                    while (k < n && text[k] in CLOSERS) k++
                    if (k >= n || text[k].isWhitespace()) { end = k; break }  // ends at EOF/whitespace
                    j = k
                } else j++
            }
            if (end < 0) end = n                                     // trailing text with no terminator
            // trim trailing whitespace out of the span (defensive; the scan already stops at it)
            var e = end
            while (e > start && text[e - 1].isWhitespace()) e--
            if (e > start) raw.add(start until e)
            i = end
        }
        // apply the per-utterance cap, then index sequentially
        val out = ArrayList<TtsSentence>()
        var idx = 0
        for (span in raw) {
            for (capped in capSpan(text, span.first, span.last + 1, maxChars)) {
                out.add(TtsSentence(idx++, capped.first, capped.last + 1, text.substring(capped.first, capped.last + 1)))
            }
        }
        return out
    }

    /** True if the period at [dot] closes a known abbreviation (so it isn't a sentence end). */
    private fun isAbbreviation(text: String, dot: Int): Boolean {
        if (text[dot] != '.') return false
        var s = dot
        while (s > 0 && (text[s - 1].isLetter() || text[s - 1] == '.')) s--
        val token = text.substring(s, dot).lowercase().trimEnd('.')
        return token in ABBREVIATIONS
    }

    /** Split `[start,end)` into ≤[max]-length pieces on a word boundary, never mid-surrogate. */
    private fun capSpan(text: String, start: Int, end: Int, max: Int): List<IntRange> {
        if (end - start <= max) return listOf(start until end)
        val pieces = ArrayList<IntRange>()
        var s = start
        while (end - s > max) {
            var cut = s + max
            // don't cut between a surrogate pair
            if (Character.isLowSurrogate(text[cut])) cut--
            // prefer the last whitespace before the cap (word boundary)
            var ws = cut
            while (ws > s && !text[ws - 1].isWhitespace()) ws--
            if (ws > s) cut = ws            // cut after the whitespace's preceding word
            // skip if a surrogate landed at the new cut
            if (cut < end && Character.isLowSurrogate(text[cut])) cut--
            // Progress guard: if no word/surrogate-safe boundary moved `cut` past `s`, advance by one
            // whole code point so the loop ALWAYS makes progress (never hangs), even at a degenerate cap.
            if (cut <= s) cut = s + Character.charCount(text.codePointAt(s))
            // trim trailing whitespace from the piece
            var e = cut
            while (e > s && text[e - 1].isWhitespace()) e--
            if (e > s) pieces.add(s until e)
            // advance past whitespace
            s = cut
            while (s < end && text[s].isWhitespace()) s++
        }
        if (end > s) pieces.add(s until end)
        return pieces
    }

    private const val MIN_UTTERANCE_CHARS = 16
}
