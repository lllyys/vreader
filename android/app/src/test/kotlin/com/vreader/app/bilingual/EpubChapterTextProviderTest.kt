// Purpose: feature #131 WI-7b — RED-first JVM tests for EpubChapterTextProvider (the EPUB
// href-keyed ChapterTextProvider). Covers: units() = spine hrefs in reading order (de-duped,
// blanks dropped); unitAfter walks the spine + returns null at the end / for an unknown unit;
// unitForHref resolves the current resource href (the EPUB divergence — the controller keys on
// this, not on unitContaining); unitContaining returns null by construction (an EPUB position is
// an href, not a char offset); sourceSegments/sourceText are empty at the provider layer (the
// controller enumerates blocks from the live navigator). Pure — plain JUnit, no Robolectric.
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EpubChapterTextProviderTest {

    private fun epub(href: String) = TranslationUnitId(TranslationUnitId.Kind.epubHref, href)

    @Test fun units_areSpineHrefsInOrder_dedupedAndTrimmed() {
        val p = EpubChapterTextProvider(listOf("a.xhtml", "", "b.xhtml", "a.xhtml", "  "))
        assertEquals(listOf(epub("a.xhtml"), epub("b.xhtml")), p.units())
    }

    @Test fun unitAfter_walksSpine_nullAtEndAndForUnknown() {
        val p = EpubChapterTextProvider(listOf("a.xhtml", "b.xhtml", "c.xhtml"))
        assertEquals(epub("b.xhtml"), p.unitAfter(epub("a.xhtml")))
        assertEquals(epub("c.xhtml"), p.unitAfter(epub("b.xhtml")))
        assertNull("last unit → null", p.unitAfter(epub("c.xhtml")))
        assertNull("unknown unit → null", p.unitAfter(epub("z.xhtml")))
    }

    @Test fun unitForHref_resolvesCurrentResource_nullForBlankOrUnknown() {
        val p = EpubChapterTextProvider(listOf("a.xhtml", "b.xhtml"))
        assertEquals(epub("b.xhtml"), p.unitForHref("b.xhtml"))
        assertNull("blank href → null", p.unitForHref(""))
        assertNull("unknown href → null", p.unitForHref("nope.xhtml"))
    }

    @Test fun unitContaining_isAlwaysNull_theEpubDivergence() {
        val p = EpubChapterTextProvider(listOf("a.xhtml"))
        assertNull("an EPUB position is an href, not a char offset", p.unitContaining(0))
        assertNull(p.unitContaining(9999))
    }

    @Test fun sourceSegmentsAndText_areEmptyAtProviderLayer() {
        val p = EpubChapterTextProvider(listOf("a.xhtml"))
        assertTrue("blocks are enumerated by the controller, not the provider", p.sourceSegments(epub("a.xhtml")).isEmpty())
        assertEquals("", p.sourceText(epub("a.xhtml")))
    }

    @Test fun emptySpine_hasNoUnits() {
        val p = EpubChapterTextProvider(emptyList())
        assertTrue(p.units().isEmpty())
        assertNull(p.unitForHref("a.xhtml"))
    }
}
