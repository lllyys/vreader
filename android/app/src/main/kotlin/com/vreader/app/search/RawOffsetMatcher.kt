// Purpose: Locate EVERY occurrence of a StructuredQuery inside a chunk's RAW text and return per-
// occurrence RAW UTF-16 spans — feature #133 WI-3 (round-2 Critical-2, half 2). Pure JVM. The FTS4
// index MATCH tells us a CHUNK hits; this re-scans the raw chunk text to locate the ACTUAL occurrences
// at their true source offsets, avoiding the FTS4 `offsets()` byte/segmented-offset trap. It is the
// raw-offset counterpart to SnippetBuilder (which returns DISPLAY-collapsed offsets for highlighting):
// a TXT/MD jump needs the true raw charOffsetUTF16, which is chunkStart + this matcher's rawStart.
//
// Key decisions:
// - Normalization is at COMPARISON time ONLY. Each candidate raw window is folded via
//   SearchTextNormalizer.normalize (NFKC full-width→half, full case fold incl. ß→ss, diacritic strip)
//   to compare against the query's (already-normalized) units — but the returned span is ALWAYS the
//   RAW UTF-16 offsets of the un-folded source. A length-changing fold (ß→ss, NFKC, combining marks)
//   never shifts the raw span.
// - The occurrence is ANCHORED on the query's FIRST unit's raw span (the jump target + highlight). The
//   remaining units need only be PRESENT in the chunk — the chunk already matched via FTS implicit-AND,
//   so presence holds; the matcher's job is to locate a concrete anchor, not re-verify AND.
// - Word-token units (Term / PrefixTerm) anchor at a WORD boundary and the span is the full matched raw
//   WORD; a CJK Phrase anchor span is TIGHT — only the phrase's ideograph subsequence (关于编程的书 +
//   编程 → 编程 only), not the surrounding run.
// - Iteration is by CODE POINT (Character.charCount) so a UTF-16 surrogate pair is never split.
// - Occurrences are enumerated DETERMINISTICALLY in start order, NON-overlapping (advance past a match's
//   end), so occurrenceIndex is stable across paged calls — a resume at fromOccurrenceIndex lands on the
//   exact next occurrence.
// - RESUMABLE within a chunk: occurrences(from, maxThisPage) returns the window
//   [from, from + emitted) and RawOccurrenceSlice.nextOccurrenceIndex (null == chunk exhausted). The
//   cap is a per-PAGE window, NOT a truncation — every occurrence is retrievable across successive pages
//   (round-3 completeness). The enumeration is naturally BOUNDED: every iteration advances the scan
//   cursor by at least one UTF-16 unit (a match advances past its own end; a non-match advances one
//   code point), so occurrences ≤ chunk length and the loop always terminates — no artificial cap or
//   OOM guard is needed, and completeness holds with no false-exhaustion edge.
package com.vreader.app.search

/** Locates raw-text occurrences of a [StructuredQuery], resumable within a chunk. Pure JVM. */
object RawOffsetMatcher {

    /**
     * Returns the page window `[fromOccurrenceIndex, fromOccurrenceIndex + maxThisPage)` of all
     * occurrences of [query] in [rawChunkText], in deterministic start order, with a
     * [RawOccurrenceSlice.nextOccurrenceIndex] resume point (null == chunk exhausted).
     *
     * [fromOccurrenceIndex] occurrences are SKIPPED (enumerated but not emitted) so a resume lands on
     * the exact next occurrence; [maxThisPage] bounds only THIS page (never truncates the chunk). A
     * query with no locatable first-unit anchor (folded-only, no raw anchor) yields an empty slice —
     * the repository's head-fallback contract.
     */
    fun occurrences(
        rawChunkText: String,
        query: StructuredQuery,
        fromOccurrenceIndex: Int,
        maxThisPage: Int,
    ): RawOccurrenceSlice {
        if (rawChunkText.isEmpty() || query.units.isEmpty() || maxThisPage <= 0 || fromOccurrenceIndex < 0) {
            return RawOccurrenceSlice(emptyList(), null)
        }
        val anchor = query.units.first()
        val text = rawChunkText
        val n = text.length

        val emitted = ArrayList<RawOccurrence>(minOf(maxThisPage, 64))
        var occurrenceIndex = 0
        var i = 0
        while (i < n) {
            val end = matchAnchorAt(text, i, anchor)
            if (end > i) {
                if (occurrenceIndex >= fromOccurrenceIndex) {
                    if (emitted.size == maxThisPage) {
                        // The page is full and there is at least one MORE occurrence → resume here.
                        return RawOccurrenceSlice(emitted, occurrenceIndex)
                    }
                    emitted.add(RawOccurrence(startUtf16 = i, endUtf16 = end, occurrenceIndex = occurrenceIndex))
                }
                occurrenceIndex++
                i = end   // non-overlapping: advance past this match.
            } else {
                i += Character.charCount(text.codePointAt(i))
            }
        }
        // Reached the end of the chunk with the page not full → exhausted.
        return RawOccurrenceSlice(emitted, null)
    }

    /**
     * Attempts to match [anchor] anchored at raw index [start]. Returns the EXCLUSIVE raw end index of
     * the anchor span on success, or [start] on no match. Word-token units match at a word boundary and
     * span the full raw word; a [QueryUnit.Phrase] spans only its tight CJK subsequence.
     */
    private fun matchAnchorAt(text: String, start: Int, anchor: QueryUnit): Int = when (anchor) {
        is QueryUnit.Phrase -> matchPhraseAt(text, start, anchor.tokens)
        is QueryUnit.PrefixTerm -> matchWordAt(text, start, anchor.token, prefix = true)
        is QueryUnit.Term -> matchWordAt(text, start, anchor.token, prefix = false)
    }

    /**
     * Matches a CJK [tokens] phrase (each token one normalized CJK code point) anchored at [start].
     * Grows the raw window code point by code point, normalizing each candidate, and returns the
     * exclusive end of the SHORTEST window whose fold equals the tokens joined in order — the TIGHT
     * phrase span. The anchor char at [start] must itself be CJK (a phrase never starts mid-word).
     */
    private fun matchPhraseAt(text: String, start: Int, tokens: List<String>): Int {
        if (tokens.isEmpty()) return start
        val firstCp = text.codePointAt(start)
        if (!SearchTextNormalizer.isCjk(firstCp)) return start
        val target = tokens.joinToString("")
        val n = text.length
        // Bound growth: a phrase span is at most one raw code point per token (CJK folds ~1:1), plus a
        // small slack for any fold expansion. Cap generously but O(phrase length).
        val maxSpanCodeUnits = target.length * 2 + 8
        var end = start
        var grown = 0
        while (end < n && grown < maxSpanCodeUnits) {
            val cp = text.codePointAt(end)
            // A CJK phrase is a contiguous CJK run — stop the moment a non-CJK code point appears.
            if (!SearchTextNormalizer.isCjk(cp)) break
            end += Character.charCount(cp)
            grown += Character.charCount(cp)
            val fold = SearchTextNormalizer.normalize(text.substring(start, end))
            if (fold == target) return end
        }
        return start
    }

    /**
     * Matches a word-token [token] (a [QueryUnit.Term] exact, or a [QueryUnit.PrefixTerm] prefix)
     * anchored at [start]. Requires [start] to be at a WORD boundary (start of text, or the previous
     * code point is a separator), then delimits the full raw word run and folds it: Term requires the
     * folded word EQUALS [token]; PrefixTerm requires the folded word STARTS WITH [token]. Returns the
     * exclusive end of the full raw WORD on success, else [start].
     */
    private fun matchWordAt(text: String, start: Int, token: String, prefix: Boolean): Int {
        if (token.isEmpty()) return start
        if (isSeparator(text.codePointAt(start))) return start
        // Word boundary: start of text OR the previous code point is a separator.
        if (start > 0) {
            val prevCp = prevCodePoint(text, start)
            if (!isSeparator(prevCp)) return start
        }
        // Delimit the full raw word: grow until a separator (a bounded run).
        var end = start
        val n = text.length
        while (end < n) {
            val cp = text.codePointAt(end)
            if (isSeparator(cp)) break
            end += Character.charCount(cp)
        }
        val fold = SearchTextNormalizer.normalize(text.substring(start, end))
        val matches = if (prefix) fold.startsWith(token) else fold == token
        return if (matches) end else start
    }

    /**
     * A word separator — anything that is NOT a token character. Mirrors SQLite FTS4 `unicode61`, which
     * treats letters, digits, AND combining marks as token characters, and EVERY other code point
     * (whitespace, punctuation, symbols, an em-dash, a period, brackets) as a separator. So
     * `cat, dog` / `(cat)` / `cat—dog` delimit `cat` as a whole word, matching what made the chunk hit
     * the FTS MATCH — without this, punctuation-glued runs would miss real anchors (Gate-4 finding 1).
     *
     * - Combining marks (Unicode categories Mn/Mc/Me — e.g. a combining acute over a preceding letter)
     *   are token continuation, NOT separators, so a diacritic stays INSIDE its word's raw span (the
     *   raw span must include the mark even though the fold strips it — a length-changing fold must not
     *   shift the span).
     * - A COMPATIBILITY character whose NFKC fold is entirely letters/digits is ALSO token continuation
     *   (Gate-4 round-3 finding): FTS tokenizes the NORMALIZED text, so raw `x²y` normalizes to `x2y`
     *   and is ONE unicode61 token. Classifying `²` (U+00B2, raw category No — not letter/digit) as a
     *   separator here would split the word and miss the anchor. So a raw code point counts as a token
     *   char if its NFKC fold is non-empty and all letters/digits — the boundary predicate mirrors the
     *   normalized token stream while the returned span stays RAW.
     * - A CJK ideograph is a separator for the WORD path (CJK is matched by the phrase path), so a
     *   Latin word adjacent to a CJK run is still bounded correctly.
     */
    private fun isSeparator(codePoint: Int): Boolean {
        if (SearchTextNormalizer.isCjk(codePoint)) return true
        if (Character.isLetterOrDigit(codePoint)) return false
        when (Character.getType(codePoint)) {
            Character.NON_SPACING_MARK.toInt(),      // Mn — combining diacritics (e.g. U+0301)
            Character.COMBINING_SPACING_MARK.toInt(), // Mc
            Character.ENCLOSING_MARK.toInt(),         // Me
            -> return false
        }
        // A compatibility char that NFKC-folds to token chars only (e.g. superscript ² → "2", ½ → "1⁄2"
        // is NOT — it contains U+2044) is token continuation, mirroring the normalized unicode61 stream.
        return !normalizesToTokenChars(codePoint)
    }

    /** Whether [codePoint]'s NFKC fold is non-empty and made up ENTIRELY of letters/digits. */
    private fun normalizesToTokenChars(codePoint: Int): Boolean {
        val folded = SearchTextNormalizer.normalize(String(Character.toChars(codePoint)))
        if (folded.isEmpty()) return false
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            if (!Character.isLetterOrDigit(cp)) return false
            i += Character.charCount(cp)
        }
        return true
    }

    /** The code point ENDING immediately before raw index [index] (surrogate-pair aware). */
    private fun prevCodePoint(text: String, index: Int): Int {
        val prevIndex = text.offsetByCodePoints(index, -1)
        return text.codePointAt(prevIndex)
    }
}
