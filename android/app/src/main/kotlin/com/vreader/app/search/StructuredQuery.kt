// Purpose: A STRUCTURE-preserving representation of a parsed in-book search query — feature #133
// WI-2 (round-2 Critical-2, half 1). Pure JVM. Where #128's `BuiltQuery.tokens` is a FLAT highlight
// list (a CJK phrase "编 程" → ["编","程"], and the final-Latin prefix lives only in the FTS string),
// this carries the TYPED grouping the RawOffsetMatcher (WI-3) needs to locate raw occurrences: a CJK
// run is ONE ordered contiguous phrase, the final Latin bareword is a prefix, other barewords are
// whole-token AND terms.
//
// Key decisions:
// - Derived from the SAME `SearchQueryBuilder.buildFtsParts` grouping as `ftsQuery` (not the flat
//   `tokens`) so the two never diverge — one grouping, two projections (FTS string / structured units).
// - FTS boolean keywords (and/or/not/near) are LITERAL whole-token terms here (Term), exactly as they
//   are quoted-not-operator in the FTS build; the structured layer matches raw text, so quoting is an
//   FTS-syntax concern with no structural analog — a keyword and a plain bareword both match as a
//   whole token.
// - Additive: `ftsQuery`/`BuiltQuery`/`tokens` are unchanged; the library search path keeps using them.
package com.vreader.app.search

/** A parsed in-book query as an ordered list of typed units (source order preserved). */
data class StructuredQuery(val units: List<QueryUnit>)

/** One typed unit of a [StructuredQuery]. Matching semantics are for the WI-3 RawOffsetMatcher. */
sealed interface QueryUnit {
    /**
     * A contiguous CJK per-code-point run that must match IN ORDER, adjacent (no intervening
     * non-CJK). [tokens] are the individual normalized CJK code points, in source order.
     */
    data class Phrase(val tokens: List<String>) : QueryUnit

    /** The FINAL Latin bareword — matched as a token PREFIX (as-you-type), mirroring `finalToken*`. */
    data class PrefixTerm(val token: String) : QueryUnit

    /** A whole-token implicit-AND bareword (or an FTS keyword literal) — matched as a complete token. */
    data class Term(val token: String) : QueryUnit
}
