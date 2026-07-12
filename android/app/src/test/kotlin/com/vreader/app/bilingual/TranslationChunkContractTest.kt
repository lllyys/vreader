// Purpose: feature #131 WI-1 — RED-first JVM tests for TranslationChunkContract,
// the port of iOS TranslationChunkContract.swift. Prompt shape (NO style — Style
// descoped in v1) + strict JSON-array decode (code-fence strip, count mismatch,
// non-array).
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TranslationChunkContractTest {

    // ---- userPrompt ----

    @Test fun userPrompt_containsSegmentsAndTargetLanguage() {
        val prompt = TranslationChunkContract.userPrompt(
            segments = listOf("Hello.", "World."),
            targetLanguage = "Chinese",
        )
        assertTrue("has target language", prompt.contains("Chinese"))
        assertTrue("has segment 0", prompt.contains("Hello."))
        assertTrue("has segment 1", prompt.contains("World."))
        assertTrue("has count", prompt.contains("2"))
    }

    @Test fun userPrompt_numbersSegments() {
        val prompt = TranslationChunkContract.userPrompt(
            segments = listOf("a", "b"),
            targetLanguage = "French",
        )
        assertTrue(prompt.contains("[0]"))
        assertTrue(prompt.contains("[1]"))
    }

    @Test fun userPrompt_asksForJsonArray() {
        val prompt = TranslationChunkContract.userPrompt(
            segments = listOf("x"),
            targetLanguage = "German",
        )
        assertTrue("mentions JSON array", prompt.contains("JSON array"))
    }

    // ---- decode ----

    @Test fun decode_plainJsonArray() {
        val result = TranslationChunkContract.decode("""["你好","世界"]""", 2)
        assertEquals(listOf("你好", "世界"), result)
    }

    @Test fun decode_stripsJsonCodeFence() {
        val raw = "```json\n[\"a\",\"b\"]\n```"
        assertEquals(listOf("a", "b"), TranslationChunkContract.decode(raw, 2))
    }

    @Test fun decode_stripsPlainCodeFence() {
        val raw = "```\n[\"only\"]\n```"
        assertEquals(listOf("only"), TranslationChunkContract.decode(raw, 1))
    }

    @Test fun decode_toleratesSurroundingWhitespace() {
        assertEquals(listOf("x"), TranslationChunkContract.decode("   [\"x\"]   ", 1))
    }

    @Test(expected = TranslationChunkContract.DecodeError.NotAStringArray::class)
    fun decode_nonArray_throwsNotAStringArray() {
        TranslationChunkContract.decode("""{"a":1}""", 1)
    }

    @Test(expected = TranslationChunkContract.DecodeError.NotAStringArray::class)
    fun decode_arrayOfNumbers_throwsNotAStringArray() {
        TranslationChunkContract.decode("[1, 2, 3]", 3)
    }

    @Test
    fun decode_countMismatch_throwsCountMismatch() {
        try {
            TranslationChunkContract.decode("""["a","b"]""", 3)
            throw AssertionError("expected CountMismatch")
        } catch (e: TranslationChunkContract.DecodeError.CountMismatch) {
            assertEquals(3, e.expected)
            assertEquals(2, e.actual)
        }
    }

    @Test(expected = TranslationChunkContract.DecodeError.NotAStringArray::class)
    fun decode_garbage_throwsNotAStringArray() {
        TranslationChunkContract.decode("not json at all", 1)
    }

    @Test fun decode_preservesBackticksInsidePayload() {
        // A JSON string element that literally contains a bare ``` must not be
        // truncated by the fence stripper.
        val raw = """["code: ```run```"]"""
        assertEquals(listOf("code: ```run```"), TranslationChunkContract.decode(raw, 1))
    }
}
