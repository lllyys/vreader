// Purpose: feature #131 WI-1 — RED-first JVM tests for BilingualLanguages. The
// set MUST match the designed BILINGUAL_LANGS in
// dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx EXACTLY
// (keys, glyphs, script classification). Default = Chinese.
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class BilingualLanguagesTest {

    @Test fun all_matchesDesignedSetInOrder() {
        val expected = listOf(
            Triple("Chinese", "中", BilingualScript.cjk),
            Triple("Japanese", "日", BilingualScript.cjk),
            Triple("Korean", "한", BilingualScript.cjk),
            Triple("Spanish", "Es", BilingualScript.latin),
            Triple("French", "Fr", BilingualScript.latin),
            Triple("German", "De", BilingualScript.latin),
            Triple("Italian", "It", BilingualScript.latin),
            Triple("Arabic", "ع", BilingualScript.rtl),
            Triple("Russian", "Ru", BilingualScript.cyrillic),
        )
        assertEquals(expected.size, BilingualLanguages.ALL.size)
        BilingualLanguages.ALL.forEachIndexed { i, lang ->
            val (k, glyph, script) = expected[i]
            assertEquals("key[$i]", k, lang.key)
            assertEquals("glyph[$i]", glyph, lang.glyph)
            assertEquals("script[$i]", script, lang.script)
        }
    }

    @Test fun findOrDefault_returnsMatch() {
        val fr = BilingualLanguages.findOrDefault("French")
        assertEquals("French", fr.key)
        assertEquals("Fr", fr.glyph)
        assertEquals(BilingualScript.latin, fr.script)
    }

    @Test fun findOrDefault_returnsChineseForUnknown() {
        val def = BilingualLanguages.findOrDefault("Klingon")
        assertEquals("Chinese", def.key)
        assertEquals("中", def.glyph)
        assertEquals(BilingualScript.cjk, def.script)
    }

    @Test fun findOrDefault_returnsChineseForEmptyKey() {
        assertEquals("Chinese", BilingualLanguages.findOrDefault("").key)
    }

    @Test fun defaultIsFirstEntry() {
        assertEquals(BilingualLanguages.ALL.first(), BilingualLanguages.findOrDefault("nope"))
        assertNotNull(BilingualLanguages.ALL.first())
    }

    @Test fun script_hasFourClassifications() {
        assertEquals(4, BilingualScript.values().size)
    }
}
