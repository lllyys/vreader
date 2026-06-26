package com.vreader.app.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #121 WI-1 — TtsChunker sentence segmentation + char-offset invariant. */
class TtsChunkerTest {

    private fun texts(s: String, max: Int = 4000) = TtsChunker.chunk(s, max).map { it.text }

    /** Every sentence's [charStart,charEnd) must reconstruct its text from the source — load-bearing
     *  for the spoken-sentence highlight mapping. */
    private fun assertOffsetsRoundTrip(source: String, max: Int = 4000) {
        TtsChunker.chunk(source, max).forEach { s ->
            assertEquals("offset round-trip for '${s.text}'", s.text, source.substring(s.charStart, s.charEnd))
            assertTrue(s.charStart in 0..s.charEnd && s.charEnd <= source.length)
        }
    }

    @Test fun splitsOnTerminalPunctuation() {
        val src = "Hello world. How are you? I am fine!"
        assertEquals(listOf("Hello world.", "How are you?", "I am fine!"), texts(src))
        assertOffsetsRoundTrip(src)
    }

    @Test fun keepsClosingQuoteWithSentence() {
        val src = "\"Stop right there!\" she cried. He paused."
        val out = texts(src)
        assertEquals(3, out.size)
        assertTrue(out[0].endsWith("there!\""))
        assertEquals("He paused.", out[2])
        assertOffsetsRoundTrip(src)
    }

    @Test fun cjkBoundaries() {
        val src = "今天天气很好。你好吗？我很好！"
        assertEquals(listOf("今天天气很好。", "你好吗？", "我很好！"), texts(src))
        assertOffsetsRoundTrip(src)
    }

    @Test fun abbreviationsDoNotSplit() {
        val src = "Mr. Bennet met Dr. Smith at 4 p.m. They talked."
        val out = texts(src)
        assertEquals(2, out.size)
        assertTrue(out[0].startsWith("Mr. Bennet"))
        assertEquals("They talked.", out[1])
        assertOffsetsRoundTrip(src)
    }

    @Test fun collapsesBlankRuns() {
        val src = "First line.\n\n\n   \n\nSecond line."
        assertEquals(listOf("First line.", "Second line."), texts(src))
        assertOffsetsRoundTrip(src)
    }

    @Test fun trailingTextWithoutTerminatorIsASentence() {
        val src = "A complete one. An incomplete trailing clause"
        assertEquals(listOf("A complete one.", "An incomplete trailing clause"), texts(src))
        assertOffsetsRoundTrip(src)
    }

    @Test fun hardCapsRunawaySentenceWithoutSplittingSurrogates() {
        // a long run with no terminator, plus an emoji (surrogate pair) at the cap boundary
        val src = "word ".repeat(50) + "😀" + " more".repeat(50)
        val out = TtsChunker.chunk(src, maxUtteranceChars = 40)
        assertTrue("caps each piece", out.all { it.text.length <= 40 })
        assertTrue("more than one piece", out.size > 1)
        // no piece ends or starts mid-surrogate
        out.forEach { s ->
            assertTrue(!s.text.isEmpty() && !Character.isLowSurrogate(s.text.first()))
            assertTrue(!Character.isHighSurrogate(s.text.last()))
        }
        assertOffsetsRoundTrip(src, 40)
    }

    @Test fun tinyCapNeverHangsAndMakesProgress() {
        // a degenerate cap must not stall capSpan — it coerces to a safe floor and always progresses
        val out = TtsChunker.chunk("oneverylongunbrokenword".repeat(5), maxUtteranceChars = 1)
        assertTrue(out.isNotEmpty())
        assertOffsetsRoundTrip("oneverylongunbrokenword".repeat(5), 1)
    }

    @Test fun emptyAndWhitespace() {
        assertTrue(TtsChunker.chunk("", 4000).isEmpty())
        assertTrue(TtsChunker.chunk("   \n\t  ", 4000).isEmpty())
    }

    @Test fun indicesAreSequential() {
        val out = TtsChunker.chunk("One. Two. Three.", 4000)
        assertEquals(listOf(0, 1, 2), out.map { it.index })
    }
}
