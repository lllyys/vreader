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
        // Quotes, stars, parens, colon, caret, minus stripped; barewords AND/OR/NOT/NEAR neutralized
        // by case-folding to lowercase (FTS4 boolean operators must be UPPERCASE to act as operators).
        val built = SearchQueryBuilder.ftsQuery("darcy AND \"elizabeth\" (chapter:1)")!!
        // No parens survive that would error the MATCH.
        assertTrue("no parens", !built.fts.contains("(") && !built.fts.contains(")"))
        // No colon survives (would be a column-filter operator).
        assertTrue("no colon", !built.fts.contains(":"))
        assertTrue(built.fts.contains("darcy"))
        assertTrue(built.fts.contains("elizabeth"))
        // The uppercase FTS operator AND is neutralized — no token is the uppercase keyword, and the
        // built FTS string carries no UPPERCASE ` AND ` boolean operator.
        assertTrue("no uppercase AND operator token", built.tokens.none { it == "AND" })
        assertFalse("no uppercase AND in fts string", built.fts.contains(" AND "))
    }

    @Test fun minusSign_notTreatedAsNotOperator() {
        val built = SearchQueryBuilder.ftsQuery("anti-hero")!!
        // The hyphen must not become an FTS column-filter/NOT operator; terms remain matchable.
        assertTrue(built.fts.contains("anti"))
        assertTrue(built.fts.contains("hero"))
    }
}
