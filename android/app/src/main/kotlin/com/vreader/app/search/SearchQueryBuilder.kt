// Purpose: Build an FTS4 MATCH query + the normalized match tokens from a raw user query —
// feature #128 WI-3. Pure JVM. Runs the SAME SearchTextNormalizer pipeline the index path uses
// (NFKC → full case fold → diacritic strip → CJK per-char segmentation) so composed/decomposed
// accents, ligatures, full-width Latin, half-width kana, Hangul/Jamo, and full-case-fold pairs
// (ß↔ss, final sigma, Cherokee) actually match. Sanitizes FTS4 operator characters so a user query
// can never error the MATCH or change its boolean meaning.
//
// Key decisions:
// - Implicit AND across terms (space-joined); a `*` prefix on the FINAL Latin term only (token-prefix
//   as-you-type), matching the iOS SearchQueryExecutor shape.
// - A CJK run becomes a QUOTED PHRASE of its per-char tokens ("编 程") so unicode61 matches the
//   sequence in order, not just the individual ideographs in any position.
// - Returns the normalized match `tokens` so SnippetBuilder can highlight token-aware (a valid match
//   frequently has NO literal raw-query substring after case/width/diacritic folding).
package com.vreader.app.search

/** The built FTS4 query string + the normalized match tokens (for token-aware snippet highlighting). */
data class BuiltQuery(val fts: String, val tokens: List<String>)

object SearchQueryBuilder {

    /**
     * Builds the FTS4 query for [raw], or null when the query is blank / sanitizes to nothing.
     * Terms are implicit-AND; the final Latin term gets a `*` prefix; a CJK run becomes a quoted
     * per-char phrase.
     */
    fun ftsQuery(raw: String): BuiltQuery? {
        if (raw.isBlank()) return null
        // Normalize (fold) then segment CJK — identical to the index path.
        val normalized = SearchTextNormalizer.normalize(raw)
        val segmented = SearchTextNormalizer.segmentCJK(normalized)
        // Split into whitespace-delimited runs, then strip every FTS4 operator character from each
        // run. A run that sanitizes to empty is dropped.
        val rawTokens = segmented
            .split(WHITESPACE)
            .map { sanitizeToken(it) }
            .filter { it.isNotEmpty() }
        if (rawTokens.isEmpty()) return null

        // The match tokens (for snippet highlighting) are exactly the sanitized normalized tokens.
        val tokens = rawTokens

        // Group consecutive single-code-point CJK tokens into quoted phrases so the ideograph
        // sequence matches in order; non-CJK tokens are implicit-AND barewords.
        val ftsParts = buildFtsParts(rawTokens)
        if (ftsParts.isEmpty()) return null
        return BuiltQuery(fts = ftsParts.joinToString(" "), tokens = tokens)
    }

    /**
     * Groups a run of adjacent single-CJK-char tokens into ONE quoted phrase; emits each non-CJK
     * token as a bareword. A `*` prefix is appended to the LAST emitted bareword token only.
     */
    private fun buildFtsParts(tokens: List<String>): List<String> {
        val parts = mutableListOf<String>()
        var cjkRun = mutableListOf<String>()

        fun flushCjkRun() {
            if (cjkRun.isNotEmpty()) {
                parts.add("\"" + cjkRun.joinToString(" ") + "\"")
                cjkRun = mutableListOf()
            }
        }

        for (t in tokens) {
            if (isCjkToken(t)) {
                cjkRun.add(t)
            } else {
                flushCjkRun()
                parts.add(t)
            }
        }
        flushCjkRun()

        // Prefix-star the final bareword term only (never a quoted CJK phrase — a prefix on a CJK
        // ideograph is meaningless and the phrase must stay exact).
        val lastIdx = parts.indexOfLast { !it.startsWith("\"") }
        if (lastIdx >= 0) parts[lastIdx] = parts[lastIdx] + "*"
        return parts
    }

    /** A token is CJK when it is a single code point classified CJK by the normalizer. */
    private fun isCjkToken(token: String): Boolean {
        if (token.isEmpty()) return false
        val cp = token.codePointAt(0)
        return Character.charCount(cp) == token.length && SearchTextNormalizer.isCjk(cp)
    }

    /**
     * Strips FTS4 operator/special characters from a token so it cannot error the MATCH or act as an
     * operator. Removes: `" * ( ) - : ^`. Barewords AND/OR/NOT/NEAR are only operators when unquoted
     * and uppercase; after normalization tokens are already case-folded to lowercase, so `and`/`or`/…
     * are no longer FTS keywords — nothing extra to do beyond the character strip.
     */
    private fun sanitizeToken(token: String): String =
        token.filter { it !in FTS_SPECIAL_CHARS }
}

private val WHITESPACE = Regex("\\s+")
private val FTS_SPECIAL_CHARS = setOf('"', '*', '(', ')', '-', ':', '^')
