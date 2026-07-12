// Purpose: feature #131 WI-1 — RED-first JVM tests for TranslationUnitId, the
// stable per-unit identity (storageKey = "${kind.name}:$value").
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class TranslationUnitIdTest {

    @Test fun storageKey_formatsAsKindNameColonValue() {
        val id = TranslationUnitId(TranslationUnitId.Kind.epubHref, "chapter1.xhtml")
        assertEquals("epubHref:chapter1.xhtml", id.storageKey)
    }

    @Test fun storageKey_forEveryKind() {
        assertEquals(
            "foliateHref:OEBPS/ch.html",
            TranslationUnitId(TranslationUnitId.Kind.foliateHref, "OEBPS/ch.html").storageKey,
        )
        assertEquals(
            "txtDocSegmentWindow:0",
            TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0").storageKey,
        )
        assertEquals(
            "mdDocSegmentWindow:12",
            TranslationUnitId(TranslationUnitId.Kind.mdDocSegmentWindow, "12").storageKey,
        )
        assertEquals(
            "pdfPageRange:3-7",
            TranslationUnitId(TranslationUnitId.Kind.pdfPageRange, "3-7").storageKey,
        )
    }

    @Test fun equality_bySameKindAndValue() {
        val a = TranslationUnitId(TranslationUnitId.Kind.epubHref, "x")
        val b = TranslationUnitId(TranslationUnitId.Kind.epubHref, "x")
        val c = TranslationUnitId(TranslationUnitId.Kind.foliateHref, "x")
        assertEquals(a, b)
        assertNotEquals(a, c)
    }

    @Test fun storageKey_toleratesColonInValue() {
        val id = TranslationUnitId(TranslationUnitId.Kind.epubHref, "a:b:c")
        assertEquals("epubHref:a:b:c", id.storageKey)
    }

    @Test fun kind_hasFiveCases() {
        assertEquals(5, TranslationUnitId.Kind.values().size)
    }
}
