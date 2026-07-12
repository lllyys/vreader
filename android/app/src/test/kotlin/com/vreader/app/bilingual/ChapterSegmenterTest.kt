// Purpose: feature #131 WI-1 — RED-first JVM tests for ChapterSegmenter, the
// port of iOS ChapterSegmenter.swift + BilingualParagraphRanges.swift. Pure
// paragraph / sentence segmentation with CJK awareness and half-open UTF-16
// spans. Sentence span peers satisfy text.substring(span) == the trimmed
// sentence exactly; PARAGRAPH span peers are source-coordinate (raw), equal to
// the string peer only after CRLF/CR->LF normalization. Count-parity always holds.
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChapterSegmenterTest {

    // ---- paragraphs ----

    @Test fun paragraphs_empty_returnsEmptyList() {
        assertEquals(emptyList<String>(), ChapterSegmenter.paragraphs(""))
        assertEquals(emptyList<String>(), ChapterSegmenter.paragraphs("   \n  \n"))
    }

    @Test fun paragraphs_single_returnsOne() {
        assertEquals(listOf("Hello world."), ChapterSegmenter.paragraphs("Hello world."))
    }

    @Test fun paragraphs_blankLineSeparates() {
        val text = "First paragraph.\n\nSecond paragraph."
        assertEquals(listOf("First paragraph.", "Second paragraph."), ChapterSegmenter.paragraphs(text))
    }

    @Test fun paragraphs_softWrapDoesNotSplit() {
        // Consecutive non-blank content lines fuse into one paragraph (soft wrap).
        val text = "Line one\nLine two\n\nSecond para"
        assertEquals(listOf("Line one\nLine two", "Second para"), ChapterSegmenter.paragraphs(text))
    }

    @Test fun paragraphs_leadingAndTrailingBlankLinesDropped() {
        val text = "\n\n  \nContent here.\n\n\n"
        assertEquals(listOf("Content here."), ChapterSegmenter.paragraphs(text))
    }

    @Test fun paragraphs_cjkIdeographicSpaceLineIsBlankSeparator() {
        // U+3000 (ideographic space) — common in CJK files — is a blank separator.
        val text = "第一段。\n　\n第二段。"
        assertEquals(listOf("第一段。", "第二段。"), ChapterSegmenter.paragraphs(text))
    }

    @Test fun paragraphs_crlfNormalizedAndSplit() {
        val text = "Para one.\r\n\r\nPara two."
        assertEquals(listOf("Para one.", "Para two."), ChapterSegmenter.paragraphs(text))
    }

    @Test fun paragraphs_softWrapCrlfNormalizesToLf() {
        // A soft-wrap \r\n inside a paragraph normalizes to \n (prompt/cache parity).
        val text = "Line A\r\nLine B\r\n\r\nNext"
        assertEquals(listOf("Line A\nLine B", "Next"), ChapterSegmenter.paragraphs(text))
    }

    // ---- sentences ----

    @Test fun sentences_empty_returnsEmptyList() {
        assertEquals(emptyList<String>(), ChapterSegmenter.sentences(""))
    }

    @Test fun sentences_latinPunctuation() {
        val text = "Hello there. How are you? I am fine!"
        assertEquals(
            listOf("Hello there.", "How are you?", "I am fine!"),
            ChapterSegmenter.sentences(text),
        )
    }

    @Test fun sentences_cjkTerminators() {
        // 。！？ are full-width CJK sentence terminators.
        val text = "你好。今天天气很好！你怎么样？"
        val result = ChapterSegmenter.sentences(text)
        assertEquals(listOf("你好。", "今天天气很好！", "你怎么样？"), result)
    }

    @Test fun sentences_noTerminator_returnsWholeFragment() {
        assertEquals(listOf("just a fragment"), ChapterSegmenter.sentences("just a fragment"))
    }

    // ---- paragraphRanges ----

    @Test fun paragraphRanges_countMatchesParagraphs() {
        val text = "First paragraph.\n\nSecond paragraph.\n\nThird."
        val ranges = ChapterSegmenter.paragraphRanges(text)
        val paras = ChapterSegmenter.paragraphs(text)
        assertEquals(paras.size, ranges.size)
    }

    @Test fun paragraphRanges_substringMatchesTrimmedParagraph() {
        val text = "  First para.  \n\n  Second para.  "
        val ranges = ChapterSegmenter.paragraphRanges(text)
        // Spans are against the RAW text; substringing them yields the paragraph
        // content (soft-wrap normalization aside — there is none here).
        assertEquals("First para.", text.substring(ranges[0].start, ranges[0].endExclusive))
        assertEquals("Second para.", text.substring(ranges[1].start, ranges[1].endExclusive))
    }

    @Test fun paragraphRanges_halfOpenAndNonOverlapping() {
        val text = "Alpha.\n\nBeta.\n\nGamma."
        val ranges = ChapterSegmenter.paragraphRanges(text)
        for (r in ranges) {
            assertTrue("endExclusive >= start", r.endExclusive >= r.start)
        }
        for (i in 1 until ranges.size) {
            assertTrue("non-overlapping", ranges[i].start >= ranges[i - 1].endExclusive)
        }
    }

    @Test fun paragraphRanges_empty() {
        assertEquals(emptyList<Utf16Span>(), ChapterSegmenter.paragraphRanges(""))
    }

    @Test fun paragraphRanges_surrogatePairSafe() {
        // An emoji (surrogate pair) inside a paragraph: span boundaries never
        // land in the middle of a surrogate pair.
        val text = "Hi 😀 there.\n\nNext line."
        val ranges = ChapterSegmenter.paragraphRanges(text)
        // First span should reproduce the whole first paragraph including the emoji.
        assertEquals("Hi 😀 there.", text.substring(ranges[0].start, ranges[0].endExclusive))
    }

    @Test fun paragraphRanges_softWrapCrlf_substringEqualsPeerAfterNormalization() {
        // For a soft-wrapped paragraph the RAW span retains \r\n; it equals the
        // string peer only after the same CRLF/CR->LF normalization paragraphs()
        // applies. Count-parity always holds.
        val text = "Line A\r\nLine B\r\n\r\nNext"
        val ranges = ChapterSegmenter.paragraphRanges(text)
        val paras = ChapterSegmenter.paragraphs(text)
        assertEquals(paras.size, ranges.size)
        ranges.forEachIndexed { i, span ->
            val raw = text.substring(span.start, span.endExclusive)
            assertEquals(paras[i], raw.replace("\r\n", "\n").replace("\r", "\n"))
        }
        // And the raw span for the soft-wrapped paragraph really does retain \r\n.
        assertEquals("Line A\r\nLine B", text.substring(ranges[0].start, ranges[0].endExclusive))
    }

    // ---- sentenceRanges ----

    @Test fun sentenceRanges_countMatchesSentences() {
        val text = "One. Two? Three!"
        val ranges = ChapterSegmenter.sentenceRanges(text)
        val sentences = ChapterSegmenter.sentences(text)
        assertEquals(sentences.size, ranges.size)
    }

    @Test fun sentenceRanges_substringMatchesTrimmedSentence() {
        val text = "Hello there. How are you?"
        val ranges = ChapterSegmenter.sentenceRanges(text)
        val sentences = ChapterSegmenter.sentences(text)
        ranges.forEachIndexed { i, span ->
            assertEquals(sentences[i], text.substring(span.start, span.endExclusive))
        }
    }

    @Test fun sentenceRanges_cjk() {
        val text = "你好。今天天气很好！"
        val ranges = ChapterSegmenter.sentenceRanges(text)
        val sentences = ChapterSegmenter.sentences(text)
        assertEquals(sentences.size, ranges.size)
        ranges.forEachIndexed { i, span ->
            assertEquals(sentences[i], text.substring(span.start, span.endExclusive))
        }
    }

    @Test fun sentenceRanges_halfOpenNonOverlapping() {
        val text = "A. B. C."
        val ranges = ChapterSegmenter.sentenceRanges(text)
        for (r in ranges) assertTrue(r.endExclusive >= r.start)
        for (i in 1 until ranges.size) {
            assertTrue(ranges[i].start >= ranges[i - 1].endExclusive)
        }
    }

    @Test fun sentenceRanges_empty() {
        assertEquals(emptyList<Utf16Span>(), ChapterSegmenter.sentenceRanges(""))
    }

    @Test fun sentenceRanges_surrogatePairSafe() {
        val text = "Cheers 😀. Next one."
        val ranges = ChapterSegmenter.sentenceRanges(text)
        val sentences = ChapterSegmenter.sentences(text)
        ranges.forEachIndexed { i, span ->
            assertEquals(sentences[i], text.substring(span.start, span.endExclusive))
        }
    }
}
