// Purpose: feature #131 WI-4a — RED-first JVM tests for TxtChapterTextProvider, the
// TXT/MD ChapterTextProvider over a real TxtDocument. Covers the H1 final-chunk / EOF
// span math (one-chunk document, final-segment anchor, exact boundary, EOF anchor —
// none may clamp-collapse), paragraph-spanning-many-chunks → ONE segment, a
// >4000-char paragraph hard-split across TxtDocument chunks → ONE segment, CR/LF/CRLF
// line endings, MD markers as ordinary text, unitContaining(charOffsetUtf16) mapping,
// unitAfter end → null, and the H3 invariant that the provider uses paragraphRanges
// ONLY (never sentence granularity). Robolectric-run so the ICU-backed segmenter used
// by ChapterSegmenter is present under the JVM (same pattern as ChapterSegmenterTest).
package com.vreader.app.bilingual

import com.vreader.app.reader.TxtDocument
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class TxtChapterTextProviderTest {

    private fun providerOf(
        text: String,
        kind: TranslationUnitId.Kind = TranslationUnitId.Kind.txtDocSegmentWindow,
        windowSize: Int = TxtChapterTextProvider.DEFAULT_WINDOW_SIZE,
    ): TxtChapterTextProvider =
        TxtChapterTextProvider(TxtDocument.of(text), kind, windowSize)

    // ── H1: one-chunk document (no trailing newline) → its segment is not dropped ──

    @Test fun oneChunkDocument_noTrailingNewline_resolvesItsSegment() {
        val text = "The only paragraph in this file."          // one line, one chunk, one paragraph
        val provider = providerOf(text)

        val unit = provider.unitContaining(0)
        assertNotNull("a one-chunk doc must resolve a unit", unit)
        assertEquals(listOf(text), provider.sourceSegments(unit!!))
        assertEquals(1, provider.units().size)
    }

    // ── H1: final-chunk anchor — a paragraph ending in the final line resolves ──

    @Test fun finalChunkAnchor_paragraphInLastLine_resolves() {
        // Two paragraphs; the second's last (only) line is the document's final line.
        val text = "First paragraph line one.\nline two.\n\nFinal paragraph in the last line."
        val provider = providerOf(text)

        val lastUnit = provider.unitContaining(text.length)   // EOF offset
        assertNotNull(lastUnit)
        val segments = provider.sourceSegments(lastUnit!!)
        assertTrue(
            "the final paragraph must survive, not clamp-collapse",
            segments.any { it.contains("Final paragraph in the last line.") },
        )
    }

    // ── H1: exact boundary — an offset at a segment's start anchors to that segment ──

    @Test fun exactBoundary_offsetAtSegmentStart_anchorsCorrectSegment() {
        // Two paragraphs. Second paragraph starts right after the blank line.
        val first = "Alpha para."
        val second = "Beta para."
        val text = "$first\n\n$second"
        val provider = providerOf(text, windowSize = 1)       // one segment per unit for clean anchoring

        val secondStart = text.indexOf(second)
        val unit = provider.unitContaining(secondStart)
        assertNotNull(unit)
        assertEquals(listOf(second), provider.sourceSegments(unit!!))
        // An offset one BEFORE (inside the blank-line gap) anchors to the FIRST segment.
        val gapUnit = provider.unitContaining(secondStart - 1)
        assertEquals(listOf(first), provider.sourceSegments(gapUnit!!))
    }

    // ── H1: EOF anchor — span.endExclusive == text.length resolves, no collapse ──

    @Test fun eofAnchor_endExclusiveEqualsLength_resolvesLastSegment() {
        val text = "Only paragraph, no newline at end."
        val provider = providerOf(text)
        // The single paragraph's span ends exactly at text.length (no trailing newline).
        val unit = provider.unitContaining(text.length)
        assertNotNull(unit)
        assertEquals(listOf(text), provider.sourceSegments(unit!!))
        // An offset PAST EOF still clamps to the last segment (never null just past end).
        val past = provider.unitContaining(text.length + 50)
        assertEquals(unit, past)
    }

    // ── paragraph spanning MANY chunks → ONE segment / one unit ──

    @Test fun paragraphSpanningManyChunks_isOneSegment() {
        // A soft-wrapped paragraph: several physical lines (many TxtDocument chunks),
        // NO blank line between them → ONE paragraph segment.
        val text = buildString {
            repeat(20) { append("soft-wrap line ").append(it).append('\n') }
        }.trimEnd('\n')                                       // 20 lines, one paragraph
        val document = TxtDocument.of(text)
        assertTrue("this fixture must span multiple chunks", document.chunkCount > 1)

        val provider = TxtChapterTextProvider(document)
        assertEquals("20 soft-wrapped lines = ONE paragraph segment", 1, provider.units().size)
        val unit = provider.unitContaining(0)!!
        assertEquals(1, provider.sourceSegments(unit).size)
    }

    // ── a >4000-char paragraph hard-split across chunks → ONE segment ──

    @Test fun oversizeParagraph_hardSplitAcrossChunks_isOneSegment() {
        val text = "x".repeat(9000)                            // one line > DEFAULT_MAX_CHUNK_CHARS
        val document = TxtDocument.of(text)
        assertTrue("a 9000-char line must hard-split into multiple chunks", document.chunkCount > 1)

        val provider = TxtChapterTextProvider(document)
        assertEquals("a hard-split line is still ONE paragraph segment", 1, provider.units().size)
        assertEquals(listOf(text), provider.sourceSegments(provider.unitContaining(0)!!))
    }

    // ── CR / LF / CRLF line endings all segment consistently ──

    @Test fun lineEndings_lf_cr_crlf_segmentConsistently() {
        val lf = providerOf("Para A.\n\nPara B.")
        val cr = providerOf("Para A.\r\rPara B.")
        val crlf = providerOf("Para A.\r\n\r\nPara B.")

        // All three: two blank-line-separated paragraphs → two segments.
        for (p in listOf(lf, cr, crlf)) {
            assertEquals(2, p.sourceSegments(p.unitContaining(0)!!).size + segmentsAfter(p))
        }
    }

    private fun segmentsAfter(p: TxtChapterTextProvider): Int {
        // With DEFAULT_WINDOW_SIZE >= 2 both paragraphs share one window; count directly.
        return p.sourceSegments(p.units().first()).size - p.sourceSegments(p.unitContaining(0)!!).size
    }

    @Test fun twoParagraphs_bothInOneWindow_yieldTwoSegments() {
        val p = providerOf("Para A.\n\nPara B.")
        assertEquals(listOf("Para A.", "Para B."), p.sourceSegments(p.units().first()))
    }

    // ── MD markers are ordinary text to the paragraph splitter ──

    @Test fun markdownMarkers_areOrdinaryText() {
        val md = "# Heading\n\n- bullet one\n- bullet two\n\n> a quote line"
        val provider = providerOf(md, kind = TranslationUnitId.Kind.mdDocSegmentWindow)
        val segments = provider.sourceSegments(provider.units().first())
        // Blank lines delimit: heading / the two-line bullet block / the quote → 3 segments.
        assertEquals(3, segments.size)
        assertEquals("# Heading", segments[0])
        assertTrue(segments[1].contains("- bullet one"))
        assertEquals("> a quote line", segments[2])
    }

    @Test fun mdKind_producesMdSegmentWindowUnits() {
        val provider = providerOf("para", kind = TranslationUnitId.Kind.mdDocSegmentWindow)
        assertEquals(TranslationUnitId.Kind.mdDocSegmentWindow, provider.units().first().kind)
    }

    // ── unitContaining(charOffsetUtf16) maps an offset to the right window ──

    @Test fun unitContaining_mapsOffsetToWindow() {
        // 3 paragraphs, windowSize=1 → 3 windows (0,1,2).
        val text = "One.\n\nTwo.\n\nThree."
        val provider = providerOf(text, windowSize = 1)
        assertEquals(3, provider.units().size)

        assertEquals("0", provider.unitContaining(text.indexOf("One."))!!.value)
        assertEquals("1", provider.unitContaining(text.indexOf("Two."))!!.value)
        assertEquals("2", provider.unitContaining(text.indexOf("Three."))!!.value)
    }

    @Test fun unitContaining_offsetBeforeFirstSegment_anchorsFirst() {
        // Leading blank lines: the first real paragraph starts past offset 0.
        val text = "\n\n  \n\nReal paragraph."
        val provider = providerOf(text, windowSize = 1)
        val unit = provider.unitContaining(0)
        assertNotNull(unit)
        assertEquals("0", unit!!.value)
        assertEquals(listOf("Real paragraph."), provider.sourceSegments(unit))
    }

    // ── unitAfter walks to the next window, null at the end ──

    @Test fun unitAfter_walksThenNullAtEnd() {
        val text = "One.\n\nTwo.\n\nThree."
        val provider = providerOf(text, windowSize = 1)
        val u0 = provider.unitContaining(text.indexOf("One."))!!
        val u1 = provider.unitAfter(u0)
        assertEquals("1", u1!!.value)
        val u2 = provider.unitAfter(u1)
        assertEquals("2", u2!!.value)
        assertNull("no unit after the last window", provider.unitAfter(u2))
    }

    // ── empty / whitespace-only documents have no units ──

    @Test fun emptyDocument_hasNoUnits() {
        val provider = providerOf("")
        assertTrue(provider.units().isEmpty())
        assertNull(provider.unitContaining(0))
    }

    @Test fun whitespaceOnlyDocument_hasNoUnits() {
        val provider = providerOf("\n\n   \n\t\n")
        assertTrue(provider.units().isEmpty())
        assertNull(provider.unitContaining(5))
    }

    // ── H3: the provider segments by PARAGRAPH, never by sentence ──

    @Test fun usesParagraphRanges_notSentences_multiSentenceParagraphStaysOne() {
        // One paragraph, three sentences. Paragraph granularity → ONE segment
        // (sentence granularity would give three — this asserts H3).
        val text = "First sentence. Second sentence! Third sentence?"
        val provider = providerOf(text)
        assertEquals(1, provider.units().size)
        assertEquals(listOf(text), provider.sourceSegments(provider.units().first()))
    }

    // ── windowing groups multiple segments per unit ──

    @Test fun windowing_groupsSegmentsPerUnit() {
        // 5 paragraphs, windowSize=2 → windows: [0,1], [2,3], [4] → 3 units.
        val text = (0 until 5).joinToString("\n\n") { "Para $it." }
        val provider = providerOf(text, windowSize = 2)
        assertEquals(3, provider.units().size)
        assertEquals(listOf("Para 0.", "Para 1."), provider.sourceSegments(provider.units()[0]))
        assertEquals(listOf("Para 2.", "Para 3."), provider.sourceSegments(provider.units()[1]))
        assertEquals(listOf("Para 4."), provider.sourceSegments(provider.units()[2]))
    }

    // ── sourceText joins the window's segments ──

    @Test fun sourceText_joinsWindowSegments() {
        val provider = providerOf("Para A.\n\nPara B.", windowSize = 2)
        assertEquals("Para A.\n\nPara B.", provider.sourceText(provider.units().first()))
    }

    // ── a huge injected windowSize must not overflow the ceiling division to 0 units ──

    @Test fun hugeWindowSize_doesNotOverflowToZeroUnits() {
        val text = "One.\n\nTwo.\n\nThree."                    // 3 paragraphs
        val provider = providerOf(text, windowSize = Int.MAX_VALUE)
        assertEquals("all segments collapse into ONE window, never zero", 1, provider.units().size)
        assertEquals(
            listOf("One.", "Two.", "Three."),
            provider.sourceSegments(provider.units().first()),
        )
    }
}
