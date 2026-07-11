// Purpose: Build an FTS4 MATCH query + the normalized match tokens from a raw user query —
// feature #128 WI-3. Pure JVM. Runs the SAME SearchTextNormalizer pipeline the index path uses
// (NFKC → full case fold → diacritic strip → CJK per-char segmentation) so composed/decomposed
// accents, ligatures, full-width Latin, half-width kana, Hangul/Jamo, and full-case-fold pairs
// (ß↔ss, final sigma, Cherokee) actually match. Sanitizes FTS4 operator characters so a user query
// can never error the MATCH or change its boolean meaning. Feature #133 WI-2 adds the ADDITIVE
// `structuredQuery` projection for in-book occurrence matching (round-2 Critical-2).
//
// Key decisions:
// - Implicit AND across terms (space-joined); a `*` prefix on the FINAL Latin term only (token-prefix
//   as-you-type), matching the iOS SearchQueryExecutor shape.
// - A CJK run becomes a QUOTED PHRASE of its per-char tokens ("编 程") so unicode61 matches the
//   sequence in order, not just the individual ideographs in any position.
// - Returns the normalized match `tokens` so SnippetBuilder can highlight token-aware (a valid match
//   frequently has NO literal raw-query substring after case/width/diacritic folding).
// - The token GROUPING (CJK-run / keyword / final-prefix bareword) is factored into a single typed
//   intermediate (`buildGroupedParts`) so `ftsQuery` (FTS string) and `structuredQuery` (typed
//   StructuredQuery for the RawOffsetMatcher, #133 WI-3) are two projections of the SAME grouping —
//   they can never diverge. `ftsQuery`/`BuiltQuery`/`tokens` are byte-for-byte unchanged by WI-2.
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
     * The public STRUCTURE-preserving projection for in-book occurrence matching (feature #133 WI-2,
     * round-2 Critical-2). Returns the SAME grouping [ftsQuery] uses (via [buildGroupedParts]) as
     * TYPED [QueryUnit]s — a CJK run → one ordered [QueryUnit.Phrase], the final Latin bareword →
     * [QueryUnit.PrefixTerm], every other bareword (including quoted FTS keywords) →
     * [QueryUnit.Term]. Blank / operator-only input → null (mirrors [ftsQuery]).
     *
     * ADDITIVE: [ftsQuery]/[BuiltQuery]/tokens are untouched; the flat `tokens` cannot express
     * phrase/prefix/AND structure, which is why this exists.
     */
    fun structuredQuery(raw: String): StructuredQuery? {
        if (raw.isBlank()) return null
        val normalized = SearchTextNormalizer.normalize(raw)
        val segmented = SearchTextNormalizer.segmentCJK(normalized)
        val rawTokens = segmented
            .split(WHITESPACE)
            .map { sanitizeToken(it) }
            .filter { it.isNotEmpty() }
        if (rawTokens.isEmpty()) return null

        val grouped = buildGroupedParts(rawTokens)
        if (grouped.isEmpty()) return null
        val lastBarewordIdx = grouped.indexOfLast { it is GroupedPart.Bareword }
        val units = grouped.mapIndexed { i, part ->
            when (part) {
                is GroupedPart.Cjk -> QueryUnit.Phrase(part.chars)
                is GroupedPart.Keyword -> QueryUnit.Term(part.token)
                is GroupedPart.Bareword ->
                    if (i == lastBarewordIdx) QueryUnit.PrefixTerm(part.token) else QueryUnit.Term(part.token)
            }
        }
        return StructuredQuery(units)
    }

    /**
     * Maps the shared token grouping to FTS4 parts: a CJK run → ONE quoted phrase, an FTS keyword →
     * a quoted literal, any other bareword → itself. A `*` prefix is appended to the LAST emitted
     * bareword only (never a quoted CJK phrase OR a quoted keyword — a prefix on a phrase/keyword is
     * meaningless and the quoted term must stay exact). Behaviorally identical to the pre-#133 inline
     * grouping — the projection is byte-for-byte the same FTS string.
     */
    private fun buildFtsParts(tokens: List<String>): List<String> {
        val grouped = buildGroupedParts(tokens)
        val parts = grouped.map { part ->
            when (part) {
                is GroupedPart.Cjk -> "\"" + part.chars.joinToString(" ") + "\""
                is GroupedPart.Keyword -> "\"" + part.token + "\""
                is GroupedPart.Bareword -> part.token
            }
        }.toMutableList()
        // Prefix-star the final bareword term only (never a quoted CJK phrase OR a quoted keyword).
        val lastIdx = parts.indexOfLast { !it.startsWith("\"") }
        if (lastIdx >= 0) parts[lastIdx] = parts[lastIdx] + "*"
        return parts
    }

    /**
     * The SHARED grouping consumed by both [ftsQuery] (via [buildFtsParts]) and [structuredQuery].
     * Groups a run of adjacent single-CJK-char tokens into ONE [GroupedPart.Cjk]; classifies each
     * non-CJK token as a [GroupedPart.Keyword] (an FTS4 boolean keyword — must stay a quoted literal,
     * fix #3) or a [GroupedPart.Bareword]. The "which bareword is final" decision (prefix-star / a
     * PrefixTerm) is made by each projection over this ordered list, so both apply it identically.
     */
    private fun buildGroupedParts(tokens: List<String>): List<GroupedPart> {
        val parts = mutableListOf<GroupedPart>()
        var cjkRun = mutableListOf<String>()

        fun flushCjkRun() {
            if (cjkRun.isNotEmpty()) {
                parts.add(GroupedPart.Cjk(cjkRun.toList()))
                cjkRun = mutableListOf()
            }
        }

        for (t in tokens) {
            when {
                isCjkToken(t) -> cjkRun.add(t)
                // A bareword equal to an FTS4 boolean keyword (and/or/not/near) is CASE-INSENSITIVE in
                // FTS4, so the case-fold to lowercase does NOT neutralize it — it would still act as an
                // operator. It must stay a quoted literal (fix #3 — FTS keyword injection).
                isFtsKeyword(t) -> { flushCjkRun(); parts.add(GroupedPart.Keyword(t)) }
                else -> { flushCjkRun(); parts.add(GroupedPart.Bareword(t)) }
            }
        }
        flushCjkRun()
        return parts
    }

    /** True for a bareword equal (case-insensitively) to an FTS4 boolean-operator keyword. Tokens are
     *  already case-folded to lowercase by the normalizer, so an ASCII lowercase compare suffices; the
     *  ASCII compare is intentional (FTS4 keyword recognition is ASCII, so only these exact spellings
     *  are operators). */
    private fun isFtsKeyword(token: String): Boolean = token in FTS_KEYWORDS

    /** A token is CJK when it is a single code point classified CJK by the normalizer. */
    private fun isCjkToken(token: String): Boolean {
        if (token.isEmpty()) return false
        val cp = token.codePointAt(0)
        return Character.charCount(cp) == token.length && SearchTextNormalizer.isCjk(cp)
    }

    /**
     * Strips FTS4 operator/special characters from a token so it cannot error the MATCH. Removes:
     * `" * ( ) - : ^`. The bareword boolean keywords AND/OR/NOT/NEAR are NOT handled here — FTS4
     * keyword matching is CASE-INSENSITIVE, so the normalizer's case-fold to lowercase does NOT strip
     * their operator meaning (a bareword `and` is still the boolean AND). They are neutralized at
     * emission time by quoting (see [isFtsKeyword] in [buildFtsParts]).
     */
    private fun sanitizeToken(token: String): String =
        token.filter { it !in FTS_SPECIAL_CHARS }
}

/**
 * The shared grouping intermediate: one grouping, two projections (FTS string / [StructuredQuery]).
 * Kept private to this file — it is an internal detail of [SearchQueryBuilder], not a public shape.
 */
private sealed interface GroupedPart {
    /** A contiguous CJK per-code-point run (ordered). */
    data class Cjk(val chars: List<String>) : GroupedPart

    /** An FTS4 boolean-operator keyword bareword — must stay a quoted literal (fix #3). */
    data class Keyword(val token: String) : GroupedPart

    /** A plain bareword — the FINAL one becomes the prefix term / prefix-star. */
    data class Bareword(val token: String) : GroupedPart
}

private val WHITESPACE = Regex("\\s+")
private val FTS_SPECIAL_CHARS = setOf('"', '*', '(', ')', '-', ':', '^')

/** FTS4 boolean-operator keywords (case-INSENSITIVE in SQLite). Tokens arrive already case-folded to
 *  lowercase, so these lowercase spellings are the ones to guard. */
private val FTS_KEYWORDS = setOf("and", "or", "not", "near")
