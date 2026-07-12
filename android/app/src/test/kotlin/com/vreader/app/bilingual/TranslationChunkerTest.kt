// Purpose: feature #131 WI-1 — RED-first JVM tests for TranslationChunker, the
// port of iOS ChapterTranslationChunker.swift. Index-group packing to a char
// budget (oversize → own chunk) + grapheme-safe subSplit (Bug #330 parity).
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TranslationChunkerTest {

    // ---- chunk ----

    @Test fun chunk_empty_returnsEmpty() {
        assertEquals(emptyList<List<Int>>(), TranslationChunker.chunk(emptyList(), 100))
    }

    @Test fun chunk_packsToBudget() {
        // "aaa"(3) + "bbb"(3) = 6 <= 6 → one chunk; "ccc" overflows → new chunk.
        val segments = listOf("aaa", "bbb", "ccc")
        val chunks = TranslationChunker.chunk(segments, 6)
        assertEquals(listOf(listOf(0, 1), listOf(2)), chunks)
    }

    @Test fun chunk_allFitInOne() {
        val segments = listOf("a", "b", "c")
        assertEquals(listOf(listOf(0, 1, 2)), TranslationChunker.chunk(segments, 100))
    }

    @Test fun chunk_oversizeSegmentGetsOwnChunk() {
        val segments = listOf("small", "waytoolongforthebudget", "small2")
        val chunks = TranslationChunker.chunk(segments, 6)
        // "small"(5)<=6 own start; oversize(22) flushes then own chunk; "small2"(6) own.
        assertEquals(listOf(listOf(0), listOf(1), listOf(2)), chunks)
    }

    @Test fun chunk_everyIndexAppearsExactlyOnceInOrder() {
        val segments = listOf("aa", "bb", "cc", "dd", "ee")
        val chunks = TranslationChunker.chunk(segments, 4)
        val flat = chunks.flatten()
        assertEquals((0 until segments.size).toList(), flat)
    }

    @Test fun chunk_nonPositiveBudgetCoercedToOne() {
        val segments = listOf("a", "b")
        // Budget coerced to 1 → each non-empty single-char segment its own chunk.
        assertEquals(listOf(listOf(0), listOf(1)), TranslationChunker.chunk(segments, 0))
    }

    // ---- subSplit ----

    @Test fun subSplit_underBudget_returnsWhole() {
        assertEquals(listOf("short"), TranslationChunker.subSplit("short", 100))
    }

    @Test fun subSplit_splitsOnWhitespaceWithinWindow() {
        // cap 10: "the quick " (10) is the window; last whitespace before index 10.
        val text = "the quick brown fox"
        val pieces = TranslationChunker.subSplit(text, 10)
        assertEquals(text, pieces.joinToString(""))
        pieces.forEach { assertTrue("piece <= cap-ish", it.length <= 10 || it.trim().isNotEmpty()) }
    }

    @Test fun subSplit_hardSplitsUnbrokenRun() {
        // CJK / no whitespace → hard split at cap boundary.
        val text = "你好世界你好世界你好世界"  // 12 chars, no whitespace
        val pieces = TranslationChunker.subSplit(text, 4)
        assertEquals(text, pieces.joinToString(""))
        pieces.dropLast(1).forEach { assertEquals(4, it.length) }
    }

    @Test fun subSplit_concatenatesBackToOriginal() {
        val text = "alpha beta gamma delta epsilon zeta eta theta"
        val pieces = TranslationChunker.subSplit(text, 12)
        assertEquals(text, pieces.joinToString(""))
    }

    @Test fun subSplit_grapheme_neverSplitsSurrogatePair() {
        // Each emoji is a surrogate pair (2 UTF-16 units, 1 grapheme). A cap
        // that would land mid-pair must never split a surrogate pair.
        val text = "😀😀😀😀😀😀"  // 6 graphemes, 12 UTF-16 units
        val pieces = TranslationChunker.subSplit(text, 3)
        assertEquals(text, pieces.joinToString(""))
        // No piece may contain a lone (unpaired) surrogate.
        pieces.forEach { piece ->
            var i = 0
            while (i < piece.length) {
                val c = piece[i]
                if (c.isHighSurrogate()) {
                    assertTrue("high surrogate must be followed by low", i + 1 < piece.length && piece[i + 1].isLowSurrogate())
                    i += 2
                } else {
                    assertTrue("no lone low surrogate", !c.isLowSurrogate())
                    i += 1
                }
            }
        }
    }

    @Test fun subSplit_combiningSequence_notSplit() {
        // "é" as e + U+0301 combining acute is one grapheme (2 chars). Repeat it
        // past the budget; a grapheme-safe splitter never separates the base
        // from its combining mark.
        val g = "é"  // é (1 grapheme, 2 UTF-16 units)
        val text = g.repeat(6)
        val pieces = TranslationChunker.subSplit(text, 3)
        assertEquals(text, pieces.joinToString(""))
        // No piece may start with a combining mark (would mean a grapheme was split).
        pieces.forEach { piece ->
            if (piece.isNotEmpty()) {
                assertTrue("piece must not begin with a combining mark", piece[0] != '́')
            }
        }
    }
}
