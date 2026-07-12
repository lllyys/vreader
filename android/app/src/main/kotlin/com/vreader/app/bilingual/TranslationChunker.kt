// Purpose: feature #131 WI-1 - pure segment-boundary chunker for chapter
// translation. Port of iOS ChapterTranslationChunker.swift. Groups translation
// segment indices into chunks each under a provider character budget, so a
// chapter that exceeds the provider's context window is sent as several requests.
//
// Key decisions (mirroring iOS):
// - A segment is NEVER split across chunks (the response<->source mapping needs a
//   1:1 segment correspondence within a chunk). One over-budget segment occupies
//   its own chunk; recombination is the caller's job.
// - The budget is a CHARACTER count (EXTENDED grapheme clusters, matching
//   Swift's String.count), not a byte or UTF-16-unit count.
// - subSplit (Bug #330 parity) is GRAPHEME-cluster-safe: it never splits a
//   surrogate pair, a combining sequence, a ZWJ emoji family, a regional-
//   indicator flag, or an emoji-modifier sequence. It splits on the last
//   whitespace within each budget window when one exists (keeps words intact for
//   space-delimited languages), else hard-splits at a grapheme boundary for a
//   long unbroken run (e.g. CJK, no inter-word whitespace).
// - Grapheme boundaries come from android.icu.text.BreakIterator (ICU
//   extended-grapheme-cluster boundaries — the true Swift `Character` analog),
//   NOT java.text.BreakIterator (which does not guarantee ZWJ/flag/modifier
//   indivisibility). android.icu is bundled from API 24 (< minSdk 26). JVM unit
//   tests run under Robolectric so the bundled ICU impl is present.
//
// @coordinates-with: ChapterSegmenter.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1),
//   iOS vreader/Services/AI/ChapterTranslationChunker.swift
package com.vreader.app.bilingual

import android.icu.text.BreakIterator

/** Pure segment-boundary chunker for chapter translation. */
object TranslationChunker {

    /**
     * Groups [segments] indices into chunks, each chunk's total grapheme count
     * not exceeding [maxCharsPerChunk] - except a single segment that is itself
     * over budget, which occupies its own chunk. A non-positive budget is coerced
     * to 1 (every non-empty segment then gets its own chunk). Flattening the
     * result yields 0 until segments.size in order - every index exactly once.
     */
    fun chunk(segments: List<String>, maxCharsPerChunk: Int): List<List<Int>> {
        if (segments.isEmpty()) return emptyList()
        val budget = maxOf(1, maxCharsPerChunk)

        val chunks = ArrayList<List<Int>>()
        var current = ArrayList<Int>()
        var currentCount = 0

        for ((index, segment) in segments.withIndex()) {
            val segmentCount = graphemeCount(segment)

            // An over-budget segment that would not fit even an empty chunk:
            // flush the current chunk, then give the big segment its own.
            if (segmentCount > budget) {
                if (current.isNotEmpty()) {
                    chunks.add(current)
                    current = ArrayList()
                    currentCount = 0
                }
                chunks.add(listOf(index))
                continue
            }

            // Adding this segment would overflow the current chunk -> start one.
            if (current.isNotEmpty() && currentCount + segmentCount > budget) {
                chunks.add(current)
                current = ArrayList()
                currentCount = 0
            }

            current.add(index)
            currentCount += segmentCount
        }

        if (current.isNotEmpty()) chunks.add(current)
        return chunks
    }

    /**
     * Sub-splits a SINGLE over-budget segment into ordered pieces each
     * <= [maxChars] grapheme clusters, concatenating back to [text]. Splits on
     * the last whitespace within each budget window when one exists; falls back
     * to a hard grapheme boundary for a long unbroken run. Grapheme-based, so it
     * never splits a surrogate pair or combining sequence. Returns [text]
     * unchanged when its grapheme count is <= maxChars.
     */
    fun subSplit(text: String, maxChars: Int): List<String> {
        val cap = maxOf(1, maxChars)
        // Grapheme boundaries as UTF-16 offsets: boundaries[0]==0 ..
        // boundaries.last()==text.length; a grapheme spans boundaries[i]..[i+1].
        val boundaries = graphemeBoundaries(text)
        val graphemes = boundaries.size - 1
        if (graphemes <= cap) return listOf(text)

        val pieces = ArrayList<String>()
        var startGrapheme = 0
        while (graphemes - startGrapheme > cap) {
            // Hard end at cap graphemes from the current start (a grapheme index).
            val hardEndGrapheme = startGrapheme + cap
            // Back up to the last whitespace boundary within (start, hardEnd].
            // "breakAtGrapheme" is the grapheme index AFTER the whitespace char,
            // mirroring the Swift version which breaks after the whitespace.
            var breakAtGrapheme = hardEndGrapheme
            var g = hardEndGrapheme
            while (g > startGrapheme) {
                val prevGrapheme = g - 1
                val prevText = text.substring(boundaries[prevGrapheme], boundaries[prevGrapheme + 1])
                if (isWhitespaceGrapheme(prevText)) {
                    breakAtGrapheme = g
                    break
                }
                g = prevGrapheme
            }
            // No whitespace in the window (one long token) -> hard split at cap.
            if (breakAtGrapheme == startGrapheme) breakAtGrapheme = hardEndGrapheme

            pieces.add(text.substring(boundaries[startGrapheme], boundaries[breakAtGrapheme]))
            startGrapheme = breakAtGrapheme
        }
        if (startGrapheme < graphemes) {
            pieces.add(text.substring(boundaries[startGrapheme], boundaries[graphemes]))
        }
        return pieces
    }

    /** Number of grapheme clusters in [text] (the Swift String.count analog). */
    private fun graphemeCount(text: String): Int = graphemeBoundaries(text).size - 1

    /**
     * UTF-16 offsets of every EXTENDED-grapheme-cluster boundary (via ICU), from
     * 0 to text.length inclusive. An empty string yields [0]; N graphemes yield
     * N+1 offsets.
     */
    private fun graphemeBoundaries(text: String): List<Int> {
        val boundaries = ArrayList<Int>()
        boundaries.add(0)
        if (text.isEmpty()) return boundaries
        val iterator = BreakIterator.getCharacterInstance()
        iterator.setText(text)
        var b = iterator.first()
        // first() is 0 (already added); walk to the end.
        b = iterator.next()
        while (b != BreakIterator.DONE) {
            boundaries.add(b)
            b = iterator.next()
        }
        return boundaries
    }

    /** True when the single-grapheme [g] is a whitespace grapheme. */
    private fun isWhitespaceGrapheme(g: String): Boolean =
        g.isNotEmpty() && g.all { it.isWhitespace() }
}
