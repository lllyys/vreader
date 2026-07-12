// Purpose: feature #131 WI-1 — RED-first JVM tests for TranslationGranularity.
// Both cases are defined; v1 render uses only paragraph.
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TranslationGranularityTest {

    @Test fun hasParagraphAndSentence() {
        val all = TranslationGranularity.values().toList()
        assertEquals(2, all.size)
        assertTrue(all.contains(TranslationGranularity.paragraph))
        assertTrue(all.contains(TranslationGranularity.sentence))
    }
}
