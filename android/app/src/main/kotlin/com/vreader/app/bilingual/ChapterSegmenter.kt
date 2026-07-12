// Purpose: feature #131 WI-1 - pure paragraph / sentence segmentation for the
// Android bilingual pipeline. Port of iOS ChapterSegmenter.swift (+ its
// BilingualParagraphRanges.swift dependency). Splits a chapter's plain text into
// translation segments (paragraphs or sentences) and their half-open UTF-16
// spans, with CJK awareness.
//
// Key decisions (mirroring iOS):
// - Paragraph = a maximal run of non-blank content lines, blank-line-separated.
//   A single newline inside a run is a SOFT WRAP (same paragraph); a
//   whitespace-only line (incl. U+3000 / U+00A0, common in CJK files) is the
//   delimiter. Leading + trailing blank lines yield no paragraph. Every emitted
//   paragraph string normalizes soft-wrap CRLF/CR endings to LF then trims.
// - Sentence split uses java.text.BreakIterator.getSentenceInstance() - the JVM
//   analog of iOS enumerateSubstrings(.bySentences): locale-aware, handling CJK
//   fullwidth terminators (. ! ? full-width) as well as Latin punctuation, with
//   no manual punctuation table.
// - Span peers (paragraphRanges / sentenceRanges) return half-open UTF-16
//   Utf16Spans shrunk to trimmed bounds, so text.substring(span.start,
//   span.endExclusive) reproduces the segment (count-parity with the string
//   peers). Surrogate halves are never whitespace, so per-code-unit trimming is
//   surrogate-safe.
//
// @coordinates-with: Utf16Span.kt, TranslationChunker.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1),
//   iOS vreader/Services/AI/ChapterSegmenter.swift +
//   iOS vreader/Services/Reader/BilingualParagraphRanges.swift
package com.vreader.app.bilingual

import java.text.BreakIterator
import java.util.Locale

/** Pure paragraph / sentence segmentation for chapter translation. */
object ChapterSegmenter {

    // ---- paragraphs ----

    /**
     * Splits chapter text into paragraphs. Paragraphs are separated by one or
     * more blank lines; a single line break inside a paragraph is a soft wrap and
     * does not split. Each paragraph normalizes soft-wrap CR/CRLF to LF and is
     * trimmed; empty ones never appear (the scanner emits only non-blank runs).
     */
    fun paragraphs(text: String): List<String> =
        scanParagraphRanges(text).map { range ->
            text.substring(range.start, range.endExclusive)
                .replace("\r\n", "\n")
                .replace("\r", "\n")
                .trim()
        }

    /**
     * Half-open UTF-16 spans of each paragraph, trimmed to its visible bounds,
     * in source order. paragraphRanges(t).size == paragraphs(t).size. Spans are
     * against the RAW text (no soft-wrap normalization) - substringing a span
     * yields the paragraph's raw content.
     */
    fun paragraphRanges(text: String): List<Utf16Span> =
        scanParagraphRanges(text).map { range ->
            trimSpan(text, range.start, range.endExclusive)
        }

    // ---- sentences ----

    /**
     * Splits chapter text into sentences. CJK-aware via BreakIterator. Each
     * sentence is trimmed; empty fragments are dropped. A fragment with no
     * terminal punctuation still yields the fragment; only fully-empty input
     * yields nothing.
     */
    fun sentences(text: String): List<String> =
        sentenceSpans(text).map { text.substring(it.start, it.endExclusive) }

    /**
     * Half-open UTF-16 spans of each sentence, trimmed to visible bounds, in
     * source order. sentenceRanges(t).size == sentences(t).size; substringing a
     * span reproduces the trimmed sentence.
     */
    fun sentenceRanges(text: String): List<Utf16Span> = sentenceSpans(text)

    // ---- internals ----

    /**
     * BreakIterator-driven sentence boundaries, each shrunk to trimmed bounds.
     * Whitespace-only fragments trim to nothing and are dropped (count parity
     * between sentences and sentenceRanges).
     */
    private fun sentenceSpans(text: String): List<Utf16Span> {
        if (text.isEmpty()) return emptyList()
        val iterator = BreakIterator.getSentenceInstance(Locale.getDefault())
        iterator.setText(text)
        val result = ArrayList<Utf16Span>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            val span = trimSpanOrNull(text, start, end)
            if (span != null) result.add(span)
            start = end
            end = iterator.next()
        }
        return result
    }

    /**
     * Port of iOS BilingualParagraphRanges.scan: raw UTF-16 half-open ranges of
     * each paragraph (maximal run of non-blank content lines). Ranges end at the
     * last non-blank char of the run (trailing blank lines excluded); leading +
     * trailing blank lines produce no range. Returned as Utf16Spans over the raw
     * text (NOT yet trimmed of intra-line leading/trailing whitespace - the
     * callers trim as needed).
     */
    private fun scanParagraphRanges(text: String): List<Utf16Span> {
        val length = text.length
        if (length == 0) return emptyList()

        val ranges = ArrayList<Utf16Span>()
        var cursor = 0
        var paragraphStart: Int? = null       // start of the currently-open paragraph
        var paragraphLastNonBlank = 0          // exclusive end (index after the last non-blank char)

        while (cursor < length) {
            // Find the end of this line (exclusive of the line terminator).
            var lineEnd = cursor
            while (lineEnd < length) {
                val unit = text[lineEnd]
                if (unit == '\n' || unit == '\r') break
                lineEnd += 1
            }
            val blank = isLineBlank(text, cursor, lineEnd)

            if (blank) {
                // Close the open paragraph, if any.
                val start = paragraphStart
                if (start != null) {
                    ranges.add(Utf16Span(start, paragraphLastNonBlank))
                    paragraphStart = null
                }
            } else {
                if (paragraphStart == null) paragraphStart = cursor
                paragraphLastNonBlank = lineEnd
            }

            // Advance past the line terminator (handle "\r\n" as one).
            if (lineEnd < length) {
                val unit = text[lineEnd]
                cursor = lineEnd + 1
                if (unit == '\r' && cursor < length && text[cursor] == '\n') cursor += 1
            } else {
                cursor = lineEnd
            }
        }

        val start = paragraphStart
        if (start != null) ranges.add(Utf16Span(start, paragraphLastNonBlank))
        return ranges
    }

    /** True when [start, end) of [text] contains only whitespace (or is empty). */
    private fun isLineBlank(text: String, start: Int, end: Int): Boolean {
        for (i in start until end) {
            if (!isWhitespaceUnit(text[i])) return false
        }
        return true
    }

    /**
     * Shrinks [start, end) to trimmed bounds and returns a Utf16Span, or null
     * when the range is whitespace-only. Surrogate halves are never whitespace,
     * so per-code-unit trimming is surrogate-safe.
     */
    private fun trimSpanOrNull(text: String, start: Int, end: Int): Utf16Span? {
        var s = start
        var e = end
        while (s < e && isWhitespaceUnit(text[s])) s += 1
        while (e > s && isWhitespaceUnit(text[e - 1])) e -= 1
        if (s >= e) return null
        return Utf16Span(s, e)
    }

    /** As [trimSpanOrNull] but returns an EMPTY span at [start] when whitespace-only. */
    private fun trimSpan(text: String, start: Int, end: Int): Utf16Span =
        trimSpanOrNull(text, start, end) ?: Utf16Span(start, start)

    /**
     * True when the UTF-16 code unit is whitespace. Kotlin's [Char.isWhitespace]
     * is Character.isWhitespace(c) OR Character.isSpaceChar(c), so it already
     * recognizes U+00A0 (no-break space) and U+3000 (ideographic space) - the
     * whitespace code points common in CJK/formatted files. This mirrors the iOS
     * scanner treating any whitespace-only line (incl. U+3000/U+00A0) as a
     * paragraph separator.
     */
    private fun isWhitespaceUnit(c: Char): Boolean = c.isWhitespace()
}
