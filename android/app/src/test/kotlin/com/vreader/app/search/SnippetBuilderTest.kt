package com.vreader.app.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #128 WI-3 — [SnippetBuilder]: token-aware snippet with wash-highlight ranges over the RAW
 * section text. Because normalization (case/width/diacritic/ß→ss fold) means a valid match often has
 * NO literal raw-query substring, the builder locates matches by scanning raw word-runs for the
 * query's NORMALIZED tokens. Robolectric-run so the normalizer's bundled `android.icu` is present.
 */
@RunWith(RobolectricTestRunner::class)
class SnippetBuilderTest {

    private fun query(raw: String) = SearchQueryBuilder.ftsQuery(raw)!!

    @Test fun locatesTokenAndCentersWindow() {
        val text = "The pragmatic programmer is quick to adapt to changing requirements over time."
        val snippet = SnippetBuilder.build(text, query("pragmatic"), window = 20)!!
        assertTrue("snippet contains the matched term", snippet.text.contains("pragmatic"))
        assertTrue("at least one match range", snippet.matchRanges.isNotEmpty())
        // The range points at "pragmatic" within the snippet text.
        val r = snippet.matchRanges.first()
        assertEquals("pragmatic", snippet.text.substring(r.first, r.last + 1))
    }

    @Test fun caseInsensitiveMatch_highlightsRawCasing() {
        val text = "The Pragmatic Programmer."
        val snippet = SnippetBuilder.build(text, query("pragmatic"), window = 40)!!
        val r = snippet.matchRanges.first()
        // Range covers the raw (capitalized) form; the raw casing is preserved in the snippet text.
        assertEquals("Pragmatic", snippet.text.substring(r.first, r.last + 1))
    }

    @Test fun eszettMatch_highlightsRawStrasse() {
        // Query "strasse" (folded from Straße) matches raw text "Strasse" with no literal substring
        // identity issue — token-aware scan folds the raw window too.
        val text = "Wir wohnen in der Hauptstrasse neben dem Park."
        val snippet = SnippetBuilder.build(text, query("hauptstrasse"), window = 40)!!
        assertTrue(snippet.matchRanges.isNotEmpty())
        val r = snippet.matchRanges.first()
        assertEquals("Hauptstrasse", snippet.text.substring(r.first, r.last + 1))
    }

    @Test fun collapsesWhitespaceRuns() {
        val text = "alpha    \n\t  beta pragmatic gamma"
        val snippet = SnippetBuilder.build(text, query("pragmatic"), window = 60)!!
        assertFalse("no double spaces in snippet", snippet.text.contains("  "))
        assertFalse("no newlines in snippet", snippet.text.contains("\n"))
    }

    @Test fun noTokenInRawText_fallsBackToHeadNoHighlight() {
        // A match that only exists post-recomposition (no raw token locatable) → head fallback,
        // empty matchRanges (no incorrect highlight).
        val text = "Completely unrelated content about weather and clouds."
        val snippet = SnippetBuilder.build(text, query("xyzzynomatch"), window = 30)!!
        assertTrue(snippet.matchRanges.isEmpty())
        // Head fallback: the snippet starts at the section head.
        assertTrue(snippet.text.startsWith("Completely"))
    }

    @Test fun emptyText_returnsNull() {
        assertNull(SnippetBuilder.build("", query("anything"), window = 30))
    }

    @Test fun multipleOccurrences_highlightsFirstAndCenters() {
        val text = "pragmatic one two three four five six seven eight nine pragmatic ten"
        val snippet = SnippetBuilder.build(text, query("pragmatic"), window = 20)!!
        // Window centers on the FIRST matched token.
        assertTrue(snippet.matchRanges.isNotEmpty())
        val r = snippet.matchRanges.first()
        assertEquals("pragmatic", snippet.text.substring(r.first, r.last + 1))
    }
}
