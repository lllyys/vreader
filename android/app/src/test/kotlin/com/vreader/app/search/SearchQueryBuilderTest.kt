package com.vreader.app.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #128 WI-3 — [SearchQueryBuilder]: raw query → FTS4 query string + normalized match tokens.
 * Implicit-AND, prefix on the final term, CJK phrase, FTS-operator sanitize, blank → null.
 * Robolectric-run so the normalizer's bundled `android.icu` case-fold is present under the JVM.
 */
@RunWith(RobolectricTestRunner::class)
class SearchQueryBuilderTest {

    @Test fun blank_returnsNull() {
        assertNull(SearchQueryBuilder.ftsQuery(""))
        assertNull(SearchQueryBuilder.ftsQuery("   "))
        assertNull(SearchQueryBuilder.ftsQuery("\t\n "))
    }

    @Test fun operatorOnly_afterSanitize_returnsNull() {
        // A query of only FTS operator characters sanitizes to nothing.
        assertNull(SearchQueryBuilder.ftsQuery("\"*()"))
        assertNull(SearchQueryBuilder.ftsQuery("-"))
    }

    @Test fun singleTerm_getsPrefixStar() {
        val built = SearchQueryBuilder.ftsQuery("prog")!!
        assertEquals("prog*", built.fts)
        assertEquals(listOf("prog"), built.tokens)
    }

    @Test fun multiTerm_implicitAnd_prefixOnFinalTermOnly() {
        val built = SearchQueryBuilder.ftsQuery("quick pragmatic prog")!!
        // Implicit AND (space-joined); ONLY the final term is a prefix match.
        assertEquals("quick pragmatic prog*", built.fts)
        assertEquals(listOf("quick", "pragmatic", "prog"), built.tokens)
    }

    @Test fun caseFold_lowercasesTokens() {
        val built = SearchQueryBuilder.ftsQuery("Pragmatic")!!
        assertEquals(listOf("pragmatic"), built.tokens)
        assertEquals("pragmatic*", built.fts)
    }

    @Test fun eszettQuery_foldsToSs() {
        // "Straße" normalizes to "strasse" so it matches an "ss"-text book.
        val built = SearchQueryBuilder.ftsQuery("Straße")!!
        assertEquals(listOf("strasse"), built.tokens)
        assertTrue(built.fts.startsWith("strasse"))
    }

    @Test fun cjkPhrase_perCharTokensQuotedPhrase() {
        val built = SearchQueryBuilder.ftsQuery("编程")!!
        // A CJK run becomes a quoted phrase of per-char tokens so unicode61 matches the sequence.
        assertEquals("\"编 程\"", built.fts)
        assertEquals(listOf("编", "程"), built.tokens)
    }

    @Test fun ftsOperators_sanitizedOut() {
        // Quotes, stars, parens, colon, caret, minus stripped; barewords AND/OR/NOT/NEAR neutralized by
        // QUOTING them (FTS4 keyword matching is case-INSENSITIVE, so case-folding to lowercase does NOT
        // strip their operator meaning — quoting does).
        val built = SearchQueryBuilder.ftsQuery("darcy AND \"elizabeth\" (chapter:1)")!!
        // No parens survive that would error the MATCH.
        assertTrue("no parens", !built.fts.contains("(") && !built.fts.contains(")"))
        // No colon survives (would be a column-filter operator).
        assertTrue("no colon", !built.fts.contains(":"))
        assertTrue(built.fts.contains("darcy"))
        assertTrue(built.fts.contains("elizabeth"))
        // The AND keyword is neutralized: no bare (case-insensitive) boolean operator survives — it is
        // quoted as a literal term, so neither ` AND ` (uppercase) nor ` and ` (case-folded) appears.
        assertFalse("no uppercase AND boolean operator", built.fts.contains(" AND "))
        assertFalse("no case-folded and boolean operator", built.fts.contains(" and "))
        assertTrue("literal and quoted", built.fts.contains("\"and\""))
    }

    @Test fun minusSign_notTreatedAsNotOperator() {
        val built = SearchQueryBuilder.ftsQuery("anti-hero")!!
        // The hyphen must not become an FTS column-filter/NOT operator; terms remain matchable.
        assertTrue(built.fts.contains("anti"))
        assertTrue(built.fts.contains("hero"))
    }

    // ---- fix #3: FTS4 keyword injection (barewords AND/OR/NOT/NEAR) ----
    // FTS4 boolean-operator keyword matching is CASE-INSENSITIVE, so case-folding a query token to
    // lowercase does NOT neutralize it — a bareword `and` is still the boolean AND operator. The
    // builder must quote (or otherwise neutralize) these barewords so they can never act as operators.

    @Test fun bareword_and_isQuotedNotEmittedAsOperator() {
        // A user searching the literal word "and" gets a literal match token, never a boolean operator.
        val built = SearchQueryBuilder.ftsQuery("and")!!
        assertEquals(listOf("and"), built.tokens)
        // The emitted FTS part must NOT be a bareword `and` / `and*` operator — it is quoted so
        // unicode61 matches the literal word.
        assertFalse("no bareword `and` operator", built.fts == "and" || built.fts == "and*")
        assertTrue("literal `and` present as a quoted term", built.fts.contains("\"and\""))
    }

    @Test fun bareword_operatorKeywords_allQuoted() {
        // AND/OR/NOT/NEAR case-fold to and/or/not/near and would ALL act as operators unquoted.
        for (kw in listOf("and", "or", "not", "near")) {
            val built = SearchQueryBuilder.ftsQuery(kw.uppercase())!!
            assertEquals("literal token preserved for $kw", listOf(kw), built.tokens)
            assertTrue("$kw is quoted, not a bareword operator", built.fts.contains("\"$kw\""))
            assertFalse("$kw not emitted as a bareword", built.fts == kw || built.fts == "$kw*")
        }
    }

    @Test fun keywordBetweenTerms_doesNotBecomeBooleanOperator() {
        // "cats and dogs" must be three implicit-AND literal terms — `and` never a boolean operator
        // between `cats` and `dogs` (which would be a no-op change in meaning but still an injection).
        val built = SearchQueryBuilder.ftsQuery("cats and dogs")!!
        assertEquals(listOf("cats", "and", "dogs"), built.tokens)
        assertTrue("cats present", built.fts.contains("cats"))
        assertTrue("literal and quoted", built.fts.contains("\"and\""))
        assertTrue("dogs present", built.fts.contains("dogs"))
        // The middle token must not be a bare ` and ` operator (surrounded by spaces, unquoted).
        assertFalse("no bare AND operator between terms", built.fts.contains(" and "))
    }

    @Test fun keywordFinalTerm_notPrefixStarredAsBareword() {
        // If the LAST term is an operator keyword it must still be quoted (not a bareword `not*`).
        val built = SearchQueryBuilder.ftsQuery("shall not")!!
        assertEquals(listOf("shall", "not"), built.tokens)
        assertTrue("literal not quoted", built.fts.contains("\"not\""))
        assertFalse("no bareword not* operator", built.fts.endsWith("not*") && !built.fts.contains("\"not\""))
    }
}
