package com.vreader.app.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #133 WI-2 — [SearchQueryBuilder.structuredQuery]: raw query → typed [QueryUnit]s
 * (Phrase / PrefixTerm / Term) derived from the SAME `buildFtsParts` grouping `ftsQuery` uses.
 * The structured representation is what the flat `BuiltQuery.tokens` cannot express (round-2 C2):
 * a CJK run is ONE ordered phrase, the final Latin bareword is a prefix, other barewords are
 * whole-token AND terms. The critical regression: `ftsQuery`/`BuiltQuery` stay byte-for-byte
 * unchanged. Robolectric-run so the normalizer's bundled `android.icu` case-fold is present.
 */
@RunWith(RobolectricTestRunner::class)
class StructuredQueryTest {

    // ---- blank / operator-only → null (mirrors ftsQuery) ----

    @Test fun blank_returnsNull() {
        assertNull(SearchQueryBuilder.structuredQuery(""))
        assertNull(SearchQueryBuilder.structuredQuery("   "))
        assertNull(SearchQueryBuilder.structuredQuery("\t\n "))
    }

    @Test fun operatorOnly_afterSanitize_returnsNull() {
        assertNull(SearchQueryBuilder.structuredQuery("\"*()"))
        assertNull(SearchQueryBuilder.structuredQuery("-"))
    }

    // ---- final Latin bareword → PrefixTerm ----

    @Test fun singleLatinTerm_isPrefixTerm() {
        val sq = SearchQueryBuilder.structuredQuery("prog")!!
        assertEquals(listOf(QueryUnit.PrefixTerm("prog")), sq.units)
    }

    @Test fun multiTerm_onlyFinalIsPrefix_othersAreTerms() {
        val sq = SearchQueryBuilder.structuredQuery("quick pragmatic prog")!!
        assertEquals(
            listOf(
                QueryUnit.Term("quick"),
                QueryUnit.Term("pragmatic"),
                QueryUnit.PrefixTerm("prog"),
            ),
            sq.units,
        )
    }

    @Test fun caseFold_appliedToStructuredTokens() {
        val sq = SearchQueryBuilder.structuredQuery("Pragmatic")!!
        assertEquals(listOf(QueryUnit.PrefixTerm("pragmatic")), sq.units)
    }

    @Test fun eszett_foldsToSs_inStructuredToken() {
        val sq = SearchQueryBuilder.structuredQuery("Straße")!!
        assertEquals(listOf(QueryUnit.PrefixTerm("strasse")), sq.units)
    }

    // ---- CJK run → one ordered Phrase ----

    @Test fun cjkRun_isOnePhraseOfOrderedPerCharTokens() {
        val sq = SearchQueryBuilder.structuredQuery("编程")!!
        assertEquals(listOf(QueryUnit.Phrase(listOf("编", "程"))), sq.units)
    }

    @Test fun cjkThenLatin_phraseThenPrefixTerm_orderPreserved() {
        // 编程 book -> a CJK phrase then a final Latin prefix term, in source order.
        val sq = SearchQueryBuilder.structuredQuery("编程 book")!!
        assertEquals(
            listOf(
                QueryUnit.Phrase(listOf("编", "程")),
                QueryUnit.PrefixTerm("book"),
            ),
            sq.units,
        )
    }

    @Test fun latinThenCjk_prefixOnLatinBareword_phraseNeverPrefixed() {
        // A trailing CJK phrase is NEVER a prefix. The prefix-star lands on the LAST BAREWORD, which
        // here is the preceding Latin `book` (the CJK phrase is quoted, so it is skipped) — matching
        // `buildFtsParts`' `indexOfLast { !it.startsWith("\"") }` behavior exactly.
        val sq = SearchQueryBuilder.structuredQuery("book 编程")!!
        assertEquals(
            listOf(
                QueryUnit.PrefixTerm("book"),
                QueryUnit.Phrase(listOf("编", "程")),
            ),
            sq.units,
        )
    }

    // ---- FTS keyword barewords are QUOTED literals (Term), never operators, never PrefixTerm ----

    @Test fun ftsKeyword_isPlainTerm_notOperatorNotPrefix() {
        val sq = SearchQueryBuilder.structuredQuery("and")!!
        assertEquals(listOf(QueryUnit.Term("and")), sq.units)
    }

    @Test fun allFtsKeywords_areTerms() {
        for (kw in listOf("and", "or", "not", "near")) {
            val sq = SearchQueryBuilder.structuredQuery(kw.uppercase())!!
            assertEquals("keyword $kw -> Term", listOf(QueryUnit.Term(kw)), sq.units)
        }
    }

    @Test fun keywordBetweenTerms_allThreeAreImplicitAndTerms() {
        // "cats and dogs" -> three whole-token AND terms; `and` is a literal Term, not an operator;
        // only the FINAL bareword (dogs) is a prefix.
        val sq = SearchQueryBuilder.structuredQuery("cats and dogs")!!
        assertEquals(
            listOf(
                QueryUnit.Term("cats"),
                QueryUnit.Term("and"),
                QueryUnit.PrefixTerm("dogs"),
            ),
            sq.units,
        )
    }

    @Test fun keywordAsFinalToken_isTerm_notPrefixTerm() {
        // A trailing keyword is quoted (exact) in FTS, so it must NOT be a prefix in the structure.
        val sq = SearchQueryBuilder.structuredQuery("shall not")!!
        assertEquals(
            listOf(
                QueryUnit.PrefixTerm("shall"),
                QueryUnit.Term("not"),
            ),
            sq.units,
        )
    }

    @Test fun minusSign_strippedInPlace_joinsIntoOneBareword() {
        // "anti-hero" -> the hyphen is stripped by sanitizeToken BEFORE the whitespace split (there is
        // no space), so the token becomes ONE bareword "antihero" -> a single final PrefixTerm.
        val sq = SearchQueryBuilder.structuredQuery("anti-hero")!!
        assertEquals(listOf(QueryUnit.PrefixTerm("antihero")), sq.units)
    }

    // ---- CRITICAL REGRESSION: ftsQuery / BuiltQuery byte-for-byte UNCHANGED ----

    @Test fun ftsQuery_outputUnchanged_forSpreadOfInputs() {
        // The exact BuiltQuery (fts + tokens) that #128 produced BEFORE this WI. If structuredQuery's
        // shared-grouping refactor shifted any FTS text, one of these fails.
        data class Expect(val raw: String, val fts: String, val tokens: List<String>)
        val cases = listOf(
            Expect("prog", "prog*", listOf("prog")),
            Expect("quick pragmatic prog", "quick pragmatic prog*", listOf("quick", "pragmatic", "prog")),
            Expect("Pragmatic", "pragmatic*", listOf("pragmatic")),
            Expect("编程", "\"编 程\"", listOf("编", "程")),
            Expect("编程 book", "\"编 程\" book*", listOf("编", "程", "book")),
            Expect("book 编程", "book* \"编 程\"", listOf("book", "编", "程")),
            Expect("and", "\"and\"", listOf("and")),
            Expect("cats and dogs", "cats \"and\" dogs*", listOf("cats", "and", "dogs")),
            Expect("shall not", "shall* \"not\"", listOf("shall", "not")),
            Expect("anti-hero", "antihero*", listOf("antihero")),
        )
        for (c in cases) {
            val built = SearchQueryBuilder.ftsQuery(c.raw)!!
            assertEquals("fts for '${c.raw}'", c.fts, built.fts)
            assertEquals("tokens for '${c.raw}'", c.tokens, built.tokens)
        }
    }

    @Test fun ftsQuery_stillNull_forBlankAndOperatorOnly() {
        assertNull(SearchQueryBuilder.ftsQuery(""))
        assertNull(SearchQueryBuilder.ftsQuery("   "))
        assertNull(SearchQueryBuilder.ftsQuery("\"*()"))
        assertNull(SearchQueryBuilder.ftsQuery("-"))
    }
}
